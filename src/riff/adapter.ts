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
  type McpServer,
  type PermissionOption,
  RequestError,
  type SessionUpdate,
  type Stream,
  type ToolCallUpdate,
  type ToolCallContent,
  type RequestPermissionRequest,
} from '@agentclientprotocol/sdk/unstable';
import {
  createFxAgent,
  type FxAgent,
  type FxAgentTools,
  type FxNodeBackendOptions,
  type FxSessionPromptInput,
  type FxFetch,
} from 'libfx/node';
import { realpath } from 'node:fs/promises';
import { type Finder, openFinder } from '../platform/fff.ts';
import {
  type HookUsage,
  messageIds,
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
import { readInstructions } from './instructions.ts';
import { discoverSkills, skillsSection } from './skills.ts';
import {
  type Connect,
  connectSdk,
  mcpTitle,
  type McpTools,
  openMcp,
  skippedNote,
} from './mcp.ts';
import { RIFF } from './start.ts';
import type { Grants } from './tools/permission.ts';
import { drawn, riffTools } from './tools/tools.ts';
import { type RiffStore, riffStore, type Sidecar } from './store.ts';
import {
  type Secrets,
  type SecretProvider,
  SecretStoreTimeout,
  SecretStoreUnavailable,
} from '../platform/secrets.ts';
import {
  credentialCell,
  type CredentialCell,
  CredentialSignedOut,
} from './credentials.ts';
import { planProvider, providerOf } from './provider.ts';
import { readProvider } from './provider_record.ts';
import { ReviewHistory } from './review/state.ts';
import { ReviewTurn } from './review/admission.ts';
import { reviewer } from './review/engine.ts';
import { currentBranch } from './review/current_branch.ts';
import type { ReviewOutcome } from './review/review.ts';

/** What a reopened session says of a turn a dead process left open. */
export const INTERRUPTED = 'The interrupted turn was cancelled.';

/** The fake Chat Completions server riff runs on in tests. */
export interface FakeProvider {
  readonly baseUrl: string;
}

export interface RiffOptions {
  /** chord's version, which riff reports as its own. */
  readonly version: string;
  /** The custom fixture provider; plans instead read the supplied secrets. */
  readonly provider: FakeProvider | undefined;
  /** Explicitly supplied; omitted access never reaches the system store. */
  readonly secrets?: Secrets;
  /** Every libfx request, including version lookups and refresh, uses this edge. */
  readonly fetch?: FxFetch;
  readonly backend: FxNodeBackendOptions;
  /** chord's state directory, where riff keeps its sessions. */
  readonly stateDir: string;
  /** chord's config home, for the user's `AGENTS.md`; none reads none. */
  readonly configHome?: string;
  /** The home directory, for the user's skills; none reads none. */
  readonly home?: string;
  /** Connects an MCP server: the SDK's client but in tests. */
  readonly connectMcp?: Connect;
  /** A line for riff's log, stderr in the binary; none in tests. */
  readonly log?: (line: string) => void;
  /** Complete shell environment for in-process fixtures; inherited when omitted. */
  readonly commandEnvironment?: NodeJS.ProcessEnv;
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
  /** Scripted safety reviewer; tests never need a real model. */
  readonly review?: (
    input: string,
    signal: AbortSignal,
  ) => Promise<ReviewOutcome>;
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
  /** The session's MCP servers' tools, and their original names. */
  readonly mcp: McpTools;
  /** chord's notes for the window ahead of the next prompt's reply. */
  readonly notices: string[];
  readonly credential: CredentialCell | undefined;
  readonly authorization: ReturnType<typeof planProvider> | undefined;
  config: RiffConfig;
  /** The last model request's context, for `usage_update`. */
  used: number | undefined;
  /** Whether a turn of a prompt is running. */
  running: boolean;
  /** Esc may arrive while prompt admission is still waiting on the store. */
  cancelled: boolean;
  /** No libfx turn exists yet for a cancel to reach during store admission. */
  admitting: boolean;
  /** Identity of the turn callbacks may still update. */
  turn: symbol | undefined;
  /** What tools kept for the window of a call, by its id, until it ends. */
  readonly shown: Map<string, string | ToolCallContent[]>;
  /** The calls this turn has sent the window, so each is sent once. */
  calls: Set<string>;
  /** What the person allowed for the rest of the session, in both modes. */
  readonly grants: Grants;
  readonly reviewHistory: ReviewHistory;
  reviews: ReviewTurn;
  readonly safetyReview: NonNullable<RiffOptions['review']>;
  /** Host execution may outlive libfx's cancellation race; riff owns its disposal. */
  readonly reviewJobs: Set<Promise<unknown>>;
  /** The window, while a turn runs that may ask it. */
  client: AgentContext | undefined;
}

type SelectedProvider =
  | { readonly plan: 'fake'; readonly fake: FakeProvider }
  | { readonly plan: SecretProvider; readonly cell: CredentialCell };

const authRequired = () =>
  new RequestError(
    -32000,
    'Sign in to a plan for riff; run chord riff to sign in.',
    {
      authMethods: riffInit('').authMethods,
    },
  );

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
    servers: readonly McpServer[],
    client: AgentContext,
    resumed?: {
      readonly id: string;
      readonly sidecar: Sidecar;
    },
  ): Promise<Open> => {
    if (open !== undefined || opening !== undefined || gone) {
      throw RequestError.invalidRequest(
        undefined,
        'riff serves one session per process',
      );
    }

    opening = (async () => {
      let provider: SelectedProvider;

      if (
        options.provider !== undefined &&
        (resumed === undefined || resumed.sidecar.provider === 'fake')
      ) {
        provider = { plan: 'fake', fake: options.provider };
      } else {
        const secrets = options.secrets;

        if (secrets === undefined || resumed?.sidecar.provider === 'fake') {
          throw authRequired();
        }

        const plan =
          resumed?.sidecar.provider ??
          providerOf(
            {
              codex: await secrets.get('codex'),
              grok: await secrets.get('grok'),
            },
            await readProvider(options.stateDir),
          );

        if (plan === undefined) {
          throw authRequired();
        }

        const cell = credentialCell(
          secrets,
          options.stateDir,
          plan,
          (state) => {
            void client
              .notify('_chord/credentials', { provider: plan, state })
              .catch(() => {});
          },
        );
        const value = await cell.check();

        if (
          resumed !== undefined &&
          resumed.sidecar.account !== value.accountId
        ) {
          throw authRequired();
        }

        provider = { plan, cell };
      }

      return made(provider, cwd, servers, resumed);
    })();

    try {
      open = await opening;
    } catch (error) {
      if (error instanceof CredentialSignedOut) {
        throw authRequired();
      }

      if (
        error instanceof SecretStoreUnavailable ||
        error instanceof SecretStoreTimeout
      ) {
        throw new RequestError(
          -32603,
          `${error.message} run chord riff to sign in.`,
          {
            riffStore: {
              state:
                error instanceof SecretStoreTimeout ? 'timeout' : 'unavailable',
              name: error.store,
              message: error.message,
            },
          },
        );
      }

      throw error;
    } finally {
      opening = undefined;
    }

    return open;
  };

  /** A session made and its sidecar written, or none, closed. */
  const made = async (
    provider: SelectedProvider,
    cwd: string,
    servers: readonly McpServer[],
    resumed: { readonly id: string; readonly sidecar: Sidecar } | undefined,
  ): Promise<Open> => {
    const session = await create(provider, cwd, servers, resumed);

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
    provider: SelectedProvider,
    cwd: string,
    servers: readonly McpServer[],
    resumed: { readonly id: string; readonly sidecar: Sidecar } | undefined,
  ): Promise<Open> => {
    const plan: RiffPlan = provider.plan;
    const credential = provider.plan === 'fake' ? undefined : provider.cell;
    const authorization =
      credential === undefined || provider.plan === 'fake'
        ? undefined
        : planProvider(credential, provider.plan);
    const config: RiffConfig = resumed?.sidecar ?? defaultConfig(plan);
    const holder: { open?: Open } = {};
    const shown = new Map<string, string | ToolCallContent[]>();
    const grants: Grants = new Set();
    const directory = await realpath(cwd).catch(() => {
      throw RequestError.invalidParams(undefined, `no directory ${cwd}`);
    });

    const selectedProvider =
      provider.plan === 'fake'
        ? {
            provider: {
              name: 'fake',
              baseUrl: provider.fake.baseUrl,
              models: {
                fake: {
                  contextWindow: windowOf(plan, 'fake'),
                  supportsToolUse: true,
                },
              },
            },
          }
        : authorization?.options;

    if (selectedProvider === undefined) {
      throw authRequired();
    }

    const safetyReview =
      options.review ??
      reviewer({
        configuration: {
          ...options.backend,
          ...selectedProvider,
          fetch: options.fetch ?? globalThis.fetch,
          model:
            plan === 'fake'
              ? 'fake'
              : plan === 'codex'
                ? 'gpt-6-luna'
                : 'grok-4.5',
        },
      });

    // An unreadable AGENTS.md refuses the start, naming the file and why.
    const instructions = await readInstructions({
      directory,
      configHome: options.configHome,
    }).catch((error: unknown) => {
      throw RequestError.internalError(
        undefined,
        `riff could not read its instructions: ${error instanceof Error ? error.message : String(error)}`,
      );
    });

    const skills = await discoverSkills({
      directory,
      home: options.home,
    }).catch((error: unknown) => {
      throw RequestError.internalError(
        undefined,
        `riff could not read its skills: ${error instanceof Error ? error.message : String(error)}`,
      );
    });

    const listed = skillsSection(skills);
    const mcp = await openMcp(
      servers,
      directory,
      options.connectMcp ?? connectSdk(options.version),
    );
    const notices = mcp.skipped.map(skippedNote);

    for (const notice of notices) {
      options.log?.(`riff: ${notice}`);
    }

    const finder = (options.openFinder ?? openFinder)(directory);
    const fx = (options.createAgent ?? createFxAgent)({
      ...options.backend,
      name: RIFF,
      instructions:
        listed === undefined ? instructions : [instructions, listed],
      durability: store.durability,
      ...selectedProvider,
      fetch: options.fetch ?? globalThis.fetch,
      model: config.model,
      tools: options.tools ?? [
        ...riffTools({
          directory,
          finder,
          skills,
          ...(options.commandEnvironment === undefined
            ? {}
            : { commandEnvironment: options.commandEnvironment }),
          show: (id, text) => shown.set(id, text),
          showContent: (id, content) => shown.set(id, content),
          stream: () => {
            const session = holder.open;
            const turn = session?.turn;
            const client = session?.client;

            return (update) => {
              if (
                session === undefined ||
                turn === undefined ||
                client === undefined ||
                session.turn !== turn ||
                !session.running ||
                !session.calls.has(update.toolCallId)
              ) {
                return;
              }

              if (update.content !== undefined && update.content !== null) {
                session.shown.set(update.toolCallId, update.content);
              }

              return notify(client, session.id, {
                sessionUpdate: 'tool_call_update',
                ...update,
              });
            };
          },
          announce: (id, name, input) => announce(holder.open, id, name, input),
          begin: (id, name, input) => {
            holder.open?.reviewHistory.admitted(id);

            return begin(holder.open, id, name, input);
          },
          permissionWaiting: (id) => holder.open?.reviewHistory.permission(id),
          review: async (action, arguments_, signal) => {
            const session = holder.open;

            if (session === undefined) {
              throw new Error('The review session is closed.');
            }

            const job = Promise.try(async () => {
              const branch = await currentBranch(directory, signal);

              signal.throwIfAborted();

              return session.reviews.run(
                arguments_,
                {
                  action,
                  ...session.reviewHistory.snapshot(),
                  ...(branch === undefined ? {} : { branch }),
                },
                signal,
              );
            });

            session.reviewJobs.add(job);

            try {
              return await job;
            } finally {
              session.reviewJobs.delete(job);
            }
          },
          mode: () => holder.open?.config.mode ?? config.mode,
          grants,
          ask: (toolCall, permissionOptions, signal, metadata) =>
            ask(holder.open, toolCall, permissionOptions, signal, metadata),
        }),
        ...mcp.tools,
      ],
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
      await closeBoth(fx, finder, mcp);

      throw error;
    }

    // The connection went while the session was being made: nobody will
    // close it but this.
    if (gone) {
      await closeBoth(fx, finder, mcp);

      throw RequestError.internalError(undefined, 'the connection closed');
    }

    holder.open = {
      id,
      plan,
      agent: fx,
      directory,
      finder,
      mcp,
      notices,
      credential,
      authorization,
      config: { model: config.model, effort: config.effort, mode: config.mode },
      used: undefined,
      running: false,
      cancelled: false,
      admitting: false,
      turn: undefined,
      shown,
      calls: new Set(),
      grants,
      reviewHistory: new ReviewHistory(),
      reviews: new ReviewTurn(safetyReview),
      safetyReview,
      reviewJobs: new Set(),
      client: undefined,
    };

    return holder.open;
  };

  /** Writes the session's sidecar as it is now, after every earlier write. */
  const save = (session: Open): Promise<void> => {
    const sidecar: Sidecar = {
      provider: session.plan,
      account: session.credential?.account ?? null,
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

    session.calls = new Set();

    const ids = messageIds();

    for await (const event of turn) {
      const messageId = ids(event);
      const update = updateOf(
        event,
        session.calls,
        drawIn(session),
        showIn(session),
      );

      if (update !== undefined) {
        await notify(client, session.id, withId(update, messageId));
      }
    }

    const result = await turn.result;

    if (result.stopReason === 'cancelled' && 'messageId' in result) {
      await notify(client, session.id, {
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text: INTERRUPTED },
        messageId: `chord-note-${crypto.randomUUID()}`,
      });
    }
  };

  /** Ends the session's libfx agent and its finder. */
  const closeOpen = async (session: Open) => {
    try {
      await closeBoth(session.agent, session.finder, session.mcp);
    } finally {
      await finishReviews(session);
    }
  };

  const drawIn = (session: Open) => (name: string, input: unknown) => {
    const original = session.mcp.originals.get(name);

    return original === undefined
      ? drawn(session.directory, name, input)
      : { title: mcpTitle(original), kind: 'other' as const };
  };

  /**
   * Sends the window a call the turn's events have not sent yet: a tool
   * runs before libfx's start of it is read, and the first of the two sends
   * it (CHD-485), so an ask or a running state never comes before its call.
   */
  const announce = async (
    session: Open | undefined,
    id: string,
    name: string,
    input: unknown,
  ) => {
    const client = session?.client;

    if (
      session === undefined ||
      client === undefined ||
      session.calls.has(id)
    ) {
      return;
    }

    session.calls.add(id);
    await notify(client, session.id, {
      sessionUpdate: 'tool_call',
      toolCallId: id,
      ...drawIn(session)(name, input),
      status: 'pending',
      rawInput: input,
    });
  };

  /** A call's effect begins: the window hears it running. */
  const begin = async (
    session: Open | undefined,
    id: string,
    name: string,
    input: unknown,
  ) => {
    const client = session?.client;

    if (session === undefined || client === undefined) {
      return;
    }

    await announce(session, id, name, input);
    await notify(client, session.id, {
      sessionUpdate: 'tool_call_update',
      toolCallId: id,
      status: 'in_progress',
    });
  };

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
    .onRequest('session/new', async ({ params, client }) => {
      const session = await start(params.cwd, params.mcpServers, client);

      return {
        sessionId: session.id,
        configOptions: configOptions(session.plan, session.config),
        _meta: { 'chord/riffProvider': session.plan },
      };
    })
    .onRequest('session/resume', async ({ params, client }) => {
      const sidecar = await store.read(params.sessionId);

      if (sidecar === undefined) {
        throw RequestError.sessionNotFound(params.sessionId);
      }

      const session = await start(params.cwd, params.mcpServers ?? [], client, {
        id: params.sessionId,
        sidecar,
      });

      // The reopen's turn is the session's running work: a prompt waits for
      // it, and a close cancels it.
      session.running = true;
      session.cancelled = false;
      session.turn = Symbol('turn');
      session.client = client;

      try {
        await closeOpenTurn(session, client);
      } finally {
        await finishReviews(session);

        session.running = false;
        session.turn = undefined;
        session.client = undefined;

        session.shown.clear();
      }

      return {
        configOptions: configOptions(session.plan, session.config),
        _meta: { 'chord/riffProvider': session.plan },
      };
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

      session.calls = new Set();

      session.running = true;
      session.cancelled = false;
      session.admitting = true;
      session.turn = Symbol('turn');
      session.client = client;

      try {
        session.authorization?.reset();

        try {
          await session.credential?.check();
        } catch (error) {
          if (error instanceof CredentialSignedOut) {
            throw authRequired();
          }

          throw error;
        }

        session.admitting = false;

        if (session.cancelled || gone) {
          return { stopReason: 'cancelled' };
        }

        const input = promptOf(params.prompt);

        session.reviewHistory.prompt(
          params.prompt
            .filter((block) => block.type === 'text')
            .map((block) => block.text)
            .join('\n'),
        );

        session.reviews = new ReviewTurn(session.safetyReview);

        // chord's own notes go to the window alone, never to libfx's history.
        const notes = session.notices.splice(0);

        for (const note of notes) {
          await notify(client, session.id, {
            sessionUpdate: 'agent_message_chunk',
            content: { type: 'text', text: note },
            messageId: `chord-note-${crypto.randomUUID()}`,
          });
        }

        const turn = session.agent
          .session(session.id, { model: { id: model, effort } })
          .prompt(input);
        const ids = messageIds();

        for await (const event of turn) {
          if (event.type === 'tool_end') {
            session.reviewHistory.result({
              id: event.id,
              tool: event.name,
              text: event.content ?? '',
            });
          }

          const messageId = ids(event);
          const update = updateOf(
            event,
            session.calls,
            drawIn(session),
            showIn(session),
          );

          if (update !== undefined) {
            await notify(client, session.id, withId(update, messageId));
          }
        }

        const result = await turn.result;

        if (session.authorization?.failed() !== undefined) {
          throw authRequired();
        }

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
        await finishReviews(session);

        session.running = false;
        session.admitting = false;
        session.turn = undefined;
        session.client = undefined;

        session.shown.clear();
      }
    })
    .onNotification('session/cancel', async ({ params }) => {
      if (open?.id === params.sessionId) {
        open.cancelled = true;

        if (!open.admitting) {
          await open.agent.session(open.id).cancel();
        }
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
  metadata?: RequestPermissionRequest['_meta'],
): Promise<string | undefined> {
  if (session?.client === undefined) {
    return undefined;
  }

  try {
    const { outcome } = await session.client.request(
      'session/request_permission',
      {
        sessionId: session.id,
        toolCall,
        options,
        ...(metadata === undefined ? {} : { _meta: metadata }),
      },
      { cancellationSignal: signal },
    );

    return outcome.outcome === 'selected' ? outcome.optionId : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Ends a libfx agent, its finder and its MCP clients together: none waits
 * on a close that waits on a turn nor is skipped by one that fails.
 */
async function closeBoth(
  agent: FxAgent,
  finder: Finder,
  mcp: McpTools,
): Promise<void> {
  const [closed] = await Promise.allSettled([
    agent.close(),
    finder.destroy(),
    mcp.close(),
  ]);

  if (closed.status === 'rejected') {
    throw closed.reason;
  }
}

/** Parent libfx cancellation does not wait for host execute promises. */
async function finishReviews(session: Open): Promise<void> {
  while (session.reviewJobs.size > 0) {
    await Promise.allSettled([...session.reviewJobs]);
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
        if ('blob' in block.resource) {
          throw RequestError.invalidParams(
            undefined,
            'riff takes no binary resources',
          );
        }

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

/** `update` with its assistant message's id, when it is a reply's text. */
function withId(
  update: SessionUpdate,
  messageId: string | undefined,
): SessionUpdate {
  return messageId === undefined ||
    update.sessionUpdate !== 'agent_message_chunk'
    ? update
    : { ...update, messageId };
}
