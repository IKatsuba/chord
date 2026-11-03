/**
 * `chord acp`: chord with no interface, an ACP agent on its input and output,
 * as `headless.ts` is to `-p`. One client connection, any number of sessions,
 * each its own `Conversation` and its own agent process.
 */
import {
  type AgentConnection,
  type ClientCapabilities,
  type CreateElicitationResponse,
  type JsonRpcId,
  type LoadSessionRequest,
  type LoadSessionResponse,
  type McpServer,
  MessageTooLargeError,
  ndJsonStream,
  type NewSessionResponse,
  type PromptResponse,
  RequestError,
  type RequestPermissionResponse,
  type ResumeSessionRequest,
  type SessionNotification,
  type SessionUpdate,
  type StopReason,
  type Usage,
} from '@agentclientprotocol/sdk/unstable';
import { type AcpRequest, connectAgentApp } from './acp/agent_app.ts';
import { foldEvent, NO_FOLD } from './acp/host_fold.ts';
import { seeingWrites } from './acp/stdio.ts';
import {
  NO_TURNS,
  reduceTurns,
  sessionStateOf,
  type TurnInput,
  turnOf,
  type Turns,
} from './acp/upstream_turns.ts';
import { transportOf } from './mcp.ts';
import { DIMCODE_WORDS, dimcodeAtRisk } from './notices.ts';
import type { ChordServer } from './server/server.ts';
import { settingsBoxClaim } from './server/tools.ts';
import { createAgentsHost, type FoldedSession } from './session/agents_host.ts';
import type {
  Conversation,
  ConversationEvent,
} from './session/conversation.ts';
import type { AgentOption } from './session/config.ts';
import {
  createLeaving,
  type LeaveExit,
  type LeaveReason,
  type LeaveStep,
} from './session/leaving.ts';
import type { Place } from './session/place.ts';
import type { ReadLimits } from './session/resource_access.ts';
import type { OpenSessionOptions, Session } from './session/session.ts';
import {
  earlierSessions,
  readRecords,
  type Resume,
  ResumeError,
  sessionById,
} from './session/sessions.ts';
import { signInLines, type SignIn } from './session/sign_in.ts';
import {
  newTeamPrompt,
  teamCommand,
  type TeamCommand,
} from './session/team_command.ts';
import { recordedSelection } from './session/team_selection.ts';
import {
  ACP_TEAM_WORDS,
  commandChunk,
  type CommandSaid,
  notAloneRefusal,
  openedText,
  runText,
  selectedRunRefusal,
  startedText,
  teamsText,
  teamText,
} from './session/upstream_commands.ts';
import {
  failureLines,
  type StartFailure,
  stepWords,
} from './session/start_failure.ts';
import {
  type AgentReport,
  agentStateOf,
  agentUpdate,
  aliasFor,
  answeredConfig,
  asksIn,
  childOf,
  type ChordCommand,
  childSession,
  commandOf,
  commandsIfNone,
  configChange,
  configSetter,
  elicitationReplyOf,
  mapUpdate,
  messageChunk,
  permissionAnswerOf,
  planAnswerOf,
  planPermission,
  promptOf,
  upstreamIdOf,
  type UpstreamSession,
  upstreamSession,
} from './session/upstream.ts';
import type {
  LeftOpen,
  PlanWait,
  TeamShown,
  TurnResult,
} from './session/transcript/types.ts';
import { agentOf, isLead } from './session/window_agents.ts';

/** The `_meta` key chord says its own of ACP under. */
const ACP_META = 'chord/acp';

/** The extensions this chord has, each at its version, as `initialize` says. */
const EXTENSIONS = { 'session/state': 1 } as const;

/** What `_chord/session/state` last said, or would have: none says idle. */
const IDLE = JSON.stringify({ state: 'idle' });

/**
 * What a person who ran it by hand reads on stderr; only a stdin that is a
 * terminal is a person's. A client's stdin is a pipe, and sees no note.
 */
export function byHandNote(stdinIsTerminal: boolean): readonly string[] {
  return stdinIsTerminal
    ? [
        'chord: acp serves ACP on stdin and stdout, for a client that starts it.',
        'chord: nothing to press here. Ctrl-D or Ctrl-C leaves; `chord` opens a window.',
      ]
    : [];
}

/** What a session's directory decides: a place, and the runtimes known there. */
export type AcpPlace = Place & { readonly runtimes: readonly string[] };

export interface AcpOptions {
  readonly input: ReadableStream<Uint8Array>;
  readonly output: WritableStream<Uint8Array>;
  /** One line for the person; it must not throw. */
  stderr(line: string): void;
  /** Ends the process: `process.exit`, or death by the signal. */
  exit(how: LeaveExit): void;
  /** The one agent this process runs, by the name chord knows it. */
  readonly agent: string;
  readonly version: string;
  /** Where records are kept, as the window's are. */
  readonly stateDir: string;
  open(options: OpenSessionOptions): Promise<Session>;
  place(cwd: string): Promise<AcpPlace>;
  readonly home?: string | undefined;
  /** The user's config directory, whose `chord/teams/` every session reads. */
  readonly configHome?: string | undefined;
  /** chord's own MCP server, shared by every session; none gives no tools. */
  readonly server?: ChordServer;
  /** The providers' limits, shared by every session, which the way out closes. */
  readonly resources?: {
    readonly read: ReadLimits;
    /** What it could not clean up, which makes the way out unclean. */
    close(): Promise<readonly string[]>;
  };
  readonly leaveMs?: number;
  readonly drainMs?: number;
}

/** A running `chord acp`. */
export interface AcpRun {
  /** The one way out, for what starts it from outside: a signal, a crash. */
  leave(reason: LeaveReason): Promise<void>;
}

/** A long-lived child of a session, as the client knows it. */
interface ChildRoute {
  /** Its immediate parent's id: main's, or its lead's. */
  readonly parent: string;
  readonly upstreamId: string;
  /** None until it is up. */
  upstream?: UpstreamSession;
  /** What it said or asked before that, which goes up in order then. */
  held: (() => void)[];
  stopReason?: StopReason;
  gone?: string;
  failed?: string;
  /** What was last said of it, and how, so only a change goes up. */
  told?: AgentReport;
  sent?: string;
}

/** Whoever an ask comes from: main, or a long-lived child. */
interface Asker {
  readonly conversation: Conversation;
  readonly upstream?: UpstreamSession | undefined;
}

/** A session this process holds, from its start until its agent is gone. */
interface Entry {
  readonly host: ReturnType<typeof createAgentsHost>;
  /** Main's, kept: the host lets go of it as soon as it closes. */
  readonly conversation: Conversation;
  /** Main's key in its host. */
  readonly key: number | undefined;
  /** What the host reads back of each of its sessions. */
  readonly folds: Map<number, FoldedSession>;
  /** Its long-lived children, by their keys. */
  readonly routes: Map<number, ChildRoute>;
  /** Who was left open when the session was left, for its answer to name. */
  leftOpen?: readonly LeftOpen[];
  /** Its name on stderr, for a way out it holds up. */
  readonly name: string;
  /** None until it is up. */
  upstream?: UpstreamSession;
  /** Whether the client has its id: what comes before waits for that. */
  live: boolean;
  /** What goes up once the client has its id. */
  held: (() => void)[];
  /**
   * Set on a `session/load`: its past, which goes up ahead of the answer.
   * A resume keeps nothing of it.
   */
  past?: ConversationEvent[];
  /** The id a load or a resume claimed for it. */
  reopens?: string;
  /** While the conversation replays the session's past, which is no news. */
  replaying: boolean;
  turns: Turns;
  /** What `_chord/session/state` last said of it, so only a change goes. */
  stateSent: string;
  opening?:
    | {
        readonly requestId: JsonRpcId;
        resolve(answer: NewSessionResponse): void;
        reject(error: unknown): void;
      }
    | undefined;
  /** Its agent went: it takes no more prompts, and closes when it can. */
  gone: boolean;
  noticed: boolean;
  closing?: Promise<void>;
}

function closingError(): RequestError {
  return new RequestError(-32603, 'chord is closing');
}

export function runAcp(options: AcpOptions): AcpRun {
  const { agent } = options;
  const wire = seeingWrites(ndJsonStream(options.output, options.input));
  /** Each session the client can name, by the name it has for it. */
  const sessions = new Map<string, Entry>();
  /**
   * The ids a load or a resume is opening again: taken from before its first
   * await until it is up or has failed, or a second could open one record twice.
   */
  const reopening = new Set<string>();
  /** Every session not closed yet, those still starting and those gone too. */
  const entries = new Set<Entry>();
  /** Each ask out with the client, by chord's id for it; its withdrawal. */
  const asks = new Map<string, AbortController>();
  /** Each `session/prompt` not yet answered. */
  const answers = new Map<
    JsonRpcId,
    {
      resolve(answer: { stopReason: string; usage?: unknown }): void;
      reject(error: unknown): void;
    }
  >();
  /** Each command still at its work, none of which any turn answers. */
  const commands = new Map<JsonRpcId, (answer: PromptResponse) => void>();
  let capabilities: ClientCapabilities | undefined;
  let starts = 0;
  // One client asks for every session, so one `settings` box among them.
  const settingsBox = settingsBoxClaim();

  const say = (line: string) => options.stderr(line);
  const send = (notification: SessionNotification) => {
    connection.client.notify('session/update', notification).catch(() => {
      // The connection went; the way out has it from there.
    });
  };

  const agentState = (entry: Entry) => entry.conversation.session?.agentState();

  const closeEntry = (entry: Entry): Promise<void> => {
    entry.host.closeRuntimes();

    for (const key of [...entry.routes.keys()]) {
      tellClosed(entry, key);
    }

    entry.closing ??= entry.host.sessions
      .closeAll()
      .catch((error: unknown) => {
        // Each agent's own words, for stderr to say what did not close.
        throw error instanceof AggregateError
          ? new Error(
              error.errors
                .map((each: unknown) =>
                  each instanceof Error ? each.message : String(each),
                )
                .join('; '),
            )
          : error;
      })
      .finally(() => {
        entries.delete(entry);
      });

    return entry.closing;
  };

  const relay = (
    entry: Entry,
    update: SessionUpdate,
    subagentId?: string,
  ): void => {
    if (entry.upstream === undefined || !entry.live) {
      entry.held.push(() => relay(entry, update, subagentId));

      return;
    }

    const mapped = mapUpdate(
      entry.upstream,
      capabilities ?? {},
      update,
      subagentId,
    );

    entry.upstream = mapped.session;

    if (mapped.notification !== undefined) {
      send(mapped.notification);
    }
  };

  /**
   * Main's state, if it changed: its turn by who began it, and its own asks
   * from what its fold has open. A child's is on its `subagent_update`.
   */
  const tellState = (entry: Entry): void => {
    if (
      entry.upstream === undefined ||
      !entry.live ||
      entry.key === undefined
    ) {
      return;
    }

    const asking =
      agentStateOf(entry.folds.get(entry.key) ?? NO_FOLD).state ===
      'requires_action';
    const state = sessionStateOf(entry.turns, asking);
    const said = JSON.stringify(state);

    if (said === entry.stateSent) {
      return;
    }

    entry.stateSent = said;

    connection.client
      .notify('_chord/session/state', {
        sessionId: entry.upstream.upstreamId,
        ...state,
      })
      .catch(() => {
        // The connection went; the way out has it from there.
      });
  };

  const tellConfig = (entry: Entry): void => {
    const state = agentState(entry);

    if (entry.upstream === undefined || !entry.live || state === undefined) {
      return;
    }

    const changed = configChange(entry.upstream, state);

    entry.upstream = changed.session;

    if (changed.notification !== undefined) {
      send(changed.notification);
    }
  };

  /**
   * One request to the client, settled once. A late answer, after its ask was
   * withdrawn, finds nothing to settle; an error is no answer, whatever the ask
   * makes of that. Nothing is settled when the connection went: the session's
   * close tells the agent `cancelled`.
   */
  const ask = <Answer>(
    id: string,
    method: string,
    params: object,
    settle: (answer: Answer | undefined) => void,
  ): void => {
    const withdrawal = new AbortController();

    asks.set(id, withdrawal);
    connection.client
      .request<Answer, object>(method, params, {
        cancellationSignal: withdrawal.signal,
      })
      .then(
        (answer) => {
          if (asks.delete(id)) {
            settle(answer);
          }
        },
        (error: unknown) => {
          if (!connection.signal.aborted && asks.delete(id)) {
            say(
              `chord: the client answered ${method} with an error: ${
                error instanceof Error ? error.message : String(error)
              }`,
            );
            settle(undefined);
          }
        },
      );
  };

  const withdrawn = (id: string): void => {
    asks.get(id)?.abort();
    asks.delete(id);
  };

  /** Runs once the client has the session's id; at once when it has. */
  const once = (entry: Entry, go: () => void): void => {
    if (entry.live) {
      go();
    } else {
      entry.held.push(go);
    }
  };

  const askPermission = (
    { conversation, upstream }: Asker,
    id: string,
    subagentId: string | undefined,
  ): void => {
    const request = conversation.permissionRequest(id);

    if (request === undefined || upstream === undefined) {
      return;
    }

    // A task's own agent asks under its own session, which the client knows
    // by the task's id.
    const named = subagentId ?? request.sessionId;

    // A session's own ask names no subagent, so one that names the session is
    // a task's agent passing itself off as it.
    if (!asksIn(upstream, named) || subagentId === upstream.agentId) {
      say(`chord: refused a permission for a session it does not know`);
      conversation.reject(id);

      return;
    }

    // It can name no session that client knows, and must not wait unseen.
    if (
      (upstream.nested === true || named !== upstream.agentId) &&
      !capabilities?.subagents
    ) {
      say(
        `chord: refused a subagent's permission: the client takes no subagents`,
      );
      conversation.reject(id);

      return;
    }

    ask<RequestPermissionResponse>(
      id,
      'session/request_permission',
      { ...request.raw, sessionId: upstreamIdOf(upstream, named) },
      (response) => {
        const answer = permissionAnswerOf(request.options, response);

        if (answer === 'reject') {
          conversation.reject(id);
        } else {
          conversation.choose(id, answer.optionId);
        }
      },
    );
  };

  const askElicitation = (
    { conversation, upstream }: Asker,
    id: string,
    subagentId: string | undefined,
  ): void => {
    const request = conversation.elicitationRequest(id);

    if (request === undefined || upstream === undefined) {
      return;
    }

    const sessionId =
      request.sessionId === undefined
        ? undefined
        : (subagentId ?? request.sessionId);

    // One scoped to a request names none of the client's.
    if (sessionId === undefined || !asksIn(upstream, sessionId)) {
      conversation.answer(id, { action: 'cancel' });

      return;
    }

    // A subagent's names none that client knows, and must not wait unseen.
    if (
      (upstream.nested === true || sessionId !== upstream.agentId) &&
      !capabilities?.subagents
    ) {
      say(`chord: refused a subagent's form: the client takes no subagents`);
      conversation.answer(id, { action: 'cancel' });

      return;
    }

    ask<CreateElicitationResponse>(
      id,
      'elicitation/create',
      { ...request.raw, sessionId: upstreamIdOf(upstream, sessionId) },
      (response) => conversation.answer(id, elicitationReplyOf(response)),
    );
  };

  const askPlan = ({ conversation, upstream }: Asker, plan: PlanWait): void => {
    // It can name no session that client knows, and is never a yes.
    if (upstream?.nested === true && !capabilities?.subagents) {
      say(`chord: refused a subagent's plan: the client takes no subagents`);
      conversation.answerPlan(plan.id, { type: 'cancelled' });

      return;
    }

    ask<RequestPermissionResponse>(
      plan.id,
      'session/request_permission',
      planPermission(upstream?.upstreamId ?? '', plan),
      (response) =>
        conversation.answerPlan(plan.id, planAnswerOf(plan, response)),
    );
  };

  /** A child as the client knows it, once it is placed in its host. */
  const routeOf = (entry: Entry, key: number): ChildRoute | undefined => {
    const had = entry.routes.get(key);

    if (had !== undefined) {
      return had;
    }

    const { agents } = entry.host.sessions;
    const child = agentOf(agents, key)?.child;
    const main = entry.upstream?.upstreamId;

    if (child === undefined || main === undefined) {
      return undefined;
    }

    const lead = agents.children.find((each) => each.id === child.lead);
    const parent =
      lead === undefined
        ? main
        : (routeOf(entry, lead.key)?.upstreamId ?? main);
    const route: ChildRoute = {
      parent,
      upstreamId: `${parent}/${child.id}`,
      held: [],
    };

    entry.routes.set(key, route);

    return route;
  };

  /** What chord says of a child, if it has changed. */
  const report = (entry: Entry, key: number): void => {
    const route = routeOf(entry, key);
    const child = agentOf(entry.host.sessions.agents, key)?.child;

    if (route === undefined || child === undefined) {
      return;
    }

    const session = child.conversation.session;

    route.told = {
      parent: route.parent,
      upstreamId: route.upstreamId,
      title: child.name,
      state:
        route.gone === undefined
          ? agentStateOf(entry.folds.get(key) ?? NO_FOLD, route.stopReason)
          : { state: 'unknown' },
      runtime: child.runtime,
      model: session?.models()?.current ?? child.model,
      effort: session?.efforts()?.current,
      mode: session?.modes()?.current ?? child.mode,
      team: child.team,
      role: isLead(child)
        ? 'lead'
        : child.lead === undefined
          ? undefined
          : 'member',
      gone: route.gone,
      failed: route.failed,
    };

    const notification = agentUpdate(capabilities ?? {}, route.told);
    const said = JSON.stringify(notification);

    if (notification !== undefined && said !== route.sent) {
      route.sent = said;

      send(notification);
    }
  };

  /** A child gone: said once, under what was last said of it. */
  const tellClosed = (entry: Entry, key: number): void => {
    const told = entry.routes.get(key)?.told;

    entry.routes.delete(key);

    if (told === undefined) {
      return;
    }

    const notification = agentUpdate(capabilities ?? {}, {
      ...told,
      closed: true,
    });

    if (notification !== undefined) {
      send(notification);
    }
  };

  /** What chord carries on past: stderr always, and `notice` for who takes it. */
  const warn = (entry: Entry, message: string): void => {
    say(`chord: ${message}`);
    relay(entry, {
      sessionUpdate: 'notice',
      severity: 'warning',
      title: message,
    });
  };

  /** dimcode's notice, once a session's, if `runtime` has it at risk. */
  const tellDimcode = (
    entry: Entry,
    runtime: string,
    options: readonly AgentOption[] | undefined,
  ): void => {
    if (
      entry.noticed ||
      options === undefined ||
      !dimcodeAtRisk(runtime, options)
    ) {
      return;
    }

    entry.noticed = true;

    for (const paragraph of DIMCODE_WORDS.paragraphs) {
      say(`chord: ${paragraph}`);
    }

    relay(entry, {
      sessionUpdate: 'notice',
      severity: 'warning',
      title: DIMCODE_WORDS.title,
      description: DIMCODE_WORDS.paragraphs.join('\n\n'),
    });
  };

  const answerOf = (result: TurnResult) =>
    result.status === 'failed'
      ? new RequestError(-32603, result.error.message)
      : {
          stopReason: result.stopReason,
          ...(result.usage === undefined
            ? {}
            : { usage: result.usage as Usage }),
        };

  const step = (entry: Entry, input: TurnInput): void => {
    const { turns, sends } = reduceTurns(entry.turns, input);

    entry.turns = turns;

    for (const send of sends) {
      switch (send.type) {
        case 'answer': {
          const answer = answerOf(send.result);
          const waiting = answers.get(send.requestId);

          answers.delete(send.requestId);

          if (answer instanceof RequestError) {
            waiting?.reject(answer);
          } else {
            waiting?.resolve(answer);
          }

          break;
        }
        case 'cancelled':
          answers.get(send.requestId)?.resolve({ stopReason: 'cancelled' });
          answers.delete(send.requestId);

          break;
        case 'session_gone': {
          const waiting = answers.get(send.requestId);

          answers.delete(send.requestId);
          waiting?.reject(
            RequestError.sessionNotFound(entry.upstream?.upstreamId ?? ''),
          );
          // Not left for a dead session to play.
          entry.conversation.cancelPrompt(send.turnId);

          break;
        }
        case 'message':
          relay(
            entry,
            messageChunk(entry.upstream?.upstreamId ?? '', send.text, send.from)
              .update,
          );

          break;
      }
    }
  };

  const failedStart = (
    message: string,
    signIn: SignIn | undefined,
    failure: StartFailure | undefined,
  ): RequestError => {
    const words = stepWords(message, failure);
    const lines = [
      ...failureLines(agent, failure),
      ...(signIn === undefined ? [] : signInLines(agent, signIn)),
    ];

    return new RequestError(signIn === undefined ? -32603 : -32000, words, {
      lines,
    });
  };

  const connected = (entry: Entry, agentId: string): void => {
    const { opening } = entry;
    const state = agentState(entry);

    if (opening === undefined || state === undefined) {
      return;
    }

    // A reopened session is under the id the client asked for, claimed for it.
    // Anything else keeps clear of what is claimed as of what is live.
    const upstreamId =
      entry.reopens === agentId
        ? agentId
        : aliasFor(new Set([...sessions.keys(), ...reopening]), agentId);
    const session = entry.conversation.session;
    const { session: upstream, configOptions } = answeredConfig(
      upstreamSession(agentId, upstreamId),
      state,
    );

    entry.upstream = upstream;
    entry.opening = undefined;

    sessions.set(upstreamId, entry);

    const release = () => {
      entry.live = true;

      for (const go of entry.held.splice(0)) {
        go();
      }

      tellConfig(entry);
      tellState(entry);
    };

    const answered = wire.expect(opening.requestId);

    // An agent that sends no list still shows chord's, once its session is
    // answered and what it held has gone, whichever way it opened.
    const tellCommands = () => {
      if (entry.upstream !== undefined) {
        const { session: told, notification } = commandsIfNone(entry.upstream);

        entry.upstream = told;

        if (notification !== undefined) {
          send(notification);
        }
      }
    };

    // The client asked for this id: its past goes ahead of the answer. A new
    // id goes first, as nothing of the session can be placed without it.
    if (entry.past === undefined) {
      void answered.then(() => {
        release();
        tellCommands();
      });
    } else {
      void answered.then(tellCommands);

      entry.live = true;

      for (const event of entry.past.splice(0)) {
        if (event.type === 'prompt') {
          relay(entry, messageChunk(upstreamId, event.text, event.from).update);
        } else if (event.type === 'update') {
          relay(entry, event.update, event.subagentId);
        }
      }
    }

    opening.resolve({
      sessionId: upstreamId,
      configOptions,
      _meta: {
        [ACP_META]: { image: session?.takesImages() === true },
        ...(session === undefined || session.heldBack.length === 0
          ? {}
          : { 'chord/held_back': session.heldBack }),
        ...(entry.leftOpen === undefined
          ? {}
          : { 'chord/left_open': entry.leftOpen }),
      },
    });

    if (entry.past !== undefined) {
      release();
    }

    tellDimcode(entry, agent, entry.conversation.session?.options());
  };

  const heard = (entry: Entry, event: ConversationEvent): void => {
    if (entry.replaying) {
      entry.past?.push(event);

      if (event.type === 'left_open') {
        entry.leftOpen = event.agents;
      }

      return;
    }

    switch (event.type) {
      case 'update':
        relay(entry, event.update, event.subagentId);
        tellConfig(entry);

        break;
      case 'modes':
      case 'model':
        tellConfig(entry);

        break;
      case 'options':
        tellConfig(entry);
        tellDimcode(entry, agent, entry.conversation.session?.options());

        break;
      case 'prompt':
        step(entry, {
          type: 'prompt',
          turnId: event.turnId,
          text: event.text,
          ...(event.from === undefined ? {} : { from: event.from }),
          ...(event.into === undefined ? {} : { into: event.into }),
        });

        break;
      case 'result':
        step(entry, {
          type: 'result',
          turnId: event.turnId,
          result: event.result,
        });

        if (entry.gone && entry.turns.lost === undefined) {
          void closeEntry(entry).catch(() => {});
        }

        break;
      case 'queue_withdrawn':
        step(entry, {
          type: 'queue_withdrawn',
          ...(event.turnIds === undefined ? {} : { turnIds: event.turnIds }),
        });

        break;
      case 'cycle_started':
      case 'self_started':
        step(entry, { type: event.type, turnId: event.turnId });

        break;
      case 'disconnected':
        entry.gone = true;

        if (entry.upstream !== undefined) {
          sessions.delete(entry.upstream.upstreamId);
        }

        step(entry, { type: 'disconnected' });

        if (entry.turns.lost === undefined) {
          void closeEntry(entry).catch(() => {});
        }

        break;
      case 'permission_requested':
        once(entry, () =>
          askPermission(
            entry,
            event.permission.id,
            event.permission.subagentId,
          ),
        );

        break;
      case 'elicitation_requested':
        once(entry, () =>
          askElicitation(
            entry,
            event.elicitation.id,
            event.elicitation.subagentId,
          ),
        );

        break;
      case 'plan_requested':
        once(entry, () => askPlan(entry, event.plan));

        break;
      case 'permission_settled':
      case 'elicitation_settled':
      case 'plan_settled':
        // The client's own answer has left the table already.
        withdrawn(event.id);

        break;
      case 'connected':
        connected(entry, event.sessionId);

        break;
      case 'connect_failed': {
        const { opening } = entry;

        entry.opening = undefined;

        const error = failedStart(event.message, event.signIn, event.failure);

        void closeEntry(entry)
          .catch(() => {})
          .then(() => opening?.reject(error));

        break;
      }
      case 'failed':
        // A set the client asked for is that request's error instead.
        if (!/^(mode|model)-/.test(event.turnId)) {
          warn(entry, event.message);
        }

        break;
      case 'warned':
        warn(entry, event.message);

        break;
      default:
        break;
    }

    tellState(entry);
  };

  /** A long-lived child's event, as the client hears of it. */
  const childHeard = (
    entry: Entry,
    key: number,
    event: ConversationEvent,
  ): void => {
    const route = routeOf(entry, key);
    const child = entry.host.conversationAt(key);

    if (route === undefined || child === undefined) {
      return;
    }

    const asker = (): Asker => ({
      conversation: child,
      upstream: route.upstream,
    });
    // A session's subscribers hear what it buffered ahead of `connected`.
    const whenUp = (go: () => void) => {
      if (route.upstream === undefined) {
        route.held.push(go);
      } else {
        go();
      }
    };

    const up = (update: SessionUpdate, subagentId?: string) => {
      if (route.upstream === undefined) {
        return;
      }

      const mapped = mapUpdate(
        route.upstream,
        capabilities ?? {},
        update,
        subagentId,
      );

      route.upstream = mapped.session;

      if (mapped.notification !== undefined) {
        send(mapped.notification);
      }
    };

    switch (event.type) {
      case 'connected':
        route.upstream = childSession(event.sessionId, route.upstreamId);

        for (const go of route.held.splice(0)) {
          go();
        }

        break;
      // A fresh session under the same identity: nothing of the last holds.
      case 'cleared':
        delete route.upstream;
        delete route.stopReason;
        delete route.gone;
        delete route.failed;

        route.held = [];

        break;
      case 'connect_failed':
        route.failed = event.message;

        break;
      case 'disconnected':
        route.gone = 'exited';

        break;
      case 'update':
        whenUp(() => up(event.update, event.subagentId));

        break;
      case 'prompt':
        delete route.stopReason;

        whenUp(() =>
          up(messageChunk(route.upstreamId, event.text, event.from).update),
        );

        break;
      case 'result':
        if (event.result.status !== 'failed') {
          route.stopReason = event.result.stopReason as StopReason;
        }

        break;
      case 'permission_requested':
        whenUp(() =>
          once(entry, () =>
            askPermission(
              asker(),
              event.permission.id,
              event.permission.subagentId,
            ),
          ),
        );

        break;
      case 'elicitation_requested':
        whenUp(() =>
          once(entry, () =>
            askElicitation(
              asker(),
              event.elicitation.id,
              event.elicitation.subagentId,
            ),
          ),
        );

        break;
      case 'plan_requested':
        whenUp(() => once(entry, () => askPlan(asker(), event.plan)));

        break;
      case 'permission_settled':
      case 'elicitation_settled':
      case 'plan_settled':
        withdrawn(event.id);

        break;
      default:
        break;
    }

    report(entry, key);
  };

  const openEntry = (
    place: AcpPlace,
    cwd: string,
    servers: readonly McpServer[],
    resume?: { readonly from: Resume; readonly replays: boolean },
  ): Entry => {
    starts += 1;

    const folds = new Map<number, FoldedSession>();
    const host = createAgentsHost(
      {
        place: { ...place, cwd },
        runtimes: place.runtimes,
        home: options.home,
        configHome: options.configHome,
        stateDir: options.stateDir,
        open: (opening) =>
          options.open({
            ...opening,
            onElicitationComplete: (params) => {
              connection.client
                .notify('elicitation/complete', params)
                .catch(() => {});
            },
          }),
        server: options.server,
        resources: options.resources?.read,
        resume: resume?.from,
        mainServers: servers,
        settingsBox,
      },
      {
        heard: (key, event) => {
          folds.set(key, foldEvent(folds.get(key), event));

          if (key === entry.key) {
            heard(entry, event);
          } else {
            childHeard(entry, key, event);
          }
        },
        replayed: (_key, replay) => {
          entry.replaying = true;

          try {
            replay();
          } finally {
            entry.replaying = false;
          }
        },
        // A close takes main out of the host first: what it still says, a
        // cancelled turn's end and its asks withdrawn, is told as ever.
        closingHeard: (key, event) => {
          if (key === entry.key) {
            heard(entry, event);
          } else if (
            // A child told closed has nothing more to say; what it asked
            // is still out with the client until it is withdrawn.
            event.type === 'permission_settled' ||
            event.type === 'elicitation_settled' ||
            event.type === 'plan_settled'
          ) {
            withdrawn(event.id);
          }
        },
        told: (event) => {
          if (event.type === 'agent_opened') {
            // Placed in the host only once the call that told this returns.
            queueMicrotask(() => report(entry, event.key));
          } else if (event.type === 'session_closed') {
            tellClosed(entry, event.key);
            folds.delete(event.key);
          }
        },
        stateOf: (key) => folds.get(key),
        // Main's goes by `heard`, which has its options as they stand.
        watched: (id, runtime, event) => {
          if (event.type === 'options' && id !== `main:${entry.key}`) {
            tellDimcode(entry, runtime, event.options);
          }
        },
      },
    );

    const key = host.sessions.start(agent);

    const entry: Entry = {
      host,
      key,
      folds,
      routes: new Map(),
      conversation: host.sessions.agents.main!.conversation,
      name: `session ${starts}`,
      live: false,
      held: [],
      turns: NO_TURNS,
      stateSent: IDLE,
      gone: false,
      noticed: false,
      replaying: false,
      ...(resume?.replays === true ? { past: [] } : {}),
      ...(resume === undefined ? {} : { reopens: resume.from.sessionId }),
    };

    entries.add(entry);

    return entry;
  };

  /** Until the session is up, its start given up on by a cancel of the request. */
  const up = (
    entry: Entry,
    requestId: JsonRpcId,
    signal: AbortSignal,
  ): Promise<NewSessionResponse> =>
    new Promise((resolve, reject) => {
      entry.opening = { requestId, resolve, reject };

      signal.addEventListener(
        'abort',
        () => {
          entry.opening = undefined;

          void closeEntry(entry)
            .catch(() => {})
            .then(() => reject(RequestError.requestCancelled()));
        },
        { once: true },
      );
    });

  /** What a client's servers and the session's directory start a session on. */
  const placed = async (
    params: { readonly cwd: string; readonly mcpServers?: McpServer[] | null },
    signal: AbortSignal,
  ): Promise<{ place: AcpPlace; servers: McpServer[] }> => {
    const asked = params.mcpServers ?? [];
    const refused = asked.find((server) => transportOf(server) === 'acp');

    if (refused !== undefined) {
      throw RequestError.invalidParams(
        undefined,
        `MCP server ${refused.name} has an acp transport, which chord does not take from a client.`,
      );
    }

    const place = await options.place(params.cwd);

    refuseIfClosing();

    // Before any host: a refused command must start nothing, and the host's
    // own refusal is for a child, whose parent is up to hear it.
    const startRefused = place.startupOf(agent)?.refused;

    if (startRefused !== undefined) {
      throw new RequestError(-32603, startRefused);
    }

    // A cancel while the place was read: its signal has fired already, and
    // no agent is to be started for it.
    if (signal.aborted) {
      throw RequestError.requestCancelled();
    }

    // A client's is the nearest layer, by name.
    const servers = new Map(
      [...place.mcpServers.map(({ server }) => server), ...asked].map(
        (server) => [server.name, server],
      ),
    );

    return { place, servers: [...servers.values()] };
  };

  /** A session opened again, under the id the client asked for. */
  const reopened = async (
    {
      params,
      requestId,
      signal,
    }: AcpRequest<LoadSessionRequest | ResumeSessionRequest>,
    replays: boolean,
  ): Promise<LoadSessionResponse> => {
    refuseIfClosing();

    const { sessionId } = params;

    if (sessions.has(sessionId) || reopening.has(sessionId)) {
      throw RequestError.invalidParams(
        undefined,
        `Session ${sessionId} is already open here.`,
      );
    }

    reopening.add(sessionId);

    try {
      const { sessionId: _id, ...answer } = await reopen(
        { params, requestId, signal },
        replays,
      );

      return answer;
    } finally {
      reopening.delete(sessionId);
    }
  };

  const reopen = async (
    {
      params,
      requestId,
      signal,
    }: AcpRequest<LoadSessionRequest | ResumeSessionRequest>,
    replays: boolean,
  ): Promise<NewSessionResponse> => {
    const { sessionId, cwd } = params;
    let from: Resume;

    try {
      from = sessionById(await readRecords(options.stateDir), sessionId, {
        agent,
        cwd,
      });
    } catch (error) {
      if (error instanceof ResumeError) {
        throw RequestError.invalidParams(undefined, error.message);
      }

      throw error;
    }

    if (from.cwd !== cwd) {
      throw RequestError.invalidParams(
        undefined,
        `Session ${sessionId} is in ${from.cwd}.`,
      );
    }

    const { place, servers } = await placed(params, signal);

    return up(
      openEntry(place, cwd, servers, { from, replays }),
      requestId,
      signal,
    );
  };

  const refuseIfClosing = () => {
    if (leaving.started()) {
      throw closingError();
    }
  };

  const named = (sessionId: string): Entry => {
    const entry = sessions.get(sessionId);

    if (entry === undefined) {
      throw RequestError.sessionNotFound(sessionId);
    }

    return entry;
  };

  /**
   * A cancel of a child of `entry`, if `sessionId` names one: a long-lived one's
   * turn stops and it stays open, a task of chord's ends, and an agent's own
   * subagent is stopped by its agent.
   */
  const cancelledIn = (entry: Entry, sessionId: string): boolean => {
    const askers: Asker[] = [entry];

    for (const [key, route] of entry.routes) {
      const child = entry.host.conversationAt(key);

      if (route.upstreamId === sessionId) {
        child?.interrupt();

        return true;
      }

      if (child !== undefined) {
        askers.push({ conversation: child, upstream: route.upstream });
      }
    }

    for (const { conversation, upstream } of askers) {
      const id =
        upstream === undefined ? undefined : childOf(upstream, sessionId);

      if (id !== undefined) {
        const task = conversation.task(id);

        if (task === undefined) {
          void conversation.stopSubagent(id).catch(() => {
            // The subagent may have ended before the stop landed.
          });
        } else {
          task.cancel('x');
        }

        return true;
      }
    }

    return false;
  };

  /**
   * What a command came to, as one chunk ahead of its answer: not an error, as
   * nothing failed at the protocol's level, and no turn of the agent's.
   */
  const commandAnswered = (
    entry: Entry,
    name: ChordCommand['name'],
    { text, failed }: CommandSaid,
  ): PromptResponse => {
    send(commandChunk(entry.upstream?.upstreamId ?? '', name, text, failed));

    return { stopReason: 'end_turn' };
  };

  /** Answered by its work, or once by the way out, whichever comes first. */
  const commanding = (
    entry: Entry,
    requestId: JsonRpcId,
    name: ChordCommand['name'],
    work: Promise<CommandSaid>,
  ): Promise<PromptResponse> => {
    const { promise, resolve, reject } =
      Promise.withResolvers<PromptResponse>();

    commands.set(requestId, resolve);

    void work.then(
      (said) => {
        if (commands.delete(requestId)) {
          resolve(commandAnswered(entry, name, said));
        }
      },
      (error: unknown) => {
        if (commands.delete(requestId)) {
          reject(error);
        }
      },
    );

    return promise;
  };

  const CLOSED: CommandSaid = {
    text: 'This session has closed',
    failed: true,
  };

  /** What a command's form said of a run, a team or an agent, as text. */
  const saidOf = (
    shown: TeamShown,
    typed: string,
    made: (answer: {
      readonly name: string;
      readonly agent: string;
      readonly note?: string;
    }) => string,
  ): CommandSaid => {
    switch (shown.kind) {
      case 'said':
        return { text: shown.text, failed: shown.failed };
      case 'ran':
        return {
          text: made(
            shown.call.answer as {
              name: string;
              agent: string;
              note?: string;
            },
          ),
          failed: false,
        };
      case 'show':
        return {
          text: teamText(shown.name, shown.file, shown.team),
          failed: false,
        };
      case 'receipt':
        return {
          text: selectedRunRefusal(
            typed,
            recordedSelection(shown.call)?.runId ?? typed,
          ),
          failed: true,
        };
      default:
        return CLOSED;
    }
  };

  /** `/team`'s forms but `new`, which is a turn of the agent's. */
  const teamSaid = async (
    { host }: Entry,
    asked: Exclude<TeamCommand, { readonly form: 'new' }>,
  ): Promise<CommandSaid> => {
    switch (asked.form) {
      case 'refused':
        return { text: asked.problem, failed: true };
      case 'list': {
        const listing = await host.listTeams();

        return listing === undefined
          ? CLOSED
          : { text: teamsText(listing, Date.now()), failed: false };
      }
      case 'show':
        return saidOf(
          await host.showTyped(asked.name, ({ file, lead, run, members }) =>
            run.selected === undefined
              ? {
                  kind: 'said',
                  text: runText({
                    name: lead.name,
                    file,
                    team: run.team,
                    job: run.job,
                    since: lead.openedAt,
                    open: members.map(({ name }) => name),
                    now: Date.now(),
                  }),
                  failed: false,
                }
              : {
                  kind: 'said',
                  text: selectedRunRefusal(
                    asked.name,
                    run.selected.receipt.runId,
                  ),
                  failed: true,
                },
          ),
          asked.name,
          () => '',
        );
      case 'run':
        return saidOf(
          await host.runTyped(asked.name, asked.job),
          asked.name,
          ({ name, note }) => startedText(asked.name, name, note),
        );
      case 'stop': {
        let said = CLOSED;

        host.stopTyped(
          asked.name,
          (shown) => {
            said = saidOf(shown, asked.name, () => '');
          },
          ACP_TEAM_WORDS,
        );

        return said;
      }
    }
  };

  /** A set's refusal as that request's error, the agent's words kept. */
  const refusal = (error: unknown): RequestError =>
    error instanceof RequestError
      ? error
      : new RequestError(
          -32603,
          error instanceof Error ? error.message : String(error),
        );

  const leaving = createLeaving({
    answer: () => {
      for (const id of [...asks.keys()]) {
        withdrawn(id);
      }

      for (const [requestId, answer] of commands) {
        void wire.expect(requestId);
        answer({ stopReason: 'cancelled' });
      }

      commands.clear();

      for (const entry of [...entries]) {
        for (const requestId of entry.turns.bound.values()) {
          void wire.expect(requestId);
        }

        step(entry, { type: 'closing' });

        const { opening } = entry;

        if (opening !== undefined) {
          entry.opening = undefined;

          void wire.expect(opening.requestId);
          opening.reject(closingError());
        }
      }
    },
    drained: () => wire.drained(),
    closeConnection: () => {
      connection.close();
    },
    get steps(): readonly LeaveStep[] {
      const { server, resources } = options;

      return [
        ...[...entries].map((entry) => ({
          name: entry.upstream?.upstreamId ?? entry.name,
          run: () => closeEntry(entry),
        })),
        ...(server === undefined
          ? []
          : [{ name: "chord's server", run: () => server.close() }]),
        ...(resources === undefined
          ? []
          : [
              {
                name: 'resource readers',
                run: async () => {
                  const warnings = await resources.close();

                  if (warnings.length > 0) {
                    throw new Error(warnings.join('; '));
                  }
                },
              },
            ]),
      ];
    },
    stderr: say,
    exit: options.exit,
    ...(options.leaveMs === undefined ? {} : { leaveMs: options.leaveMs }),
    ...(options.drainMs === undefined ? {} : { drainMs: options.drainMs }),
  });

  const connection: AgentConnection = connectAgentApp(
    {
      initialize: ({ params }) => {
        capabilities ??= params.clientCapabilities ?? {};

        return {
          protocolVersion: 1,
          agentInfo: { name: 'chord', version: options.version },
          authMethods: [],
          agentCapabilities: {
            loadSession: true,
            promptCapabilities: {
              image: true,
              audio: false,
              embeddedContext: false,
            },
            mcpCapabilities: { http: true, sse: true },
            sessionCapabilities: { list: {}, resume: {}, close: {} },
          },
          _meta: {
            [ACP_META]: {
              version: 1,
              extensions: EXTENSIONS,
              agent: { name: agent },
            },
          },
        };
      },
      newSession: async ({ params, requestId, signal }) => {
        refuseIfClosing();

        const { place, servers } = await placed(params, signal);

        return up(openEntry(place, params.cwd, servers), requestId, signal);
      },
      listSessions: async ({ cwd }) => ({
        sessions: earlierSessions(await readRecords(options.stateDir), {
          agent,
          ...(typeof cwd === 'string' ? { cwd } : {}),
        }).map(({ resume, prompt, lastUsedAt }) => ({
          sessionId: resume.sessionId,
          cwd: resume.cwd,
          title: prompt,
          updatedAt: lastUsedAt,
        })),
      }),
      loadSession: (request) => reopened(request, true),
      resumeSession: (request) => reopened(request, false),
      prompt: ({ params, requestId, signal }) => {
        refuseIfClosing();

        // A cancel that came right behind it has fired already, and an abort
        // listener hears nothing of one past.
        if (signal.aborted) {
          return Promise.resolve({ stopReason: 'cancelled' as const });
        }

        const entry = named(params.sessionId);
        const command = commandOf(params.prompt);
        const asked =
          command?.name === 'team'
            ? teamCommand(command.args, ACP_TEAM_WORDS)
            : undefined;

        if (command !== undefined && !command.alone) {
          return Promise.resolve(
            commandAnswered(entry, command.name, {
              text: notAloneRefusal(command.name),
              failed: true,
            }),
          );
        }

        if (command?.name === 'new') {
          return commanding(
            entry,
            requestId,
            'new',
            entry.host
              .newTyped(command.args, () => {})
              .then((shown) =>
                saidOf(shown, '', ({ name, agent: runtime, note }) =>
                  openedText(name, runtime, note),
                ),
              ),
          );
        }

        if (asked !== undefined && asked.form !== 'new') {
          return commanding(entry, requestId, 'team', teamSaid(entry, asked));
        }

        const session = entry.conversation.session;
        const parsed = promptOf(
          params.prompt,
          agent,
          session?.takesImages() === true,
        );

        if ('refused' in parsed) {
          throw RequestError.invalidParams(undefined, parsed.refused);
        }

        const turnId = crypto.randomUUID();
        const answer = Promise.withResolvers<never>();

        answers.set(requestId, answer as never);
        // Before `send`, which emits before it returns, and with no await
        // since the request came, or a cancel could pass it.
        step(entry, { type: 'bind', requestId, turnId });

        signal.addEventListener(
          'abort',
          () => {
            // The connection's end aborts this too, and is no client's cancel.
            if (!connection.signal.aborted) {
              const running = turnOf(entry.turns, requestId);

              if (running !== undefined) {
                entry.conversation.cancelPrompt(running);
              }
            }
          },
          { once: true },
        );

        if (
          !entry.conversation.send(
            parsed.text,
            asked?.form === 'new' ? newTeamPrompt(asked.words) : parsed.text,
            parsed.attachments,
            [],
            { turnId, links: parsed.links },
          )
        ) {
          step(entry, { type: 'unbind', turnId });
          answers.delete(requestId);

          throw RequestError.sessionNotFound(params.sessionId);
        }

        return answer.promise;
      },
      cancel: ({ sessionId }) => {
        const entry = sessions.get(sessionId);

        if (entry !== undefined) {
          entry.conversation.interrupt();

          return;
        }

        for (const each of sessions.values()) {
          if (cancelledIn(each, sessionId)) {
            return;
          }
        }
      },
      setConfigOption: async ({ params }) => {
        refuseIfClosing();

        const entry = named(params.sessionId);
        const state = agentState(entry);
        const setter =
          state === undefined
            ? undefined
            : configSetter(state, params.configId);

        if (
          setter === undefined ||
          !('value' in params) ||
          typeof params.value !== 'string' ||
          ('type' in params && params.type === 'boolean')
        ) {
          throw RequestError.invalidParams(
            undefined,
            `No option ${params.configId} takes that value.`,
          );
        }

        const { conversation } = entry;
        const { configId, value } = params;

        await (
          setter === 'mode'
            ? conversation.setMode(value)
            : setter === 'model'
              ? conversation.setModel(value)
              : conversation.setOption(configId, value)
        ).catch((error: unknown) => {
          throw refusal(error);
        });

        const now = agentState(entry);

        if (now === undefined || entry.upstream === undefined) {
          throw RequestError.sessionNotFound(params.sessionId);
        }

        const { session: told, configOptions } = answeredConfig(
          entry.upstream,
          now,
        );

        entry.upstream = told;

        return { configOptions };
      },
      setMode: async ({ params }) => {
        refuseIfClosing();

        await named(params.sessionId)
          .conversation.setMode(params.modeId)
          .catch((error: unknown) => {
            throw refusal(error);
          });

        return {};
      },
      close: async ({ params }) => {
        refuseIfClosing();

        const entry = named(params.sessionId);

        sessions.delete(params.sessionId);
        step(entry, { type: 'closing' });

        await closeEntry(entry);

        return {};
      },
    },
    wire.stream,
  );

  void connection.closed.then(() => {
    if (leaving.started()) {
      return;
    }

    const reason: unknown = connection.signal.reason;

    if (wire.failed() || reason instanceof MessageTooLargeError) {
      say(
        `chord: the connection closed: ${
          reason instanceof Error ? reason.message : String(reason)
        }`,
      );

      void leaving.leave({ kind: 'broken' });

      return;
    }

    void leaving.leave({ kind: 'eof' });
  });

  return { leave: (reason) => leaving.leave(reason) };
}
