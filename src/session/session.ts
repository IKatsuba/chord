import type {
  AvailableCommand,
  ContentBlock,
  McpServer,
  PromptResponse,
  SessionNotification,
  SessionUpdate,
} from '@agentclientprotocol/sdk';
import process from 'node:process';
import { type Agent, openAgent } from '../acp/connection.ts';
import type { Traffic } from '../acp/traffic.ts';
import { agentStart } from '../agents.ts';
import { mentionLinks, type ResourceLink } from '../files.ts';
import {
  foldUpdate,
  effortsOf,
  modelsOf,
  modesOf,
  optionsOf,
  type SessionAnswer,
  stateOf,
  withOptions,
} from './agent_state.ts';
import type { AgentOption } from './config.ts';
import type { AgentEfforts } from './efforts.ts';
import { ElicitationBridge } from './elicitations.ts';
import { enricherRelay } from './enrich.ts';
import { usageCountOf } from '../cost_counts.ts';
import { ENRICHERS } from './enrichers.ts';
import { type AgentModels, isModelState, modelConfigId } from './models.ts';
import { type AgentModes, modeConfigId } from './modes.ts';
import { PermissionBridge } from './permissions.ts';
import { PlanBridge } from './plan_asks.ts';
import { type HeldBack, serversFor } from './servers.ts';
import { dirname } from 'node:path';
import {
  lastTotal,
  pastBySession,
  readPast,
  recordActions,
  runPasts,
  taskPasts,
  withTaskWork,
} from './record.ts';
import { type Heard, pastActions } from './replay.ts';
import type { Resume } from './sessions.ts';
import { routed, type SessionTree, sessionTree } from './subagents.ts';
import type { TranscriptAction, TurnResult } from './transcript/types.ts';
import { tokensOf } from './usage.ts';
import type { TurnFigures } from './turn_costs.ts';

/**
 * One step of a session's past: what the transcript drew, or a turn's tokens,
 * which only a record keeps; an agent's replay carries none.
 */
export type PastAction =
  TranscriptAction | ({ readonly type: 'usage' } & TurnFigures);

export interface OpenSessionOptions {
  /** A name `chord agents` lists, or the label for `agentCommand`. */
  agent: string;
  /** The directory the agent works in. */
  cwd: string;
  /**
   * Starts this command instead of the registry's for `agent` — a fake agent
   * in tests, or any ACP agent chord does not know.
   */
  agentCommand?: string | string[];
  /**
   * An earlier session to open again instead of a new one, which the agent
   * loads by its id: `session/resume`, which replays nothing, when the agent
   * offers it and chord's record holds the past, else `session/load`, which
   * replays it; the record, where there is one, is what is drawn.
   */
  resume?: Resume;
  /**
   * MCP servers for the agent, sent with `session/new`, `session/load` and
   * `session/resume`, those whose transport it does not advertise held back
   * (`serversFor`); none by default.
   */
  mcpServers?: readonly McpServer[];
  /**
   * The agent takes no MCP servers at all, as its `agents.<name>.mcpServers`
   * setting or chord's own table says: every one is held back, chord's own
   * too, and the session says so (CHD-441).
   */
  noMcpServers?: boolean;
  /**
   * chord's own MCP server, sent after `mcpServers` under the same rule; an
   * agent that would refuse it never sees it.
   */
  chordServer?: McpServer;
  /**
   * Gives up on a session still starting: the open rejects with the signal's
   * reason once the agent is stopped.
   */
  signal?: AbortSignal;
}

/**
 * Claude Code leaves its task list tools out for models newer than the ones it
 * lists, unless the host opts in; without them Claude never sends a plan, and
 * chord draws one. Other agents ignore the variable. A value the person set
 * stays theirs.
 */
export function agentEnv(
  parent: Readonly<Record<string, string | undefined>>,
): Record<string, string> {
  return 'CLAUDE_CODE_ENABLE_TODO_TOOLS' in parent
    ? {}
    : { CLAUDE_CODE_ENABLE_TODO_TOOLS: '1' };
}

/** An image a prompt sends after its text, base64. */
export interface Attachment {
  readonly mediaType: string;
  readonly data: string;
}

/** A prompt sent: its id, how it ended, and the way to stop it. */
export interface Turn {
  readonly id: string;
  /**
   * Settles with the agent's answer, or `failed` with why there was none; it
   * never rejects. The turn's updates went to the session's subscribers.
   */
  readonly result: Promise<TurnResult>;
  /**
   * Settles once the prompt has gone to the agent, with the `resource_link`
   * blocks that went after its text and images; `undefined` when it never
   * went, as when a cancel came before the walk for its mentions ended.
   */
  readonly sent: Promise<readonly ResourceLink[] | undefined>;
  /**
   * Asks the agent to stop the turn, or, before the prompt has gone, keeps it
   * back and tells the agent nothing; `result` then says `cancelled`.
   */
  cancel(): Promise<void>;
}

/**
 * How a steer went: `injected` into the running turn, `startedNewTurn` as a
 * turn of the agent's own, or `refused`, the agent having done nothing with
 * it, as with no turn running.
 */
export type SteerOutcome = 'injected' | 'startedNewTurn' | 'refused';

/** The name Claude's adapter gives itself in `initialize`'s `agentInfo`. */
export const CLAUDE_ADAPTER = '@agentclientprotocol/claude-agent-acp';

/** One agent process and one ACP session in it, until `close()`. */
export interface Session {
  readonly agent: string;
  readonly cwd: string;
  /**
   * The agent's id for the session, which `--resume` takes; for Claude, the
   * id Claude Code keeps the conversation under.
   */
  readonly id: string;
  /**
   * The file of chord's record this session was opened from, which it goes
   * on in; none for a session chord has no record of.
   */
  readonly record?: string | undefined;
  /**
   * Set for a session opened again from an earlier one, with when that was
   * last used, its first prompt and an agent another started's name, where
   * chord's record says.
   */
  readonly resumed?:
    | {
        readonly lastUsedAt?: number | undefined;
        readonly prompt?: string | undefined;
        readonly name?: string | undefined;
      }
    | undefined;
  /** Permission requests waiting on the person. */
  readonly permissions: PermissionBridge;
  /** Forms and links the agent asks the person to fill in or open. */
  readonly elicitations: ElicitationBridge;
  /** Plans cursor or grok puts to the person (CHD-437, CHD-457). */
  readonly plans: PlanBridge;
  /** Agent processes this session started that have not exited yet. */
  readonly agentPids: ReadonlySet<number>;
  /** Settles once the agent's process has exited, however it came to. */
  readonly exited: Promise<void>;
  /**
   * Once the agent has gone, its last words: the end of its stderr, empty
   * when it left none; undefined while it is up.
   */
  gone(): string | undefined;
  /**
   * A resumed session's past as the reducers' actions: what chord's record of
   * it kept, its turns' tokens with them, however the agent reopened it, or,
   * for a session chord has no record of, what the agent replayed as it
   * loaded it. Empty for a new session.
   */
  history(): readonly PastAction[];
  /**
   * Hears every `session/update` the agent sends for the session from now on,
   * in turns and outside them, after the session's own state has taken it in,
   * and those it sends for the session's subagents, at any depth, with the
   * subagent's id: they are the session's work too, but not what the
   * session's own agent said. Those that came before the first listener are
   * handed to it first.
   */
  subscribe(
    listener: (update: SessionUpdate, subagentId?: string) => void,
  ): () => void;
  /**
   * Sends a prompt, with images after its text, then a `resource_link` for
   * each of the `mentions` that is a file `@` offers in the session's
   * directory; the text names them already.
   */
  prompt(
    text: string,
    attachments?: readonly Attachment[],
    mentions?: readonly string[],
  ): Turn;
  /**
   * Whether the agent takes images in a prompt, as the `promptCapabilities`
   * it gave in `initialize` say.
   */
  takesImages(): boolean;
  /**
   * Whether the agent takes a prompt into the turn it is running, as its
   * `initialize` answer advertises `_session/steering`.
   */
  steers(): boolean;
  /**
   * Whether a steer cuts off the tool calls the turn has open: Claude's
   * adapter, told by the name it gives in `initialize`, delivers a steer
   * at a priority that aborts them, a `send_message` among them lost
   * before it reaches chord (CHD-417). Codex's queues a steer as input to
   * the live turn and cuts nothing, as the records show, so it is not.
   */
  cutsCallsOnSteer(): boolean;
  /**
   * Whether the agent runs cycles of its own once a turn has ended, which
   * start unmarked and end on a usage update of an autonomous origin:
   * Claude's adapter, by the name it gives in `initialize` (CHD-426, Q49).
   */
  startsOwnCycles(): boolean;
  /**
   * Puts `text` into the turn the agent is running, asking an agent with
   * none running to do nothing with it; rejects when the request fails.
   */
  steer(text: string): Promise<SteerOutcome>;
  /**
   * chord's own MCP server as the agent was given it, under the name it went
   * by; none when it was not passed, as to an agent that does not take HTTP.
   */
  readonly chordServer?: McpServer;
  /**
   * The MCP servers the agent was not given, chord's own among them, as its
   * `initialize` does not advertise their transport; none when all went.
   */
  readonly heldBack: readonly HeldBack[];
  /** Cancels the turn that is running, if any, and its subagents' work. */
  cancel(): Promise<void>;
  /**
   * Stops subagent `id`'s work alone, its parent's turn going on; rejects
   * when the stop cannot be sent.
   */
  stopSubagent(id: string): Promise<void>;
  /**
   * The models the agent offers, by their display names where it gave them,
   * and the one it says it is using; none when it advertises none.
   */
  models(): AgentModels | undefined;
  /**
   * Asks the agent for a model, through its `model` config option or the
   * older `session/set_model`; `models()` then holds what the agent answered.
   */
  setModel(id: string): Promise<void>;
  /**
   * The slash commands the agent advertised in `available_commands_update`,
   * which it may send outside any turn; none until it has.
   */
  commands(): readonly AvailableCommand[];
  /** The modes the agent offers and the one it reports; none when it offers none. */
  modes(): AgentModes | undefined;
  /**
   * Asks the agent for a mode, through its `mode` config option or the older
   * `session/set_mode`. The mode the agent reports afterwards is what counts,
   * read from `modes()`.
   */
  setMode(id: string): Promise<void>;
  /**
   * The agent's config options other than its mode and its model, with the
   * value each is set to; none when it offers none.
   */
  options(): AgentOption[];
  /**
   * Asks the agent to set a config option through
   * `session/set_config_option`; `options()` then holds what it answered.
   */
  setOption(id: string, value: string): Promise<void>;
  /**
   * The efforts the agent offers for the model it is on, and the one it
   * reports; none when it offers none.
   */
  efforts(): AgentEfforts | undefined;
  /**
   * Asks the agent for an effort through its `thought_level` config option;
   * `efforts()` then holds what it answered. Rejects when it offers none.
   */
  setEffort(id: string): Promise<void>;
  /**
   * Ends the session and returns once its agent process has exited; rejects
   * with `AgentExitError` if that exit cannot be seen even after a kill.
   */
  close(): Promise<void>;
  /**
   * Withdraws what the session still asks of the person, its permissions,
   * forms and links, as its close does, and leaves it open for what its
   * agent says after: a session `/clear` lets go, whose last turn may still
   * say what it cost (CHD-373 S3c). A session that asks nothing has none.
   */
  withdraw?(): void;
}

export async function openSession(
  options: OpenSessionOptions,
): Promise<Session> {
  const { agent, cwd, resume, signal } = options;
  const permissions = new PermissionBridge();
  const elicitations = new ElicitationBridge();
  const plans = new PlanBridge();
  /** The agent's process until its exit is seen. */
  const live = new Set<number>();
  const start = agentStart(agent, options.agentCommand);
  const userServers = options.mcpServers ?? [];
  /** Known once the agent answers; updates before that wait in `early`. */
  let sessionId = resume?.sessionId;
  const early: SessionNotification[] = [];
  /** Whether the session is open, and `state` holds the agent's answer. */
  let opened = false;
  let state = stateOf({});
  /** The session and its subagents, whose updates are the session's. */
  let tree: SessionTree = sessionTree(sessionId ?? '');
  const listeners = new Set<
    (update: SessionUpdate, subagentId?: string) => void
  >();
  /** Updates no listener has heard yet, for the first one to come. */
  const held: Heard[] = [];

  /** Where `notification` belongs, the tree grown by what it announces. */
  const route = (notification: SessionNotification): Heard | undefined => {
    const where = routed(tree, notification);

    tree = where.tree;

    if (!where.heard) {
      return undefined;
    }

    return where.subagentId === undefined
      ? { update: notification.update }
      : { update: notification.update, subagentId: where.subagentId };
  };

  const hear = (heard: Heard) => {
    // A subagent's modes, options and commands are not the session's.
    if (heard.subagentId === undefined) {
      state = foldUpdate(state, heard.update);
    }

    if (listeners.size === 0) {
      held.push(heard);
    }

    for (const listener of listeners) {
      listener(heard.update, heard.subagentId);
    }
  };

  const onTraffic = (traffic: Traffic) => {
    const notification =
      traffic.from === 'agent' ? updateIn(traffic.message) : undefined;

    if (notification === undefined) {
      return;
    }

    if (!opened) {
      early.push(notification);

      return;
    }

    const heard = route(notification);

    if (heard !== undefined) {
      hear(heard);
    }
  };

  const totals = usageCountOf(agent) === 'session';
  const relay = enricherRelay(ENRICHERS, totals);
  const connection = await openAgent({
    command: start.command,
    relay,
    env: { ...start.env, ...agentEnv(process.env) },
    cwd,
    onTraffic,
    onPermission: permissions.handler,
    onElicitation: elicitations.handler,
    onPlan: plans.handler,
    ...(signal === undefined ? {} : { signal }),
  });

  live.add(connection.pid);
  void connection.exited.then(() => live.delete(connection.pid));

  const {
    servers: mcpServers,
    heldBack,
    chord: chordPassed,
  } = serversFor(
    agent,
    connection.init.agentCapabilities?.mcpCapabilities,
    userServers,
    options.chordServer,
    options.noMcpServers === true,
  );

  const shutdown = async () => {
    permissions.close();
    elicitations.close();
    plans.close();
    await connection.close();
  };

  let answer: SessionAnswer;
  let past: readonly PastAction[] = [];

  try {
    if (resume === undefined) {
      const created = await connection.newSession(
        { cwd, mcpServers, ...openingMeta(connection) },
        signal,
      );

      sessionId = created.sessionId;
      tree = sessionTree(sessionId);
      answer = created;
    } else {
      // A task's work is in its own record, beside its parent's.
      const own =
        resume.record === undefined ? [] : await readPast(resume.record);
      const recorded =
        resume.record === undefined
          ? []
          : withTaskWork(
              own,
              await taskPasts(dirname(resume.record), resume.sessionId),
            );
      // On an agent whose answers give the session's running total, the last
      // the session's own record kept, which chord's estimate goes on from.
      const total = totals ? lastTotal(own) : undefined;
      const pasts = pastBySession(resume.sessionId, recorded);

      if (total !== undefined && !pasts.has(resume.sessionId)) {
        pasts.set(resume.sessionId, []);
      }

      // The agent replays nothing of a session resumed from the record, so
      // the enrichers hear its past, the cost it had come to, from there. Each
      // update goes back to the session that sent it, as it did live, so a
      // child's cost and calls never count as the parent's.
      for (const [id, past] of pasts) {
        relay.recall(id, past, id === resume.sessionId ? total : undefined);
      }

      const loaded = await reopen(
        connection,
        resume.sessionId,
        recorded.length > 0,
        cwd,
        mcpServers,
        signal,
      );

      // What the agent replayed came before its answer. A session chord has
      // a record of is drawn from it however the agent reopened it, as only
      // the record keeps what chord did beside the agent: its task agents'
      // work, the messages' senders, the long-lived agents left open. The
      // replay is the past only of a session chord never recorded.
      const replayed = loaded.replays
        ? early.splice(0).flatMap((each) => route(each) ?? [])
        : [];

      answer = loaded.answer;
      past =
        recorded.length > 0
          ? recordActions(
              recorded,
              await runPasts(dirname(resume.record!), resume.sessionId),
            )
          : pastActions(replayed, Date.now());
    }
  } catch (error) {
    try {
      await shutdown();
    } catch (cleanup) {
      throw new AggregateError(
        [error, cleanup],
        'The agent did not start, and did not exit.',
      );
    }

    if (signal?.aborted || resume === undefined) {
      throw error;
    }

    // The agent's own words for a session it does not know rarely say which
    // session that was.
    throw new Error(
      `it cannot resume session ${resume.sessionId}: ${messageOf(error)}`,
      { cause: error },
    );
  }

  const id = sessionId ?? '';

  state = stateOf(answer);
  opened = true;

  for (const each of early.splice(0)) {
    const heard = route(each);

    if (heard !== undefined) {
      hear(heard);
    }
  }

  let closing: Promise<void> | undefined;

  return {
    agent,
    cwd,
    id,
    ...(chordPassed === undefined ? {} : { chordServer: chordPassed }),
    heldBack,
    ...(resume?.record === undefined ? {} : { record: resume.record }),
    ...(resume === undefined
      ? {}
      : {
          resumed: {
            lastUsedAt: resume.lastUsedAt,
            prompt: resume.prompt,
            name: resume.name,
          },
        }),
    permissions,
    elicitations,
    plans,
    agentPids: live,
    exited: connection.exited.then(() => {}),
    gone: () => connection.gone(),
    history: () => past,
    subscribe: (listener) => {
      listeners.add(listener);

      for (const { update, subagentId } of held.splice(0)) {
        listener(update, subagentId);
      }

      return () => listeners.delete(listener);
    },
    prompt: (text, attachments = [], mentions = []) => {
      const blocks: ContentBlock[] = [
        { type: 'text', text },
        ...attachments.map(({ mediaType, data }): ContentBlock => ({
          type: 'image',
          mimeType: mediaType,
          data,
        })),
      ];
      let cancelled = false;
      /** Whether the prompt has gone to the agent, which a cancel then tells. */
      let gone = false;
      const { promise: sent, resolve: went } = Promise.withResolvers<
        readonly ResourceLink[] | undefined
      >();
      const send = (links: readonly ResourceLink[]) => {
        gone = true;

        went(links);

        return connection.prompt({
          sessionId: id,
          prompt: [...blocks, ...links],
        });
      };

      // A prompt without mentions goes at once, as it always has; one with
      // them waits on the walk, and a cancel in that wait keeps it back.
      const answer: Promise<PromptResponse> =
        mentions.length === 0
          ? send([])
          : mentionLinks(mentions, cwd).then((links) => {
              if (cancelled) {
                went(undefined);

                return { stopReason: 'cancelled' };
              }

              return send(links);
            });

      return {
        id: crypto.randomUUID(),
        sent,
        result: answer.then(
          ({ stopReason, usage }): TurnResult => ({
            status: stopReason === 'cancelled' ? 'cancelled' : 'completed',
            stopReason,
            ...(usage ? { usage: tokensOf(usage) } : {}),
          }),
          (error: unknown): TurnResult => {
            // A prompt that went has said so already; this one never did.
            went(undefined);

            const code = codeOf(error);

            return {
              status: 'failed',
              error: {
                message: messageOf(error),
                ...(code === undefined ? {} : { code }),
              },
            };
          },
        ),
        cancel: () => {
          cancelled = true;

          // A prompt still waiting on its mentions never reached the agent:
          // the cancel only keeps it back. Told the agent, it could land on
          // the next turn instead, as the agent may take the next prompt
          // before it (Q42).
          return gone
            ? connection.cancel(id, tree.subagents)
            : Promise.resolve();
        },
      };
    },
    takesImages: () =>
      connection.init.agentCapabilities?.promptCapabilities?.image === true,
    steers: () => connection.steering,
    cutsCallsOnSteer: () => connection.init.agentInfo?.name === CLAUDE_ADAPTER,
    startsOwnCycles: () => connection.init.agentInfo?.name === CLAUDE_ADAPTER,
    steer: async (text) => {
      const { outcome } = await connection.steer({
        sessionId: id,
        prompt: [{ type: 'text', text }],
        _meta: { steering: { idleBehavior: 'promptRequired' } },
      });

      return outcome === 'injected' || outcome === 'startedNewTurn'
        ? outcome
        : 'refused';
    },
    cancel: () => connection.cancel(id, tree.subagents),
    stopSubagent: (subagent) => connection.stopSubagent(subagent),
    models: () => modelsOf(state),
    setModel: async (model) => {
      const key = modelConfigId(state.configOptions);

      if (key !== undefined) {
        const answered = await connection.setConfigOption({
          sessionId: id,
          configId: key,
          value: model,
        });

        state = withOptions(state, answered.configOptions);

        return;
      }

      await connection.setModel({ sessionId: id, modelId: model });

      // The older call answers with nothing; that it answered at all is the
      // agent taking the model, as no update follows it.
      if (isModelState(state.models)) {
        state = {
          ...state,
          models: { ...state.models, currentModelId: model },
        };
      }
    },
    commands: () => state.commands,
    modes: () => modesOf(state),
    setMode: async (mode) => {
      const key = modeConfigId(state.configOptions);

      // An agent that answers with nothing, as Codex's does, is read back by
      // the enrichers, which fill in the update or the options it left out.
      if (key === undefined) {
        await connection.setMode({ sessionId: id, modeId: mode });

        return;
      }

      const answered = await connection.setConfigOption({
        sessionId: id,
        configId: key,
        value: mode,
      });

      state = withOptions(state, answered.configOptions);
    },
    options: () => optionsOf(state),
    setOption: async (key, value) => {
      const answered = await connection.setConfigOption({
        sessionId: id,
        configId: key,
        value,
      });

      state = withOptions(state, answered.configOptions);
    },
    efforts: () => effortsOf(state),
    setEffort: async (effort) => {
      const key = effortsOf(state)?.option;

      if (key === undefined) {
        throw new Error('the agent offers no efforts');
      }

      const answered = await connection.setConfigOption({
        sessionId: id,
        configId: key,
        value: effort,
      });

      state = withOptions(state, answered.configOptions);
    },
    close: () => (closing ??= shutdown()),
    withdraw: () => {
      permissions.close();
      elicitations.close();
      plans.close();
    },
  };
}

/**
 * What chord adds to the request that opens a session, new or again: for
 * Claude's adapter, its prompt suggestions off. The adapter turns them on by
 * default and shows them only to JetBrains AIR, so chord would pay for
 * suggestions it never shows (CHD-439); `false` goes on to its SDK, whose
 * contract is that the agent then predicts none. Nothing for any other
 * agent. The adapter reads its options on new, load and resume alike, and
 * the same value each time lets it reuse a session it still has live.
 */
function openingMeta(connection: Agent): { _meta?: Record<string, unknown> } {
  return connection.init.agentInfo?.name === CLAUDE_ADAPTER
    ? { _meta: { claudeCode: { options: { promptSuggestions: false } } } }
    : {};
}

/**
 * Opens an earlier session again. `session/resume` replays nothing, so it is
 * taken when chord's record holds the past to draw (`recorded`), or when the
 * agent cannot load; else `session/load`, whose replay is the past only when
 * chord has no record.
 */
async function reopen(
  connection: Agent,
  sessionId: string,
  recorded: boolean,
  cwd: string,
  mcpServers: McpServer[],
  signal: AbortSignal | undefined,
): Promise<{ answer: SessionAnswer; replays: boolean }> {
  const offers = connection.init.agentCapabilities ?? {};
  const resumes = Boolean(offers.sessionCapabilities?.resume);
  const request = { sessionId, cwd, mcpServers, ...openingMeta(connection) };

  if (resumes && (recorded || !offers.loadSession)) {
    return {
      answer: await connection.resumeSession(request, signal),
      replays: false,
    };
  }

  return {
    answer: await connection.loadSession(request, signal),
    replays: true,
  };
}

/**
 * The `session/update` in a message the agent sent, when it is one: not
 * checked against ACP's schema, so an update of a kind it does not know
 * still comes through, for the reducer to pass over.
 */
function updateIn(message: unknown): SessionNotification | undefined {
  if (
    typeof message !== 'object' ||
    message === null ||
    'id' in message ||
    !('method' in message) ||
    message.method !== 'session/update' ||
    !('params' in message)
  ) {
    return undefined;
  }

  const { params } = message as { params: unknown };

  if (typeof params !== 'object' || params === null) {
    return undefined;
  }

  const { sessionId, update } = params as Record<string, unknown>;

  return typeof sessionId === 'string' &&
    typeof update === 'object' &&
    update !== null &&
    typeof (update as Record<string, unknown>).sessionUpdate === 'string'
    ? (params as SessionNotification)
    : undefined;
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** A JSON-RPC error's code, as the transcript keeps it. */
function codeOf(error: unknown): string | undefined {
  return typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    typeof error.code === 'number'
    ? String(error.code)
    : undefined;
}
