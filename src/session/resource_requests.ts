/** Temporary factual reads own relevance, never a provider or an allocation. */
import { performance } from 'node:perf_hooks';

export const RESOURCE_REQUEST_MS = 30_000;

interface Request {
  readonly caller: object;
  readonly generation: object;
  readonly agents: readonly string[];
  readonly signal: AbortSignal;
  readonly valid: () => boolean;
  readonly turnId?: string;
  readonly admittedAt: number;
}

interface Owner {
  readonly generation: object;
  readonly filter: string;
  readonly deadline: number;
  turnId: string | undefined;
  signal: AbortSignal;
  valid: () => boolean;
  readonly release: () => void;
}

/** One current filter per caller; ResourceAccess still owns shared reads. */
export class ResourceRequests {
  readonly #owners = new Map<object, Owner>();
  readonly #retain: (
    agents: readonly string[],
    signal: AbortSignal,
    valid: () => boolean,
  ) => () => void;
  readonly #now: () => number;
  readonly #after: (milliseconds: number, release: () => void) => () => void;

  constructor(
    retain: (
      agents: readonly string[],
      signal: AbortSignal,
      valid: () => boolean,
    ) => () => void,
    options: {
      readonly now?: () => number;
      readonly after?: (
        milliseconds: number,
        release: () => void,
      ) => () => void;
    } = {},
  ) {
    this.#retain = retain;
    this.#now = options.now ?? (() => performance.now());
    this.#after =
      options.after ??
      ((milliseconds, release) => {
        const timer = setTimeout(release, milliseconds);

        return () => clearTimeout(timer);
      });
  }

  retain(request: Request): void {
    const deadline = request.admittedAt + RESOURCE_REQUEST_MS;

    // A late request has no authority over a replacement's existing owner.
    if (this.#now() >= deadline || request.signal.aborted || !request.valid()) {
      return;
    }

    const agents = [...new Set(request.agents)].sort();
    const filter = JSON.stringify(agents);
    const previous = this.#owners.get(request.caller);

    if (
      previous !== undefined &&
      previous.generation === request.generation &&
      previous.filter === filter &&
      this.#now() < previous.deadline &&
      (previous.turnId === undefined || previous.turnId === request.turnId)
    ) {
      // Only the current request's cancellation listener is retained; repeats
      // neither accumulate listeners nor move the original expiry.
      previous.signal.removeEventListener('abort', previous.release);

      previous.signal = request.signal;
      previous.valid = request.valid;
      previous.turnId ??= request.turnId;

      request.signal.addEventListener('abort', previous.release, {
        once: true,
      });

      return;
    }

    previous?.release();

    if (agents.length === 0) {
      return;
    }

    const abort = new AbortController();
    let released = false;
    let releaseResources = () => {};

    let cancelTimer = () => {};

    const owner: Owner = {
      generation: request.generation,
      filter,
      deadline,
      turnId: request.turnId,
      signal: request.signal,
      valid: request.valid,
      release: () => {
        if (released) {
          return;
        }

        released = true;

        owner.signal.removeEventListener('abort', owner.release);
        cancelTimer();
        abort.abort();
        releaseResources();

        if (this.#owners.get(request.caller) === owner) {
          this.#owners.delete(request.caller);
        }
      },
    };

    this.#owners.set(request.caller, owner);
    owner.signal.addEventListener('abort', owner.release, { once: true });

    cancelTimer = this.#after(deadline - this.#now(), owner.release);

    try {
      releaseResources = this.#retain(
        agents,
        abort.signal,
        () => !released && owner.valid(),
      );
    } catch (error) {
      owner.release();

      throw error;
    }

    // A synchronous retain callback can revoke the caller before it returns.
    if (released) {
      releaseResources();
    } else if (request.signal.aborted || !request.valid()) {
      owner.release();
    }
  }

  /** An actual terminal event ends only its own turn's temporary interest. */
  ended(caller: object, turnId: string): void {
    const owner = this.#owners.get(caller);

    if (owner?.turnId === turnId) {
      owner.release();
    }
  }

  release(caller: object): void {
    this.#owners.get(caller)?.release();
  }

  close(): void {
    for (const owner of this.#owners.values()) {
      owner.release();
    }
  }
}
