/**
 * The window's agents, driven through `OpenAgents`: main and each child
 * opened with a conversation of its own whose events go into the reducer
 * under its key, picked, closed, resumed and quit, and the prompts sent to
 * them.
 */
import { type Dispatch, useEffect, useRef, useState } from 'react';
import { closeOnForcedExit, useApp } from './renderer.tsx';
import { relative, resolve } from 'node:path';
import type { DefinedServer, Ignored } from '../../mcp.ts';
import type { Wait } from '../../notify.ts';
import { withContext } from '../../session/context.ts';
import {
  Conversation,
  type ConversationEvent,
  type OpenSession,
  type Starting,
} from '../../session/conversation.ts';
import { OpenAgents } from '../../session/open_agents.ts';
import type { Session } from '../../session/session.ts';
import { signInNote } from '../../session/sign_in.ts';
import {
  failureNote,
  sentence,
  stepWords,
} from '../../session/start_failure.ts';
import { Runtimes, sessionProbe } from '../../server/runtimes.ts';
import type { ChordServer } from '../../server/server.ts';
import type {
  Caller,
  CloseAnswer,
  EffortStarted,
  MemberArgs,
  MessageAnswer,
  OpenAnswer,
  OpenArgs,
  RunTeamAnswer,
  RunTeamArgs,
  SpawnAnswer,
  SpawnArgs,
  WindowView,
} from '../../server/tools.ts';
import {
  findTeams,
  type FoundTeam,
  type Team,
  teamDirs,
  teamFile,
  teamPart,
} from '../../teams.ts';
import { TaskAgent, taskName } from '../../session/tasks.ts';
import type {
  ChordCall,
  MessageFrom,
  TeamAgentShown,
  TeamPart,
  TeamShown,
} from '../../session/transcript/types.ts';
import { FileRecording } from '../../session/record.ts';
import {
  type EarlierSession,
  earlierSessions,
  elsewhereRefusal,
  type Resumable,
  type Resume,
  type SessionRecord,
} from '../../session/sessions.ts';
import { chordStateDir } from '../../session/state_dir.ts';
import {
  monitorsIn,
  startMonitorIn,
  stopMonitorIn,
} from '../../session/window_monitors.ts';
import type { AgentWait } from '../../session/waits.ts';
import {
  agentOf,
  type Child,
  childEnded,
  type ChildInfo,
  childName,
  isLead,
  MAX_CHILDREN,
  membersOf,
  namedChild,
  notifiedName,
  ownChildren,
  pickedChild,
  runName,
  ownedBy,
  shownKey,
  type StartedAgents,
} from '../../session/window_agents.ts';
import { subagentPath } from '../../session/subagents.ts';
import { askerParts } from '../dialogs/asker.ts';
import { homePath } from '../../settings.ts';
import type { AgentOption } from '../../session/config.ts';
import {
  DIMCODE_NOTICE,
  dismissedNotices,
  dismissNotice,
  NoticeGate,
  NoticeWatch,
  noticesFile,
} from '../../notices.ts';
import { modelName } from '../../session/models.ts';
import { modelToAsk, valueToAsk } from '../pickers/picker.ts';
import { attachmentsOf, imagesIn, type PastedImage } from '../prompt/images.ts';
import { mentionsIn } from '../prompt/mentions.ts';
import { type Cursor, endOf, START } from '../prompt/prompt.ts';
import { mine, restoredDraft } from '../prompt/queue.ts';
import { heldContext } from '../prompt/state.ts';
import { vimReset } from '../prompt/vim.ts';
import { hintKey } from '../shortcuts/bindings.ts';
import { betweenNotice, waitsNotice } from '../status/status.ts';
import { askedPermission } from '../dialogs/permission.ts';
import { heldBack } from '../dialogs/state.ts';
import {
  agentCloseArmedLine,
  busyOf,
  ctrlCArmedLine,
  teamCloseArmedLine,
} from './closing.ts';
import {
  type AgentRow,
  agentMark,
  agentsHeight,
  agentsLayout,
  agentState,
  enteredView,
  listRows,
  type ListTarget,
  moveListFocus,
  scrolledView,
} from '../agents/agents.ts';
import {
  type BackgroundAgent,
  type BackgroundItem,
  backgroundItems,
  callPlace,
  type ItemOwner,
  stoppingIn,
} from '../background/background.ts';
import {
  focusedItem,
  moveView,
  stepDetail,
  NO_STOP_HINT,
  stopRefused,
} from '../background/view.ts';
import {
  headlineText,
  type ListedTeam,
  messageHeadline,
  ranNote,
  stoppedLine,
  type TeamListing,
  teamRefusal,
  type TeamRun,
} from '../teams/teams.ts';
import { firstLine, headline } from '../transcript/tools/tools.ts';
import { windowSpend } from '../transcript/spend.ts';
import {
  type AppAction,
  type KeptPlace,
  keptSpend,
  type AppState,
  canSend,
  resumableSession,
  resumeRefusal,
  type WindowedAction,
  type WindowedState,
} from './state.ts';

/** `a, b and c`. */
function andList(names: readonly string[]): string {
  return new Intl.ListFormat('en', { type: 'conjunction' }).format(names);
}

/** How a session of one agent starts: its command, and its model and mode. */
export interface SessionStart {
  /** Replaces the registry's command for the agent. */
  readonly agentCommand?: string | string[] | undefined;
  /**
   * Why the agent is not started at all, as said to the person: its command
   * was refused (CHD-466). Nothing starts on chord's own command instead.
   */
  readonly refused?: string | undefined;
  readonly starting?: Starting | undefined;
  /**
   * `false` where the agent takes no MCP servers at all, as its setting or
   * chord's own table says (CHD-441).
   */
  readonly mcpServers?: false | undefined;
}

/**
 * Where the window's sessions work, and what that directory's files give them:
 * a session resumed from another directory takes that directory's project
 * settings and MCP servers, as had chord been started there.
 */
export interface Place {
  readonly cwd: string;
  /**
   * How a session of each agent starts there; none for an agent chord
   * cannot start.
   */
  readonly startupOf: (agent: string) => SessionStart | undefined;
  /** The MCP servers each session there gets, which `/mcp` lists. */
  readonly mcpServers: readonly DefinedServer[];
  /** What the files there defined that chord did not pass. */
  readonly mcpIgnored: readonly Ignored[];
}

export interface SessionsOptions {
  agent: string;
  /** The `--agent-command` the person typed, which a resume line repeats. */
  typedCommand?: string | undefined;
  /** The window's own place: where `agent`'s first session works. */
  place: Place;
  stateDir: string | undefined;
  readRecords: (stateDir: string) => Promise<SessionRecord[]>;
  open: OpenSession;
  resume: Resume | undefined;
  /**
   * chord's own MCP server, which every session gets beside `mcpServers`
   * where its agent takes HTTP; none in tests that do not ask for it.
   */
  server: ChordServer | undefined;
  /** Every runtime chord can start, which `list_agents` names. */
  runtimes: readonly string[];
  home: string | undefined;
  /**
   * The user's config directory, whose `chord/teams/` holds the teams for
   * every project; none reads only the project's.
   */
  configHome: string | undefined;
  onQuit: ((session: Resumable | undefined) => void) | undefined;
}

/** What the sessions read of the window and do to it. */
export interface SessionsWindow {
  all: WindowedState;
  /** The session in front, as the window was last drawn. */
  state: AppState;
  dispatch: Dispatch<WindowedAction>;
  /** Starts the box afresh on the draft and cursor the state has. */
  redraw: () => void;
  showDraft: (text: string, at: Cursor) => void;
  /** Tells the terminal chord waits on the person, for the agent named. */
  notify: (wait: Wait | undefined, name: string) => void;
  /** Keeps a prompt sent, with its images, in history. */
  remember: (text: string, images: readonly PastedImage[]) => void;
  /** Stops the command running in session `key`, if one runs. */
  stopCommand: (key: number) => void;
}

export function useSessions(
  {
    agent,
    typedCommand,
    place,
    stateDir,
    readRecords,
    open,
    resume,
    server,
    runtimes: runtimeNames,
    home,
    configHome,
    onQuit,
  }: SessionsOptions,
  host: SessionsWindow,
) {
  const { all, state, dispatch, redraw, showDraft, stopCommand } = host;
  const { exit } = useApp();
  // The session main opens next resumes: the one `--resume` asks for, and
  // each `/resume` picks; the one `/clear` opens is new.
  const resuming = useRef<Resume | undefined>(resume);
  const heard = (key: number, event: ConversationEvent, wait?: Wait) => {
    if (retiredHeard(key, event)) {
      return;
    }

    dispatch({ type: 'in_session', key, action: event });
    host.notify(wait, notifiedName(sessions.agents, key) ?? agent);
  };

  /**
   * What a session main, `key`, let go said of a turn of its, from main
   * open or closed since: kept where that session is held (CHD-373 S3c).
   * Whether `event` was one.
   */
  const retiredHeard = (key: number, event: ConversationEvent): boolean => {
    if (event.type === 'retired_update') {
      // A cost it said, or a task of its ending with what it spent.
      dispatch({
        type: 'retired_heard',
        from: key,
        event: { type: 'update', turnId: event.turnId, update: event.update },
      });

      return true;
    }

    if (event.type !== 'retired_usage') {
      return false;
    }

    const { type: _, ...figures } = event;

    dispatch({
      type: 'retired_heard',
      from: key,
      event: { type: 'usage', ...figures },
    });

    return true;
  };

  // The sessions are made once and keep the first listener; this one reads
  // the latest props through the ref.
  const hear = useRef(heard);

  hear.current = heard;

  // dimcode's one-time notice comes due the first time any of the
  // window's sessions, `main`, a child, a team member or a task, has its
  // permission option at anything but read-only, unless dismissed on this
  // machine; a record that does not read shows it, and a session that left
  // that moment, closed or was cleared while the record was read shows none
  // (docs/design/CHD-434.md).
  const noticeWatch = useRef(new NoticeWatch());
  const noticeGate = useRef(
    new NoticeGate(
      () => dismissedNotices(noticesFile(configHome)),
      (id) => {
        const file = noticesFile(configHome);

        return file === undefined ? Promise.resolve() : dismissNotice(file, id);
      },
    ),
  );

  const watchNotice = (id: string, agent: string, event: ConversationEvent) => {
    const watch = noticeWatch.current;

    // A session cleared is gone as one closed is: the one after it, under
    // the same id, comes due of its own.
    if (event.type === 'closing' || event.type === 'cleared') {
      watch.gone(id);
    }

    const ticket =
      event.type === 'options'
        ? watch.heard(id, agent, event.options)
        : undefined;

    if (ticket === undefined) {
      return;
    }

    void noticeGate.current
      .due(DIMCODE_NOTICE, () => watch.holds(id, ticket))
      .then((shows) => {
        if (shows) {
          dispatch({ type: 'notice_opened', id: DIMCODE_NOTICE });
        }
      });
  };

  /** Dismisses notice `id` for good on this machine: the person's `1`. */
  const dismissNoticeFor = (id: string) => {
    void noticeGate.current.dismiss(id);
  };

  const conversationOf = (
    agent: string,
    emit: (event: ConversationEvent) => void,
    key: number,
  ) => {
    const { cwd, mcpServers, startupOf } = place;
    const {
      agentCommand,
      starting,
      refused,
      mcpServers: takes,
    } = startupOf(agent) ?? {};

    return new Conversation(
      (signal) => {
        if (refused !== undefined) {
          throw new Error(refused);
        }

        const next = resuming.current;
        // A token for each session main opens, `/clear`'s included, good
        // until that session's agent has gone.
        const admitted = server?.admit({ role: 'person', key, window: view });
        const options = {
          agent,
          cwd,
          signal,
          ...(agentCommand === undefined ? {} : { agentCommand }),
          ...(next === undefined ? {} : { resume: next }),
          ...(mcpServers.length === 0
            ? {}
            : { mcpServers: mcpServers.map(({ server }) => server) }),
          ...(admitted === undefined ? {} : { chordServer: admitted.server }),
          ...(takes === false ? { noMcpServers: true } : {}),
        };

        resuming.current = undefined;

        if (admitted === undefined) {
          return open(options);
        }

        const revoke = () => server?.revoke(admitted.token);

        return open(options).then(
          (session: Session) => {
            void session.exited.finally(revoke);

            return session;
          },
          (error: unknown) => {
            revoke();

            throw error;
          },
        );
      },
      (event) => {
        watchNotice(`main:${key}`, agent, event);
        emit(event);
      },
      Date.now,
      starting,
      new FileRecording(stateDir ?? chordStateDir(), (message) =>
        emit({
          type: 'failed',
          turnId: `record-${crypto.randomUUID()}`,
          message,
        }),
      ),
    );
  };

  /** Each task agent's own conversation, by its id, while it runs. */
  const children = useRef(new Map<string, Conversation>());

  /**
   * Why a child of `args.agent` cannot start from `parent` of main, `key`, with
   * what is offered; none when it may: a parent closing, a runtime chord
   * cannot start there, or a model it is known to lack.
   */
  const startRefusal = async (
    key: number,
    parent: Conversation | undefined,
    args: OpenArgs,
    kind: string,
  ): Promise<string | undefined> => {
    const startup = runtimeNames.includes(args.agent)
      ? place.startupOf(args.agent)
      : undefined;

    if (parent?.session === undefined) {
      return `This session is closing; no ${kind} can start from it`;
    }

    if (startup === undefined) {
      return `No agent named ${args.agent}; chord knows ${runtimeNames.join(
        ', ',
      )}`;
    }

    if (startup.refused !== undefined) {
      return startup.refused;
    }

    const known = await view.offer(args.agent, false, key);

    if (
      args.model !== undefined &&
      known !== undefined &&
      !('error' in known) &&
      known.models.length > 0 &&
      !known.models.some((model) => model.id === args.model)
    ) {
      return `${args.agent} offers no model ${args.model}; it offers ${known.models
        .map((model) => model.id)
        .join(', ')}`;
    }

    if (
      args.mode !== undefined &&
      known !== undefined &&
      !('error' in known) &&
      (known.modes?.length ?? 0) > 0 &&
      !known.modes!.some((mode) => mode.id === args.mode)
    ) {
      return `${args.agent} has no mode ${args.mode} · ${known
        .modes!.map((mode) => mode.id)
        .join(', ')}`;
    }

    return undefined;
  };

  /**
   * A child's own conversation, a session of `args.agent` where main, `key`,
   * works, on the model asked for or not at all, with chord's server given
   * it as `caller`, whose tools its role gives. Its record names
   * `parent`, it as `name`, a task's id, which its parent's record keeps
   * the task's block under, a long-lived one's, which its parent's record
   * names it by, and a lead's `team`.
   */
  const childConversation = (
    key: number,
    parent: Conversation | undefined,
    args: OpenArgs,
    name: string,
    caller: Caller,
    asked: string,
    emit: (event: ConversationEvent) => void,
    team?: string,
  ) => {
    const { cwd, mcpServers, startupOf } = place;
    const startup = startupOf(args.agent) ?? {};

    return new Conversation(
      (signal) => {
        if (startup.refused !== undefined) {
          throw new Error(startup.refused);
        }

        const admitted = server?.admit(caller);
        const options = {
          agent: args.agent,
          cwd,
          signal,
          ...(startup.agentCommand === undefined
            ? {}
            : { agentCommand: startup.agentCommand }),
          ...(mcpServers.length === 0
            ? {}
            : { mcpServers: mcpServers.map(({ server }) => server) }),
          ...(admitted === undefined ? {} : { chordServer: admitted.server }),
          ...(startup.mcpServers === false ? { noMcpServers: true } : {}),
        };
        const revoke = () => admitted && server?.revoke(admitted.token);

        return open(options).then(
          (session: Session) => {
            void session.exited.finally(revoke);

            return session;
          },
          (error: unknown) => {
            revoke();

            throw error;
          },
        );
      },
      (event) => {
        watchNotice(
          caller.task ?? caller.agent ?? `child:${key}`,
          args.agent,
          event,
        );
        emit(event);
      },
      Date.now,
      // The model asked for, which the child runs on or not at all, and the
      // mode a team file set, likewise, or else the settings' one.
      {
        ...(args.mode !== undefined
          ? { mode: { id: args.mode, from: asked, required: true } }
          : startup.starting?.mode === undefined
            ? {}
            : { mode: startup.starting.mode }),
        ...(args.model === undefined
          ? {}
          : {
              model: { id: args.model, from: asked, required: true },
            }),
        // Never required: a refusal leaves it on the runtime's own.
        ...(args.effort === undefined
          ? {}
          : { effort: { id: args.effort, from: asked } }),
      },
      new FileRecording(stateDir ?? chordStateDir(), () => {}, Date.now, {
        parent: () => parent?.session?.id,
        name,
        ...(caller.task === undefined ? {} : { task: caller.task }),
        ...(caller.agent === undefined ? {} : { id: caller.agent }),
        ...(team === undefined ? {} : { team }),
      }),
    );
  };

  /**
   * The conversation a caller's own work runs in: a long-lived child's, or
   * main's; none once it has closed.
   */
  const callerConversation = (key: number, agent: string | undefined) =>
    agent === undefined
      ? conversationAt(key)
      : childOf(key, agent)?.conversation;

  /**
   * Waits on a child's start when it was asked for an effort: the answer
   * says the effort it is on and, when it was refused, why, as the
   * transcript does. `settle` takes each event the child reports; `started`
   * settles once it is up, failed or closing, nothing else being known then.
   */
  const effortStart = (
    args: OpenArgs,
    child: () => Conversation | undefined,
  ) => {
    const { promise, resolve } = Promise.withResolvers<void>();

    return {
      settle: (event: ConversationEvent) => {
        if (
          event.type === 'connected' ||
          event.type === 'connect_failed' ||
          event.type === 'closing'
        ) {
          resolve();
        }
      },
      /** For a child that never started. */
      never: resolve,
      started: async (): Promise<EffortStarted> => {
        if (args.effort === undefined) {
          return {};
        }

        await promise;

        const conversation = child();
        const effort = conversation?.session?.efforts()?.current;
        const note = conversation?.effortRefused;

        return {
          ...(effort === undefined ? {} : { effort }),
          ...(note === undefined ? {} : { note }),
        };
      },
    };
  };

  /**
   * Starts a task agent for the caller, main or a long-lived child of it: a
   * session of `agent` where main works, with no row of
   * its own, drawn in the caller's turn and closed with it. Refused as
   * `startRefusal` says.
   */
  const spawn = async (from: Caller, args: SpawnArgs): Promise<SpawnAnswer> => {
    const { key } = from;
    const parent = callerConversation(key, from.agent);
    const refused = await startRefusal(key, parent, args, 'task');

    if (parent === undefined || refused !== undefined) {
      return { error: refused ?? 'This session has closed' };
    }

    const id = crypto.randomUUID();
    const name = taskName(args.name, args.prompt);
    const task = new TaskAgent(
      {
        id,
        name,
        runtime: args.agent,
        prompt: args.prompt,
        ...(args.model === undefined ? {} : { model: args.model }),
      },
      parent.taskParent(id),
      Date.now,
    );
    const caller: Caller = {
      role: 'child',
      key,
      task: id,
      ...(from.agent === undefined ? {} : { by: from.agent }),
      window: view,
    };
    const effort = effortStart(args, () => child);
    const child = childConversation(
      key,
      parent,
      args,
      name,
      caller,
      'asked by spawn_task',
      (event) => {
        task.heard(event);
        effort.settle(event);

        if (!task.running) {
          children.current.delete(id);
        }
      },
    );

    children.current.set(id, child);
    parent.adopt(task, child);

    const started = await effort.started();

    // Its block says the effort it started on, as it says the model.
    if (started.effort !== undefined) {
      task.startedOn(started.effort);
    }

    return {
      id,
      name,
      agent: args.agent,
      ...(args.model === undefined ? {} : { model: args.model }),
      ...started,
    };
  };

  /**
   * Messages for a long-lived child that is still starting, its first
   * prompt first, by its key: they go, in order, once it is up.
   */
  const early = useRef(
    new Map<number, [MessageFrom, string, (TeamPart | undefined)?][]>(),
  );

  /**
   * A `send_message` to child `key`: into its running turn, a turn there,
   * queued, or held until it is up; `queued` is called if a message sent
   * into its turn goes as the next turn after all.
   */
  const deliverTo = (
    child: Child<Conversation>,
    from: MessageFrom,
    text: string,
    queued?: () => void,
  ): 'sent' | 'queued' => {
    const held = early.current.get(child.key);

    if (held !== undefined) {
      held.push([from, text]);

      return 'queued';
    }

    return child.conversation.tell(from, text, queued) ?? 'queued';
  };

  /** How the parent's messages read to a child: from `main`. */
  const MAIN: MessageFrom = { name: 'main', reachable: true };

  /** How a long-lived child opens, besides its runtime, model and prompt. */
  interface Opening {
    readonly name: string;
    /** The conversation it answers to: main's, or its lead's. */
    readonly parent: () => Conversation | undefined;
    /** Who its first prompt is a message from. */
    readonly from: MessageFrom;
    /** The team it is of, by its file's name, and a member's lead's id. */
    readonly team?: { readonly name: string; readonly lead?: string };
    /** The team part that goes ahead of its first prompt. */
    readonly part?: TeamPart;
    /** Where its model and mode were asked for, as a refusal says it. */
    readonly asked: string;
  }

  /**
   * Opens a long-lived agent of main, `key`, in the list of agents under
   * the prompt, its first prompt `opening.from`'s
   * message; chord's id for it, which its parent quotes, as answered, and
   * where an effort asked for left it, once it has started.
   */
  const startChild = (
    key: number,
    args: OpenArgs,
    opening: Opening,
  ): {
    opened: Exclude<OpenAnswer, { readonly error: string }>;
    started: Promise<EffortStarted>;
  } => {
    // Eight hex digits: the parent quotes it, and so does the person's close.
    const id = crypto.randomUUID().slice(0, 8);
    const { name, team } = opening;
    const caller: Caller = {
      role: 'child',
      key,
      agent: id,
      ...(team === undefined
        ? {}
        : { team: team.lead === undefined ? 'lead' : 'member' }),
      window: view,
    };
    const childKey = sessions.agents.nextKey;

    early.current.set(childKey, [[opening.from, args.prompt, opening.part]]);
    // Its state is there before its first event, which may come at once.
    dispatch({ type: 'agent_opened', key: childKey });

    const effort = effortStart(args, () => conversationAt(childKey));
    const placed = sessions.openChild(
      {
        id,
        name,
        runtime: args.agent,
        openedAt: Date.now(),
        ...(args.model === undefined ? {} : { model: args.model }),
        ...(args.mode === undefined ? {} : { mode: args.mode }),
        ...(team === undefined ? {} : { team: team.name }),
        ...(team?.lead === undefined ? {} : { lead: team.lead }),
      },
      (emit, own) =>
        childConversation(
          key,
          opening.parent(),
          args,
          name,
          caller,
          opening.asked,
          (event) => {
            emit(event);
            tellEnded(key, own, event);
            effort.settle(event);

            if (event.type === 'connected' || event.type === 'connect_failed') {
              const held = early.current.get(own) ?? [];

              early.current.delete(own);

              // After the event is drawn, so the first turn comes after it.
              queueMicrotask(() => {
                const child = agentOf(sessions.agents, own)?.child;

                if (event.type === 'connected') {
                  // The first prompt starts its first turn; the messages
                  // sent while it started go into that turn.
                  for (const [index, [from, text, part]] of held.entries()) {
                    if (index === 0) {
                      child?.conversation.deliver(from, text, part);
                    } else {
                      child?.conversation.tell(from, text);
                    }
                  }
                } else if (child !== undefined) {
                  parentOf(child)?.deliver(
                    { name: 'chord' },
                    `${child.name} (${child.runtime}) did not start: ` +
                      `${sentence(stepWords(event.message, event.failure))}${failureNote(
                        child.runtime,
                        event.failure,
                      )}${
                        event.signIn === undefined
                          ? ''
                          : signInNote(child.runtime, event.signIn)
                      } It takes no messages; open_agent starts another.`,
                  );
                }
              });
            }
          },
          team?.lead === undefined ? team?.name : undefined,
        ),
    );

    if (placed === undefined) {
      effort.never();
    }

    return {
      opened: {
        id,
        name,
        agent: args.agent,
        ...(args.model === undefined ? {} : { model: args.model }),
        ...(args.mode === undefined ? {} : { mode: args.mode }),
      },
      started: effort.started(),
    };
  };

  /** Why main, `key`, cannot open another child of its own, if it cannot. */
  const fullRefusal = (key: number): string | undefined => {
    const agents = ownedBy(sessions.agents, key);

    return agents === undefined
      ? 'This session has closed'
      : ownChildren(agents).length >= MAX_CHILDREN
        ? `This session has ${MAX_CHILDREN} agents open; close_agent one first`
        : undefined;
  };

  /**
   * Opens a long-lived agent for main, `key`: a session of `agent` where
   * main works, its first prompt the parent's message.
   * Refused as `startRefusal` says, and past `MAX_CHILDREN`.
   */
  const openAgent = async (
    key: number,
    args: OpenArgs,
  ): Promise<OpenAnswer> => {
    const refused =
      (await startRefusal(key, conversationAt(key), args, 'agent')) ??
      fullRefusal(key);
    const agents = ownedBy(sessions.agents, key);

    if (agents === undefined || refused !== undefined) {
      return { error: refused ?? 'This session has closed' };
    }

    const { opened, started } = startChild(key, args, {
      name: childName(agents, args.name, args.agent),
      parent: () => conversationAt(key),
      from: MAIN,
      asked: 'asked by open_agent',
    });

    return { ...opened, ...(await started) };
  };

  /**
   * Each open run's team, by its lead's id: the file as it was read when the
   * run started, so a file changed since does not change a running team,
   * and the job it was handed.
   */
  const runs = useRef(
    new Map<
      string,
      FoundTeam & { readonly team: Team; readonly job: string }
    >(),
  );

  /** The team files where main, `key`, works, read now, each path as shown. */
  const teamsAt = async (key: number): Promise<ListedTeam[]> =>
    (await findTeams({ configHome, cwd: place.cwd }, runtimeNames)).map(
      (found) => ({ ...found, shown: shownTeamFile(key, found) }),
    );

  /**
   * A team file as the window shows it to main, `key`: a project's from the
   * directory main works in, the user's from `~`.
   */
  const shownTeamFile = (key: number, found: FoundTeam) =>
    found.place === 'project'
      ? relative(place.cwd, found.file)
      : homePath(found.file, home);

  /**
   * Where a team named `name` goes for main, `key`, a project's file shown
   * from the directory main works in and the user's from `~`, and the
   * team saved under the name now.
   */
  const teamPlaces = async (key: number, name: string) => {
    const { cwd } = place;
    const dirs = teamDirs({ configHome, cwd });
    const project = teamFile(dirs.project, name);
    const user =
      dirs.user === undefined ? undefined : teamFile(dirs.user, name);
    const saved = (await teamsAt(key)).find((each) => each.name === name);
    const shown = (file: string) => ({
      file,
      shown:
        file === project || (saved?.place === 'project' && file === saved.file)
          ? relative(cwd, file)
          : homePath(file, home),
    });

    return {
      agent: ownedBy(sessions.agents, key)?.main.agent ?? 'the agent',
      project: shown(project),
      ...(user === undefined ? {} : { user: shown(user) }),
      ...(saved === undefined
        ? {}
        : {
            saved: {
              ...shown(saved.file),
              ...('team' in saved ? { team: saved.team } : {}),
            },
          }),
    };
  };

  /**
   * `run_team`, and `/team run`: the team's lead opened as a child of main,
   * `key`'s session, named after the team and numbered past its first run,
   * on the lead's runtime, model, effort and mode, with the team part and
   * the job as main's message. Refused for a team not found, `lists` saying
   * what lists them, a file that fails its check, and as `openAgent` is.
   * `started` settles where the file's effort left the lead once it is up.
   */
  const runTeamAt = async (
    key: number,
    { team, job }: RunTeamArgs,
    lists: string,
  ): Promise<
    | { readonly error: string }
    | {
        readonly ran: Exclude<RunTeamAnswer, { readonly error: string }>;
        readonly started: Promise<EffortStarted>;
      }
  > => {
    const found = (await teamsAt(key)).find((each) => each.name === team);

    if (found === undefined) {
      return { error: `No team named ${team} · ${lists}` };
    }

    if ('problem' in found) {
      return {
        error: `${found.shown} is not a team chord can run: ${found.problem}`,
      };
    }

    const { lead } = found.team;
    const args: OpenArgs = {
      agent: lead.agent,
      prompt: job,
      ...(lead.model === undefined ? {} : { model: lead.model }),
      ...(lead.effort === undefined ? {} : { effort: lead.effort }),
      ...(lead.mode === undefined ? {} : { mode: lead.mode }),
    };
    const refused =
      (await startRefusal(key, conversationAt(key), args, 'agent')) ??
      fullRefusal(key);
    const agents = ownedBy(sessions.agents, key);

    if (agents === undefined || refused !== undefined) {
      return { error: refused ?? 'This session has closed' };
    }

    const name = runName(agents, team);
    const others = ownChildren(agents)
      .filter(isLead)
      .map((each) => each.name);
    const { opened, started } = startChild(key, args, {
      name,
      parent: () => conversationAt(key),
      from: MAIN,
      team: { name: team },
      part: teamPart(team, found.team, { lead: name, others }, place.cwd),
      asked: `set by team ${team}`,
    });

    runs.current.set(opened.id, { ...found, job });

    return { ran: { ...opened, team }, started };
  };

  /**
   * A lead's `open_agent`: a member of its team's file, by name, on the
   * file's runtime, model, effort and mode, with the team part ahead of the lead's
   * prompt. Refused for a name the file does not have and for one open.
   */
  const openMember = async (
    caller: Caller,
    { member, prompt }: MemberArgs,
  ): Promise<OpenAnswer> => {
    const { key } = caller;
    const lead =
      caller.agent === undefined ? undefined : childOf(key, caller.agent);
    const run = lead === undefined ? undefined : runs.current.get(lead.id);

    if (lead === undefined || run === undefined) {
      return { error: 'You are closed; you open no members' };
    }

    const defined = run.team.members.find((each) => each.name === member);

    if (defined === undefined) {
      return {
        error: `Team ${run.name} has no member ${member}; its members are ${andList(
          run.team.members.map((each) => each.name),
        )}`,
      };
    }

    /** Why `member` cannot open now: its lead closed, or it is open. */
    const occupied = () => {
      const agents = ownedBy(sessions.agents, key);

      if (
        agents === undefined ||
        !agents.children.some((each) => each.id === lead.id)
      ) {
        return 'You are closed; you open no members';
      }

      return membersOf(agents, lead.id).some((each) => each.name === member)
        ? `${member} is open; send_message reaches it`
        : undefined;
    };

    const open = occupied();

    if (open !== undefined) {
      return { error: open };
    }

    const args: OpenArgs = {
      agent: defined.agent,
      prompt,
      ...(defined.model === undefined ? {} : { model: defined.model }),
      ...(defined.effort === undefined ? {} : { effort: defined.effort }),
      ...(defined.mode === undefined ? {} : { mode: defined.mode }),
    };
    // Asked again after the wait: two calls for one member may both have
    // passed the first look, and the lead may have closed meanwhile.
    const refused =
      (await startRefusal(key, lead.conversation, args, 'agent')) ?? occupied();

    if (refused !== undefined) {
      return { error: refused };
    }

    const { opened, started } = startChild(key, args, {
      name: member,
      parent: () => conversationAt(lead.key),
      from: { name: lead.name, reachable: true },
      team: { name: run.name, lead: lead.id },
      part: teamPart(
        run.name,
        run.team,
        { member: defined, lead: lead.name },
        place.cwd,
      ),
      asked: `set by team ${run.name}`,
    });

    return { ...opened, ...(await started) };
  };

  /** Session `key`'s open child `to`, by chord's id or its name. */
  const childOf = (key: number, to: string) =>
    ownedBy(sessions.agents, key)?.children.find(
      (child) => child.id === to || child.name === to,
    );

  /**
   * Session `key`'s own open child `to`, by chord's id or its name: one the
   * session opened, a team's lead among them, and no member.
   */
  const ownChild = (key: number, to: string) =>
    ownedBy(sessions.agents, key)?.children.find(
      (child) =>
        child.lead === undefined && (child.id === to || child.name === to),
    );

  /**
   * The conversation a child answers to: its lead's for a member, main's
   * session's for any other.
   */
  const parentOf = (child: Child<Conversation>): Conversation | undefined => {
    const agents = front();

    return child.lead === undefined
      ? agents && conversationAt(agents.main.key)
      : agents?.children.find((each) => each.id === child.lead)?.conversation;
  };

  /**
   * Why main, `key`, has no open child `to`: closed, or open when the
   * session was left, as a resumed past's closing note names it.
   */
  const noChild = (key: number, to: string): string => {
    const closed = ownedBy(sessions.agents, key)?.closed.findLast(
      (child) =>
        child.lead === undefined && (child.id === to || child.name === to),
    );

    if (closed !== undefined) {
      return `${closed.name} is closed; open_agent starts another`;
    }

    const left = stateOf(key)
      ?.transcript.entries.flatMap((entry) =>
        entry.kind === 'left_open' ? entry.agents : [],
      )
      .findLast((agent) => agent.name === to);

    return left === undefined
      ? `No agent ${to} is open in this session; list_sessions names them`
      : left.team === undefined
        ? `${to} was closed when this session was left; open_agent starts ` +
          'another'
        : `${to} was closed when this session was left; run_team starts ` +
          'the team again';
  };

  /**
   * A message to `to`: a parent's to its child, or a team agent's, as
   * `teamTell` routes it; a turn there, or queued.
   */
  const tell = (
    caller: Caller,
    to: string,
    text: string,
    queued?: () => void,
  ): MessageAnswer => {
    if (caller.team !== undefined) {
      return teamTell(caller, to, text, queued);
    }

    const child = ownChild(caller.key, to);

    if (child === undefined) {
      return { error: noChild(caller.key, to) };
    }

    return {
      delivered: deliverTo(child, MAIN, text, queued),
      to: child.name,
    };
  };

  /**
   * A team agent's message, straight to whom it names, never routed through
   * the lead: a lead's to `main`, to one of its open members, which hear it
   * from their parent, or to another run's lead; a member's to its lead or
   * to another open member of its team. Nothing counts them.
   */
  const teamTell = (
    caller: Caller,
    to: string,
    text: string,
    queued?: () => void,
  ): MessageAnswer => {
    const agents = ownedBy(sessions.agents, caller.key);
    const self =
      caller.agent === undefined
        ? undefined
        : childOf(caller.key, caller.agent);

    if (agents === undefined || self === undefined) {
      return { error: 'You are closed; nothing more reaches anyone' };
    }

    const from: MessageFrom = {
      name: self.name,
      runtime: self.runtime,
      reachable: true,
    };
    const named = (child: ChildInfo) => child.id === to || child.name === to;
    const lead = isLead(self)
      ? self
      : agents.children.find((each) => each.id === self.lead);

    if (lead === undefined) {
      return { error: 'Your lead has closed; nothing more reaches it' };
    }

    const members = membersOf(agents, lead.id).filter((each) => each !== self);
    const leads =
      self === lead
        ? ownChildren(agents).filter((each) => isLead(each) && each !== self)
        : [];

    if (self === lead && to === 'main') {
      const delivered = conversationAt(agents.main.key)?.tell(
        from,
        text,
        queued,
      );

      return delivered === undefined
        ? { error: 'main has closed' }
        : { delivered, to: 'main' };
    }

    const member = members.find(named);

    if (member !== undefined) {
      return {
        delivered: deliverTo(
          member,
          self === lead ? { name: lead.name, reachable: true } : from,
          text,
          queued,
        ),
        to: member.name,
      };
    }

    const other =
      self === lead ? leads.find(named) : named(lead) ? lead : undefined;

    if (other !== undefined) {
      return {
        delivered: deliverTo(other, from, text, queued),
        to: other.name,
      };
    }

    const closed = agents.closed.findLast(
      (each) =>
        named(each) &&
        (each.lead === lead.id || (self === lead && isLead(each))),
    );

    if (closed !== undefined) {
      return {
        error:
          closed.lead === undefined
            ? `${closed.name} is closed`
            : `${closed.name} is closed; ${
                self === lead ? 'open_agent opens' : `${lead.name} can open`
              } it again`,
      };
    }

    return {
      error: `No agent ${to} is open for you; you reach ${andList([
        ...(self === lead ? ['main'] : [lead.name]),
        ...members.map((each) => each.name),
        ...leads.map((each) => each.name),
      ])}`,
    };
  };

  /**
   * Tells main, `key`, with `← chord`, of an `event` that ends its
   * child `own`'s work on its own, as `childEnded` words it; a child the
   * window has let go is no news.
   */
  const tellEnded = (key: number, own: number, event: ConversationEvent) => {
    if (event.type !== 'disconnected' && event.type !== 'result') {
      return;
    }

    const child = agentOf(sessions.agents, own)?.child;
    const lead = child !== undefined && isLead(child);
    const text =
      child &&
      childEnded(child.name, event, child.conversation.session?.gone(), lead);

    if (child === undefined || text === undefined) {
      return;
    }

    // A lead gone leaves its members nobody to answer to.
    if (lead && event.type === 'disconnected') {
      const agents = ownedBy(sessions.agents, key);

      for (const member of agents === undefined
        ? []
        : membersOf(agents, child.id)) {
        dropChild(member.key);
      }
    }

    parentOf(child)?.deliver({ name: 'chord' }, text);
  };

  /**
   * Takes child `key` out of the window and closes its agent, its turn
   * cancelled first so the agent ends it as it would any cancel; a lead's
   * members go first, as a parent's children close with it.
   */
  /**
   * Holds session `key` as it closes, or is cleared, for the window's total
   * (the owner's Q59: closed agents count): its last events still count,
   * a cancelled turn's end among them, until `settled` is called with its
   * close, or at once with none (CHD-373).
   */
  const keepSpend = (key: number, place: KeptPlace, from?: number) => {
    dispatch({
      type: 'spend_closing',
      key,
      place,
      ...(from === undefined ? {} : { from }),
    });

    return (closed?: Promise<unknown>) => {
      const kept = () => dispatch({ type: 'spend_closed', key });

      if (closed === undefined) {
        kept();
      } else {
        void closed.then(kept, kept);
      }
    };
  };

  // Keys of the sessions main let go, held as they close, apart from every
  // session's own, which count up from one.
  const retiredKeys = useRef(0);
  const retiredKey = () => --retiredKeys.current;

  /** Holds what a child spent, by its team, as it closes. */
  const keepChild = (child: ChildInfo & { readonly key: number }) =>
    keepSpend(child.key, {
      // A run's lead is `lead` under its team's row, as when it is open.
      name: isLead(child) ? 'lead' : child.name,
      kind: child.team === undefined ? 'agent' : 'member',
      runtime: child.runtime,
      ...(child.team === undefined ? {} : { team: child.team }),
      ...(isLead(child)
        ? { lead: child.id }
        : child.lead === undefined
          ? {}
          : { lead: child.lead }),
    });

  const dropChild = (key: number) => {
    const found = agentOf(sessions.agents, key);
    const child = found?.child;

    if (found === undefined || child === undefined) {
      return;
    }

    for (const member of membersOf(sessions.agents, child.id)) {
      dropChild(member.key);
    }

    runs.current.delete(child.id);

    early.current.delete(key);

    if (stateOf(key) && busyOf(stateOf(key)!) !== undefined) {
      child.conversation.interrupt();
    }

    stopCommand(key);

    const kept = keepChild(child);
    const closed = sessions.closeChild(key);

    kept(closed);
    void closed.catch(() => {});

    dispatch({
      type: 'session_closed',
      key,
      front: shownKey(sessions.agents) ?? all.front,
    });

    // The list goes with the last child, and the keys go back to the box.
    if (
      agentOf(sessions.agents, key) === undefined &&
      front()?.children.length === 0
    ) {
      dispatch({ type: 'agents_focused', focused: false });
    }
  };

  /**
   * `close_agent`: the parent closes its child `to`, a lead's with its
   * members, and is told nothing; a lead closes one of its members.
   */
  const closeAgent = (caller: Caller, to: string): CloseAnswer => {
    const lead =
      caller.team === 'lead' && caller.agent !== undefined
        ? childOf(caller.key, caller.agent)
        : undefined;
    const agents = ownedBy(sessions.agents, caller.key);
    const child =
      lead === undefined
        ? ownChild(caller.key, to)
        : agents &&
          membersOf(agents, lead.id).find(
            (each) => each.id === to || each.name === to,
          );

    if (child === undefined) {
      return {
        error:
          lead === undefined
            ? noChild(caller.key, to)
            : `No member ${to} of yours is open`,
      };
    }

    dropChild(child.key);
    (lead?.conversation ?? conversationAt(caller.key))?.agentClosed(child.id);
    redraw();

    return { closed: child.name };
  };

  /**
   * A child's message to its parent: into its running turn, a turn there,
   * or queued.
   */
  const message = (
    caller: Caller,
    text: string,
    queued?: () => void,
  ): MessageAnswer => {
    const parent = conversationAt(caller.key);

    if (caller.agent !== undefined) {
      const child = childOf(caller.key, caller.agent);

      if (parent === undefined) {
        return { error: 'The session that opened you has closed' };
      }

      if (child === undefined) {
        return { error: 'You are closed; nothing more reaches your parent' };
      }

      const delivered = parent.tell(
        { name: child.name, runtime: child.runtime, reachable: true },
        text,
        queued,
      );

      return delivered === undefined
        ? { error: 'The session that opened you has closed' }
        : { delivered };
    }

    // A task a child started reports to that child.
    const owner = callerConversation(caller.key, caller.by);
    const task =
      caller.task === undefined ? undefined : owner?.task(caller.task);

    if (task === undefined || !task.running) {
      return { error: 'Your task has ended; nothing more reaches its parent' };
    }

    const delivered = owner?.tell(task.from, text, queued);

    return delivered === undefined
      ? { error: 'The session that started you has closed' }
      : { delivered };
  };

  const [sessions] = useState(
    () =>
      new OpenAgents({
        conversation: conversationOf,
        heard: (key, event, wait) => hear.current(key, event, wait),
        closingHeard: (key, event) => {
          if (!retiredHeard(key, event)) {
            dispatch({ type: 'closing_heard', key, event });
          }
        },
      }),
  );
  // What each runtime offers, read in the window's place: its files say how
  // a runtime starts there, or that it does not (CHD-466). Made at the
  // first ask.
  const runtimesMade = useRef<Runtimes | undefined>(undefined);
  const runtimes = (): Runtimes =>
    (runtimesMade.current ??= new Runtimes({
      probe: sessionProbe(place.cwd, (runtime) => place.startupOf(runtime)),
    }));

  /** What chord's MCP server reads of the window, when a session calls. */
  const view: WindowView = {
    sessions: () => {
      const agents = front();
      const session = agents?.main.conversation.session;

      return agents === undefined
        ? []
        : [
            {
              key: agents.main.key,
              runtime: agents.main.agent,
              id: session?.id,
              model: session?.models()?.current,
              children: agents.children.map((child) => ({
                id: child.id,
                name: child.name,
                runtime: child.runtime,
                model:
                  child.conversation.session?.models()?.current ?? child.model,
              })),
            },
          ];
    },
    runtimes: () => runtimeNames,
    offer: (runtime, probe) => {
      const refused = place.startupOf(runtime)?.refused;

      // Refused where the asking session works: nothing is read, nor
      // started to be.
      if (refused !== undefined) {
        return Promise.resolve({ error: refused });
      }

      const main = sessions.agents.main;
      const session =
        main?.agent === runtime ? main.conversation.session : undefined;

      if (session !== undefined) {
        runtimes().heard(runtime, {
          models: session.models(),
          modes: session.modes(),
          efforts: session.efforts(),
        });
      }

      return runtimes().read(runtime, probe);
    },
    spawn: (caller, args) => spawn(caller, args),
    open: (key, args) => openAgent(key, args),
    teams: async (caller) => {
      const agents = ownedBy(sessions.agents, caller.key);

      return {
        found: await teamsAt(caller.key),
        runs: (agents === undefined ? [] : ownChildren(agents)).flatMap(
          (child) =>
            child.team === undefined
              ? []
              : [
                  {
                    team: child.team,
                    name: child.name,
                  },
                ],
        ),
      };
    },
    // As open_agent's, the answer waits on a lead given an effort.
    runTeam: async (caller, args) => {
      const answer = await runTeamAt(caller.key, args, 'list_teams lists them');

      return 'error' in answer
        ? answer
        : { ...answer.ran, ...(await answer.started) };
    },
    teamPlaces: (caller, name) => teamPlaces(caller.key, name),
    askPerson: (caller, wait, signal) =>
      conversationAt(caller.key)?.ask(wait, signal) ??
      Promise.resolve(undefined),
    openMember: (caller, args) => openMember(caller, args),
    message: (caller, text, queued) => message(caller, text, queued),
    tell: (caller, to, text, queued) => tell(caller, to, text, queued),
    close: (caller, to) => closeAgent(caller, to),
    monitor: (caller, args) =>
      startMonitorIn(sessions.agents, caller, args, place.cwd),
    stopMonitor: (caller, id) => stopMonitorIn(sessions.agents, caller, id),
    monitors: (caller) => monitorsIn(sessions.agents, caller),
    served: (caller, call) =>
      caller.task !== undefined
        ? children.current.get(caller.task)?.served(call)
        : caller.agent !== undefined
          ? childOf(caller.key, caller.agent)?.conversation.served(call)
          : conversationAt(caller.key)?.served(call),
    servedLater: (caller) => {
      const { task } = caller;
      const child = task === undefined ? undefined : children.current.get(task);
      const parent = callerConversation(caller.key, caller.by);
      const agent = task === undefined ? undefined : parent?.task(task);

      if (task === undefined || child === undefined || agent === undefined) {
        return (call) => view.served(caller, call);
      }

      // A task that has ended no longer hears its conversation: the call is
      // kept in its record and drawn in its block in the parent from here.
      const block = parent?.endedTaskServed(task);

      return (call) => {
        if (agent.running) {
          return child.served(call);
        }

        child.servedEnded(call);
        block?.(call);
      };
    },
  };

  useEffect(() => {
    // The window's one session, its state the window's from its first
    // frame; it resumes `resume`, which `resuming` holds from the start.
    sessions.start(agent);

    // A crash or a signal closes and reaps them too before chord exits.
    const forget = closeOnForcedExit(() => sessions.closeAll());

    return () => {
      forget();

      runtimesMade.current?.close();

      void sessions.closeAll().catch(() => {});
    };
  }, [sessions]);

  /**
   * The session in front, read when a key or a pick acts rather than when
   * the window was drawn, as the first is opened only after.
   */
  const conversation = () => sessions.front;

  /** The conversation of main or child `key`; none once it has closed. */
  const conversationAt = (key: number) => sessions.conversationOf(key);

  /**
   * Draws the session `sessions` has in front, on the agent picked in it, as
   * it was left; the box starts afresh on its draft and cursor.
   */
  const showFront = () => {
    const front = shownKey(sessions.agents);

    if (front === undefined || front === all.front) {
      return;
    }

    dispatch({ type: 'session_shown', key: front });
    redraw();
  };

  /** The window's agents, as `sessions` has them now, once main has started. */
  const front = (): StartedAgents<Conversation> | undefined =>
    ownedBy(sessions.agents, sessions.agents.main?.key);

  /**
   * Moves the pick in the list under the prompt `by` rows, as it is drawn
   * in `limit` lines at `width`, the transcript and the box following;
   * above `main` the focus goes back to the box. On a picked row taller
   * than the list it moves a line of it first, and a row so tall picked
   * comes into sight the least move from where the list was (CHD-471).
   */
  const moveAgent = (by: number, limit: number, width: number) => {
    const rows = listed(limit, width);
    const now = Date.now();
    const frame = { limit, width, now };
    const view = state.agentsView;
    const scrolled =
      state.summaryFocus === true
        ? undefined
        : scrolledView(rows, by, { ...frame, view });

    if (scrolled !== undefined) {
      dispatch({ type: 'agents_scrolled', view: scrolled });

      return;
    }

    const { top } = agentsLayout(rows, { ...frame, focused: true, view });
    const target = moveListFocus(rows, by, {
      summary: background().length > 0,
      onSummary: state.summaryFocus === true,
    });

    // The last stays the last: where ↓ leaves the pick on the row it was
    // on, the window stays where that row was read to (CHD-471).
    const stays =
      target?.kind === 'agent' &&
      state.summaryFocus !== true &&
      target.key === rows.find((row) => row.picked)?.key;

    if (!stays) {
      dispatch({
        type: 'agents_scrolled',
        view:
          target?.kind === 'agent'
            ? enteredView(
                rows.map((row) => ({
                  ...row,
                  picked: row.key === target.key,
                })),
                top,
                frame,
              )
            : undefined,
      });
    }

    focusOn(target);
  };

  /**
   * The `❯` onto `target`: an agent's row picks it, the transcript and the
   * box following; the summary line picks nothing; none hands the keys back
   * to the box.
   */
  const focusOn = (target: ListTarget | undefined) => {
    if (target === undefined) {
      return dispatch({ type: 'agents_focused', focused: false });
    }

    dispatch({ type: 'agent_close_disarmed' });

    if (target.kind === 'summary') {
      return dispatch({ type: 'summary_focused', focused: true });
    }

    dispatch({ type: 'summary_focused', focused: false });
    sessions.pick(target.key);
    showFront();
  };

  /**
   * ↑ ↓ in the background view: the `❯` `by` rows on, stopping at the ends;
   * in a detail, to the next item's detail (CHD-481).
   */
  const moveBackground = (
    by: 1 | -1,
    frame: { readonly width: number; readonly height: number },
  ) => {
    const detail = state.backgroundView?.detail;

    if (detail !== undefined) {
      const to = stepDetail(background(), detail, by);

      if (to === 'closed') {
        dispatch({ type: 'background_closed' });
      } else if (to !== undefined) {
        dispatch({ type: 'background_focused', focus: to });
      }

      return;
    }

    const at = moveView(background(), state.backgroundView, by, {
      ...frame,
      now: Date.now(),
    });

    if (at?.focus !== undefined) {
      dispatch({
        type: 'background_focused',
        focus: at.focus,
        ...(at.top === undefined ? {} : { top: at.top }),
        ...(at.laid === undefined ? {} : { laid: at.laid }),
      });
    }
  };

  /**
   * `x` in the background view: the focused item stops at once, with no
   * confirmation, its row turning to stopped in place. A monitor stops as
   * its row's `x` stopped it before, its agent told; a task's turn is
   * cancelled, which ends it and closes its session; an agent is asked to
   * stop alone, its row stopping until its agent says it ended, and a stop
   * that cannot be sent, or an agent that offers none, says so on the hint
   * line. An ended one, and one already stopping, is left.
   */
  const stopBackground = () => {
    const item = focusedItem(background(), state.backgroundView?.focus);

    if (
      item === undefined ||
      (item.status.group !== 'running' && item.status.group !== 'asking')
    ) {
      return;
    }

    // Kept on it by its ref, so the ❯ stays on the row as it changes.
    dispatch({
      type: 'background_focused',
      focus: { key: item.key, id: item.id },
    });

    if (item.kind === 'agent') {
      // A second x while its stop is pending does nothing.
      if (item.status.group === 'running' && item.status.stopping) {
        return;
      }

      // Its own, so an earlier stop's late answer is never this one's.
      const token = crypto.randomUUID();
      const hinted = (hint: string) =>
        dispatch({ type: 'background_hinted', token, hint });

      dispatch({
        type: 'background_stop_asked',
        focus: { key: item.key, id: item.id },
        token,
      });

      if (!item.stoppable) {
        hinted(NO_STOP_HINT);
      } else {
        conversationAt(item.key)
          ?.stopSubagent(item.id)
          .catch((error: unknown) => hinted(stopRefused(error)));
      }
    } else if (item.kind === 'monitor') {
      conversationAt(item.key)?.stopMonitor(item.id, 'person');
    } else {
      conversationAt(item.key)?.task(item.id)?.cancel('x');
    }
  };

  /**
   * Enter in the background view: the view closes, the item's owner is
   * picked, as moving onto its row picks it, and its transcript scrolls back
   * so that the call that started the item is its top line, the keys going
   * to the box. A call no longer in the transcript leaves the view as it is.
   */
  const goToCall = () => {
    const item = focusedItem(background(), state.backgroundView?.focus);

    // On a row, enter opens its detail; in it, to its call (CHD-481; an
    // agent's or a task's too, Q134 and Q138).
    if (item !== undefined && state.backgroundView?.detail === undefined) {
      dispatch({
        type: 'background_detail_opened',
        focus: { key: item.key, id: item.id },
      });

      return;
    }

    const entries = item && all.sessions[item.key]?.transcript.entries;
    const place = entries && callPlace(entries, item);

    if (item === undefined || place === undefined) {
      return;
    }

    dispatch({ type: 'background_closed' });
    dispatch({ type: 'agents_focused', focused: false });
    dispatch({ type: 'agent_close_disarmed' });
    sessions.pick(item.key);
    showFront();
    dispatch({
      type: 'in_session',
      key: item.key,
      action: { type: 'jumped_to', ...place },
    });
  };

  /**
   * `x` in the list: closes the picked child, once a second press confirms
   * cutting a busy one short. chord tells the parent, so it is not left
   * waiting on a child that will never answer. On `main` it closes nothing.
   */
  const closePicked = () => {
    const agents = front();
    const child = agents && pickedChild(agents);

    if (agents === undefined || child === undefined) {
      return dispatch({
        type: 'sessions_noted',
        message: 'main is the session · ctrl+d quits',
      });
    }

    // A lead closes with its members, so their work counts as its own.
    const members = isLead(child) ? membersOf(agents, child.id) : [];
    const busy = [child, ...members].some(
      (each) =>
        stateOf(each.key) !== undefined &&
        busyOf(stateOf(each.key)!) !== undefined,
    );

    if (busy && state.agentCloseArmed !== child.key) {
      return dispatch({ type: 'agent_close_armed', key: child.key });
    }

    closeByPerson(child);
  };

  /**
   * Closes `child`, a lead with its members, as the person asked, and tells
   * its parent, so it is not left waiting on a child that will never
   * answer; the members closed with it, by name.
   */
  const closeByPerson = (child: Child<Conversation>): string[] => {
    const agents = front();
    const members =
      agents !== undefined && isLead(child) ? membersOf(agents, child.id) : [];
    const parent = parentOf(child);

    dropChild(child.key);
    parent?.agentClosed(child.id);
    redraw();

    const model =
      conversationAt(child.key)?.session?.models()?.current ?? child.model;
    const described = `${[child.runtime, model]
      .filter((part) => part !== undefined)
      .join(' · ')}, id ${child.id}`;

    parent?.deliver(
      { name: 'chord' },
      isLead(child)
        ? `The person closed team ${child.name}: its lead (${described})${
            members.length === 0
              ? ''
              : ` and its members ${andList(members.map((each) => each.name))}`
          }. It takes no more messages; run_team starts it again.`
        : `The person closed ${child.name} (${described}). It takes no ` +
            `more messages; open_agent ${
              child.lead === undefined ? 'starts another' : 'opens it again'
            }.`,
    );

    return members.map((each) => each.name);
  };

  /** The runs open in `agents`, a lead each, in the order they started. */
  const runsIn = (agents: StartedAgents<Conversation>): TeamRun[] =>
    ownChildren(agents).flatMap((child) =>
      isLead(child) && child.team !== undefined
        ? [{ team: child.team, name: child.name, since: child.openedAt }]
        : [],
    );

  /**
   * `/team`'s picker and its names: the team files where the window
   * works, read now, the runs open in it, and the two directories as the
   * window shows them; none once main has closed.
   */
  const listTeams = async (): Promise<TeamListing | undefined> => {
    const agents = front();

    if (agents === undefined) {
      return undefined;
    }

    const { cwd } = place;
    const dirs = teamDirs({ configHome, cwd });

    return {
      teams: await teamsAt(agents.main.key),
      runs: runsIn(agents),
      dirs: {
        project: relative(cwd, dirs.project),
        ...(dirs.user === undefined ? {} : { user: homePath(dirs.user, home) }),
      },
    };
  };

  /** The team file `name` where the window works, read now. */
  const teamNamed = async (name: string): Promise<ListedTeam | undefined> => {
    const agents = front();

    return agents === undefined
      ? undefined
      : (await teamsAt(agents.main.key)).find((each) => each.name === name);
  };

  /**
   * `/team run`: the run `run_team` starts, for `main`, with
   * the person's words as the job, drawn as its call is; main, which took
   * no part, hears of it ahead of its next prompt.
   */
  const runTyped = async (name: string, job: string): Promise<TeamShown> => {
    const agents = front();
    const refused = teamRefusal(name, await teamNamed(name));

    if (agents === undefined || refused !== undefined) {
      return {
        kind: 'said',
        text: refused ?? 'This session has closed',
        failed: true,
      };
    }

    const answer = await runTeamAt(
      agents.main.key,
      { team: name, job },
      '/team lists them',
    );

    if ('error' in answer) {
      return { kind: 'said', text: answer.error, failed: true };
    }

    // Drawn at once, not after the lead's start: the list says the effort
    // it is on, and its transcript a refusal.
    const call: ChordCall = {
      tool: 'run_team',
      input: { team: name, job },
      answer: answer.ran,
    };

    conversationAt(agents.main.key)?.aside(
      { name: 'chord' },
      ranNote(name, answer.ran.name, job),
    );
    conversationAt(agents.main.key)?.ranTyped(call);

    return { kind: 'ran', call };
  };

  /**
   * `/team stop`: the run `name` closed with its members, at
   * once, as the person typed it on purpose; `show` hears what it did
   * before main is told, as for `x`, so the command's line comes first.
   */
  const stopTyped = (name: string, show: (shown: TeamShown) => void) => {
    const agents = front();
    const lead =
      agents === undefined
        ? undefined
        : ownChildren(agents).find(
            (child) => isLead(child) && child.name === name,
          );

    if (agents === undefined || lead === undefined) {
      return show({
        kind: 'said',
        text:
          `No run named ${name} is open · the list under the prompt ` +
          'names them',
        failed: true,
      });
    }

    show({
      kind: 'said',
      text: stoppedLine(
        lead.name,
        membersOf(agents, lead.id).map((each) => each.name),
      ),
      failed: false,
    });
    closeByPerson(lead);
  };

  /**
   * `/team show`: team `name` as its file has it; while it runs in the
   * window, its first run as it stands now, each of the file's agents
   * with its state and latest headline, the file as the run read it.
   */
  const showTyped = async (name: string): Promise<TeamShown> => {
    const agents = front();
    const found = await teamNamed(name);
    const refused = teamRefusal(name, found);

    if (agents === undefined || found === undefined || !('team' in found)) {
      return {
        kind: 'said',
        text: refused ?? 'This session has closed',
        failed: true,
      };
    }

    const lead = ownChildren(agents).find(
      (child) => isLead(child) && child.team === name,
    );
    const run = lead === undefined ? undefined : runs.current.get(lead.id);

    if (lead === undefined || run === undefined) {
      return { kind: 'show', name, file: found.shown, team: found.team };
    }

    const now = Date.now();
    const members = membersOf(agents, lead.id);
    const shownAgent = (
      agent: string,
      child: Child<Conversation> | undefined,
      lead?: true,
    ): TeamAgentShown => {
      const who = { name: agent, ...(lead ? { lead } : {}) };

      if (child === undefined) {
        return { ...who, open: false };
      }

      const row = {
        key: child.key,
        name: child.name,
        runtime: child.runtime,
        wait: child.wait,
        picked: false,
        failed: all.sessions[child.key]?.connection.status === 'failed',
      };
      const state = agentState(row, now);
      const mark = agentMark(row);
      const latest = stateOf(child.key)?.transcript.entries.findLast(
        (entry) => entry.kind === 'tool' || entry.kind === 'message',
      );

      return {
        ...who,
        open: true,
        state,
        ...(mark === undefined ? {} : { mark }),
        ...(latest?.kind === 'tool'
          ? {
              latest: headlineText(
                firstLine(
                  headline(
                    latest.call,
                    child.conversation.session?.chordServer?.name,
                  ),
                ),
              ),
            }
          : latest?.kind === 'message'
            ? { latest: messageHeadline(latest.from) }
            : {}),
      };
    };

    return {
      kind: 'show',
      name,
      file: found.shown,
      team: run.team,
      running: {
        name: lead.name,
        since: lead.openedAt,
        at: now,
        job: run.job,
        agents: [
          shownAgent('lead', lead, true),
          ...run.team.members.map((member) =>
            shownAgent(
              member.name,
              members.find((each) => each.name === member.name),
            ),
          ),
        ],
      },
    };
  };

  /**
   * `/team new`: `typed` drawn as the person's
   * prompt in `main`, `prompt` what its agent gets, with
   * the shell output held there ahead of it.
   */
  const sendToMain = (typed: string, prompt: string) => {
    const key = front()?.main.key;
    const now = key === undefined ? undefined : stateOf(key);

    if (
      key !== undefined &&
      now !== undefined &&
      canSend(now, typed) &&
      conversationAt(key)?.send(typed, withContext(heldContext(now), prompt))
    ) {
      dispatch({
        type: 'in_session',
        key,
        action: { type: 'context_sent', held: now.held },
      });
    }
  };

  /**
   * `/clear` on the session in front: refused while a child is picked, as
   * clearing it would leave the parent talking to an agent that no longer
   * knows what it was asked; on `main`, its children close with the session
   * it lets go, as its task agents do. The refusal, if any.
   */
  const clearFront = (before: () => void): string | undefined => {
    const agents = front();

    if (agents !== undefined && pickedChild(agents) !== undefined) {
      return '/clear clears main; pick main first';
    }

    before();

    for (const child of agents?.children ?? []) {
      dropChild(child.key);
    }

    // The new session's record says what it closed, from none (Q184).
    sessions.forgetClosed();

    // Its session goes; what it spent still counts, its turn running too,
    // to that turn's end.
    if (agents !== undefined) {
      keepSpend(
        retiredKey(),
        { name: 'main', kind: 'main', agent: agents.main.agent },
        agents.main.key,
      )(conversationAt(agents.main.key)?.clear());
    } else {
      void conversation()?.clear();
    }

    return undefined;
  };

  /**
   * The window's agents as the list under the prompt draws them, `main`
   * first; none while it has no child, and the list is not drawn.
   */
  const agentRows = (): AgentRow[] => {
    const agents = front();

    if (agents === undefined || agents.children.length === 0) {
      return [];
    }

    const describe = (key: number) => {
      const session = all.sessions[key];

      return {
        model:
          session?.models === undefined ? undefined : modelName(session.models),
        effort: conversationAt(key)?.session?.efforts()?.current,
        failed: session?.connection.status === 'failed',
      };
    };

    return [
      {
        key: agents.main.key,
        name: 'main',
        runtime: agents.main.agent,
        wait: agents.main.wait,
        picked: agents.picked === agents.main.key,
        ...describe(agents.main.key),
      },
      ...agents.children.map((child) => {
        const described = describe(child.key);
        const team = isLead(child)
          ? child.key
          : agents.children.find((each) => each.id === child.lead)?.key;

        return {
          key: child.key,
          name: child.name,
          // A lead reads as a team before any member is open.
          runtime: isLead(child) ? `team · ${child.runtime}` : child.runtime,
          colour: child.colour,
          ...(team === undefined ? {} : { team }),
          wait: child.wait,
          picked: agents.picked === child.key,
          ...described,
          model: described.model ?? child.model,
        };
      }),
    ];
  };

  /**
   * The list under the prompt as it is drawn in `limit` lines at `width`:
   * the window's agents while it has a child, a team folded where their
   * lines do not fit, so a resize may fold or unfold one.
   */
  const listed = (limit: number, width: number): AgentRow[] =>
    listRows(agentRows(), limit, (rows) =>
      agentsHeight(rows, { width, now: Date.now() }),
    );

  /**
   * The window's background: every monitor and task of `main` and
   * its children, those ended since the person's last prompt there kept.
   */
  const background = (): BackgroundItem[] => {
    const agents = front();

    if (agents === undefined) {
      return [];
    }

    const agentIn = (key: number, owner?: ItemOwner): BackgroundAgent[] => {
      const session = all.sessions[key];

      return session === undefined
        ? []
        : [
            {
              key,
              ...(owner === undefined ? {} : { owner }),
              since: session.since,
              monitors: session.monitors,
              endedMonitors: session.endedMonitors,
              transcript: session.transcript,
              stopping: stoppingIn(session.transcript.entries),
            },
          ];
    };

    return backgroundItems(
      [
        ...agentIn(agents.main.key),
        ...agents.children.flatMap((child) =>
          agentIn(child.key, { name: child.name, colour: child.colour }),
        ),
      ],
      // The item whose detail is open stays, ended or not, until the person
      // leaves it (Q126).
      state.backgroundView?.detail,
    );
  };

  /** The child picked, as the box and the header name it. */
  const picked = () => {
    const agents = front();
    const child = agents && pickedChild(agents);
    const lead =
      child?.lead === undefined
        ? undefined
        : agents?.children.find((each) => each.id === child.lead);

    return (
      child && {
        ...child,
        ...(lead === undefined ? {} : { leadName: lead.name }),
      }
    );
  };

  /** ctrl+x a: the agent that waits longest on the person, if one does. */
  const attend = () => {
    if (!sessions.attend()) {
      return dispatch({
        type: 'sessions_noted',
        message: 'Nothing waits on you',
      });
    }

    return showFront();
  };

  // Every session's state, for a read that finishes after the person has
  // picked another agent: what it finishes into is the session it began in.
  const allNow = useRef(all);

  allNow.current = all;

  /** The window as the session `key` fills it now; none once it has closed. */
  const stateOf = (key: number): AppState | undefined => {
    const session = allNow.current.sessions[key];

    return session && { ...allNow.current.window, ...session };
  };

  /** `showDraft` for the session `key`, in front or not. */
  const showDraftIn = (key: number, text: string, at: Cursor) => {
    dispatch({
      type: 'in_session',
      key,
      action: { type: 'draft_set', text, cursor: at },
    });

    if (key === sessions.agents.main?.key) {
      redraw();
    }
  };

  /**
   * Sends `text` to the session `key` with the images its placeholders stand
   * for, and the shell output held there for it; `images` are ones read since
   * the state was drawn. `left` is what the box holds once it has gone: a
   * draft typed while the prompt's files were read, which stays with its
   * images.
   */
  const send = (
    text: string,
    key = all.front,
    images?: readonly PastedImage[],
    left = '',
  ) => {
    // Read through the refs, as a prompt sent after its files were read is
    // sent from a render that has gone by, maybe with another agent picked.
    const now = stateOf(key);
    const sending = images ?? now?.images ?? [];
    const inSession = (action: AppAction) =>
      dispatch({ type: 'in_session', key, action });

    if (
      now !== undefined &&
      canSend(now, text) &&
      conversationAt(key)?.send(
        text,
        withContext(heldContext(now), text),
        attachmentsOf(text, sending),
        mentionsIn(text),
      )
    ) {
      inSession({ type: 'context_sent', held: now.held });
      inSession({ type: 'images_sent', keeping: left });
      host.remember(text, imagesIn(text, sending));

      if (left === '') {
        showDraftIn(key, '', START);

        // Vim mode is the window's, so only the box in front starts again.
        if (key === sessions.agents.main?.key && now.vim) {
          dispatch({ type: 'vim_changed', vim: vimReset(now.vim) });
        }
      }
    }
  };

  const quit = () => {
    const { main } = sessions.agents;
    const session = main && all.sessions[main.key];
    const sessionId = session && resumableSession(session);

    onQuit?.(
      main === undefined || sessionId === undefined
        ? undefined
        : { agent: main.agent, sessionId },
    );

    // The window closes itself: `closeAll` takes the agents out first, so the
    // `closing` their conversations report is no longer heard, and keys
    // would go on starting work while the agents shut down.
    dispatch({ type: 'closing' });
    void sessions.closeAll().then(() => exit(), exit);
  };

  /**
   * What the whole window has spent, for `/cost`: main, its agents, closed
   * ones too, and the sessions still closing as they stand (CHD-373 S4).
   */
  const spend = () => {
    const now = allNow.current;

    return windowSpend(sessions.agents, now.sessions, [
      ...(now.window.keptSpend ?? []),
      ...Object.values(now.closing ?? {}).map((closing) =>
        keptSpend(closing.session, closing.place),
      ),
    ]);
  };

  /**
   * The ids of the sessions open as long-lived children of this one: one of
   * them `/resume` picks rather than loading it twice.
   */
  const openChildren = (): ReadonlySet<string> =>
    new Set(
      (front()?.children ?? []).flatMap((child) => {
        const id = all.sessions[child.key]?.sessionId;

        return id === undefined ? [] : [id];
      }),
    );

  /** The queued prompts back into the box, ahead of what is typed there. */
  const takeBackQueue = (typed: string) => {
    if (mine(state.queue).length > 0) {
      const text = restoredDraft(state.queue, typed);

      showDraft(text, endOf(text));
    }
  };

  /** A sentence `/resume` says in the transcript instead of opening. */
  const sayResume = (text: string) =>
    dispatch({
      type: 'reported',
      turnId: crypto.randomUUID(),
      command: 'resume',
      rows: [{ text }],
    });

  /**
   * `/resume`: reads chord's session records afresh, so a session another
   * chord used since is there, and opens the picker on this
   * directory's, with every other directory's a key away.
   * What the read finds goes through the reducer, which drops it if a
   * `/clear` or quitting came first and refuses it if a turn started.
   */
  const openResume = () => {
    const refusal = resumeRefusal(state);

    if (refusal !== undefined) {
      return sayResume(refusal);
    }

    const asked = crypto.randomUUID();
    // Main's agent, whose sessions it can load.
    const front = sessions.agents.main?.agent ?? agent;
    const find = { agent: front };
    const here = resolve(place.cwd);
    const dir = stateDir ?? chordStateDir();

    dispatch({ type: 'resume_asked', asked });

    readRecords(dir).then(
      (records) =>
        dispatch({
          type: 'resume_listed',
          asked,
          sessions: earlierSessions(records, find, state.sessionId),
          cwd: here,
          otherwise:
            `No earlier ${front} session to resume, ` +
            'here or in any other directory.',
        }),
      (error: unknown) =>
        dispatch({
          type: 'resume_listed',
          asked,
          sessions: [],
          cwd: here,
          otherwise: `Could not read the earlier sessions: ${
            error instanceof Error ? error.message : String(error)
          }`,
        }),
    );
  };

  /**
   * Enter on `/resume`'s list: leaves the session on screen for `chosen`,
   * the way `/clear` leaves it for a new one: the transcript empties and the
   * chosen session's past plays into it, as `--resume` plays it. One open
   * as a child of this session is picked instead: two conversations on one
   * session would each write its record over the other's.
   */
  const pickSession = (chosen: Resume) => {
    const refusal = resumeRefusal(state);
    const agents = front();
    const open = agents?.children.find(
      (each) => all.sessions[each.key]?.sessionId === chosen.sessionId,
    );

    dispatch({ type: 'resume_picker_closed' });

    if (open !== undefined) {
      sessions.pick(open.key);

      return showFront();
    }

    if (refusal !== undefined) {
      return sayResume(refusal);
    }

    if (chosen.cwd !== resolve(place.cwd)) {
      // The window's directory, its settings, MCP servers, files and shell
      // were all read for this one; `--resume` starts in the session's own.
      // Its agent is main's, whose command is overridden only when it is the
      // one the window was started on, as on quit.
      const front = sessions.agents.main?.agent ?? agent;

      return sayResume(
        elsewhereRefusal(chosen, {
          agent: front,
          agentCommand: front === agent ? typedCommand : undefined,
          shownCwd: homePath(chosen.cwd, home),
        }),
      );
    }

    takeBackQueue('');
    stopCommand(all.front);

    // The main session goes, and its children with it, as on `/clear`;
    // the resumed one's record says what it closed (Q184).
    for (const child of agents?.children ?? []) {
      dropChild(child.key);
    }

    sessions.forgetClosed();

    if (agents !== undefined) {
      const kept = keepSpend(
        retiredKey(),
        { name: 'main', kind: 'main', agent: agents.main.agent },
        agents.main.key,
      );

      sessions.pick(agents.main.key);
      showFront();

      resuming.current = chosen;

      kept(conversationAt(agents.main.key)?.clear());
    }
  };

  /** Enter on `/resume`'s list. */
  const pickResume = (chosen: EarlierSession) => pickSession(chosen.resume);

  /** Enter on `/model`'s list. */
  const pickModel = (id: string) => {
    dispatch({ type: 'model_picker_closed' });

    const model = modelToAsk(state.models, id);

    if (model !== undefined) {
      conversation()?.setModel(model);
    }
  };

  /** Enter on one of `/config`'s values. */
  const pickOption = (option: AgentOption, value: string) => {
    dispatch({ type: 'config_picker_closed' });

    const asked = valueToAsk(option, value);

    if (asked !== undefined) {
      conversation()?.setOption(option.id, asked);
    }
  };

  /**
   * What the status line says of the session's agents that wait and of a
   * close or quit armed.
   */
  const lines = () => {
    // The task of session `key`'s whose request `wait` is, by the name its
    // box gives it; none when the session's agent or a subagent of its own,
    // not a task, asks (CHD-431).
    const taskOf = (key: number, wait: AgentWait) => {
      const id = wait.asking?.on.subagentId;
      const entries = id === undefined ? [] : stateOf(key)?.transcript.entries;

      if (id === undefined || entries === undefined) {
        return {};
      }

      const task = subagentPath(entries, id).at(-1)?.task;

      return task === undefined
        ? {}
        : {
            task: askerParts({ entries, subagentId: id })
              .map((part) => part.text)
              .join(''),
          };
    };

    const frontTab = ownedBy(sessions.agents, sessions.agents.main?.key);
    // The session's agents but the one picked, by their names: `main`
    // too, while a child is picked.
    const others =
      frontTab === undefined || frontTab.children.length === 0
        ? []
        : [
            { key: frontTab.main.key, name: 'main', wait: frontTab.main.wait },
            ...frontTab.children,
          ]
            .filter(({ key }) => key !== frontTab.picked)
            .map((other) => {
              const name =
                'id' in other ? namedChild(frontTab, other) : other.name;

              return {
                name,
                wait: other.wait,
                ...taskOf(other.key, other.wait),
              };
            });

    const waits = waitsNotice(others, hintKey(state.keys, 'session:attention'));
    const closeAgentKey = hintKey(state.keys, 'agents:close');
    const armedChild =
      state.agentCloseArmed === undefined
        ? undefined
        : agentOf(sessions.agents, state.agentCloseArmed)?.child;
    const busyAt = (key: number) => stateOf(key) && busyOf(stateOf(key)!);
    const childBusy = armedChild && busyAt(armedChild.key);
    // A lead closes with its members, so it is armed while any of them works.
    const members =
      armedChild && frontTab && isLead(armedChild)
        ? membersOf(frontTab, armedChild.id)
        : [];
    const teamBusy =
      members.length > 0 &&
      [armedChild!, ...members].some(({ key }) => busyAt(key) !== undefined);
    const armed =
      armedChild && teamBusy && closeAgentKey !== undefined
        ? teamCloseArmedLine(armedChild.name, members.length, closeAgentKey)
        : armedChild && childBusy && closeAgentKey !== undefined
          ? agentCloseArmedLine(armedChild.name, childBusy, closeAgentKey)
          : state.quitArmed
            ? ctrlCArmedLine()
            : undefined;

    // The front session's own request between turns comes first: it is
    // on screen, waiting for the keys.
    const between = heldBack(state)
      ? betweenNotice(
          askedPermission(state.transcript.turn) === undefined
            ? 'input'
            : 'permission',
          hintKey(state.keys, 'session:attention'),
        )
      : undefined;

    return { waits: between ?? waits, armed };
  };

  return {
    sessions,
    place,
    lines,
    conversation,
    showFront,
    attend,
    stateOf,
    showDraftIn,
    send,
    quit,
    takeBackQueue,
    spend,
    openChildren,
    openResume,
    pickResume,
    pickModel,
    pickOption,
    moveAgent,
    closePicked,
    moveBackground,
    stopBackground,
    goToCall,
    frontKey: () => front()?.main.key,
    listTeams,
    runTyped,
    stopTyped,
    showTyped,
    sendToMain,
    clearFront,
    agentRows,
    listed,
    background,
    picked,
    dismissNotice: dismissNoticeFor,
  };
}
