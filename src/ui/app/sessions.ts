/**
 * The window's agents, on `agents_host.ts`: what the host says of main and
 * each child goes into the reducer under its key; here they are picked, closed
 * by the person, resumed and quit, and the prompts are sent to them.
 */
import type { ReadLimits } from '../../session/resource_access.ts';
import { agentNameProblem } from '../../agent_name.ts';
import { type Dispatch, useEffect, useRef, useState } from 'react';
import { useApp } from './renderer.tsx';
import { resolve } from 'node:path';
import type { Wait } from '../../notify.ts';
import { busyOf, mine } from '../../session/busy.ts';
import { withContext } from '../../session/context.ts';
import {
  Conversation,
  type ConversationEvent,
  type OpenSession,
} from '../../session/conversation.ts';
import { createAgentsHost } from '../../session/agents_host.ts';
import { closeOnForcedExit } from '../../session/leaving.ts';
import type { Place } from '../../session/place.ts';
import type { ChordServer } from '../../server/server.ts';
import type {
  TeamAgentShown,
  TeamShown,
} from '../../session/transcript/types.ts';
import {
  type EarlierSession,
  earlierSessions,
  elsewhereRefusal,
  type Resumable,
  type Resume,
  type SessionRecord,
} from '../../session/sessions.ts';
import { chordStateDir } from '../../session/state_dir.ts';
import type { AgentWait } from '../../session/waits.ts';
import {
  agentOf,
  type Child,
  childName,
  isLead,
  membersOf,
  messageRecipients,
  namedChild,
  notifiedName,
  pickedChild,
  ownedBy,
  shownKey,
} from '../../session/window_agents.ts';
import { subagentPath } from '../../session/subagents.ts';
import { askerParts } from '../dialogs/asker.ts';
import type { ListedAgent } from '../../agents.ts';
import { homePath } from '../../settings.ts';
import { settingActions } from './setting_picked_up.ts';
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
import { restoredDraft } from '../prompt/queue.ts';
import { heldContext } from '../prompt/state.ts';
import { vimReset } from '../prompt/vim.ts';
import { hintKey } from '../shortcuts/bindings.ts';
import { betweenNotice, waitsNotice } from '../status/status.ts';
import { credentialWords } from '../status/credentials.ts';
import { askedPermission } from '../dialogs/permission.ts';
import { heldBack } from '../dialogs/state.ts';
import {
  agentCloseArmedLine,
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
import { headlineText, messageHeadline, TEAM_WORDS } from '../teams/teams.ts';
import {
  firstLine,
  guardianView,
  headline,
} from '../transcript/tools/tools.ts';
import { windowSpend } from '../transcript/spend.ts';
import {
  type AppAction,
  keptSpend,
  type AppState,
  canSend,
  resumableSession,
  resumeRefusal,
  type WindowedAction,
  type WindowedState,
} from './state.ts';

export interface SessionsOptions {
  resources?: ReadLimits | undefined;
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
  /** The agents the registry and PATH list, which `/new` is drawn from. */
  listedAgents?: readonly ListedAgent[] | undefined;
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
  readonly riffHeard?: (
    key: number,
    agent: string,
    event: ConversationEvent,
  ) => void;
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
    resources,
    agent,
    typedCommand,
    place,
    stateDir,
    readRecords,
    open,
    resume,
    server,
    runtimes: runtimeNames,
    listedAgents = [],
    home,
    configHome,
    onQuit,
  }: SessionsOptions,
  host: SessionsWindow,
) {
  const { all, state, dispatch, redraw, showDraft, stopCommand } = host;
  const { exit } = useApp();
  /** What a session replaying its past has said, by its key, so far. */
  const replays = new Map<number, ConversationEvent[]>();
  /**
   * Runs session `key`'s replay of its past, whose actions reach the window
   * as one, folded at once: one by one a long record's took seconds
   * (CHD-559).
   */
  const replayed = (key: number, replay: () => void) => {
    const actions: ConversationEvent[] = [];

    replays.set(key, actions);

    try {
      replay();
    } finally {
      replays.delete(key);

      if (actions.length > 0) {
        dispatch({ type: 'in_session_past', key, actions });
      }
    }
  };

  const heard = (key: number, event: ConversationEvent, wait?: Wait) => {
    const who = agentOf(sessions.agents, key);

    host.riffHeard?.(
      key,
      who?.child?.runtime ?? who?.main?.agent ?? agent,
      event,
    );

    if (event.type === 'credentials') {
      dispatch({ type: 'sessions_noted', message: credentialWords(event) });

      return;
    }

    if (retiredHeard(key, event)) {
      return;
    }

    const replay = replays.get(key);

    if (replay === undefined) {
      dispatch({ type: 'in_session', key, action: event });
    } else {
      replay.push(event);
    }

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

  const [agentsHost] = useState(() =>
    createAgentsHost(
      {
        place,
        runtimes: runtimeNames,
        home,
        configHome,
        stateDir,
        open,
        server,
        resources,
        resume,
      },
      {
        heard: (key, event, wait) => hear.current(key, event, wait),
        replayed,
        closingHeard: (key, event) => {
          if (!retiredHeard(key, event)) {
            dispatch({ type: 'closing_heard', key, event });
          }
        },
        told: (event) => {
          switch (event.type) {
            case 'session_closed':
              return dispatch({
                ...event,
                front: event.front ?? allNow.current.front,
              });
            case 'agents_unfocused':
              return dispatch({ type: 'agents_focused', focused: false });
            case 'setting_saved':
              for (const action of settingActions(event.picked, {
                runtimes: runtimeNames,
                listed: listedAgents,
              })) {
                dispatch(action);
              }

              return;
            default:
              return dispatch(event);
          }
        },
        stateOf: (key) => stateOf(key),
        watched: watchNotice,
        queueBack: (key, typed) => {
          const now = stateOf(key);

          if (now !== undefined && mine(now.queue).length > 0) {
            // After what is typed there, but for the /clear typed to clear it.
            const text = restoredDraft(now.queue, typed ?? now.draft);

            dispatch({
              type: 'in_session',
              key,
              action: { type: 'queue_withdrawn' },
            });

            if (key === shownKey(sessions.agents)) {
              showDraft(text, endOf(text));
            } else {
              showDraftIn(key, text, endOf(text));
            }
          }
        },
        redraw,
        stopCommand,
      },
    ),
  );
  const {
    sessions,
    view,
    resumeNext,
    conversation,
    conversationAt,
    front,
    closeRuntimes,
    keepSpend,
    retiredKey,
    dropChild,
    closeByPerson,
    listTeams,
    runTyped,
    newTyped: newTypedIn,
    stopTyped: stopTypedIn,
    showTyped: showTeam,
    clearedHeard,
    clearByPerson,
    childConversation,
  } = agentsHost;

  useEffect(() => {
    // The window's one session, its state the window's from its first
    // frame; it resumes `resume`, which `resuming` holds from the start.
    sessions.start(agent);

    // A crash or a signal closes and reaps them too before chord exits.
    const forget = closeOnForcedExit(() => {
      return sessions.closeAll();
    });

    return () => {
      forget();
      closeRuntimes();

      void sessions.closeAll().catch(() => {});
    };
  }, [sessions]);

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
                { ...frame, reading: view !== undefined },
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
   * `/fork`: the agent on screen, main or a fork, forked into a new agent of
   * its runtime beside main, of no one, in a process of its own, picked once
   * it is up (CHD-101). Its name and the key of the agent it was forked
   * from, or why it was not forked, with that key once it was asked of the
   * agent; none at all once the source's session has gone meanwhile, as a
   * line in its next session would be about another conversation.
   */
  const forkTyped = async (
    named: string,
  ): Promise<
    | { readonly name: string; readonly from: number }
    | { readonly refused: string; readonly from?: number }
    | undefined
  > => {
    const agents = front();
    const refused = (text: string, from?: number) => ({
      refused: text,
      ...(from === undefined ? {} : { from }),
    });

    if (agents === undefined) {
      return refused('This session has closed');
    }

    const picked = pickedChild(agents);

    if (picked !== undefined && picked.forkedFrom === undefined) {
      return refused('/fork forks main or a fork');
    }

    const sourceKey = picked?.key ?? agents.main.key;
    const sourceName = picked?.name ?? 'main';
    const runtime = picked?.runtime ?? agents.main.agent;
    const session = conversationAt(sourceKey)?.session;
    const now = stateOf(sourceKey);

    if (session === undefined) {
      return refused('This session is closing; nothing can fork from it');
    }

    if (!session.forks()) {
      return refused('This agent does not fork sessions');
    }

    if (now !== undefined && busyOf(now) !== undefined) {
      return refused(`${sourceName} is working · /fork once its turn ends`);
    }

    const problem = agentNameProblem(named);

    if (problem !== undefined) {
      return refused(`An agent name ${problem}`);
    }

    const id = crypto.randomUUID().slice(0, 8);
    const name = childName(agents, named || 'fork', 'fork');
    const up = Promise.withResolvers<string | undefined>();

    const forkKey = sessions.agents.nextKey;

    // Its state is there before its first event, which may come at once,
    // and its view is the conversation as it stood.
    dispatch({
      type: 'agent_opened',
      key: forkKey,
      ...(now === undefined ? {} : { transcript: now.transcript }),
    });

    const key = sessions.openChild(
      { id, name, runtime, forkedFrom: sourceName, openedAt: Date.now() },
      (emit, own) =>
        childConversation(
          agents.main.key,
          undefined,
          { agent: runtime, prompt: '' },
          name,
          // The person's, in the fork's own session (CHD-101).
          { role: 'person', key: forkKey, fork: true, window: view },
          'asked by /fork',
          (event) => {
            emit(event);

            // Cleared later, its fresh session is no fork (CHD-476).
            if (clearedHeard(own, event)) {
              return;
            }

            if (event.type === 'connected') {
              up.resolve(undefined);
              // Where it parted, under what it was copied from.
              queueMicrotask(() => conversationAt(own)?.forked(sourceName));
            } else if (event.type === 'connect_failed') {
              up.resolve(event.message);
              queueMicrotask(() => dropChild(own));
            } else if (
              event.type === 'closing' ||
              event.type === 'disconnected'
            ) {
              // Closed by x or a quit before it was up: nothing to pick.
              up.resolve('it was closed before it started');
            }
          },
          undefined,
          session.id,
        ),
    );

    if (key === undefined) {
      return refused('This session is closing; nothing can fork from it');
    }

    const failed = await up.promise;

    if (conversationAt(sourceKey)?.session !== session) {
      return undefined;
    }

    if (failed !== undefined) {
      return refused(`Could not fork: ${failed}`, sourceKey);
    }

    // Closed as it came up: nothing to pick or announce.
    if (agentOf(sessions.agents, key) === undefined) {
      return refused(
        'Could not fork: it was closed before it started',
        sourceKey,
      );
    }

    sessions.pick(key);
    showFront();

    return { name, from: sourceKey };
  };

  /**
   * `/team show`: the team as the host has it; while it runs in the window,
   * each of the file's agents with its state and latest headline.
   */
  const showTyped = (name: string): Promise<TeamShown> =>
    showTeam(name, ({ file, lead, run, members }) => {
      const now = Date.now();
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
          (entry) =>
            entry.kind === 'message' ||
            (entry.kind === 'tool' && guardianView(entry.call) === 'block'),
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
        file,
        team: run.team,
        running: {
          name: lead.name,
          since: lead.openedAt,
          at: now,
          job: run.job,
          ...(run.selected === undefined
            ? {}
            : { receipt: run.selected.receipt }),
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
    });

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
   * `/clear` on the session in front: a child or fork picked gets a fresh
   * session of its own, its parent told (CHD-476); on `main`, its children
   * close with the session it lets go, as its task agents do.
   */
  const clearFront = (before: () => void): void => {
    const agents = front();

    const picked = agents === undefined ? undefined : pickedChild(agents);

    // A child or a fork picked is the one cleared, main and the rest left as
    // they are (CHD-476), its queue back in its box as clearChild puts it;
    // why not, under the command in its view.
    if (picked !== undefined) {
      void clearByPerson(picked).then(
        (failed) =>
          failed !== undefined &&
          dispatch({
            type: 'in_session',
            key: picked.key,
            action: {
              type: 'noted',
              turnId: `clear-${crypto.randomUUID()}`,
              command: 'clear',
              text: failed,
              failed: true,
            },
          }),
      );

      return;
    }

    before();

    // Main's children go with its session; the forks stand beside it.
    for (const child of agents?.children ?? []) {
      if (child.forkedFrom === undefined) {
        dropChild(child.key);
      }
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
          // A lead reads as a team before any member is open; a fork says so.
          runtime: isLead(child)
            ? `team · ${child.runtime}`
            : child.forkedFrom === undefined
              ? child.runtime
              : `fork · ${child.runtime}`,
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
      went(key, now, text, sending, left);
    }
  };

  /**
   * Tab: the oldest of the person's queued messages into the running turn
   * of the session `key`, the draft left as it is (CHD-535); on an agent
   * that takes no steering it stays queued, and the status line says why.
   */
  const steerQueued = (key = all.front) => {
    if (conversationAt(key)?.steerQueued() === 'unsteerable') {
      dispatch({
        type: 'in_session',
        key,
        action: { type: 'steer_refused', refused: false },
      });
    }
  };

  /**
   * A prompt gone from the box of `key` by Enter: its held output
   * and images went with it, history has it, and the box is what is `left`.
   */
  const went = (
    key: number,
    now: AppState,
    text: string,
    sending: readonly PastedImage[],
    left: string,
  ) => {
    const inSession = (action: AppAction) =>
      dispatch({ type: 'in_session', key, action });

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

  /**
   * The queued prompts back into the box, ahead of what is typed there,
   * their images and held output with them, as a child's clear puts its
   * own back (CHD-476).
   */
  const takeBackQueue = (typed: string) => {
    if (mine(state.queue).length > 0) {
      const text = restoredDraft(state.queue, typed);

      dispatch({ type: 'queue_withdrawn' });
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

      resumeNext(chosen);

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
    conversationAt,
    restartRiff: (key: number, preserve: boolean) => {
      if (preserve) {
        dispatch({
          type: 'in_session',
          key,
          action: { type: 'riff_restarting' },
        });
      }

      const found = agentOf(sessions.agents, key);

      if (found?.child !== undefined) {
        void clearByPerson(found.child);
      } else {
        for (const child of sessions.agents.children) {
          if (child.forkedFrom === undefined) {
            dropChild(child.key);
          }
        }

        sessions.forgetClosed();

        if (found?.main !== undefined) {
          keepSpend(
            retiredKey(),
            { name: 'main', kind: 'main', agent: found.main.agent },
            key,
          )(conversationAt(key)?.clear());
        }
      }
    },
    cancelRiff: () => {
      const agents = sessions.agents;
      const mainRiff = agents.main?.agent === 'riff';
      const leads = new Set(
        agents.children
          .filter((child) => child.runtime === 'riff')
          .map((child) => child.id),
      );

      if (mainRiff) {
        agents.main?.conversation.interrupt();
      }

      for (const child of agents.children) {
        if (
          child.runtime === 'riff' ||
          (mainRiff && child.forkedFrom === undefined) ||
          (child.lead !== undefined && leads.has(child.lead))
        ) {
          child.conversation.interrupt();
        }
      }
    },
    sessions,
    place,
    lines,
    conversation,
    showFront,
    attend,
    stateOf,
    showDraftIn,
    send,
    steerQueued,
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
    newTyped: (named: string) => newTypedIn(named, showFront),
    forkTyped,
    stopTyped: (name: string, show: (shown: TeamShown) => void) =>
      stopTypedIn(name, show, TEAM_WORDS),
    showTyped,
    sendToMain,
    clearFront,
    agentRows,
    recipients: () => {
      const agents = front();

      return agents === undefined
        ? []
        : messageRecipients(agents, agents.picked);
    },
    listed,
    background,
    picked,
    dismissNotice: dismissNoticeFor,
  };
}
