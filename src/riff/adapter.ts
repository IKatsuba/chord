/**
 * riff's ACP agent: libfx turned into an ACP agent on the SDK's agent side,
 * over any `Stream`, so tests drive it over an in-memory pair (CHD-485, "The
 * protocol between the window and riff"). What is not here is -32601.
 */
import {
  agent,
  type AgentConnection,
  type AgentContext,
  type ContentBlock,
  type InitializeResponse,
  type PermissionOption,
  RequestError,
  type SessionUpdate,
  type Stream,
  type ToolCallUpdate,
} from '@agentclientprotocol/sdk/unstable';
import {
  createFxAgent,
  type FxAgent,
  type FxAgentTools,
  type FxNodeBackendOptions,
  type FxSessionPromptInput,
} from 'libfx/node';
import { realpath } from 'node:fs/promises';
import { type Finder, openFinder } from '../platform/fff.ts';
import {
  type HookUsage,
  stopReasonOf,
  updateOf,
  usageOf,
  usedOf,
} from './events.ts';
import {
  configOptions,
  defaultConfig,
  type RiffConfig,
  type RiffPlan,
  setOption,
  windowOf,
} from './models.ts';
import { RIFF } from './start.ts';
import type { Grants } from './tools/permission.ts';
import { drawn, riffTools } from './tools/tools.ts';
import { type RiffStore, riffStore, type Sidecar } from './store.ts';

/** What a reopened session says of a turn a dead process left open. */
export const INTERRUPTED = 'The interrupted turn was cancelled.';

/** The fake Chat Completions server riff runs on in tests. */
export interface FakeProvider {
  readonly baseUrl: string;
}

export interface RiffOptions {
  /** chord's version, which riff reports as its own. */
  readonly version: string;
  /**
   * The provider; undefined until riff has credentials (CHD-485 part 4), so
   * `session/new` asks for a sign-in.
   */
  readonly provider: FakeProvider | undefined;
  readonly backend: FxNodeBackendOptions;
  /** chord's state directory, where riff keeps its sessions. */
  readonly stateDir: string;
  /**
   * Host tools, for tests constructing riff in-process alone: nothing in the
   * binary can add one.
   */
  readonly tools?: FxAgentTools;
  /**
   * Makes the libfx agent: libfx's own but in tests that hold its creation
   * to put a close in the middle.
   */
  readonly createAgent?: typeof createFxAgent;
  /** Makes the session's finder: fff's but in tests that watch its end. */
  readonly openFinder?: typeof openFinder;
  /** The store: `riffStore(stateDir)` but in tests that hold its writes. */
  readonly store?: RiffStore;
}

/** riff on a connection, and when it has let its session go. */
export interface Riff {
  readonly connection: AgentConnection;
  /** Settles once the connection has closed and the session with it. */
  readonly finished: Promise<void>;
}

/** `initialize`'s answer, as the design gives it. */
export function riffInit(version: string): InitializeResponse {
  return {
    protocolVersion: 1,
    agentInfo: { name: RIFF, title: RIFF, version },
    authMethods: [
      {
        id: 'chatgpt',
        name: 'ChatGPT plan',
        description: 'Sign in to ChatGPT in chord',
      },
      {
        id: 'grok',
        name: 'Grok plan',
        description: 'Sign in to Grok in chord',
      },
    ],
    agentCapabilities: {
      loadSession: false,
      promptCapabilities: { image: true, audio: false, embeddedContext: true },
      mcpCapabilities: { http: true, sse: true },
      sessionCapabilities: { resume: {}, close: {} },
    },
    // The owner's call: libfx's steer starts a turn of its own when none
    // runs, so a steer could race the turn's end; chord sends riff's steers
    // as queued prompts. At the top, where chord reads it from every agent.
    _meta: { steering: { supported: false } },
  };
}

/** The one session a riff process serves. */
interface Open {
  readonly id: string;
  readonly plan: RiffPlan;
  readonly agent: FxAgent;
  /** The session's directory, as its real path: where its tools work. */
  readonly directory: string;
  readonly finder: Finder;
  config: RiffConfig;
  /** The last model request's context, for `usage_update`. */
  used: number | undefined;
  /** Whether a turn of a prompt is running. */
  running: boolean;
  /** What tools kept for the window of a call, by its id, until it ends. */
  readonly shown: Map<string, string>;
  /** What the person allowed for the rest of the session, in both modes. */
  readonly grants: Grants;
  /** The window, while a turn runs that may ask it. */
  client: AgentContext | undefined;
}

export function connectRiff(stream: Stream, options: RiffOptions): Riff {
  const store = options.store ?? riffStore(options.stateDir);
  let open: Open | undefined;
  // The session being created, so a second session/new and a close that
  // comes meanwhile see it; and whether the session is closing, by
  // session/close or the connection's end.
  let opening: Promise<Open> | undefined;
  let gone = false;
  // The one cleanup both a session/close and the connection's end await.
  let closing: Promise<void> | undefined;
  // Sidecar writes, one after another in the order they were asked, so the
  // last config change is the one on disk.
  let saving: Promise<void> = Promise.resolve();

  const opened = (sessionId: string): Open => {
    if (open?.id !== sessionId) {
      throw RequestError.sessionNotFound(sessionId);
    }

    // Nothing more is admitted once the close has begun: it owns what runs.
    if (gone) {
      throw RequestError.invalidRequest(undefined, 'the session is closing');
    }

    return open;
  };

  /**
   * Opens the session `id` on its sidecar, or a new one on the provider's
   * defaults, and writes its sidecar.
   */
  const start = async (
    cwd: string,
    resumed?: {
      readonly id: string;
      readonly sidecar: Sidecar;
    },
  ): Promise<Open> => {
    // A session of a plan riff cannot run now needs a sign-in too.
    if (
      options.provider === undefined ||
      (resumed !== undefined && resumed.sidecar.provider !== 'fake')
    ) {
      throw new RequestError(-32000, 'Sign in to a plan for riff.', {
        authMethods: riffInit(options.version).authMethods,
      });
    }

    if (open !== undefined || opening !== undefined || gone) {
      throw RequestError.invalidRequest(
        undefined,
        'riff serves one session per process',
      );
    }

    opening = made(options.provider, cwd, resumed);

    try {
      open = await opening;
    } finally {
      opening = undefined;
    }

    return open;
  };

  /** A session made and its sidecar written, or none, closed. */
  const made = async (
    provider: FakeProvider,
    cwd: string,
    resumed: { readonly id: string; readonly sidecar: Sidecar } | undefined,
  ): Promise<Open> => {
    const session = await create(provider, cwd, resumed);

    try {
      await save(session);
    } catch (error) {
      await closeOpen(session);

      throw error;
    }

    // The connection went while the sidecar was written: nobody will close
    // the session but this.
    if (gone) {
      await closeOpen(session);

      throw RequestError.internalError(undefined, 'the connection closed');
    }

    return session;
  };

  const create = async (
    provider: FakeProvider,
    cwd: string,
    resumed: { readonly id: string; readonly sidecar: Sidecar } | undefined,
  ): Promise<Open> => {
    const plan: RiffPlan = 'fake';
    const config: RiffConfig = resumed?.sidecar ?? defaultConfig(plan);
    const holder: { open?: Open } = {};
    const shown = new Map<string, string>();
    const grants: Grants = new Set();
    const directory = await realpath(cwd).catch(() => {
      throw RequestError.invalidParams(undefined, `no directory ${cwd}`);
    });

    const finder = (options.openFinder ?? openFinder)(directory);
    const fx = (options.createAgent ?? createFxAgent)({
      ...options.backend,
      name: RIFF,
      durability: store.durability,
      provider: {
        name: 'fake',
        baseUrl: provider.baseUrl,
        models: {
          fake: {
            contextWindow: windowOf(plan, 'fake'),
            supportsToolUse: true,
          },
        },
      },
      model: config.model,
      tools:
        options.tools ??
        riffTools({
          directory,
          finder,
          show: (id, text) => shown.set(id, text),
          mode: () => holder.open?.config.mode ?? config.mode,
          grants,
          ask: (toolCall, permissionOptions, signal) =>
            ask(holder.open, toolCall, permissionOptions, signal),
        }),
      hooks: {
        onEvent: (event) => {
          if (
            event.type === 'model.end' &&
            event.data.usage !== undefined &&
            holder.open !== undefined
          ) {
            holder.open.used = usedOf(event.data.usage as HookUsage);
          }
        },
      },
    });
    let id: string;

    try {
      id = resumed?.id ?? (await fx.newSessionId());
    } catch (error) {
      await closeBoth(fx, finder);

      throw error;
    }

    // The connection went while the session was being made: nobody will
    // close it but this.
    if (gone) {
      await closeBoth(fx, finder);

      throw RequestError.internalError(undefined, 'the connection closed');
    }

    holder.open = {
      id,
      plan,
      agent: fx,
      directory,
      finder,
      config: { model: config.model, effort: config.effort, mode: config.mode },
      used: undefined,
      running: false,
      shown,
      grants,
      client: undefined,
    };

    return holder.open;
  };

  /** Writes the session's sidecar as it is now, after every earlier write. */
  const save = (session: Open): Promise<void> => {
    const sidecar: Sidecar = {
      provider: session.plan,
      account: null,
      ...session.config,
    };
    const next = saving
      .catch(() => {
        // An earlier write's caller has its failure.
      })
      .then(() => store.write(session.id, sidecar));

    saving = next;

    return next;
  };

  /**
   * libfx's `resume()` runs a turn a crashed process left open, and a plain
   * next prompt would run it first, unseen (CHD-485, T2). So every reopen
   * cancels first and then resumes: `cancelled` with a turn id means a turn
   * was open and is now ended, its failed calls sent and a line saying so;
   * `idle` means none was. This follows from libfx's code order, not a
   * documented guarantee, so a fake-crash test counts what it runs.
   */
  const closeOpenTurn = async (session: Open, client: AgentContext) => {
    const fx = session.agent.session(session.id);

    await fx.cancel();

    // The connection went during the cancel: resume nothing it would leave
    // running.
    if (gone) {
      return;
    }

    const turn = fx.resume();
    const started = new Set<string>();

    for await (const event of turn) {
      const update = updateOf(event, started, drawIn(session), showIn(session));

      if (update !== undefined) {
        await notify(client, session.id, update);
      }
    }

    const result = await turn.result;

    if (result.stopReason === 'cancelled' && 'messageId' in result) {
      await notify(client, session.id, {
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text: INTERRUPTED },
      });
    }
  };

  /** Ends the session's libfx agent and its finder. */
  const closeOpen = (session: Open) => closeBoth(session.agent, session.finder);

  const drawIn = (session: Open) => (name: string, input: unknown) =>
    drawn(session.directory, name, input);

  /** What a call's tool kept for the window, given once, as its call ends. */
  const showIn = (session: Open) => (id: string) => {
    const text = session.shown.get(id);

    session.shown.delete(id);

    return text;
  };

  const notify = (
    client: AgentContext,
    sessionId: string,
    update: SessionUpdate,
  ) =>
    client.notify('session/update', { sessionId, update }).catch(() => {
      // The window has gone; the turn ends on its cancel or the close.
    });

  const shutdown = (): Promise<void> => (closing ??= cleanUp());

  const cleanUp = async () => {
    gone = true;

    await opening?.catch(() => {
      // It closed itself on seeing the connection gone.
    });

    await saving.catch(() => {
      // Its caller had the failure.
    });

    const session = open;

    if (session !== undefined) {
      // A cancel that fails still leaves nothing running.
      try {
        if (session.running) {
          await session.agent.session(session.id).cancel();
        }
      } finally {
        await closeOpen(session);
      }
    }

    open = undefined;
  };

  const connection = agent({ name: RIFF })
    .onRequest('initialize', () => riffInit(options.version))
    .onRequest('session/new', async ({ params }) => {
      const session = await start(params.cwd);

      return {
        sessionId: session.id,
        configOptions: configOptions(session.plan, session.config),
      };
    })
    .onRequest('session/resume', async ({ params, client }) => {
      const sidecar = await store.read(params.sessionId);

      if (sidecar === undefined) {
        throw RequestError.sessionNotFound(params.sessionId);
      }

      const session = await start(params.cwd, {
        id: params.sessionId,
        sidecar,
      });

      // The reopen's turn is the session's running work: a prompt waits for
      // it, and a close cancels it.
      session.running = true;
      session.client = client;

      try {
        await closeOpenTurn(session, client);
      } finally {
        session.running = false;
        session.client = undefined;
      }

      return { configOptions: configOptions(session.plan, session.config) };
    })
    .onRequest('session/set_config_option', async ({ params }) => {
      const session = opened(params.sessionId);
      const next = setOption(
        session.plan,
        session.config,
        params.configId,
        params.value,
      );

      if (next === undefined) {
        throw RequestError.invalidParams(
          undefined,
          `riff has no ${params.configId} ${String(params.value)}`,
        );
      }

      session.config = next;

      await save(session);

      return { configOptions: configOptions(session.plan, next) };
    })
    .onRequest('session/prompt', async ({ params, client }) => {
      const session = opened(params.sessionId);

      // One prompt at a time: the running flag is that prompt's, so close
      // knows to cancel its turn.
      if (session.running) {
        throw RequestError.invalidRequest(
          undefined,
          'riff runs one prompt at a time',
        );
      }

      const { model, effort } = session.config;
      const started = new Set<string>();

      session.running = true;
      session.client = client;

      try {
        const turn = session.agent
          .session(session.id, { model: { id: model, effort } })
          .prompt(promptOf(params.prompt));

        for await (const event of turn) {
          const update = updateOf(
            event,
            started,
            drawIn(session),
            showIn(session),
          );

          if (update !== undefined) {
            await notify(client, session.id, update);
          }
        }

        const result = await turn.result;

        if (session.used !== undefined) {
          await notify(client, session.id, {
            sessionUpdate: 'usage_update',
            used: session.used,
            size: windowOf(session.plan, model),
          });
        }

        if (result.error?.code === 'LIBFX_MODEL_UNSUPPORTED_EFFORT') {
          session.config = { ...session.config, effort: 'default' };

          // A close that began during the turn owns the sidecar now.
          if (!gone) {
            await save(session);
          }

          await notify(client, session.id, {
            sessionUpdate: 'config_option_update',
            configOptions: configOptions(session.plan, session.config),
          });
        }

        const usage = usageOf(result.usage);

        return {
          stopReason: stopReasonOf(result),
          ...(usage === undefined ? {} : { usage }),
        };
      } finally {
        session.running = false;
        session.client = undefined;
      }
    })
    .onNotification('session/cancel', async ({ params }) => {
      if (open?.id === params.sessionId) {
        await open.agent.session(open.id).cancel();
      }
    })
    .onRequest('session/close', async ({ params }) => {
      opened(params.sessionId);
      await shutdown();

      return {};
    })
    .connect(stream);

  return { connection, finished: connection.closed.then(shutdown) };
}

/**
 * Asks the window about a call of `session`'s running turn: the option the
 * person chose, or undefined when the ask was cancelled, failed, or no
 * window is there to answer.
 */
async function ask(
  session: Open | undefined,
  toolCall: ToolCallUpdate,
  options: PermissionOption[],
  signal: AbortSignal,
): Promise<string | undefined> {
  if (session?.client === undefined) {
    return undefined;
  }

  try {
    const { outcome } = await session.client.request(
      'session/request_permission',
      { sessionId: session.id, toolCall, options },
      { cancellationSignal: signal },
    );

    return outcome.outcome === 'selected' ? outcome.optionId : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Ends a libfx agent and its finder together: the finder neither waits on a
 * close that waits on a turn nor is skipped by one that fails.
 */
async function closeBoth(agent: FxAgent, finder: Finder): Promise<void> {
  const [closed] = await Promise.allSettled([agent.close(), finder.destroy()]);

  if (closed.status === 'rejected') {
    throw closed.reason;
  }
}

/** ACP's prompt blocks as a libfx session takes them. */
function promptOf(blocks: readonly ContentBlock[]): FxSessionPromptInput {
  return blocks.map((block) => {
    switch (block.type) {
      case 'text':
        return { type: 'text', text: block.text };
      case 'image':
        return { type: 'image', data: block.data, mimeType: block.mimeType };
      case 'resource_link':
        return { type: 'text', text: `${block.name}: ${block.uri}` };
      case 'resource':
        return {
          type: 'resource',
          resource: {
            uri: block.resource.uri,
            ...('text' in block.resource ? { text: block.resource.text } : {}),
          },
        };
      case 'audio':
        throw RequestError.invalidParams(undefined, 'riff takes no audio');
    }
  });
}
