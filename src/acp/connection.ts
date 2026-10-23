import * as acp from '@agentclientprotocol/sdk';
import manifest from '../../package.json' with { type: 'json' };
import type { Exit } from '../platform/process.ts';
import {
  type AgentProcess,
  settledWithin,
  STDERR_SETTLE_MS,
  type Tail,
  spawnAgent,
  type StopBounds,
} from './process.ts';
import {
  cursorPlan,
  grokPlan,
  PLAN_CANCELLED,
  PLAN_METHODS,
  type PlanRequest,
  type PlanResponse,
} from './plans.ts';
import { type Relay, relayStream, tapStream, type Traffic } from './traffic.ts';

/**
 * The elicitation modes chord draws: a form of flat fields, and a link to
 * open. `initialize` declares them, and a request in any other mode is
 * cancelled without reaching the person.
 */
export const ELICITATION_MODES = ['form', 'url'] as const;

export type ElicitationMode = (typeof ELICITATION_MODES)[number];

export interface OpenAgentOptions {
  /** A command line or an argv, as `agentStart` gives it. */
  readonly command: string | readonly string[];
  /** Laid over chord's own environment for the agent alone. */
  readonly env?: Readonly<Record<string, string>>;
  /** Where the process starts; each session names its own directory too. */
  readonly cwd: string;
  /**
   * Stands between the agent's stdio and everything else, the subscriber
   * included, so what it fills in is all that chord ever reads.
   */
  readonly relay?: Relay;
  /**
   * The one subscriber: every message either way, in wire order as the relay
   * leaves it, and the agent's stderr. It must not throw; nothing is filtered
   * for it.
   */
  readonly onTraffic: (traffic: Traffic) => void;
  /**
   * Answers a permission request. The signal aborts once the answer stops
   * mattering — its session's turn was cancelled, the agent withdrew it, or
   * the agent is closing — and chord has answered `cancelled` itself.
   */
  readonly onPermission: (
    request: acp.RequestPermissionRequest,
    signal: AbortSignal,
  ) => Promise<acp.RequestPermissionResponse>;
  /** Answers a form or a link the agent asks for; the signal as above. */
  readonly onElicitation: (
    request: acp.CreateElicitationRequest,
    signal: AbortSignal,
  ) => Promise<acp.CreateElicitationResponse>;
  /**
   * Answers a plan cursor or grok puts to the person, or one that did not
   * read, `undefined`, which is answered `cancelled`; the signal as above
   * (CHD-437, CHD-457). None: every plan is answered `cancelled`.
   */
  readonly onPlan?: (
    request: PlanRequest | undefined,
    signal: AbortSignal,
  ) => Promise<PlanResponse>;
  /** Gives up on a start: the agent is stopped and the open rejects. */
  readonly signal?: AbortSignal;
  /** How long `close()` waits at each step; chord's own bounds by default. */
  readonly stop?: StopBounds;
}

/**
 * `session/set_model`, which ACP v1 has not made stable: chord asks it only
 * of an agent that offers models but no `model` config option, as cursor's
 * and dimcode's adapters answer it. Claude's adapter has no handler for it
 * (claude-agent-acp 0.93.0) and is asked through its `model` config option.
 */
export interface SetSessionModelRequest {
  readonly sessionId: string;
  readonly modelId: string;
}

/**
 * `_session/steering`, the steering extension Claude's and Codex's adapters
 * answer and ACP's schema does not have yet: a prompt put into the turn the
 * session is running. `promptRequired` asks an agent with no turn running to
 * answer so and do nothing; Claude's adapter honours it, Codex's does not.
 */
export interface SteerRequest {
  readonly sessionId: string;
  readonly prompt: readonly acp.ContentBlock[];
  readonly _meta?: {
    readonly steering?: { readonly idleBehavior?: 'promptRequired' };
  };
}

/**
 * The agent's answer to a steer, unchecked: `injected` into the running turn,
 * `startedNewTurn` of its own, `promptRequired` with nothing done, or
 * Codex's `failed`.
 */
export type SteerResponse = Readonly<Record<string, unknown>>;

/**
 * A running agent and its ACP connection, initialised, until `close()`. Every
 * request takes a signal that stops the wait for its answer.
 */
export interface Agent {
  readonly pid: number;
  /** The agent's answer to `initialize`: its version, capabilities and info. */
  readonly init: acp.InitializeResponse;
  /**
   * Whether the agent takes `_session/steering`, as its answer to
   * `initialize` says under `_meta.steering.supported`.
   */
  readonly steering: boolean;
  /**
   * Settles once the agent's exit is seen, however it came, and what it left
   * on stderr has come, or could not in time (CHD-495).
   */
  readonly exited: Promise<Exit>;
  /**
   * Once the agent's connection has gone, the end of what it wrote to stderr,
   * empty when it left nothing; undefined while it is up. A turn that failed
   * with this set failed because the agent went.
   */
  gone(): string | undefined;
  newSession(
    request: acp.NewSessionRequest,
    signal?: AbortSignal,
  ): Promise<acp.NewSessionResponse>;
  /** Throws without asking when the agent does not offer `session/load`. */
  loadSession(
    request: acp.LoadSessionRequest,
    signal?: AbortSignal,
  ): Promise<acp.LoadSessionResponse>;
  /** Throws without asking when the agent does not offer `session/resume`. */
  resumeSession(
    request: acp.ResumeSessionRequest,
    signal?: AbortSignal,
  ): Promise<acp.ResumeSessionResponse>;
  /** Throws without asking when the agent does not offer `session/list`. */
  listSessions(
    request: acp.ListSessionsRequest,
    signal?: AbortSignal,
  ): Promise<acp.ListSessionsResponse>;
  /**
   * Sends a prompt and settles with the agent's answer. Its updates, and any
   * the agent sends after answering, come to the subscriber, not here. The
   * signal stops the wait and cancels the turn too.
   */
  prompt(
    request: acp.PromptRequest,
    signal?: AbortSignal,
  ): Promise<acp.PromptResponse>;
  /**
   * Asks the agent to stop the session's turn, and answers `cancelled` to the
   * permission requests and session forms it has waiting, as ACP asks, and to
   * those of `subagents`, the sessions the turn's subagents run in, whose
   * work the turn's cancel stops too; the prompt then settles with the
   * agent's own answer.
   */
  cancel(sessionId: string, subagents?: Iterable<string>): Promise<void>;
  /**
   * Asks the agent to stop one subagent's work alone, by its own session id,
   * as one that announced `capabilities.cancel` takes it. Its requests stay
   * open until the agent withdraws them; rejects when the notice cannot go.
   */
  stopSubagent(sessionId: string): Promise<void>;
  setConfigOption(
    request: acp.SetSessionConfigOptionRequest,
    signal?: AbortSignal,
  ): Promise<acp.SetSessionConfigOptionResponse>;
  setMode(
    request: acp.SetSessionModeRequest,
    signal?: AbortSignal,
  ): Promise<acp.SetSessionModeResponse>;
  setModel(
    request: SetSessionModelRequest,
    signal?: AbortSignal,
  ): Promise<unknown>;
  /** Throws without asking when the agent does not offer steering. */
  steer(request: SteerRequest, signal?: AbortSignal): Promise<SteerResponse>;
  /**
   * Stops the agent within the bounds whatever it answers, and returns once
   * its exit is seen and what it wrote before going has reached the
   * subscriber; rejects with `AgentExitError` if that exit is not seen even
   * after SIGKILL. Idempotent.
   */
  close(): Promise<void>;
}

/** How long, past the exit, the rest of stdout gets to reach the subscriber. */
const DRAIN_MS = 1000;

/**
 * What chord tells an agent it can do: forms and links, plans by id (Codex's
 * adapter sends its plan as reply text to a client that does not say so),
 * compactions by id (Claude's and Codex's adapters send one otherwise as a
 * tool call, which carries no summary), subagents as sessions of their own
 * (Claude's adapter otherwise stamps a child's updates into its parent's
 * under a `_meta` of its own, and Codex's sends none of them), and nothing of
 * files or terminals, so agents use their own tools for those.
 * `terminal_output_delta` asks for what those tools' commands write as
 * `_meta` on the tool call, which chord draws itself: Claude's adapter sends
 * it only to a client that says so, and a block of text otherwise. droid and
 * pi send `terminal_output` as a delta, the new part alone under the name
 * chord reads as the whole output; droid, asked for the delta, sends the
 * whole output as text instead, and asked for `terminal_output` would show
 * only its last chunk (docs/agent-capabilities.md dr12, pi10). chord keeps
 * one reading for every agent on purpose (CHD-456).
 */
const CLIENT_CAPABILITIES: acp.ClientCapabilities = {
  elicitation: Object.fromEntries(ELICITATION_MODES.map((mode) => [mode, {}])),
  plan: {},
  session: { compaction: {} },
  subagents: {},
  _meta: { terminal_output_delta: true },
};

/**
 * Starts the agent, connects to it on its stdio and initialises ACP v1.
 * Rejects, with the agent stopped, if it cannot start, will not initialise,
 * or the signal aborts first.
 */
export async function openAgent(options: OpenAgentOptions): Promise<Agent> {
  options.signal?.throwIfAborted();

  const process = await spawnAgent({
    command: options.command,
    ...(options.env === undefined ? {} : { env: options.env }),
    cwd: options.cwd,
    onStderr: (text) => options.onTraffic({ from: 'stderr', text }),
  });

  return await connectAgent(process, options);
}

/**
 * `openAgent`'s connection over an agent process already started: apart,
 * so a test can drive the process's pipes in the order it needs (CHD-495).
 */
export async function connectAgent(
  process: AgentProcess,
  options: OpenAgentOptions,
): Promise<Agent> {
  /** What each session has waiting on the person, to cancel with its turn. */
  const waiting = new Map<string, Set<AbortController>>();
  const closing = new AbortController();

  /**
   * Runs a handler for a request the agent sent, answering `fallback` once
   * the answer stops mattering or the handler fails, whichever comes first.
   */
  const answer = <T>(
    sessionId: string | undefined,
    requestSignal: AbortSignal,
    fallback: T,
    handler: (signal: AbortSignal) => Promise<T>,
  ): Promise<T> => {
    const controller = new AbortController();
    const signal = AbortSignal.any([
      controller.signal,
      requestSignal,
      closing.signal,
    ]);
    const held =
      sessionId === undefined
        ? undefined
        : (waiting.get(sessionId) ?? new Set());

    if (sessionId !== undefined && held !== undefined) {
      held.add(controller);
      waiting.set(sessionId, held);
    }

    return new Promise<T>((resolve) => {
      const withdrawn = () => resolve(fallback);

      if (signal.aborted) {
        return withdrawn();
      }

      signal.addEventListener('abort', withdrawn, { once: true });
      handler(signal).then(resolve, withdrawn);
    }).finally(() => {
      held?.delete(controller);

      if (sessionId !== undefined && held?.size === 0) {
        waiting.delete(sessionId);
      }
    });
  };

  const app = acp
    .client({ name: 'chord' })
    .onRequest('session/request_permission', ({ params, signal }) =>
      answer(
        params.sessionId,
        signal,
        { outcome: { outcome: 'cancelled' } },
        (signal) => options.onPermission(params, signal),
      ),
    )
    .onRequest('elicitation/create', ({ params, signal }) => {
      const cancel: acp.CreateElicitationResponse = { action: 'cancel' };

      if (!(ELICITATION_MODES as readonly string[]).includes(params.mode)) {
        return cancel;
      }

      const sessionId =
        'sessionId' in params && typeof params.sessionId === 'string'
          ? params.sessionId
          : undefined;

      return answer(sessionId, signal, cancel, (signal) =>
        options.onElicitation(params, signal),
      );
    });

  // A plan is the person's to take: one that does not read, or that nobody
  // answers, is `cancelled`, never method-not-found, which cursor reads as
  // accepted (CHD-437, CHD-457).
  for (const [method, read] of [
    [PLAN_METHODS.cursor, cursorPlan],
    [PLAN_METHODS.grok, grokPlan],
  ] as const) {
    app.onRequest<PlanRequest | undefined, PlanResponse>(
      method,
      (params) => read(params),
      ({ params, signal }) =>
        options.onPlan === undefined
          ? PLAN_CANCELLED
          : answer(params?.sessionId, signal, PLAN_CANCELLED, (signal) =>
              options.onPlan!(params, signal),
            ),
    );
  }

  const wire = acp.ndJsonStream(process.stdin, process.stdout);
  const connection = app.connect(
    tapStream(
      options.relay === undefined ? wire : relayStream(wire, options.relay),
      options.onTraffic,
    ),
  );

  /**
   * The agent's exit as an error, once its last words have come; the
   * caller's abort while they are awaited ends the wait at once, with its
   * own reason (CHD-495).
   */
  const exitError = (signal: AbortSignal | undefined): Promise<unknown> =>
    new Promise((resolve) => {
      const aborted = () => resolve(signal?.reason);

      signal?.addEventListener('abort', aborted, { once: true });
      void goneError(process).then((gone) => {
        signal?.removeEventListener('abort', aborted);
        resolve(gone);
      });
    });

  /**
   * Waits for the agent's answer, giving up on the signal or on the agent's
   * exit, whichever comes first.
   */
  const ask = async <T>(
    send: () => Promise<T>,
    signal: AbortSignal | undefined,
  ): Promise<T> => {
    let stop: (() => void) | undefined;
    const gone = AbortSignal.any([
      connection.signal,
      ...(signal === undefined ? [] : [signal]),
    ]);

    // Withdrawn work must not reach the agent: a rejected set_mode that still
    // changed the mode, or a prompt that still started a turn, lies to the caller.
    if (gone.aborted) {
      throw signal?.aborted ? signal.reason : await exitError(signal);
    }

    // A request the closed connection fails is the agent's exit too, said
    // with its last words, which can come after the close (CHD-495).
    const request = send().catch(async (error: unknown) => {
      if (!signal?.aborted && connection.signal.aborted) {
        throw await exitError(signal);
      }

      throw error;
    });

    request.catch(() => {});

    try {
      return await Promise.race([
        request,
        new Promise<never>((_, reject) => {
          stop = () => {
            if (signal?.aborted) {
              reject(signal.reason);
            } else {
              void exitError(signal).then(reject);
            }
          };

          if (gone.aborted) {
            stop();
          } else {
            gone.addEventListener('abort', stop, { once: true });
          }
        }),
      ]);
    } finally {
      if (stop) {
        gone.removeEventListener('abort', stop);
      }
    }
  };

  let closed: Promise<void> | undefined;

  const close = () =>
    (closed ??= (async () => {
      closing.abort();

      try {
        await process.stop(options.stop);
      } finally {
        // stdout ends once the group is gone; what it held still counts.
        await settledWithin(connection.closed, DRAIN_MS);
        connection.close();
      }
    })());

  let init: acp.InitializeResponse;

  try {
    init = await ask(
      () =>
        connection.agent.request('initialize', {
          protocolVersion: acp.PROTOCOL_VERSION,
          clientCapabilities: CLIENT_CAPABILITIES,
          clientInfo: { name: 'chord', version: manifest.version },
        }),
      options.signal,
    );
  } catch (error) {
    await close();

    throw error;
  }

  const offers = init.agentCapabilities ?? {};

  const offered = (method: string, yes: unknown) => {
    if (!yes) {
      throw new Error(`The agent does not offer ${method}.`);
    }
  };

  const steering = steeringOf(init);
  // What the agent left on stderr, once it has gone and all of it has come.
  let lastWords: string | undefined;

  const agent: Agent = {
    pid: process.pid,
    init,
    steering,
    // Once its last words have come too, which `gone` then gives whole.
    exited: process.status.then(async (exit) => {
      lastWords = (await process.lastWords()).trim();

      return exit;
    }),
    gone: () =>
      connection.signal.aborted
        ? (lastWords ?? process.stderrTail().trim())
        : undefined,
    newSession: (request, signal) =>
      ask(() => connection.agent.request('session/new', request), signal),
    loadSession: async (request, signal) => {
      offered('session/load', offers.loadSession);

      return await ask(
        () => connection.agent.request('session/load', request),
        signal,
      );
    },
    resumeSession: async (request, signal) => {
      offered('session/resume', offers.sessionCapabilities?.resume);

      return await ask(
        () => connection.agent.request('session/resume', request),
        signal,
      );
    },
    listSessions: async (request, signal) => {
      offered('session/list', offers.sessionCapabilities?.list);

      return await ask(
        () => connection.agent.request('session/list', request),
        signal,
      );
    },
    prompt: async (request, signal) => {
      const cancel = () => void agent.cancel(request.sessionId).catch(() => {});

      signal?.addEventListener('abort', cancel, { once: true });

      try {
        return await ask(
          () => connection.agent.request('session/prompt', request),
          signal,
        );
      } finally {
        signal?.removeEventListener('abort', cancel);
      }
    },
    cancel: async (sessionId, subagents = []) => {
      for (const each of [sessionId, ...subagents]) {
        for (const controller of waiting.get(each) ?? []) {
          controller.abort();
        }
      }

      await connection.agent.notify('session/cancel', { sessionId });
    },
    stopSubagent: (sessionId) =>
      connection.agent.notify('session/cancel', { sessionId }),
    setConfigOption: (request, signal) =>
      ask(
        () => connection.agent.request('session/set_config_option', request),
        signal,
      ),
    setMode: (request, signal) =>
      ask(() => connection.agent.request('session/set_mode', request), signal),
    setModel: (request, signal) =>
      ask(() => connection.agent.request('session/set_model', request), signal),
    steer: async (request, signal) => {
      offered('_session/steering', steering);

      return await ask(
        () =>
          connection.agent.request<SteerResponse, SteerRequest>(
            '_session/steering',
            request,
          ),
        signal,
      );
    },
    close,
  };

  return agent;
}

/** Whether `initialize`'s answer advertises `_session/steering`. */
function steeringOf(init: acp.InitializeResponse): boolean {
  const steering: unknown = init._meta?.['steering'];

  return (
    typeof steering === 'object' &&
    steering !== null &&
    'supported' in steering &&
    steering.supported === true
  );
}

/**
 * The agent's process ended before it answered: how, and what it wrote to
 * stderr last, for a start failure to say (CHD-454).
 */
export class AgentGone extends Error {
  constructor(
    message: string,
    /** How its process ended, when that was seen. */
    readonly exit: Exit | undefined,
    /** The end of its stderr, as lines. */
    readonly stderr: Tail,
  ) {
    super(message);

    this.name = 'AgentGone';
  }
}

/**
 * The agent went, with the end of its stderr when it left any, once that
 * has all come (CHD-495), and how its process ended if that is seen by
 * then: one that closed its stdout and lives on is not waited for.
 */
async function goneError(process: AgentProcess): Promise<AgentGone> {
  const tail = (await process.lastWords()).trim();
  const exit = await settledWithin(process.status, STDERR_SETTLE_MS);

  return new AgentGone(
    tail === '' ? 'The agent exited.' : `The agent exited: ${tail}`,
    exit?.status === 'fulfilled' ? exit.value : undefined,
    process.stderrEnd(),
  );
}
