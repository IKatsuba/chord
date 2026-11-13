/**
 * The ACP agent (CHD-622, "The protocol"): one cloud agent per session, its
 * id the session's, so the adapter keeps nothing a session needs to reopen.
 * It reaches Cursor, git and the key only through `ServeContext`, and the
 * SDK only for its types, so tests drive it with fakes alone.
 */
import { randomUUID } from 'node:crypto';
import { Readable, Writable } from 'node:stream';
import {
  agent,
  type AgentConnection,
  ndJsonStream,
  type ContentBlock,
  type InitializeResponse,
  type McpServer,
  RequestError,
  type SessionUpdate,
  type Stream,
} from '@agentclientprotocol/sdk/unstable';
import type { ModelListItem, SDKImage, SDKUserMessage } from '@cursor/sdk';
import {
  type Choice,
  choose,
  chosen,
  configOptions,
  sdkMode,
  selection,
} from './config.ts';
import { apiKey, type CredentialSource } from './credentials.ts';
import { INTERNAL_ERROR, INVALID_PARAMS, signedOut, toAcp } from './errors.ts';
import type { Port, PortAgent, PortRun } from './port.ts';
import { cursorUrl, type Git, repository } from './repo.ts';
import { Turn } from './turn.ts';
import {
  firstMessage,
  line,
  type LastRun,
  noConversation,
  replay,
  resumedMessage,
} from './updates.ts';

export const NAME = '@chorded/cursor-cloud-acp';
/** How long a shutdown waits for the SDK to let go of its agents. */
export const RELEASE_MS = 1000;

/** What the agent reaches. */
export interface ServeContext {
  readonly port: Port;
  readonly git: Git;
  /** Read again for each session: a sign-in while chord is open counts. */
  readonly credentials: () => CredentialSource;
  /** The package's own version, which the sign-in line names. */
  readonly version: string;
}

/** One open session: its cloud agent and what was chosen for it. */
interface Session {
  readonly agent: PortAgent;
  readonly apiKey: string;
  readonly mcpServers: readonly string[];
  choice: Choice;
  models: readonly ModelListItem[];
  turn: Turn | undefined;
}

/** The `login` command for this version, as the sign-in names it. */
export function loginCommand(version: string): string {
  return `npx -y ${NAME}@${version} login`;
}

export function initialize(version: string): InitializeResponse {
  return {
    protocolVersion: 1,
    agentInfo: { name: NAME, title: 'Cursor Cloud Agents', version },
    authMethods: [
      {
        id: 'cursor-login',
        name: 'Cursor login',
        description: `Run \`${loginCommand(version)}\` in a terminal, or set CURSOR_API_KEY`,
      },
    ],
    agentCapabilities: {
      loadSession: true,
      promptCapabilities: { image: true, embeddedContext: false },
      // stdio servers are taken, as ACP asks, and named unreachable (Q5).
      mcpCapabilities: { http: false, sse: false },
      sessionCapabilities: { list: {}, resume: {}, close: {} },
    },
    // Cloud agents' steer() always reverts to a follow-up.
    _meta: { steering: { supported: false } },
  };
}

/** The prompt's text, with its resource links named, and its images. */
function message(prompt: readonly ContentBlock[]): SDKUserMessage {
  const texts: string[] = [];
  const images: SDKImage[] = [];

  for (const block of prompt) {
    if (block.type === 'text') {
      texts.push(block.text);
    } else if (block.type === 'image') {
      images.push({ data: block.data, mimeType: block.mimeType });
    } else if (block.type === 'resource_link') {
      texts.push(block.uri);
    }
  }

  return images.length === 0
    ? { text: texts.join('\n') }
    : { text: texts.join('\n'), images };
}

/** The names of the MCP servers a session was given, for the first message. */
function serverNames(servers: readonly McpServer[] | undefined): string[] {
  return (servers ?? []).map((each) => each.name);
}

/** The agent being served, and its end. */
export interface Served {
  readonly connection: AgentConnection;
  /**
   * Stops forwarding and closes the adapter's hold on each cloud agent,
   * cancelling no run: the agents go on in Cursor's cloud.
   */
  shutdown(): Promise<void>;
}

/** Serves ACP on `stream` over `context` until the stream ends. */
export function serve(stream: Stream, context: ServeContext): Served {
  const sessions = new Map<string, Session>();
  const { port } = context;

  const session = (sessionId: string): Session => {
    const open = sessions.get(sessionId);

    if (open === undefined) {
      throw RequestError.resourceNotFound(sessionId);
    }

    return open;
  };

  const key = async (): Promise<string> => {
    const found = await apiKey(context.credentials());

    if (found === undefined) {
      throw signedOut();
    }

    // A key Cursor refuses, one minted for another backend among them,
    // answers as signed out with the SDK's words.
    await port.me({ apiKey: found });

    return found;
  };

  const models = (key: string) =>
    port.models({ apiKey: key }).catch((): ModelListItem[] => []);

  const options = (open: Session) =>
    configOptions(open.choice, open.models, open.agent.model === undefined);

  /** Whether serving has ended: an agent opened after is let go at once. */
  let ended = false;

  /** The adapter's hold on `agent` let go: the cloud agent goes on. */
  const release = (agent: PortAgent) =>
    agent[Symbol.asyncDispose]().catch(() => undefined);

  /**
   * `open` kept as its agent's session, unless serving ended while it was
   * being opened: then the request fails, and `opening` lets the agent go.
   */
  const hold = async (open: Session): Promise<void> => {
    if (ended) {
      throw new RequestError(INTERNAL_ERROR, 'The adapter is shutting down.');
    }

    const replaced = sessions.get(open.agent.agentId);

    sessions.set(open.agent.agentId, open);

    // A session opened again: the earlier hold lets go, and what its run
    // still sends is no longer forwarded.
    if (replaced !== undefined) {
      await release(replaced.agent);
    }
  };

  /**
   * `agent` let go when `opening` fails before the session is held, so a
   * failed start or reopen leaves no handle behind.
   */
  const opening = async <T>(
    agent: PortAgent,
    work: () => Promise<T>,
  ): Promise<T> => {
    try {
      return await work();
    } catch (error) {
      if (sessions.get(agent.agentId)?.agent !== agent) {
        await release(agent);
      }

      throw error;
    }
  };

  /** Every run of agent `id`, page after page, newest first as listRuns gives them. */
  const allRuns = async (id: string, apiKey: string) => {
    const runs: PortRun[] = [];
    let cursor: string | undefined;

    do {
      const page = await port.listRuns(id, {
        runtime: 'cloud',
        apiKey,
        ...(cursor === undefined ? {} : { cursor }),
      });

      runs.push(...page.items);

      cursor = page.nextCursor;
    } while (cursor !== undefined);

    return runs;
  };

  /** Reopens agent `id`: its session, and how its latest run stands. */
  const reopen = async (
    id: string,
    mcpServers: readonly McpServer[] | undefined,
  ): Promise<{
    open: Session;
    last: LastRun | undefined;
    url: string | undefined;
  }> => {
    const found = await key();
    const reopened = await port.resume(id, { apiKey: found });

    return opening(reopened, async () => {
      // listRuns gives the latest run first (Q9, fact 3).
      const [latest] = (
        await port.listRuns(id, { runtime: 'cloud', apiKey: found })
      ).items;
      const last = latest === undefined ? undefined : await latestState(latest);
      const info = await port.get(id, { apiKey: found });
      const repo = info.runtime === 'cloud' ? info.repos?.[0] : undefined;
      const open: Session = {
        agent: reopened,
        apiKey: found,
        mcpServers: serverNames(mcpServers),
        choice: {
          mode: 'default',
          ...(reopened.model === undefined
            ? {}
            : { model: chosen(reopened.model) }),
        },
        models: await models(found),
        turn: undefined,
      };

      await hold(open);

      return {
        open,
        last,
        url: repo === undefined ? undefined : cursorUrl(repo),
      };
    });
  };

  const connection = agent({ name: NAME })
    .onRequest('initialize', () => initialize(context.version))
    .onRequest('authenticate', () => {
      // The owner put sign-in in the package's own command.
      throw new RequestError(
        INVALID_PARAMS,
        `Sign in with \`${loginCommand(context.version)}\` in a terminal, or set CURSOR_API_KEY.`,
      );
    })
    .onRequest('session/new', async ({ params, client }) => {
      try {
        // Git first: a refusal needs no key, keychain or network.
        const repo = await repository(params.cwd, context.git);
        const found = await key();
        const created = await port.create({
          apiKey: found,
          mode: 'agent',
          cloud: {
            repos: [{ url: repo.url, startingRef: repo.branch }],
            workOnCurrentBranch: false,
            autoCreatePR: false,
          },
        });
        const open = await opening(created, async () => {
          const opened: Session = {
            agent: created,
            apiKey: found,
            mcpServers: serverNames(params.mcpServers),
            choice: { mode: 'default' },
            models: await models(found),
            turn: undefined,
          };

          await hold(opened);

          return opened;
        });

        // Before the answer: the ACP SDK's agent side has no way to write
        // after one, and a client holds an update for a session it is being
        // answered (owner, CHD-622).
        await client.notify('session/update', {
          sessionId: created.agentId,
          update: line(
            firstMessage({
              url: repo.url,
              branch: repo.branch,
              remote: repo.remote,
              agentId: created.agentId,
              mcpServers: open.mcpServers,
            }),
          ),
        });

        return { sessionId: created.agentId, configOptions: options(open) };
      } catch (error) {
        throw toAcp(error);
      }
    })
    .onRequest('session/prompt', async ({ params, client }) => {
      const open = session(params.sessionId);
      /** Whether the session is still this one: closed, it forwards nothing. */
      const current = () => sessions.get(params.sessionId) === open;
      const before = JSON.stringify(options(open));
      const turn = new Turn({
        agentId: open.agent.agentId,
        send: (onDelta) => {
          const model = selection(open.choice);

          return open.agent.send(message(params.prompt), {
            mode: sdkMode(open.choice),
            ...(model === undefined ? {} : { model }),
            idempotencyKey: randomUUID(),
            onDelta,
          });
        },
        artifacts: () => open.agent.listArtifacts().catch(() => []),
        // A model Cursor ran that the list lacks shows under its own id.
        ran: (model) => {
          if (current()) {
            open.choice = { ...open.choice, model: chosen(model) };
          }
        },
        emit: (update: SessionUpdate) =>
          current()
            ? client.notify('session/update', {
                sessionId: params.sessionId,
                update,
              })
            : Promise.resolve(),
      });

      // A prompt while one runs is Cursor's to refuse (AgentBusyError); the
      // running one stays the one a cancel stops.
      if (open.turn === undefined) {
        open.turn = turn;
      }

      try {
        return await turn.run();
      } catch (error) {
        throw toAcp(error, `https://cursor.com/agents/${open.agent.agentId}`);
      } finally {
        if (open.turn === turn) {
          open.turn = undefined;
        }

        // The whole set again when the run changed it: the model Cursor ran,
        // or Cursor's default gone once a model was sent.
        const after = options(open);

        if (current() && JSON.stringify(after) !== before) {
          await client
            .notify('session/update', {
              sessionId: params.sessionId,
              update: {
                sessionUpdate: 'config_option_update',
                configOptions: after,
              },
            })
            .catch(() => undefined);
        }
      }
    })
    .onNotification('session/cancel', ({ params }) => {
      sessions.get(params.sessionId)?.turn?.cancel();
    })
    .onRequest('session/set_config_option', ({ params }) => {
      const open = session(params.sessionId);
      const next =
        typeof params.value === 'string'
          ? choose(
              open.choice,
              open.models,
              open.agent.model === undefined,
              params.configId,
              params.value,
            )
          : undefined;

      if (next === undefined) {
        throw new RequestError(
          INVALID_PARAMS,
          `${params.configId} has no value ${String(params.value)}`,
        );
      }

      open.choice = next;

      return { configOptions: options(open) };
    })
    .onRequest('session/list', async ({ params }) => {
      try {
        const found = await key();
        const url =
          params.cwd === undefined || params.cwd === null
            ? undefined
            : (await repository(params.cwd, context.git, { pushed: false }))
                .url;
        const listed = await port.list({
          runtime: 'cloud',
          apiKey: found,
          ...(params.cursor === undefined || params.cursor === null
            ? {}
            : { cursor: params.cursor }),
        });

        return {
          sessions: listed.items
            .filter(
              (each) =>
                each.archived !== true &&
                (url === undefined ||
                  (each.runtime === 'cloud' &&
                    (each.repos ?? []).some(
                      (repo) => cursorUrl(repo) === url,
                    ))),
            )
            .map((each) => ({
              sessionId: each.agentId,
              cwd: params.cwd ?? '',
              title: each.name,
              updatedAt: new Date(each.lastModified).toISOString(),
            })),
          ...(listed.nextCursor === undefined
            ? {}
            : { nextCursor: listed.nextCursor }),
        };
      } catch (error) {
        throw toAcp(error);
      }
    })
    .onRequest('session/resume', async ({ params, client }) => {
      try {
        const { open, last, url } = await reopen(
          params.sessionId,
          params.mcpServers,
        );

        await client.notify('session/update', {
          sessionId: params.sessionId,
          update: line(
            resumedMessage({
              url,
              agentId: params.sessionId,
              last,
              mcpServers: open.mcpServers,
            }),
          ),
        });

        return { configOptions: options(open) };
      } catch (error) {
        throw toAcp(error);
      }
    })
    .onRequest('session/load', async ({ params, client }) => {
      try {
        const { open, last, url } = await reopen(
          params.sessionId,
          params.mcpServers,
        );
        const notify = (update: SessionUpdate) =>
          client.notify('session/update', {
            sessionId: params.sessionId,
            update,
          });
        const runs = await allRuns(params.sessionId, open.apiKey);

        for (const run of oldestFirst(runs)) {
          const updates = run.supports('conversation')
            ? replay(await run.conversation())
            : [line(noConversation(run.unsupportedReason('conversation')))];

          for (const update of updates) {
            await notify(update);
          }
        }

        await notify(
          line(
            resumedMessage({
              url,
              agentId: params.sessionId,
              last,
              mcpServers: open.mcpServers,
            }),
          ),
        );

        return { configOptions: options(open) };
      } catch (error) {
        throw toAcp(error);
      }
    })
    .onRequest('session/close', async ({ params }) => {
      const open = sessions.get(params.sessionId);

      sessions.delete(params.sessionId);

      try {
        // The cloud agent goes on; only the adapter's hold on it ends.
        await open?.agent[Symbol.asyncDispose]();
      } catch (error) {
        throw toAcp(error);
      }

      return {};
    })
    .connect(stream);

  return {
    connection,
    shutdown: async () => {
      ended = true;

      connection.close();

      const releasing = Promise.allSettled(
        [...sessions.values()].map((each) => release(each.agent)),
      );

      sessions.clear();
      // Within the process's 1.5 s to exit: an agent that does not let go
      // in time is left to the SDK; it runs on in Cursor's cloud regardless.
      await Promise.race([
        releasing,
        new Promise((resolve) => setTimeout(resolve, RELEASE_MS).unref()),
      ]);
    },
  };
}

/**
 * Runs oldest first. listRuns gives them newest first, as a live run showed
 * (Q9, fact 3), so its first item is the latest run.
 */
function oldestFirst<T>(runs: readonly T[]): T[] {
  return [...runs].reverse();
}

/**
 * How a run stands, from what the SDK gives of it: one still going is said
 * so at once, never waited on, as the adapter does not follow it.
 */
async function latestState(
  run: Pick<PortRun, 'status' | 'wait'>,
): Promise<LastRun> {
  if (run.status === 'running') {
    return { status: 'running' };
  }

  const result = await run.wait();

  return {
    status: result.status as LastRun['status'],
    branch: result.git?.branches.find((each) => each.branch !== undefined)
      ?.branch,
    error: result.error?.message,
  };
}

/**
 * Serves ACP on stdin and stdout until stdin ends or a signal comes, then
 * lets go of every cloud agent, cancelling no run, and answers 0 at once:
 * the SDK may hold sockets open, and the agents go on without this process.
 */
export function serveStdio(context: ServeContext): Promise<number> {
  const served = serve(
    ndJsonStream(
      Writable.toWeb(process.stdout),
      Readable.toWeb(process.stdin) as ReadableStream<Uint8Array>,
    ),
    context,
  );

  return new Promise((resolve) => {
    const stop = () => {
      void served.shutdown().then(() => resolve(0));
    };

    for (const signal of ['SIGTERM', 'SIGINT', 'SIGHUP'] as const) {
      process.once(signal, stop);
    }

    void served.connection.closed.then(stop);
  });
}
