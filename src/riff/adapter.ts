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
  RequestError,
  type SessionUpdate,
  type Stream,
} from '@agentclientprotocol/sdk/unstable';
import { z } from '@zod/zod';
import {
  createFxAgent,
  type Durability,
  type FxAgent,
  type FxAgentTools,
  type FxNodeBackendOptions,
  type FxSessionPromptInput,
} from 'libfx/node';
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
  /** Where libfx keeps its sessions. */
  readonly durability: Durability;
  /**
   * Host tools, for tests constructing riff in-process alone: nothing in the
   * binary can add one.
   */
  readonly tools?: FxAgentTools;
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
    // At the top, where chord reads it from every agent, as Claude's and
    // Codex's adapters send it.
    _meta: { steering: { supported: true } },
  };
}

/** The `_session/steering` request, as far as riff reads it. */
const STEER = z.object({
  sessionId: z.string(),
  prompt: z.array(z.looseObject({ type: z.string() })),
  _meta: z
    .looseObject({
      steering: z
        .looseObject({ idleBehavior: z.string().optional() })
        .optional(),
    })
    .nullish(),
});

/** The one session a riff process serves. */
interface Open {
  readonly id: string;
  readonly plan: RiffPlan;
  readonly agent: FxAgent;
  config: RiffConfig;
  /** The last model request's context, for `usage_update`. */
  used: number | undefined;
  /** Whether a turn of a prompt is running. */
  running: boolean;
}

export function connectRiff(stream: Stream, options: RiffOptions): Riff {
  let open: Open | undefined;
  // The session being created, so a second session/new and a close that
  // comes meanwhile see it; and whether the connection has gone.
  let opening: Promise<Open> | undefined;
  let gone = false;

  const opened = (sessionId: string): Open => {
    if (open?.id !== sessionId) {
      throw RequestError.sessionNotFound(sessionId);
    }

    return open;
  };

  const start = async (): Promise<Open> => {
    if (options.provider === undefined) {
      throw new RequestError(-32000, 'Sign in to a plan for riff.', {
        authMethods: riffInit(options.version).authMethods,
      });
    }

    if (open !== undefined || opening !== undefined) {
      throw RequestError.invalidRequest(
        undefined,
        'riff serves one session per process',
      );
    }

    opening = create(options.provider);

    try {
      open = await opening;
    } finally {
      opening = undefined;
    }

    return open;
  };

  const create = async (provider: FakeProvider): Promise<Open> => {
    const plan: RiffPlan = 'fake';
    const config = defaultConfig(plan);
    const holder: { open?: Open } = {};
    const fx = createFxAgent({
      ...options.backend,
      name: RIFF,
      durability: options.durability,
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
      ...(options.tools === undefined ? {} : { tools: options.tools }),
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
      id = await fx.newSessionId();
    } catch (error) {
      await fx.close();

      throw error;
    }

    // The connection went while the session was being made: nobody will
    // close it but this.
    if (gone) {
      await fx.close();

      throw RequestError.internalError(undefined, 'the connection closed');
    }

    holder.open = {
      id,
      plan,
      agent: fx,
      config,
      used: undefined,
      running: false,
    };

    return holder.open;
  };

  const notify = (
    client: AgentContext,
    sessionId: string,
    update: SessionUpdate,
  ) =>
    client.notify('session/update', { sessionId, update }).catch(() => {
      // The window has gone; the turn ends on its cancel or the close.
    });

  const shutdown = async () => {
    gone = true;

    await opening?.catch(() => {
      // It closed itself on seeing the connection gone.
    });

    const closing = open;

    open = undefined;

    if (closing !== undefined) {
      if (closing.running) {
        await closing.agent.session(closing.id).cancel();
      }

      await closing.agent.close();
    }
  };

  const connection = agent({ name: RIFF })
    .onRequest('initialize', () => riffInit(options.version))
    .onRequest('session/new', async () => {
      const session = await start();

      return {
        sessionId: session.id,
        configOptions: configOptions(session.plan, session.config),
      };
    })
    .onRequest('session/set_config_option', ({ params }) => {
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

      try {
        const turn = session.agent
          .session(session.id, { model: { id: model, effort } })
          .prompt(promptOf(params.prompt));

        for await (const event of turn) {
          const update = updateOf(event, started);

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
      }
    })
    .onNotification('session/cancel', async ({ params }) => {
      if (open?.id === params.sessionId) {
        await open.agent.session(open.id).cancel();
      }
    })
    .onRequest('_session/steering', STEER, async ({ params }) => {
      const session = opened(params.sessionId);

      // chord always asks `promptRequired`; a steer with no turn running
      // would start one whose events no prompt reads.
      if (!session.running) {
        return { outcome: 'promptRequired' };
      }

      await session.agent
        .session(session.id)
        .steer(promptOf(params.prompt as unknown as ContentBlock[]));

      return { outcome: 'injected' };
    })
    .onRequest('session/close', async ({ params }) => {
      opened(params.sessionId);
      await shutdown();

      return {};
    })
    .connect(stream);

  return { connection, finished: connection.closed.then(shutdown) };
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
