/**
 * A Port over no Cursor at all, for serve_test and the fixture: agents and
 * runs in memory, each run driven by a script of the SDK's own deltas and
 * stream messages, and a log of every call with the key it was given.
 */
import type {
  ConversationTurn,
  InteractionUpdate,
  ListResult,
  ModelListItem,
  ModelSelection,
  RunResult,
  SDKAgentInfo,
  SDKMessage,
  SendOptions,
} from '@cursor/sdk';
import { CursorError } from '../../src/errors.ts';
import type { Port, PortAgent, PortRun } from '../../src/port.ts';

/** What one send does: deltas through onDelta, messages on the stream, an end. */
export interface Script {
  readonly deltas?: readonly InteractionUpdate[];
  readonly messages?: readonly SDKMessage[];
  readonly result?: Partial<RunResult>;
  /** A run that never ends by itself: only a cancel ends it. */
  readonly hang?: boolean;
  /** The send itself fails. */
  readonly refuse?: CursorError;
  /** The stream loses its connection after its messages; the run goes on. */
  readonly lose?: boolean;
  /** What conversation() gives; else one turn naming the run. */
  readonly conversation?: readonly ConversationTurn[];
}

/** One call the adapter made, with the key it passed. */
export interface Call {
  readonly method: string;
  readonly apiKey: string | undefined;
  readonly args?: unknown;
}

export interface FakeCursor {
  readonly port: Port;
  readonly calls: Call[];
  /** Keys Cursor takes; any other is refused as the SDK refuses it. */
  readonly keys: Set<string>;
  readonly models: ModelListItem[];
  /** Agents Cursor knows, as Agent.list gives them, newest first. */
  readonly listed: SDKAgentInfo[];
  /** What the next sends do, in order; an empty queue answers "ok". */
  readonly scripts: Script[];
  /** Past runs per agent, for resume and load. */
  readonly runs: Map<string, FakeRun[]>;
  /** Agents closed, by id. */
  readonly closed: string[];
  /** How many runs listRuns gives a page; all of them when unset. */
  pageSize: number | undefined;
  /** What Agent.get does; by default answers for an agent Cursor knows. */
  failGet: Error | undefined;
  /** Each send's onDelta, so a test can deliver an update late. */
  readonly onDeltas: NonNullable<SendOptions['onDelta']>[];
}

export interface FakeRun extends PortRun {
  readonly cancelled: boolean;
}

const auth = (key: string | undefined, keys: Set<string>) => {
  if (key === undefined || !keys.has(key)) {
    throw new CursorError('auth', 'Invalid API key', {
      sdkClass: 'AuthenticationError',
    });
  }
};

/** A finished or scripted run of agent `agentId`. */
export function fakeRun(
  agentId: string,
  script: Script,
  onDelta?: SendOptions['onDelta'],
): FakeRun {
  let cancelled = false;
  let finish: (result: RunResult) => void = () => undefined;
  // Deltas wait for the stream's messages, which come first in a run
  // (a CREATING status before any tool).
  let streamed: () => void = () => undefined;
  const messagesDrawn = new Promise<void>((resolve) => {
    streamed = resolve;
  });

  let status: RunResult['status'] | 'running' = 'running';
  const ended = new Promise<RunResult>((resolve) => {
    finish = (done) => {
      status = done.status;

      resolve(done);
    };
  });

  const id = `run-${Math.random().toString(36).slice(2, 8)}`;
  const result = (status: RunResult['status']): RunResult => ({
    id,
    status,
    ...script.result,
  });
  const run: FakeRun = {
    id,
    agentId,
    get cancelled() {
      return cancelled;
    },
    get status() {
      return status;
    },
    supports: (operation) => operation !== 'conversation' || !script.hang,
    unsupportedReason: (operation) =>
      operation === 'conversation' && script.hang ? 'Still running' : undefined,
    conversation: () =>
      Promise.resolve(
        script.conversation
          ? [...script.conversation]
          : [
              {
                type: 'agentConversationTurn',
                turn: {
                  userMessage: { text: `asked ${id}` },
                  steps: [
                    {
                      type: 'assistantMessage',
                      message: { text: `answered ${id}` },
                    },
                  ],
                },
              },
            ],
      ),
    async *stream() {
      for (const message of script.messages ?? []) {
        yield message;
      }

      streamed();

      if (script.lose === true) {
        throw new CursorError('network', 'Connection reset', {
          sdkClass: 'NetworkError',
        });
      }
    },
    wait: () => ended,
    cancel: () => {
      cancelled = true;

      finish(result('cancelled'));

      return Promise.resolve();
    },
  };

  void (async () => {
    if ((script.messages ?? []).length > 0) {
      await messagesDrawn;
    }

    for (const update of script.deltas ?? []) {
      await onDelta?.({ update });
    }

    if (!script.hang && script.lose !== true) {
      finish(result(script.result?.status ?? 'finished'));
    }
  })();

  return run;
}

/**
 * A Cursor in memory. `scriptFor` picks a send's script from its text when
 * the queue is empty, as the fixture's scenarios do.
 */
export function fakeCursor(
  scriptFor?: (text: string) => Script | undefined,
): FakeCursor {
  const calls: Call[] = [];
  const keys = new Set<string>(['key_good']);
  const models: ModelListItem[] = [
    {
      id: 'composer-2',
      displayName: 'Composer 2',
      variants: [{ displayName: 'Composer 2', params: [] }],
    },
  ];
  const listed: SDKAgentInfo[] = [];
  const scripts: Script[] = [];
  const runs = new Map<string, FakeRun[]>();
  const closed: string[] = [];
  const onDeltas: NonNullable<SendOptions['onDelta']>[] = [];
  /** Created and not yet sent to: unknown to Cursor. */
  const pending = new Map<string, SDKAgentInfo>();
  let next = 0;

  const agent = (agentId: string, model?: ModelSelection): PortAgent => {
    let current = model;

    return {
      agentId,
      get model() {
        return current;
      },
      [Symbol.asyncDispose]: () => {
        closed.push(agentId);

        return Promise.resolve();
      },
      listArtifacts: () => Promise.resolve([]),
      send: (message, options) => {
        calls.push({
          method: 'send',
          apiKey: undefined,
          args: { message, options: { ...options, onDelta: undefined } },
        });

        const created = pending.get(agentId);

        if (created !== undefined) {
          pending.delete(agentId);
          listed.unshift(created);
        }

        const text = typeof message === 'string' ? message : message.text;
        const script = scripts.shift() ??
          scriptFor?.(text) ?? {
            deltas: [{ type: 'text-delta', text: 'ok' }],
          };

        if (script.refuse !== undefined) {
          return Promise.reject(script.refuse);
        }

        if (options?.model !== undefined) {
          current = options.model;
        }

        if (options?.onDelta !== undefined) {
          onDeltas.push(options.onDelta);
        }

        const run = fakeRun(agentId, script, options?.onDelta);

        runs.set(agentId, [...(runs.get(agentId) ?? []), run]);

        return Promise.resolve(run);
      },
    };
  };

  const known = (agentId: string) => {
    if (!listed.some((each) => each.agentId === agentId)) {
      throw new CursorError('not-found', `Agent ${agentId} not found`, {
        sdkClass: 'AgentNotFoundError',
        code: 'agent_not_found',
      });
    }
  };

  const port: Port = {
    me: (options) => {
      calls.push({ method: 'me', apiKey: options?.apiKey });
      auth(options?.apiKey, keys);

      return Promise.resolve({ apiKeyName: 'test', createdAt: '2026-11-01' });
    },
    models: (options) => {
      calls.push({ method: 'models', apiKey: options?.apiKey });

      return Promise.resolve(models);
    },
    login: () => Promise.reject(new Error('no login in tests')),
    logout: () => Promise.reject(new Error('no logout in tests')),
    status: () => Promise.reject(new Error('no status in tests')),
    create: (options) => {
      calls.push({ method: 'create', apiKey: options.apiKey, args: options });
      auth(options.apiKey, keys);

      const agentId = `bc-${(next += 1)}`;

      // Lazy, as Cursor's is (Q9): Cursor knows the agent from its first send.
      pending.set(agentId, {
        agentId,
        name: `Agent ${next}`,
        summary: '',
        lastModified: Date.now(),
        runtime: 'cloud',
        repos: options.cloud?.repos?.map((repo) => repo.url) ?? [],
      });

      return Promise.resolve(agent(agentId));
    },
    resume: (agentId, options) => {
      calls.push({ method: 'resume', apiKey: options.apiKey, args: agentId });
      auth(options.apiKey, keys);
      known(agentId);

      return Promise.resolve(agent(agentId));
    },
    list: (options) => {
      calls.push({
        method: 'list',
        apiKey: options?.runtime === 'cloud' ? options.apiKey : undefined,
        args: options,
      });

      return Promise.resolve({
        items: listed,
      } satisfies ListResult<SDKAgentInfo>);
    },
    listRuns: (agentId, options) => {
      calls.push({
        method: 'listRuns',
        apiKey: options.runtime === 'cloud' ? options.apiKey : undefined,
        args: agentId,
      });
      known(agentId);

      // Newest first, as Cursor's listRuns gives them (Q9, fact 3).
      const all = [...(runs.get(agentId) ?? [])].reverse();
      const from = Number(options.cursor ?? 0);
      const size = fake.pageSize ?? all.length;
      const items = all.slice(from, from + size);

      return Promise.resolve({
        items,
        ...(from + size < all.length
          ? { nextCursor: String(from + size) }
          : {}),
      });
    },
    get: (agentId, options) => {
      calls.push({ method: 'get', apiKey: options?.apiKey, args: agentId });

      if (fake.failGet !== undefined) {
        return Promise.reject(fake.failGet);
      }

      known(agentId);

      return Promise.resolve(listed.find((each) => each.agentId === agentId)!);
    },
  };
  const fake: FakeCursor = {
    port,
    calls,
    keys,
    models,
    listed,
    scripts,
    runs,
    closed,
    pageSize: undefined,
    failGet: undefined,
    onDeltas,
  };

  return fake;
}
