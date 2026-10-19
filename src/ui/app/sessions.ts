/**
 * The window's sessions, driven through `OpenSessions`: each opened with a
 * conversation of its own whose events go into the reducer under its key,
 * switched, closed, resumed and quit, and the prompts sent to them.
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
import { OpenSessions } from '../../session/open_sessions.ts';
import type { Session } from '../../session/session.ts';
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
  earlierSessions,
  elsewhereRefusal,
  type ResumableTab,
  type Resume,
  type SessionRecord,
} from '../../session/sessions.ts';
import { chordStateDir } from '../../session/state_dir.ts';
import {
  monitorsIn,
  startMonitorIn,
  stopMonitorIn,
} from '../../session/window_monitors.ts';
import {
  capNote,
  type EarlierWindow,
  earlierWindows,
  readWindows,
  type ResumeEntry,
  windowElsewhereRefusal,
  windowRoom,
} from '../../session/windows.ts';
import {
  agentOf,
  askingChild,
  waitingChild,
  type Child,
  childEnded,
  type ChildInfo,
  childName,
  frontTab,
  full,
  isLead,
  listStart,
  MAX_CHILDREN,
  membersOf,
  mergedWait,
  namedChild,
  notifiedName,
  ownChildren,
  pickedChild,
  position,
  runName,
  shownKey,
  shownWait,
  type Tab,
  tabOf,
  type TabWait,
} from '../../session/tabs.ts';
import { subagentPath } from '../../session/subagents.ts';
import { askerParts } from '../dialogs/asker.ts';
import { homePath } from '../../settings.ts';
import type { AgentOption } from '../../session/config.ts';
import { modelName } from '../../session/models.ts';
import { modelToAsk, type TabRow, valueToAsk } from '../pickers/picker.ts';
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
  type BusyTab,
  closeArmedLine,
  ctrlCArmedLine,
  quitArmedLine,
  tabBusy,
  teamCloseArmedLine,
} from './closing.ts';
import {
  type AgentRow,
  agentMark,
  agentState,
  listRows,
  type ListTarget,
  moveListFocus,
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
  NO_STOP_HINT,
  stopRefused,
} from '../background/view.ts';
import { stripLayout, tabGlyphs } from './strip.ts';
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
}

/**
 * Where a tab's sessions work, and what that directory's files give them:
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

/** A tab the window opens with: its agent, the session it resumes, where. */
export interface OpeningTab {
  readonly agent: string;
  readonly resume: Resume;
  readonly place: Place;
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
   * The tabs the window opens with in place of `agent`'s one, in order, the
   * first in front, each where its session works.
   */
  resumes: readonly OpeningTab[] | undefined;
  /** Which of `resumes` comes to the front, by its index; the first if none. */
  resumedFront: number | undefined;
  /** What the status line says once `resumes` are open. */
  resumedNote: string | undefined;
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
  onQuit:
    ((sessions: readonly ResumableTab[], front: number) => void) | undefined;
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
  /** Tells the terminal chord waits on the person, for the tab named. */
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
    resumes,
    resumedFront,
    resumedNote,
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
  // The session each tab opens next resumes, by its key: those `--resume`
  // asks for, and each `/resume` picks; the one `/clear` opens is new.
  const resuming = useRef(new Map<number, Resume>());
  // Where each tab's sessions work, by its key; the window's by default.
  const places = useRef(new Map<number, Place>());
  const placeOf = (key: number | undefined): Place =>
    (key === undefined ? undefined : places.current.get(key)) ?? place;
  /** Where the session in front works. */
  const frontPlace = () => placeOf(sessions.tabs.front);
  const heard = (key: number, event: ConversationEvent, wait?: Wait) => {
    if (retiredHeard(key, event)) {
      return;
    }

    dispatch({ type: 'in_session', key, action: event });
    host.notify(wait, notifiedName(sessions.tabs, key) ?? agent);
  };

  /**
   * What a session tab `key` let go said of a turn of its, from the tab
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

  const conversationOf = (
    agent: string,
    emit: (event: ConversationEvent) => void,
    key: number,
  ) => {
    const { cwd, mcpServers, startupOf } = placeOf(key);
    const { agentCommand, starting, refused } = startupOf(agent) ?? {};

    return new Conversation(
      (signal) => {
        if (refused !== undefined) {
          throw new Error(refused);
        }

        const next = resuming.current.get(key);
        // A token for each session the tab opens, `/clear`'s included, good
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
        };

        resuming.current.delete(key);

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
      emit,
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
   * Why a child of `args.agent` cannot start from `parent` in tab `key`, with
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
      ? placeOf(key).startupOf(args.agent)
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
   * A child's own conversation, a session of `args.agent` where tab `key`
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
    const { cwd, mcpServers, startupOf } = placeOf(key);
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
      emit,
      Date.now,
      // The model asked for, which the child runs on or not at all, and the
      // mode a team file set, likewise, or else the tab's settings' one.
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
   * the tab's session's; none once it has closed.
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
   * Starts a task agent for the caller, the tab's session or a long-lived
   * child of it: a session of `agent` where that tab works, with no tab of
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
    /** The conversation it answers to: the tab's session's, or its lead's. */
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
   * Opens a long-lived agent in tab `key`, in its list of agents under the
   * prompt rather than a tab of its own, its first prompt `opening.from`'s
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
    const childKey = sessions.tabs.nextKey;

    early.current.set(childKey, [[opening.from, args.prompt, opening.part]]);
    // Its state is there before its first event, which may come at once.
    dispatch({ type: 'agent_opened', key: childKey });

    const effort = effortStart(args, () => conversationAt(childKey));
    const placed = sessions.openChild(
      key,
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
                const child = agentOf(sessions.tabs, own)?.child;

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
                      `${event.message}. It takes no messages; open_agent ` +
                      'starts another.',
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

  /** Why tab `key` cannot open another child of its own, if it cannot. */
  const fullRefusal = (key: number): string | undefined => {
    const tab = tabOf(sessions.tabs, key);

    return tab === undefined
      ? 'This session has closed'
      : ownChildren(tab).length >= MAX_CHILDREN
        ? `This session has ${MAX_CHILDREN} agents open; close_agent one first`
        : undefined;
  };

  /**
   * Opens a long-lived agent for the session in tab `key`: a session of
   * `agent` where that tab works, its first prompt the parent's message.
   * Refused as `startRefusal` says, and past `MAX_CHILDREN`.
   */
  const openAgent = async (
    key: number,
    args: OpenArgs,
  ): Promise<OpenAnswer> => {
    const refused =
      (await startRefusal(key, conversationAt(key), args, 'agent')) ??
      fullRefusal(key);
    const tab = tabOf(sessions.tabs, key);

    if (tab === undefined || refused !== undefined) {
      return { error: refused ?? 'This session has closed' };
    }

    const { opened, started } = startChild(key, args, {
      name: childName(tab, args.name, args.agent),
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

  /** The team files where tab `key` works, read now, each path as shown. */
  const teamsAt = async (key: number): Promise<ListedTeam[]> =>
    (await findTeams({ configHome, cwd: placeOf(key).cwd }, runtimeNames)).map(
      (found) => ({ ...found, shown: shownTeamFile(key, found) }),
    );

  /**
   * A team file as the window shows it to tab `key`: a project's from the
   * directory the tab works in, the user's from `~`.
   */
  const shownTeamFile = (key: number, found: FoundTeam) =>
    found.place === 'project'
      ? relative(placeOf(key).cwd, found.file)
      : homePath(found.file, home);

  /**
   * Where a team named `name` goes for tab `key`, a project's file shown
   * from the directory the tab works in and the user's from `~`, and the
   * team saved under the name now.
   */
  const teamPlaces = async (key: number, name: string) => {
    const { cwd } = placeOf(key);
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
      agent: tabOf(sessions.tabs, key)?.agent ?? 'the agent',
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
   * `run_team`, and `/team run`: the team's lead opened as a child of tab
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
    const tab = tabOf(sessions.tabs, key);

    if (tab === undefined || refused !== undefined) {
      return { error: refused ?? 'This session has closed' };
    }

    const name = runName(tab, team);
    const others = ownChildren(tab)
      .filter(isLead)
      .map((each) => each.name);
    const { opened, started } = startChild(key, args, {
      name,
      parent: () => conversationAt(key),
      from: MAIN,
      team: { name: team },
      part: teamPart(
        team,
        found.team,
        { lead: name, others },
        placeOf(key).cwd,
      ),
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
      const tab = tabOf(sessions.tabs, key);

      if (
        tab === undefined ||
        !tab.children.some((each) => each.id === lead.id)
      ) {
        return 'You are closed; you open no members';
      }

      return membersOf(tab, lead.id).some((each) => each.name === member)
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
        placeOf(key).cwd,
      ),
      asked: `set by team ${run.name}`,
    });

    return { ...opened, ...(await started) };
  };

  /** Tab `key`'s open child `to`, by chord's id or its name. */
  const childOf = (key: number, to: string) =>
    tabOf(sessions.tabs, key)?.children.find(
      (child) => child.id === to || child.name === to,
    );

  /**
   * Tab `key`'s own open child `to`, by chord's id or its name: one the
   * session opened, a team's lead among them, and no member.
   */
  const ownChild = (key: number, to: string) =>
    tabOf(sessions.tabs, key)?.children.find(
      (child) =>
        child.lead === undefined && (child.id === to || child.name === to),
    );

  /**
   * The conversation a child answers to: its lead's for a member, the tab's
   * session's for any other.
   */
  const parentOf = (child: Child<Conversation>): Conversation | undefined => {
    const tab = agentOf(sessions.tabs, child.key)?.tab;

    return child.lead === undefined
      ? tab && conversationAt(tab.key)
      : tab?.children.find((each) => each.id === child.lead)?.conversation;
  };

  /**
   * Why tab `key` has no open child `to`: closed in it, or open when the
   * session was left, as a resumed past's closing note names it.
   */
  const noChild = (key: number, to: string): string => {
    const closed = tabOf(sessions.tabs, key)?.closed.findLast(
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
    const tab = tabOf(sessions.tabs, caller.key);
    const self =
      caller.agent === undefined
        ? undefined
        : childOf(caller.key, caller.agent);

    if (tab === undefined || self === undefined) {
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
      : tab.children.find((each) => each.id === self.lead);

    if (lead === undefined) {
      return { error: 'Your lead has closed; nothing more reaches it' };
    }

    const members = membersOf(tab, lead.id).filter((each) => each !== self);
    const leads =
      self === lead
        ? ownChildren(tab).filter((each) => isLead(each) && each !== self)
        : [];

    if (self === lead && to === 'main') {
      const delivered = conversationAt(tab.key)?.tell(from, text, queued);

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

    const closed = tab.closed.findLast(
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
   * Tells tab `key`'s session, with `← chord`, of an `event` that ends its
   * child `own`'s work on its own, as `childEnded` words it; a child the
   * window has let go is no news.
   */
  const tellEnded = (key: number, own: number, event: ConversationEvent) => {
    if (event.type !== 'disconnected' && event.type !== 'result') {
      return;
    }

    const child = agentOf(sessions.tabs, own)?.child;
    const lead = child !== undefined && isLead(child);
    const text =
      child &&
      childEnded(child.name, event, child.conversation.session?.gone(), lead);

    if (child === undefined || text === undefined) {
      return;
    }

    // A lead gone leaves its members nobody to answer to.
    if (lead && event.type === 'disconnected') {
      const tab = tabOf(sessions.tabs, key);

      for (const member of tab === undefined ? [] : membersOf(tab, child.id)) {
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

  // Keys of the sessions a tab let go, held as they close, apart from every
  // session's own, which count up from one.
  const retiredKeys = useRef(0);
  const retiredKey = () => --retiredKeys.current;

  /** Holds what a child of tab `tab` spent, by its team, as it closes. */
  const keepChild = (
    tab: number,
    child: ChildInfo & { readonly key: number },
  ) =>
    keepSpend(child.key, {
      tab,
      // A run's lead is `lead` under its team's row, as when it is open.
      name: isLead(child) ? 'lead' : child.name,
      kind: child.team === undefined ? 'agent' : 'member',
      ...(child.team === undefined ? {} : { team: child.team }),
      ...(isLead(child)
        ? { lead: child.id }
        : child.lead === undefined
          ? {}
          : { lead: child.lead }),
    });

  const dropChild = (key: number) => {
    const found = agentOf(sessions.tabs, key);
    const child = found?.child;

    if (found === undefined || child === undefined) {
      return;
    }

    for (const member of membersOf(found.tab, child.id)) {
      dropChild(member.key);
    }

    runs.current.delete(child.id);

    early.current.delete(key);

    if (stateOf(key) && busyOf(stateOf(key)!) !== undefined) {
      child.conversation.interrupt();
    }

    stopCommand(key);

    const kept = keepChild(found.tab.key, child);
    const closed = sessions.closeChild(key);

    kept(closed);
    void closed.catch(() => {});

    dispatch({
      type: 'session_closed',
      key,
      front: shownKey(sessions.tabs) ?? all.front,
    });

    // The list goes with the last child, and the keys go back to the box.
    if (
      agentOf(sessions.tabs, key) === undefined &&
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
    const tab = tabOf(sessions.tabs, caller.key);
    const child =
      lead === undefined
        ? ownChild(caller.key, to)
        : tab &&
          membersOf(tab, lead.id).find(
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
      new OpenSessions({
        conversation: conversationOf,
        heard: (key, event, wait) => hear.current(key, event, wait),
        closingHeard: (key, event) => {
          if (!retiredHeard(key, event)) {
            dispatch({ type: 'closing_heard', key, event });
          }
        },
      }),
  );
  // What each runtime offers, read in each directory's place apart: its
  // files say how a runtime starts there, or that it does not (CHD-466).
  const runtimesAt = useRef(new Map<Place, Runtimes>());
  const runtimesOf = (at: Place): Runtimes => {
    const known = runtimesAt.current.get(at);

    if (known !== undefined) {
      return known;
    }

    const made = new Runtimes({
      probe: sessionProbe(at.cwd, (runtime) => at.startupOf(runtime)),
    });

    runtimesAt.current.set(at, made);

    return made;
  };

  /** The place of the session `key`, a child's its tab's. */
  const placeOfSession = (key: number | undefined) =>
    placeOf(
      key === undefined
        ? undefined
        : (agentOf(sessions.tabs, key)?.tab.key ?? key),
    );

  /** What chord's MCP server reads of the window, when a session calls. */
  const view: WindowView = {
    sessions: () =>
      sessions.tabs.tabs.map((tab, index) => {
        const session = tab.conversation.session;

        return {
          key: tab.key,
          tab: index + 1,
          runtime: tab.agent,
          id: session?.id,
          model: session?.models()?.current,
          children: tab.children.map((child) => ({
            id: child.id,
            name: child.name,
            runtime: child.runtime,
            model: child.conversation.session?.models()?.current ?? child.model,
          })),
        };
      }),
    runtimes: () => runtimeNames,
    offer: (runtime, probe, key) => {
      const at = placeOfSession(key);
      const refused = at.startupOf(runtime)?.refused;

      // Refused where the asking session works: nothing is read, nor
      // started to be.
      if (refused !== undefined) {
        return Promise.resolve({ error: refused });
      }

      const runtimes = runtimesOf(at);
      const tab = sessions.tabs.tabs.find(
        (each) =>
          each.agent === runtime &&
          each.conversation.session !== undefined &&
          placeOf(each.key) === at,
      );
      const session = tab?.conversation.session;

      if (session !== undefined) {
        runtimes.heard(runtime, {
          models: session.models(),
          modes: session.modes(),
          efforts: session.efforts(),
        });
      }

      return runtimes.read(runtime, probe);
    },
    spawn: (caller, args) => spawn(caller, args),
    open: (key, args) => openAgent(key, args),
    teams: async (caller) => {
      const tab = tabOf(sessions.tabs, caller.key);

      return {
        found: await teamsAt(caller.key),
        runs: (tab === undefined ? [] : ownChildren(tab)).flatMap((child) =>
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
      startMonitorIn(sessions.tabs, caller, args, placeOf(caller.key).cwd),
    stopMonitor: (caller, id) => stopMonitorIn(sessions.tabs, caller, id),
    monitors: (caller) => monitorsIn(sessions.tabs, caller),
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
    const opening = resumes ?? [{ agent, resume, place }];

    for (const [index, tab] of opening.entries()) {
      const key = sessions.tabs.nextKey;

      places.current.set(key, tab.place);

      if (tab.resume !== undefined) {
        resuming.current.set(key, tab.resume);
      }

      // The first's state is the window's from its first frame.
      if (index > 0) {
        dispatch({ type: 'session_opened', key });
      }

      sessions.open(tab.agent);
    }

    if (opening.length > 1 && sessions.goTo((resumedFront ?? 0) + 1)) {
      dispatch({ type: 'session_shown', key: sessions.tabs.front ?? 0 });
      redraw();
    }

    // After the front is shown, which takes a note of the sessions away.
    if (resumedNote !== undefined) {
      dispatch({ type: 'sessions_noted', message: resumedNote });
    }

    // A crash or a signal closes and reaps them too before chord exits.
    const forget = closeOnForcedExit(() => sessions.closeAll());

    return () => {
      forget();

      for (const runtimes of runtimesAt.current.values()) {
        runtimes.close();
      }

      void sessions.closeAll().catch(() => {});
    };
  }, [sessions]);

  /**
   * The session in front, read when a key or a pick acts rather than when
   * the window was drawn, as the first is opened only after.
   */
  const conversation = () => sessions.front;

  /** The conversation of tab or child `key`; none once it has closed. */
  const conversationAt = (key: number) => sessions.conversationOf(key);

  /**
   * Draws the session `sessions` has in front, on the agent picked in it, as
   * it was left; the box starts afresh on its draft and cursor.
   */
  const showFront = () => {
    const front = shownKey(sessions.tabs);

    if (front === undefined || front === all.front) {
      return;
    }

    dispatch({ type: 'session_shown', key: front });
    redraw();
  };

  /** The front tab, as `sessions` has it now. */
  const front = (): Tab<Conversation> | undefined => frontTab(sessions.tabs);

  /**
   * Moves the pick in the list under the prompt `by` rows, the transcript
   * and the box following; above `main` the focus goes back to the box.
   */
  const moveAgent = (by: number, limit: number) => {
    focusOn(
      moveListFocus(listed(limit), by, {
        summary: background().length > 0,
        onSummary: state.summaryFocus === true,
      }),
    );
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

  /** ↑ ↓ in the background view: the `❯` `by` rows on, stopping at the ends. */
  const moveBackground = (
    by: 1 | -1,
    frame: { readonly width: number; readonly height: number },
  ) => {
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
      conversationAt(item.key)?.task(item.id)?.cancel();
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
    const tab = front();
    const child = tab && pickedChild(tab);

    if (tab === undefined || child === undefined) {
      const close = hintKey(state.keys, 'session:close');

      return dispatch({
        type: 'sessions_noted',
        message:
          close === undefined
            ? 'main is the session'
            : `main is the session · ${close} closes it`,
      });
    }

    // A lead closes with its members, so their work counts as its own.
    const members = isLead(child) ? membersOf(tab, child.id) : [];
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
    const tab = agentOf(sessions.tabs, child.key)?.tab;
    const members =
      tab !== undefined && isLead(child) ? membersOf(tab, child.id) : [];
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

  /** The runs open in `tab`, a lead each, in the order they started. */
  const runsIn = (tab: Tab<Conversation>): TeamRun[] =>
    ownChildren(tab).flatMap((child) =>
      isLead(child) && child.team !== undefined
        ? [{ team: child.team, name: child.name, since: child.openedAt }]
        : [],
    );

  /**
   * `/team`'s picker and its names: the team files where the front tab
   * works, read now, the runs open in it, and the two directories as the
   * window shows them; none once the window has no tab.
   */
  const listTeams = async (): Promise<TeamListing | undefined> => {
    const tab = front();

    if (tab === undefined) {
      return undefined;
    }

    const { cwd } = placeOf(tab.key);
    const dirs = teamDirs({ configHome, cwd });

    return {
      teams: await teamsAt(tab.key),
      runs: runsIn(tab),
      dirs: {
        project: relative(cwd, dirs.project),
        ...(dirs.user === undefined ? {} : { user: homePath(dirs.user, home) }),
      },
    };
  };

  /** The team file `name` where the front tab works, read now. */
  const teamNamed = async (name: string): Promise<ListedTeam | undefined> => {
    const tab = front();

    return tab === undefined
      ? undefined
      : (await teamsAt(tab.key)).find((each) => each.name === name);
  };

  /**
   * `/team run`: the run `run_team` starts, for the front tab's `main`, with
   * the person's words as the job, drawn as its call is; main, which took
   * no part, hears of it ahead of its next prompt.
   */
  const runTyped = async (name: string, job: string): Promise<TeamShown> => {
    const tab = front();
    const refused = teamRefusal(name, await teamNamed(name));

    if (tab === undefined || refused !== undefined) {
      return {
        kind: 'said',
        text: refused ?? 'This session has closed',
        failed: true,
      };
    }

    const answer = await runTeamAt(
      tab.key,
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

    conversationAt(tab.key)?.aside(
      { name: 'chord' },
      ranNote(name, answer.ran.name, job),
    );
    conversationAt(tab.key)?.ranTyped(call);

    return { kind: 'ran', call };
  };

  /**
   * `/team stop`: the front tab's run `name` closed with its members, at
   * once, as the person typed it on purpose; `show` hears what it did
   * before main is told, as for `x`, so the command's line comes first.
   */
  const stopTyped = (name: string, show: (shown: TeamShown) => void) => {
    const tab = front();
    const lead =
      tab === undefined
        ? undefined
        : ownChildren(tab).find(
            (child) => isLead(child) && child.name === name,
          );

    if (tab === undefined || lead === undefined) {
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
        membersOf(tab, lead.id).map((each) => each.name),
      ),
      failed: false,
    });
    closeByPerson(lead);
  };

  /**
   * `/team show`: team `name` as its file has it; while it runs in the
   * front tab, its first run as it stands now, each of the file's agents
   * with its state and latest headline, the file as the run read it.
   */
  const showTyped = async (name: string): Promise<TeamShown> => {
    const tab = front();
    const found = await teamNamed(name);
    const refused = teamRefusal(name, found);

    if (tab === undefined || found === undefined || !('team' in found)) {
      return {
        kind: 'said',
        text: refused ?? 'This session has closed',
        failed: true,
      };
    }

    const lead = ownChildren(tab).find(
      (child) => isLead(child) && child.team === name,
    );
    const run = lead === undefined ? undefined : runs.current.get(lead.id);

    if (lead === undefined || run === undefined) {
      return { kind: 'show', name, file: found.shown, team: found.team };
    }

    const now = Date.now();
    const members = membersOf(tab, lead.id);
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
   * The person's prompt to session `key`: its tab's ended background items
   * go, as a message between agents never clears them.
   */
  const backgroundCleared = (key: number) => {
    const tab = agentOf(sessions.tabs, key)?.tab;

    if (tab !== undefined) {
      dispatch({ type: 'background_cleared', tab: tab.key, at: Date.now() });
    }
  };

  /**
   * `/team new`: `typed` drawn as the person's
   * prompt in the front tab's `main`, `prompt` what its agent gets, with
   * the shell output held there ahead of it.
   */
  const sendToMain = (typed: string, prompt: string) => {
    const key = front()?.key;
    const now = key === undefined ? undefined : stateOf(key);

    if (
      key !== undefined &&
      now !== undefined &&
      canSend(now, typed) &&
      conversationAt(key)?.send(typed, withContext(heldContext(now), prompt))
    ) {
      backgroundCleared(key);
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
    const tab = front();

    if (tab !== undefined && pickedChild(tab) !== undefined) {
      return '/clear clears main; pick main first';
    }

    before();

    for (const child of tab?.children ?? []) {
      dropChild(child.key);
    }

    // Its session goes; what it spent still counts, its turn running too,
    // to that turn's end.
    if (tab !== undefined) {
      keepSpend(
        retiredKey(),
        { tab: tab.key, name: 'main', kind: 'main', agent: tab.agent },
        tab.key,
      )(conversationAt(tab.key)?.clear());
    } else {
      void conversation()?.clear();
    }

    return undefined;
  };

  /**
   * The front tab's agents as the list under the prompt draws them, `main`
   * first; none while it has no child, and the list is not drawn.
   */
  const agentRows = (): AgentRow[] => {
    const tab = front();

    if (tab === undefined || tab.children.length === 0) {
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
        key: tab.key,
        name: 'main',
        runtime: tab.agent,
        wait: tab.wait,
        picked: tab.picked === tab.key,
        ...describe(tab.key),
      },
      ...tab.children.map((child) => {
        const described = describe(child.key);
        const team = isLead(child)
          ? child.key
          : tab.children.find((each) => each.id === child.lead)?.key;

        return {
          key: child.key,
          name: child.name,
          // A lead reads as a team before any member is open.
          runtime: isLead(child) ? `team · ${child.runtime}` : child.runtime,
          colour: child.colour,
          ...(team === undefined ? {} : { team }),
          wait: child.wait,
          picked: tab.picked === child.key,
          ...described,
          model: described.model ?? child.model,
        };
      }),
    ];
  };

  /**
   * The list under the prompt as it is drawn in `limit` rows: the front
   * tab's agents while it has a child, a team folded where they do not fit.
   */
  const listed = (limit: number): AgentRow[] => listRows(agentRows(), limit);

  /**
   * The front tab's background: every monitor and task of its `main` and
   * its children, those ended since the person's last prompt there kept.
   */
  const background = (): BackgroundItem[] => {
    const tab = front();

    if (tab === undefined) {
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
        ...agentIn(tab.key),
        ...tab.children.flatMap((child) =>
          agentIn(child.key, { name: child.name, colour: child.colour }),
        ),
      ],
      all.window.backgroundCleared[tab.key],
    );
  };

  /** The child picked in the front tab, as the box and the header name it. */
  const picked = () => {
    const tab = front();
    const child = tab && pickedChild(tab);
    const lead =
      child?.lead === undefined
        ? undefined
        : tab?.children.find((each) => each.id === child.lead);

    return (
      child && {
        ...child,
        ...(lead === undefined ? {} : { leadName: lead.name }),
      }
    );
  };

  /**
   * Why tab `tab` is busy, its children's work counted with its own; none
   * when closing it cuts nothing short.
   */
  const busyOfTab = (tab: Tab<Conversation>) => {
    const main = all.sessions[tab.key];

    return (
      main &&
      tabBusy(
        main,
        tab.children.flatMap((child) => {
          const session = all.sessions[child.key];

          return session ? [session] : [];
        }),
      )
    );
  };

  /**
   * A new session of `named`, or of the front one's agent, where the front
   * one works, at the end of the strip and in front; none past nine, and
   * none of an agent chord cannot start, which the front session is told.
   */
  const openBeside = (named?: string) => {
    const { tabs } = sessions;
    const here = frontPlace();

    const refused = here.startupOf(
      named ?? frontTab(sessions.tabs)?.agent ?? agent,
    )?.refused;

    if (
      (named !== undefined && here.startupOf(named) === undefined) ||
      refused !== undefined
    ) {
      return dispatch({
        type: 'noted',
        turnId: `new-${crypto.randomUUID()}`,
        // As typed, so the refusal stands under the name it refuses.
        command: named === undefined ? 'new' : `new ${named}`,
        text: refused ?? `No agent named ${named} · chord agents lists them`,
        failed: true,
      });
    }

    if (full(tabs)) {
      const close = hintKey(state.keys, 'session:close');

      return dispatch({
        type: 'sessions_noted',
        message:
          close === undefined
            ? 'Nine sessions are open; close one first'
            : `Nine sessions are open; close one with ${close} first`,
      });
    }

    const opening =
      named ?? tabs.tabs.find((tab) => tab.key === tabs.front)?.agent ?? agent;

    places.current.set(tabs.nextKey, here);
    // Its state is there before its first event, which may come at once.
    dispatch({ type: 'session_opened', key: tabs.nextKey });
    sessions.open(opening);
    redraw();
  };

  /** ctrl+x ↓: the session that waits longest on the person, if one does. */
  const attend = () => {
    if (!sessions.attend()) {
      return dispatch({ type: 'sessions_noted', message: 'No session waits' });
    }

    return showFront();
  };

  // Every session's state, for a read that finishes after the person has
  // gone to another tab: what it finishes into is the session it began in.
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

    if (key === sessions.tabs.front) {
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
    // sent from a render that has gone by, maybe with another tab in front.
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
      backgroundCleared(key);
      inSession({ type: 'context_sent', held: now.held });
      inSession({ type: 'images_sent', keeping: left });
      host.remember(text, imagesIn(text, sending));

      if (left === '') {
        showDraftIn(key, '', START);

        // Vim mode is the window's, so only the box in front starts again.
        if (key === sessions.tabs.front && now.vim) {
          dispatch({ type: 'vim_changed', vim: vimReset(now.vim) });
        }
      }
    }
  };

  /** The open sessions that are busy, in tab order; none while one is open. */
  const busyTabs = (): BusyTab[] =>
    sessions.tabs.tabs.length < 2
      ? []
      : sessions.tabs.tabs.flatMap((tab, index) => {
          const busy = busyOfTab(tab);

          return busy ? [{ number: index + 1, agent: tab.agent, busy }] : [];
        });

  const quit = () => {
    const { tabs, front } = sessions.tabs;
    const resumable = tabs.flatMap((tab) => {
      const session = all.sessions[tab.key];
      const sessionId = session && resumableSession(session);

      return sessionId === undefined
        ? []
        : [{ agent: tab.agent, sessionId, cwd: placeOf(tab.key).cwd, tab }];
    });

    const at = tabs.findIndex((tab) => tab.key === front);
    // The one in front, or the nearest to its left that a prompt went to.
    const shown = resumable.findLastIndex(({ tab }) => tabs.indexOf(tab) <= at);

    onQuit?.(
      resumable.map(({ tab: _, ...kept }) => kept),
      Math.max(shown, 0),
    );

    // The window closes itself: `closeAll` takes the tabs out first, so the
    // `closing` their conversations report is no longer heard, and keys
    // would go on starting work while the agents shut down.
    dispatch({ type: 'closing' });
    void sessions.closeAll().then(() => exit(), exit);
  };

  /**
   * ctrl+d or `/exit`: quits, or with several sessions open and any busy,
   * asks for a second press first, as ctrl+c always does.
   */
  const askQuit = () =>
    state.quitArmed || busyTabs().length === 0
      ? quit()
      : dispatch({ type: 'quit_armed', by: 'ctrl+d' });

  /**
   * `ctrl+x k`: closes the session in front, the one to its left coming
   * forward, once a second press confirms cutting a busy one short; the
   * last one is a quit. Its agent is waited for in the background.
   */
  const closeFront = () => {
    const { tabs, front } = sessions.tabs;
    const tab = front === undefined ? undefined : tabOf(sessions.tabs, front);
    const session = front === undefined ? undefined : all.sessions[front];

    if (front === undefined || tab === undefined || session === undefined) {
      return;
    }

    if (tabs.length === 1) {
      return askQuit();
    }

    const busy = busyOfTab(tab);

    if (busy !== undefined && state.closeArmed !== front) {
      return dispatch({ type: 'close_armed', key: front });
    }

    const named = `${position(sessions.tabs, front)} ${tab.agent}`;

    // Its turn is cancelled before its agent goes, so the agent can end it
    // as it would any cancel; the close withdraws what it still asks. Its
    // long-lived children close with it: with no tab of their own, left
    // running they would be out of sight.
    if (session && busyOf(session) !== undefined) {
      conversationAt(front)?.interrupt();
    }

    for (const child of tab.children) {
      dropChild(child.key);
    }

    const kept = keepSpend(front, {
      tab: front,
      tabName: named,
      name: 'main',
      kind: 'main',
      agent: tab.agent,
    });

    // Its command stops with it: nothing would be left to show or stop it.
    stopCommand(front);

    const closed = sessions.close(front);

    kept(closed);
    void closed.catch(() => {});

    places.current.delete(front);

    dispatch({
      type: 'session_closed',
      key: front,
      front: shownKey(sessions.tabs) ?? front,
    });
    redraw();

    const count = tab.children.length;

    if (resumableSession(session) !== undefined) {
      dispatch({
        type: 'sessions_noted',
        message:
          count === 0
            ? `Closed ${named} · /resume opens it again`
            : `Closed ${named} and its ${
                count === 1 ? 'agent' : `${count} agents`
              } · /resume opens them again`,
      });
    }
  };

  /** The sessions picker's rows, in tab order. */
  const tabRows = (): TabRow[] =>
    sessions.tabs.tabs.map((tab) => {
      const first = all.sessions[tab.key]?.transcript.entries.find(
        (entry) => entry.kind === 'user',
      );
      const waiter = waitingChild(tab)?.name;

      return {
        agent: tab.agent,
        wait: shownWait(tab),
        front: tab.key === sessions.tabs.front,
        prompt:
          first?.kind === 'user'
            ? first.text.replace(/\s+/g, ' ').trim()
            : undefined,
        agents: tab.children.length,
        ...(waiter === undefined ? {} : { waiter }),
      };
    });

  /**
   * How many sessions are open, and how many wait on the person for a
   * permission, a form or a link, as `/status` counts them.
   */
  const counted = () => ({
    open: sessions.tabs.tabs.length,
    waits: sessions.tabs.tabs.filter(
      (tab) => mergedWait(tab).asking !== undefined,
    ).length,
  });

  /**
   * What the whole window has spent, for `/cost`: each tab, closed agents
   * and tabs, and the sessions still closing as they stand (CHD-373 S4).
   */
  const spend = () => {
    const now = allNow.current;

    return windowSpend(sessions.tabs.tabs, now.sessions, [
      ...(now.window.keptSpend ?? []),
      ...Object.values(now.closing ?? {}).map((closing) =>
        keptSpend(closing.session, closing.place),
      ),
    ]);
  };

  /** The tab the sessions picker opens on. */
  const listFrom = () => listStart(sessions.tabs);

  /**
   * Enter or a digit on the sessions picker: that tab in front, on the
   * child that waits there, if one does.
   */
  const pickTab = (number: number) => {
    dispatch({ type: 'sessions_picker_closed' });
    sessions.goTo(number);

    const waiter = front() && askingChild(front()!);

    if (waiter !== undefined) {
      sessions.pick(waiter.key);
    }

    showFront();
  };

  /**
   * The tab each session open in the window is in, by its id: a tab's own
   * and its long-lived children's, which are open there too.
   */
  const openTabs = (): Map<string, number> =>
    new Map(
      sessions.tabs.tabs.flatMap((tab, index) =>
        [tab.key, ...tab.children.map((child) => child.key)].flatMap((key) => {
          const id = all.sessions[key]?.sessionId;

          return id === undefined ? [] : [[id, index + 1] as const];
        }),
      ),
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
   * `/resume`: reads chord's session and window records afresh, so a session
   * another window used since is there, and opens the picker on this
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
    // The front session's agent, whose sessions it can load.
    const front = frontTab(sessions.tabs)?.agent ?? agent;
    const find = { agent: front };
    const here = resolve(frontPlace().cwd);
    const dir = stateDir ?? chordStateDir();

    dispatch({ type: 'resume_asked', asked });

    Promise.all([readRecords(dir), readWindows(dir)]).then(
      ([records, windows]) =>
        dispatch({
          type: 'resume_listed',
          asked,
          sessions: earlierSessions(records, find, state.sessionId),
          windows: earlierWindows(windows, records),
          cwd: here,
          otherwise:
            `No earlier ${front} session or window to resume, ` +
            'here or in any other directory.',
        }),
      (error: unknown) =>
        dispatch({
          type: 'resume_listed',
          asked,
          sessions: [],
          windows: [],
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
   * chosen session's past plays into it, as `--resume` plays it. One open in
   * another tab is gone to instead: two conversations on one session would
   * each write its record over the other's.
   */
  const pickSession = (chosen: Resume) => {
    const refusal = resumeRefusal(state);
    const open = openTabs().get(chosen.sessionId);

    dispatch({ type: 'resume_picker_closed' });

    if (open !== undefined) {
      sessions.goTo(open);

      // The agent in that tab whose session it is, the tab's own or a child.
      const tab = front();
      const child = tab?.children.find(
        (each) => all.sessions[each.key]?.sessionId === chosen.sessionId,
      );

      if (tab !== undefined) {
        sessions.pick(child?.key ?? tab.key);
      }

      return showFront();
    }

    if (refusal !== undefined) {
      return sayResume(refusal);
    }

    if (chosen.cwd !== resolve(frontPlace().cwd)) {
      // The tab's directory, its settings, MCP servers, files and shell
      // were all read for this one; `--resume` starts in the session's own.
      // Its agent is the front session's, whose command is overridden only
      // when it is the one the window was started on, as on quit.
      const front = frontTab(sessions.tabs)?.agent ?? agent;

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

    // The tab's own session goes, and its children with it, as on `/clear`.
    const tab = front();

    for (const child of tab?.children ?? []) {
      dropChild(child.key);
    }

    if (tab !== undefined) {
      const kept = keepSpend(
        retiredKey(),
        { tab: tab.key, name: 'main', kind: 'main', agent: tab.agent },
        tab.key,
      );

      sessions.pick(tab.key);
      showFront();
      resuming.current.set(tab.key, chosen);
      kept(conversationAt(tab.key)?.clear());
    }
  };

  /**
   * Enter on a saved window in `/resume`'s list: its tabs open beside those
   * open, in its order at the end of the strip, and its front tab comes to
   * the front. A tab whose session is open already is not opened twice, and
   * a front tab never prompted gives its place, so plain `chord` and then
   * `/resume` leaves just the window. Refused whole, never opened in part,
   * when the cap has no room for it, and, as a session from elsewhere is,
   * when any tab works in another directory. `columns` is the status line's
   * width, which words the cap's refusal.
   */
  const pickWindow = (chosen: EarlierWindow, columns: number) => {
    dispatch({ type: 'resume_picker_closed' });

    const here = frontPlace();
    const elsewhere = chosen.tabs.find((tab) => tab.cwd !== resolve(here.cwd));

    if (elsewhere !== undefined) {
      return sayResume(
        windowElsewhereRefusal(chosen.id, homePath(elsewhere.cwd, home)),
      );
    }

    const refused = chosen.opening.tabs
      .map((tab) => here.startupOf(tab.agent)?.refused)
      .find((line) => line !== undefined);

    if (refused !== undefined) {
      return sayResume(refused);
    }

    const unknown = chosen.opening.tabs.find(
      (tab) => here.startupOf(tab.agent) === undefined,
    );

    if (unknown !== undefined) {
      return sayResume(
        `That window has a ${unknown.agent} tab, which chord cannot start here.`,
      );
    }

    const open = openTabs();
    // By key, read now, as closing a reused tab moves the numbers after it.
    const openKeys = new Map(
      [...open].map(([id, number]) => [
        id,
        sessions.tabs.tabs[number - 1]?.key,
      ]),
    );
    const opening = chosen.opening.tabs.filter(
      (tab) => !open.has(tab.resume.sessionId),
    );
    const tab = front();
    const session = tab && all.sessions[tab.key];
    // Never prompted, with nothing of its own open: a place, not a session.
    const empty =
      tab !== undefined &&
      session !== undefined &&
      tab.children.length === 0 &&
      session.resumed === undefined &&
      resumableSession(session) === undefined &&
      !resuming.current.has(tab.key);
    const reused = empty && opening.length > 0;
    const room = windowRoom({
      open: sessions.tabs.tabs.length,
      reused,
      needed: opening.length,
    });

    if (!room.fits) {
      return dispatch({
        type: 'sessions_noted',
        message: capNote(room, hintKey(state.keys, 'session:close'), columns),
      });
    }

    // Out first, so the window's tabs have its place under the cap.
    if (reused) {
      const named = `${position(sessions.tabs, tab.key)} ${tab.agent}`;

      const kept = [
        ...tab.children.map((child) => keepChild(tab.key, child)),
        keepSpend(tab.key, {
          tab: tab.key,
          tabName: named,
          name: 'main',
          kind: 'main',
          agent: tab.agent,
        }),
      ];
      const closed = sessions.close(tab.key);

      kept.forEach((each) => each(closed));
      void closed.catch(() => {});

      places.current.delete(tab.key);
    }

    const keys = new Map<string, number>();

    for (const each of opening) {
      const key = sessions.tabs.nextKey;

      places.current.set(key, here);
      resuming.current.set(key, each.resume);
      dispatch({ type: 'session_opened', key });
      sessions.open(each.agent);
      keys.set(each.resume.sessionId, key);
    }

    if (reused) {
      dispatch({
        type: 'session_closed',
        key: tab.key,
        front: shownKey(sessions.tabs) ?? tab.key,
      });
    }

    const frontId = chosen.opening.tabs[chosen.opening.front]?.resume.sessionId;
    const frontKey =
      frontId === undefined
        ? undefined
        : (keys.get(frontId) ?? openKeys.get(frontId));
    const number =
      frontKey === undefined ? undefined : position(sessions.tabs, frontKey);

    if (number !== undefined) {
      sessions.goTo(number);
    }

    showFront();
    redraw();

    if (chosen.opening.note !== undefined && opening.length > 0) {
      dispatch({ type: 'sessions_noted', message: chosen.opening.note });
    }
  };

  /** Enter on `/resume`'s list: a session, or a saved window. */
  const pickResume = (chosen: ResumeEntry, columns: number) =>
    chosen.kind === 'window'
      ? pickWindow(chosen.window, columns)
      : pickSession(chosen.session.resume);

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
   * The header's strip of tabs, and what the status line says of the tabs
   * behind that wait and of a close or quit armed, at `columns` wide.
   */
  const lines = (columns: number) => {
    const { tabs } = sessions;
    // The task of session `key`'s whose request `wait` is, by the name its
    // box gives it; none when the session's agent or a subagent of its own,
    // not a task, asks (CHD-431).
    const taskOf = (key: number, wait: TabWait) => {
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

    const frontTab = tabs.tabs.find((tab) => tab.key === tabs.front);
    // The front tab's agents but the one picked, by their names: `main`
    // too, while a child is picked.
    const others =
      frontTab === undefined || frontTab.children.length === 0
        ? []
        : [
            { key: frontTab.key, name: 'main', wait: frontTab.wait },
            ...frontTab.children,
          ]
            .filter(({ key }) => key !== frontTab.picked)
            .map((other) => {
              const name =
                'id' in other ? namedChild(frontTab, other) : other.name;

              return {
                number: 0,
                agent: name,
                name,
                wait: other.wait,
                ...taskOf(other.key, other.wait),
              };
            });

    const waits = waitsNotice(
      [
        ...others,
        ...tabs.tabs.flatMap((tab, index) => {
          if (tab.key === tabs.front) {
            return [];
          }

          const waiter = waitingChild(tab);
          const wait = mergedWait(tab);

          return [
            {
              number: index + 1,
              agent: tab.agent,
              wait,
              ...taskOf(waiter?.key ?? tab.key, wait),
              ...(waiter === undefined
                ? {}
                : { waiter: namedChild(tab, waiter) }),
            },
          ];
        }),
      ],
      hintKey(state.keys, 'session:attention'),
    );
    const frontBusy = frontTab && busyOfTab(frontTab);
    const closeKey = hintKey(state.keys, 'session:close');
    const closeAgentKey = hintKey(state.keys, 'agents:close');
    const armedChild =
      state.agentCloseArmed === undefined
        ? undefined
        : agentOf(tabs, state.agentCloseArmed)?.child;
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
          : state.closeArmed !== undefined &&
              frontTab &&
              frontBusy &&
              closeKey !== undefined
            ? closeArmedLine(
                {
                  number: position(tabs, frontTab.key) ?? 1,
                  agent: frontTab.agent,
                  busy: frontBusy,
                },
                closeKey,
              )
            : state.quitArmed === 'ctrl+d'
              ? quitArmedLine(busyTabs(), columns - 4)
              : state.quitArmed
                ? ctrlCArmedLine(busyTabs().length)
                : undefined;
    const strip = stripLayout(
      tabs.tabs.map((tab, index) => ({
        number: index + 1,
        agent: tab.agent,
        front: tab.key === tabs.front,
        glyphs: tabGlyphs(shownWait(tab)),
      })),
      homePath(frontPlace().cwd, home),
      // Inside the header's padding.
      columns - 2,
    );

    // The front session's own request between turns comes first: it is
    // on screen, waiting for the keys.
    const front = heldBack(state)
      ? betweenNotice(
          askedPermission(state.transcript.turn) === undefined
            ? 'input'
            : 'permission',
          hintKey(state.keys, 'session:attention'),
        )
      : undefined;

    return { waits: front ?? waits, armed, strip };
  };

  return {
    sessions,
    placeOf,
    frontPlace,
    lines,
    conversation,
    showFront,
    openBeside,
    attend,
    stateOf,
    showDraftIn,
    send,
    busyTabs,
    askQuit,
    closeFront,
    takeBackQueue,
    tabRows,
    counted,
    spend,
    listFrom,
    pickTab,
    openTabs,
    openResume,
    pickResume,
    pickModel,
    pickOption,
    moveAgent,
    closePicked,
    moveBackground,
    stopBackground,
    goToCall,
    frontKey: () => front()?.key,
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
  };
}
