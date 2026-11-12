/**
 * A Port over no Cursor at all, for serve_test and the fixture: agents and
 * runs in memory, each run driven by a script of the SDK's own deltas and
 * stream messages, and a log of every call with the key it was given.
 */
import type {
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
  createdAt?: number,
): FakeRun {
  let cancelled = false;
  let finish: (result: RunResult) => void = () => undefined;
  const ended = new Promise<RunResult>((resolve) => {
    finish = resolve;
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
    ...(createdAt === undefined ? {} : { createdAt }),
    get cancelled() {
      return cancelled;
    },
    supports: (operation) => operation !== 'conversation' || !script.hang,
    unsupportedReason: (operation) =>
      operation === 'conversation' && script.hang ? 'Still running' : undefined,
    conversation: () =>
      Promise.resolve([
        {
          type: 'agentConversationTurn',
          turn: {
            userMessage: { text: `asked ${id}` },
            steps: [
              { type: 'assistantMessage', message: { text: `answered ${id}` } },
            ],
          },
        },
      ]),
    async *stream() {
      for (const message of script.messages ?? []) {
        yield message;
      }

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
  /** Created and not yet sent to: unknown to Cursor. */
  const pending = new Map<string, SDKAgentInfo>();
  let next = 0;
  let clock = Date.now();

  const agent = (agentId: string, model?: ModelSelection): PortAgent => {
    let current = model;

    return {
      agentId,
      get model() {
        return current;
      },
      close: () => void closed.push(agentId),
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

        // Strictly later than the last, as two runs may start in one millisecond.
        const run = fakeRun(agentId, script, options?.onDelta, (clock += 1));

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

      return Promise.resolve({
        items: [...(runs.get(agentId) ?? [])].reverse(),
      });
    },
  };

  return { port, calls, keys, models, listed, scripts, runs, closed };
}
