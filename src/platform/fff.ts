/**
 * One fff finder per session directory, in a Bun `Worker` (CHD-485,
 * "Tools"): fff's grep is a synchronous FFI call that would hold chord's
 * event loop. `bun:ffi` and `Worker` are Bun's own, so this lives here.
 */
import type {
  DirSearchOptions,
  DirSearchResult,
  FileFinder,
  GrepOptions,
  GrepResult,
  SearchResult,
} from '@ff-labs/fff-bun';

// fff's index leaves its glob options type out; its method still names it.
type GlobOptions = NonNullable<Parameters<FileFinder['glob']>[1]>;

/** A search the Worker answers. */
type Call =
  | {
      readonly op: 'grep';
      readonly query: string;
      readonly options: GrepOptions;
    }
  | {
      readonly op: 'glob';
      readonly pattern: string;
      readonly options: GlobOptions;
    }
  | {
      readonly op: 'directorySearch';
      readonly query: string;
      readonly options: DirSearchOptions;
    };

/** A call the Worker answers, on the finder of `basePath`. */
export type FffRequest = { readonly id: number; readonly basePath: string } & (
  Call | { readonly op: 'destroy' }
);

export type FffReply =
  | { readonly id: number; readonly ok: true; readonly value: unknown }
  | { readonly id: number; readonly ok: false; readonly error: string };

/** How long a destroy may wait on a call still running in the Worker. */
const DESTROY_MS = 1000;

/** A session directory's finder; every call takes the tool call's signal. */
export interface Finder {
  grep(
    query: string,
    options: GrepOptions,
    signal: AbortSignal,
  ): Promise<GrepResult>;
  glob(
    pattern: string,
    options: GlobOptions,
    signal: AbortSignal,
  ): Promise<SearchResult>;
  directorySearch(
    query: string,
    options: DirSearchOptions,
    signal: AbortSignal,
  ): Promise<DirSearchResult>;
  /** Frees the finder and ends its Worker; later calls fail. */
  destroy(): Promise<void>;
}

interface Pending {
  readonly call: Call;
  readonly resolve: (value: unknown) => void;
  readonly reject: (error: unknown) => void;
}

/** The part of a `Worker` the finder uses, so tests can order its events. */
export interface FffWorker {
  onmessage: ((event: MessageEvent<FffReply>) => void) | null;
  onerror: ((event: ErrorEvent) => void) | null;
  postMessage(request: FffRequest): void;
  terminate(): void;
}

/** The id of a destroy request, which no call takes. */
const DESTROY_ID = -1;

function fffWorker(): FffWorker {
  return new Worker(new URL('./fff_worker.ts', import.meta.url));
}

/**
 * A finder over `basePath`, made in its Worker at the first call. A synchronous
 * FFI call cannot be interrupted, so an aborted call ends its Worker, and the
 * next call starts another that scans the directory again: the rescan is what
 * honouring the signal costs. Calls the abort did not concern are sent again.
 */
export function openFinder(
  basePath: string,
  makeWorker: () => FffWorker = fffWorker,
): Finder {
  let worker: FffWorker | undefined;
  let destroyed = false;
  let next = 0;
  const pending = new Map<number, Pending>();

  const post = (id: number, call: Call) => {
    worker ??= spawn();

    worker.postMessage({ ...call, id, basePath } satisfies FffRequest);
  };

  const spawn = (): FffWorker => {
    const made = makeWorker();

    // A Worker retired by an abort may still deliver: its answers belong to
    // calls now sent again to its successor, so only the current one counts.
    made.onmessage = ({ data }) => {
      const waiting = worker === made ? pending.get(data.id) : undefined;

      if (waiting === undefined) {
        return;
      }

      pending.delete(data.id);

      if (data.ok) {
        waiting.resolve(data.value);
      } else {
        waiting.reject(new Error(`fff: ${data.error}`));
      }
    };

    // A Worker that failed takes every call in it; the next call starts anew.
    made.onerror = (event) => {
      event.preventDefault();

      if (worker !== made) {
        return;
      }

      // An error need not have ended the Worker; nothing is left running.
      retire(made);

      worker = undefined;

      const failed = [...pending.values()];

      pending.clear();

      for (const { reject } of failed) {
        reject(new Error(`fff: the search worker failed: ${event.message}`));
      }
    };

    return made;
  };

  const retire = (old: FffWorker) => {
    old.onmessage = null;
    old.onerror = null;

    old.terminate();
  };

  const restart = () => {
    if (worker !== undefined) {
      retire(worker);
    }

    worker = undefined;

    for (const [id, { call }] of pending) {
      post(id, call);
    }
  };

  const request = <T>(call: Call, signal: AbortSignal): Promise<T> => {
    if (destroyed) {
      return Promise.reject(new Error('fff: the finder is destroyed'));
    }

    if (signal.aborted) {
      return Promise.reject(signal.reason);
    }

    const id = next++;
    const { promise, resolve, reject } = Promise.withResolvers<unknown>();
    const onAbort = () => {
      if (pending.delete(id)) {
        reject(signal.reason);
        restart();
      }
    };

    pending.set(id, { call, resolve, reject });
    signal.addEventListener('abort', onAbort, { once: true });
    post(id, call);

    return promise.finally(() => {
      signal.removeEventListener('abort', onAbort);
    }) as Promise<T>;
  };

  return {
    grep: (query, options, signal) =>
      request({ op: 'grep', query, options }, signal),
    glob: (pattern, options, signal) =>
      request({ op: 'glob', pattern, options }, signal),
    directorySearch: (query, options, signal) =>
      request({ op: 'directorySearch', query, options }, signal),
    destroy: async () => {
      if (destroyed) {
        return;
      }

      destroyed = true;

      const running = worker;

      worker = undefined;

      const failed = [...pending.values()];

      pending.clear();

      for (const { reject } of failed) {
        reject(new Error('fff: the finder is destroyed'));
      }

      if (running === undefined) {
        return;
      }

      // The finder frees its index and watcher when the Worker reaches the
      // request, after any call still running there; the bound cuts off one
      // that never ends. Earlier calls' answers are not the destroy's.
      const freed = Promise.withResolvers<void>();

      running.onmessage = ({ data }) => {
        if (data.id === DESTROY_ID) {
          freed.resolve();
        }
      };

      running.onerror = () => freed.resolve();

      running.postMessage({
        id: DESTROY_ID,
        basePath,
        op: 'destroy',
      } satisfies FffRequest);

      const timer = setTimeout(freed.resolve, DESTROY_MS);

      await freed.promise;
      clearTimeout(timer);
      retire(running);
    },
  };
}
