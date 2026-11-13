/**
 * A host's agents, with no window: main and each child opened with a
 * conversation of its own, the teams they run, and what chord's MCP server
 * asks of them. The driver hears of it through its port, at once and in order:
 * the window turns that into the actions it dispatches, each as it comes.
 */
import { relative } from 'node:path';
import type { McpServer } from '@agentclientprotocol/sdk/unstable';
import { agentNameProblem } from '../agent_name.ts';
import type { Wait } from '../notify.ts';
import { Runtimes, sessionProbe } from '../server/runtimes.ts';
import type { ChordServer } from '../server/server.ts';
import { closesAgents, settingsBoxClaim } from '../server/tools.ts';
import type {
  Caller,
  ClearAnswer,
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
} from '../server/tools.ts';
import { homePath, type TeamSelectionPolicy } from '../settings.ts';
import {
  findTeams,
  type FoundTeam,
  type Team,
  teamDirs,
  teamFile,
  teamPart,
} from '../teams.ts';
import { busyOf, type QueuedFrom } from './busy.ts';
import {
  Conversation,
  type ConversationEvent,
  type OpenSession,
} from './conversation.ts';
import { OpenAgents } from './open_agents.ts';
import type { Place } from './place.ts';
import { FileRecording } from './record.ts';
import type { ReadLimits } from './resource_access.ts';
import type { Resume } from './sessions.ts';
import { settingPickedUp, type SettingPickedUp } from './setting_picked_up.ts';
import type { Session } from './session.ts';
import { signInNote } from './sign_in.ts';
import { failureNote, sentence, stepWords } from './start_failure.ts';
import { chordStateDir } from './state_dir.ts';
import { TaskAgent, taskName } from './tasks.ts';
import { tasksIn } from './transcript/subagents.ts';
import {
  type ListedTeam,
  ranNote,
  stoppedLine,
  type TeamListing,
  teamRefusal,
  type TeamRun,
  type TeamWords,
} from './team_command.ts';
import {
  confirmSelectionRole,
  recordedSelection,
  freezeSelection,
  type FrozenSelection,
  type SelectionCapabilities,
  selectionReceipt,
  validateSelectedRole,
  type SelectionReceipt,
  withSelectionCleanupWarning,
} from './team_selection.ts';
import type {
  ChordCall,
  MessageFrom,
  TeamPart,
  TeamShown,
  Transcript,
} from './transcript/types.ts';
import type { KeptPlace } from './usage.ts';
import {
  monitorsIn,
  startMonitorIn,
  stopMonitorIn,
} from './window_monitors.ts';
import {
  agentOf,
  type Child,
  childEnded,
  childName,
  type ChildInfo,
  isLead,
  MAX_CHILDREN,
  membersOf,
  messageRecipients,
  ownChildren,
  ownedBy,
  runName,
  shownKey,
  type StartedAgents,
} from './window_agents.ts';

export interface AgentsHostOptions {
  /** The host's own place: where every agent's session works. */
  readonly place: Place;
  /** Every runtime chord can start, which `list_agents` names. */
  readonly runtimes: readonly string[];
  readonly home: string | undefined;
  /**
   * The user's config directory, whose `chord/teams/` holds the teams for
   * every project; none reads only the project's.
   */
  readonly configHome: string | undefined;
  /** Where a session's record goes; none is chord's own directory. */
  readonly stateDir: string | undefined;
  readonly open: OpenSession;
  /** chord's own MCP server, which every session is admitted to; none in tests. */
  readonly server: ChordServer | undefined;
  /** The providers' limits, which `get_budgets` reads; none reads none. */
  readonly resources?: ReadLimits | undefined;
  /** The session main opens first resumes this one. */
  readonly resume: Resume | undefined;
  /**
   * Main's servers in place of the place's: a client's go to the session it
   * named, and children take the settings' only.
   */
  readonly mainServers?: readonly McpServer[];
  /** One claim among hosts that ask one person; none is this host's own. */
  readonly settingsBox?: ReturnType<typeof settingsBoxClaim>;
}

/** What the host reads of a session from its driver's fold. */
export interface FoldedSession {
  readonly transcript: Transcript;
  readonly queue: readonly QueuedFrom[];
}

/** What the host tells its driver has happened. */
export type AgentsEvent =
  /** A long-lived agent opens under `key`, ahead of its first event. */
  | { readonly type: 'agent_opened'; readonly key: number }
  /** Session `key` is closing: it is held until `spend_closed`. */
  | {
      readonly type: 'spend_closing';
      readonly key: number;
      readonly place: KeptPlace;
      /** Main's key, when main goes on with another session. */
      readonly from?: number;
    }
  | { readonly type: 'spend_closed'; readonly key: number }
  /** Session `key` closed; none in front only once main has gone. */
  | {
      readonly type: 'session_closed';
      readonly key: number;
      readonly front: number | undefined;
    }
  /** The last child has gone: no list of agents is left to hold the keys. */
  | { readonly type: 'agents_unfocused' }
  /** A `settings` write was saved: what of it the host's driver takes up. */
  | {
      readonly type: 'setting_saved';
      readonly picked: SettingPickedUp | undefined;
    };

/** What a selected run knows of its team, with its receipt so far. */
export interface SelectedRun {
  readonly frozen: FrozenSelection;
  receipt: SelectionReceipt;
  readonly publish: () => void;
}

/** What the host tells its driver and asks of it, synchronously. */
export interface AgentsPort {
  /** Each event an agent reports, and the wait it starts, if any. */
  readonly heard: (
    key: number,
    event: ConversationEvent,
    wait: Wait | undefined,
  ) => void;
  /**
   * Runs session `key`'s replay of its past, whose events `heard` takes in
   * meanwhile, so a driver can fold them as one.
   */
  readonly replayed: (key: number, replay: () => void) => void;
  /** Each event an agent let go still reports as it closes. */
  readonly closingHeard: (key: number, event: ConversationEvent) => void;
  /** What happened that the driver draws, as it happens. */
  readonly told: (event: AgentsEvent) => void;
  /**
   * Session `key` as the driver's own fold has it now; none once it has
   * closed. The window's lags its dispatches until it next draws.
   */
  readonly stateOf: (key: number) => FoldedSession | undefined;
  /** Starts the box afresh; no window, none. */
  readonly redraw?: () => void;
  /**
   * The person's own prompts queued in session `key` back into its box, after
   * `typed`, or else what is typed there; no window, none.
   */
  readonly queueBack?: (key: number, typed: string | undefined) => void;
  /**
   * Each event of a session, `id` naming it apart from main's key, ahead of
   * its being told; no window, none.
   */
  readonly watched?: (
    id: string,
    agent: string,
    event: ConversationEvent,
  ) => void;
  /** Stops the command running in session `key`; no window, none. */
  readonly stopCommand?: (key: number) => void;
}

export interface LaunchGuard {
  readonly signal: AbortSignal;
  readonly valid: () => boolean;
  committed: boolean;
}

/** How a long-lived child opens, besides its runtime, model and prompt. */
interface Opening {
  readonly launch?: LaunchGuard;
  readonly id?: string;
  readonly checkStarted?: (conversation: Conversation) => string | undefined;
  readonly refused?: (reason: string) => void;
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
  /**
   * Opened by the person's `/new`: no first prompt, the person's own in
   * its view being its first (Q187).
   */
  readonly idle?: true;
}

/** A team's open run, as `/team show` reads it, for its driver to fill in. */
export interface TeamRunNow {
  /** Its file, as the host shows paths. */
  readonly file: string;
  readonly lead: Child<Conversation>;
  readonly run: FoundTeam & {
    readonly team: Team;
    readonly job: string;
    readonly selected?: SelectedRun;
  };
  readonly members: readonly Child<Conversation>[];
}

/** `a, b and c`. */
function andList(names: readonly string[]): string {
  return new Intl.ListFormat('en', { type: 'conjunction' }).format(names);
}

export function createAgentsHost(
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
    mainServers,
    settingsBox = settingsBoxClaim(),
  }: AgentsHostOptions,
  port: AgentsPort,
) {
  const { told, stateOf } = port;

  /**
   * The session in front, read when a key or a pick acts rather than when
   * the window was drawn, as the first is opened only after.
   */
  const conversation = () => sessions.front;

  /** The conversation of main or child `key`; none once it has closed. */
  const conversationAt = (key: number) => sessions.conversationOf(key);

  /** The window's agents, as `sessions` has them now, once main has started. */
  const front = (): StartedAgents<Conversation> | undefined =>
    ownedBy(sessions.agents, sessions.agents.main?.key);

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
        child.lead === undefined &&
        child.forkedFrom === undefined &&
        (child.id === to || child.name === to),
    );

  /**
   * The conversation a caller's own work runs in: a long-lived child's, or
   * main's; none once it has closed.
   */
  const callerConversation = (key: number, agent: string | undefined) =>
    agent === undefined
      ? conversationAt(key)
      : childOf(key, agent)?.conversation;

  // What each runtime offers, read in the window's place: its files say how
  // a runtime starts there, or that it does not (CHD-466). Made at the
  // first ask.
  let runtimesMade: Runtimes | undefined;

  const runtimes = (): Runtimes =>
    (runtimesMade ??= new Runtimes({
      probe: sessionProbe(place.cwd, (runtime) => place.startupOf(runtime)),
    }));

  const closeRuntimes = () => runtimesMade?.close();

  /**
   * Stops monitor `id` of main `key`, or of its long-lived child `agent`,
   * as `stop_monitor` would for that session: only its own.
   */
  const stopMonitor = (key: number, agent: string | undefined, id: string) =>
    stopMonitorIn(sessions.agents, { key, agent }, id);

  /** What `runtime` offers, as `list_agents` and a child's start read it. */
  const offer: WindowView['offer'] = (runtime, probe) => {
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
  };

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

  const policyNow = async (): Promise<TeamSelectionPolicy> => {
    try {
      return await (place.selectionPolicy?.() ??
        Promise.resolve({ policy: place.teamSelection ?? {} }));
    } catch {
      return {
        error:
          'Team selection settings could not be validated. Correct the settings before selecting a team.',
      };
    }
  };

  /**
   * Messages for a long-lived child that is still starting, its first
   * prompt first, by its key: they go, in order, once it is up.
   */
  const early = new Map<
    number,
    [MessageFrom, string, (TeamPart | undefined)?][]
  >();

  /** Each team agent's part, by its key, that its first message carries. */
  const parts = new Map<number, TeamPart>();

  /** Each child being cleared, by its key: told once its fresh session is up or failed. */
  const clearing = new Map<
    number,
    (failed?: string, dropped?: readonly MessageFrom[]) => void
  >();

  /**
   * Each open run's team, by its lead's id: the file as it was read when the
   * run started, so a file changed since does not change a running team,
   * and the job it was handed.
   */
  const runs = new Map<
    string,
    FoundTeam & {
      readonly team: Team;
      readonly job: string;
      readonly selected?: SelectedRun;
    }
  >();

  /**
   * The conversation a child answers to: its lead's for a member, main's
   * session's for any other.
   */
  const parentOf = (child: Child<Conversation>): Conversation | undefined => {
    const agents = front();

    // A fork is no one's child: no one is told of it (CHD-101).
    if (child.forkedFrom !== undefined) {
      return undefined;
    }

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
   * Holds session `key` as it closes, or is cleared, for the window's total
   * (the owner's Q59: closed agents count): its last events still count,
   * a cancelled turn's end among them, until `settled` is called with its
   * close, or at once with none (CHD-373).
   */
  const keepSpend = (key: number, place: KeptPlace, from?: number) => {
    told({
      type: 'spend_closing',
      key,
      place,
      ...(from === undefined ? {} : { from }),
    });

    return (closed?: Promise<unknown>) => {
      const kept = () => told({ type: 'spend_closed', key });

      if (closed === undefined) {
        kept();
      } else {
        void closed.then(kept, kept);
      }
    };
  };

  // Keys of the sessions main let go, held as they close, apart from every
  // session's own, which count up from one.
  let retiredKeys = 0;

  const retiredKey = () => --retiredKeys;

  /**
   * Holds what a child spent, by its team, as it closes, or as a clear lets
   * its session go, under a key of its own (CHD-476).
   */
  const keepChild = (
    child: ChildInfo & { readonly key: number },
    retiring = false,
  ) =>
    keepSpend(
      retiring ? retiredKey() : child.key,
      {
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
      },
      retiring ? child.key : undefined,
    );

  /**
   * Takes child `key` out of the window and closes its agent, its turn
   * cancelled first so the agent ends it as it would any cancel; a lead's
   * members go first, as a parent's children close with it.
   */
  const dropChild = (key: number) => {
    const found = agentOf(sessions.agents, key);
    const child = found?.child;

    if (found === undefined || child === undefined) {
      return;
    }

    for (const member of membersOf(sessions.agents, child.id)) {
      dropChild(member.key);
    }

    const selected = runs.get(child.lead ?? child.id)?.selected;

    runs.delete(child.id);

    // Closed while it restarts: the clear settles, what waited for the
    // fresh session counted as not delivered (CHD-476).
    const clearingIt = clearing.get(key);

    clearing.delete(key);
    clearingIt?.(
      'it was closed',
      (early.get(key) ?? []).map(([from]) => from),
    );
    early.delete(key);

    if (stateOf(key) && busyOf(stateOf(key)!) !== undefined) {
      child.conversation.interrupt();
    }

    port.stopCommand?.(key);

    const kept = keepChild(child);
    const closed = sessions.closeChild(key);

    kept(closed);
    void closed.catch(() => {
      if (selected !== undefined) {
        selected.receipt = withSelectionCleanupWarning(selected.receipt);

        selected.publish();
      }
    });

    told({
      type: 'session_closed',
      key,
      front: shownKey(sessions.agents),
    });

    // The list goes with the last child, and the keys go back to the box.
    if (
      agentOf(sessions.agents, key) === undefined &&
      front()?.children.length === 0
    ) {
      told({ type: 'agents_unfocused' });
    }
  };

  /**
   * An event of child `key` while it is being cleared, which is no first
   * start: its fresh session up, failed or closing settles the clear, and
   * what waited for it goes then. Whether it was being cleared (CHD-476).
   */
  const clearedHeard = (key: number, event: ConversationEvent): boolean => {
    const cleared = clearing.get(key);

    if (cleared === undefined) {
      return false;
    }

    if (
      event.type === 'connected' ||
      event.type === 'connect_failed' ||
      event.type === 'closing'
    ) {
      const waited = early.get(key) ?? [];

      early.delete(key);
      clearing.delete(key);

      // After the event is drawn, as a first start's messages go.
      if (event.type === 'connected') {
        queueMicrotask(() => {
          const child = agentOf(sessions.agents, key)?.child;

          for (const [from, text] of waited) {
            if (child !== undefined) {
              deliverTo(child, from, text);
            }
          }
        });
      }

      // Up, they go; failed or closed, they are dropped, and said so.
      cleared(
        event.type === 'connected'
          ? undefined
          : event.type === 'closing'
            ? 'it was closed'
            : event.message,
        event.type === 'connected' ? [] : waited.map(([from]) => from),
      );
    }

    return true;
  };

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
  ): 'sent' | 'queued' | undefined => {
    const held = early.get(child.key);

    if (held !== undefined) {
      held.push([from, text]);

      return 'queued';
    }

    return child.conversation.tell(from, text, queued);
  };

  /** `deliverTo`'s answer to the sender: a refusal when nothing went. */
  const sentTo = (
    child: Child<Conversation>,
    from: MessageFrom,
    text: string,
    queued?: () => void,
  ): MessageAnswer => {
    const delivered = deliverTo(child, from, text, queued);

    return delivered === undefined
      ? { error: `${child.name} is closing; nothing reaches it` }
      : { delivered, to: child.name };
  };

  /** How the parent's messages read to a child: from `main`. */
  const MAIN: MessageFrom = { name: 'main', reachable: true };

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

    const agents = ownedBy(sessions.agents, caller.key);
    const target =
      agents &&
      messageRecipients(agents, caller.key).find(
        (each) => each.id === to || each.name === to,
      );
    const child =
      target && agents?.children.find((each) => each.key === target.key);

    if (child === undefined) {
      return { error: noChild(caller.key, to) };
    }

    return sentTo(child, MAIN, text, queued);
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

    const targets = messageRecipients(agents, self.key);
    const target = targets.find((each) => each.id === to || each.name === to);

    if (target?.key === agents.main.key) {
      const delivered = conversationAt(agents.main.key)?.tell(
        from,
        text,
        queued,
      );

      return delivered === undefined
        ? { error: 'main has closed' }
        : { delivered, to: 'main' };
    }

    const member =
      target &&
      agents.children.find(
        (each) => each.key === target.key && each.lead === lead.id,
      );

    if (member !== undefined) {
      return sentTo(
        member,
        self === lead ? { name: lead.name, reachable: true } : from,
        text,
        queued,
      );
    }

    const other =
      target && agents.children.find((each) => each.key === target.key);

    if (other !== undefined) {
      return sentTo(other, from, text, queued);
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
      error: `No agent ${to} is open for you; you reach ${andList(targets.map((each) => each.name))}`,
    };
  };

  /**
   * The tasks session `key` started that `to` names, by id or name: those
   * running, and those ended, of which only their blocks are left.
   */
  const tasksNamed = (key: number, to: string) => {
    const running =
      conversationAt(key)?.tasks.filter(
        (task) => task.id === to || task.start.name === to,
      ) ?? [];
    // Those of this conversation it keeps; those before a resume, only
    // their blocks in the transcript.
    const kept = conversationAt(key)?.endedTasks ?? new Map<string, string>();
    const drawn = tasksIn(stateOf(key)?.transcript.entries ?? []).flatMap(
      ({ id, state, task }) =>
        task !== undefined && state !== 'running' && !kept.has(id)
          ? [{ id, name: task.name }]
          : [],
    );
    const ended = [
      ...[...kept].map(([id, name]) => ({ id, name })),
      ...drawn,
    ].filter(
      ({ id, name }) =>
        !running.some((each) => each.id === id) && (id === to || name === to),
    );

    return { running, ended };
  };

  /**
   * `close_agent` on a task the caller started with `spawn_task`, by its id
   * or a name only one of its tasks has: a running one stopped as the
   * person's `x` stops it, its end naming the caller; one ended said to
   * have. None when `to` names no task of the caller's.
   */
  const closeTask = (caller: Caller, to: string): CloseAnswer | undefined => {
    const child =
      caller.agent === undefined
        ? undefined
        : childOf(caller.key, caller.agent);

    if (caller.agent !== undefined && child === undefined) {
      return undefined;
    }

    const { running, ended } = tasksNamed(child?.key ?? caller.key, to);
    const found = [
      ...running.map((task) => task.id),
      ...ended.map((task) => task.id),
    ];

    if (found.length > 1) {
      return {
        error: `${found.length} of your tasks are named ${to}; close_agent one by its id: ${andList(found)}`,
      };
    }

    const [task] = running;

    if (task !== undefined) {
      task.cancel({ agent: child?.name ?? MAIN.name });
      port.redraw?.();

      return { closed: task.start.name };
    }

    const name = ended[0]?.name;

    return name === undefined ? undefined : { ended: name };
  };

  /**
   * `close_agent`: a task the caller started, stopped; else the parent
   * closes its child `to`, a lead's with its members, and is told nothing;
   * a lead closes one of its members. A long-lived child or a member closes
   * only its tasks.
   */
  const closeAgent = (caller: Caller, to: string): CloseAnswer => {
    const task = closeTask(caller, to);

    if (task !== undefined) {
      return task;
    }

    if (!closesAgents(caller)) {
      return {
        error: `No task ${to} of yours; spawn_task's answer names them`,
      };
    }

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
    port.redraw?.();

    return { closed: child.name };
  };

  /**
   * Clears `child`'s context (CHD-476): its session let go as main's /clear
   * lets main's, a fresh one in its place under the same id and name, which
   * runs nothing until its next message, its first again. Settles once that
   * session is up, with why not if it is not, and the messages queued to it
   * from others that were dropped, said so.
   */
  const clearChild = async (
    child: Child<Conversation>,
    typed?: string,
  ): Promise<{ readonly failed?: string; readonly dropped?: string }> => {
    // Queued in its session, or held while it still starts.
    if (clearing.has(child.key)) {
      return { failed: 'it is being cleared already' };
    }

    // Queued or held in its session, or held while it still starts.
    const before = [
      ...(early.get(child.key) ?? []).map(([from]) => from),
      ...child.conversation.queuedFrom,
    ];
    const up = Promise.withResolvers<{
      readonly failed?: string;
      readonly later: readonly MessageFrom[];
    }>();

    // The person's own prompts queued for it come back into its box, their
    // images and held output with them, whoever clears it.
    port.queueBack?.(child.key, typed);

    clearing.set(child.key, (failed, later = []) =>
      up.resolve({ ...(failed === undefined ? {} : { failed }), later }),
    );
    // What comes while it restarts waits for the fresh session.
    early.set(child.key, []);
    port.stopCommand?.(child.key);
    keepChild(child, true)(child.conversation.clear(parts.get(child.key)));

    const { failed, later } = await up.promise;
    // Those sent while it restarted count too when it did not come up.
    const others = [...before, ...later].map((from) => from.name);
    const dropped =
      others.length === 0
        ? undefined
        : `${others.length} queued message${others.length === 1 ? '' : 's'} ` +
          `from ${andList([...new Set(others)])} ` +
          `${others.length === 1 ? 'was' : 'were'} not delivered.`;

    return {
      ...(failed === undefined ? {} : { failed }),
      ...(dropped === undefined ? {} : { dropped }),
    };
  };

  /** Why `name` was not cleared, and the messages to it that went nowhere. */
  const notCleared = (
    name: string,
    failed: string,
    dropped: string | undefined,
  ) =>
    `Could not clear ${name}: ${failed}${dropped === undefined ? '' : `. ${dropped}`}`;

  /**
   * The person's clear of `child`: as `clearChild`, and its parent told
   * once it is up, as it did not ask; a fork has none. Why not, if not.
   */
  const clearByPerson = async (
    child: Child<Conversation>,
  ): Promise<string | undefined> => {
    const { failed, dropped } = await clearChild(child, '');

    if (failed !== undefined) {
      return notCleared(child.name, failed, dropped);
    }

    const model =
      conversationAt(child.key)?.session?.models()?.current ?? child.model;
    const described = `${[child.runtime, model]
      .filter((part) => part !== undefined)
      .join(' · ')}, id ${child.id}`;

    parentOf(child)?.deliver(
      { name: 'chord' },
      `The person cleared ${child.name}'s context (${described}). It is ` +
        'open with a fresh session and knows nothing of earlier turns; ' +
        `your next message is its first.${dropped === undefined ? '' : ` ${dropped}`}`,
    );

    return undefined;
  };

  /**
   * `clear_agent`: the caller clears a child of its own, found as
   * `close_agent` finds it, and hears once its fresh session is up.
   */
  const clearAgent = async (
    caller: Caller,
    to: string,
  ): Promise<ClearAnswer> => {
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

    const { failed, dropped } = await clearChild(child);

    return failed === undefined
      ? {
          cleared: child.name,
          id: child.id,
          ...(dropped === undefined ? {} : { dropped }),
        }
      : { error: notCleared(child.name, failed, dropped) };
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
    if (caller.agent !== undefined) {
      const child = childOf(caller.key, caller.agent);
      const agents = ownedBy(sessions.agents, caller.key);
      const target =
        agents &&
        child &&
        messageRecipients(agents, child.key).find(
          (each) => each.key === agents.main.key,
        );
      const parent = target && conversationAt(target.key);

      if (conversationAt(caller.key) === undefined) {
        return { error: 'The session that opened you has closed' };
      }

      if (child === undefined) {
        return { error: 'You are closed; nothing more reaches your parent' };
      }

      const delivered = parent?.tell(
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

  /** Each task agent's own conversation, by its id, while it runs. */
  const children = new Map<string, Conversation>();

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
    name = args.name?.trim() || args.agent,
  ): Promise<string | undefined> => {
    const named = kind === 'agent' ? agentNameProblem(name) : undefined;

    if (named !== undefined) {
      return `An agent name ${named}`;
    }

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
    fork?: string,
  ) => {
    const { cwd, mcpServers, startupOf } = place;
    const startup = startupOf(args.agent) ?? {};
    let releaseCurrentCaller = () => {};

    // A fork forks once; a clear opens it afresh, from nothing (CHD-476).
    let forking = fork;

    const conversation = new Conversation(
      (signal) => {
        if (startup.refused !== undefined) {
          throw new Error(startup.refused);
        }

        let live = true;
        const launch = {
          valid: () => live,
          signal: () => conversation.launchSignal,
        };
        const admitted = server?.admit({ ...caller, launch });

        releaseCurrentCaller();

        // A cleared or closing session's calls stop now, not once its
        // process has gone (CHD-476).
        releaseCurrentCaller = () => {
          live = false;

          if (admitted !== undefined) {
            server?.revoke(admitted.token);
          }
        };

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
          ...(startup.mcpServers === false
            ? {
                noMcpServers: true,
                ...(startup.mcpServersFrom === undefined
                  ? {}
                  : { noMcpServersFrom: startup.mcpServersFrom }),
              }
            : {}),
          ...(forking === undefined ? {} : { fork: forking }),
        };

        forking = undefined;

        const revoke = () => {
          live = false;

          if (admitted !== undefined) {
            server?.revoke(admitted.token);
          }
        };

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
        if (event.type === 'cleared' || event.type === 'closing') {
          releaseCurrentCaller();
        }

        port.watched?.(
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

    return conversation;
  };

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
   * Whether `caller` speaks for a session already let go, cleared or
   * closing: what it asks reaches no one (CHD-476).
   */
  const stale = (caller: Caller) => caller.launch?.valid() === false;

  const STALE = {
    error: 'Your session was cleared or closed; nothing more goes from it',
  } as const;

  /**
   * Starts a task agent for the caller, main or a long-lived child of it: a
   * session of `agent` where main works, with no row of
   * its own, drawn in the caller's turn and closed with it. Refused as
   * `startRefusal` says.
   */
  const spawn = async (from: Caller, args: SpawnArgs): Promise<SpawnAnswer> => {
    const { key } = from;
    const parent = callerConversation(key, from.agent);
    const session = parent?.session;
    const refused = await startRefusal(key, parent, args, 'task');

    // Its session let go while it waited: no task starts in the next one.
    if (stale(from) || parent?.session !== session) {
      return STALE;
    }

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
          children.delete(id);
        }
      },
    );

    children.set(id, child);

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

  const captureLaunch = (key: number, caller?: Caller): LaunchGuard => {
    const parent = conversationAt(key);
    const session = parent?.session;
    const signal = AbortSignal.any([
      ...(parent === undefined ? [] : [parent.launchSignal]),
      ...(caller?.signal === undefined ? [] : [caller.signal]),
      ...(caller?.launch === undefined ? [] : [caller.launch.signal()]),
    ]);

    return {
      signal,
      committed: false,
      valid: () =>
        !signal.aborted &&
        session !== undefined &&
        conversationAt(key) === parent &&
        parent?.session === session &&
        caller?.launch?.valid() !== false,
    };
  };

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
    validated: Promise<string | undefined>;
  } => {
    // Eight hex digits: the parent quotes it, and so does the person's close.
    const id = opening.id ?? crypto.randomUUID().slice(0, 8);
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

    early.set(
      childKey,
      opening.idle ? [] : [[opening.from, args.prompt, opening.part]],
    );
    // Its state is there before its first event, which may come at once.
    told({ type: 'agent_opened', key: childKey });

    if (opening.part !== undefined) {
      parts.set(childKey, opening.part);
    }

    const effort = effortStart(args, () => conversationAt(childKey));
    const validation = Promise.withResolvers<string | undefined>();
    let primaryRefusal: string | undefined;
    const refuse = (reason: string) => {
      // Closing is a consequence, not a replacement for the actionable cause.
      if (primaryRefusal !== undefined) {
        return;
      }

      primaryRefusal = reason;

      opening.refused?.(reason);
      validation.resolve(reason);
    };

    const cancelLaunch = () => {
      if (opening.launch?.valid() === false) {
        refuse(
          'Cancelled before its first job; the attempted agent is closing.',
        );
        dropChild(childKey);
      }
    };

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

            if (event.type === 'closing' || event.type === 'disconnected') {
              if (!opening.launch?.committed) {
                refuse(
                  event.type === 'closing' || opening.launch?.valid() === false
                    ? 'Cancelled before its first job; the attempted agent is closing.'
                    : 'Startup ended before the first job; the attempted agent is closing.',
                );
              }

              opening.launch?.signal.removeEventListener('abort', cancelLaunch);
            }

            if (clearedHeard(own, event)) {
              return;
            }

            if (event.type === 'connected' || event.type === 'connect_failed') {
              const held = early.get(own) ?? [];

              early.delete(own);

              // After the event is drawn, so the first turn comes after it.
              queueMicrotask(() => {
                opening.launch?.signal.removeEventListener(
                  'abort',
                  cancelLaunch,
                );

                const child = agentOf(sessions.agents, own)?.child;

                if (opening.launch?.valid() === false) {
                  refuse(
                    'Cancelled before its first job; the attempted agent is closing.',
                  );
                  dropChild(own);

                  return;
                }

                if (event.type === 'connected') {
                  const invalid =
                    child === undefined
                      ? 'The attempted agent closed before its first job.'
                      : opening.checkStarted?.(child.conversation);

                  if (invalid !== undefined) {
                    refuse(invalid);
                    dropChild(own);

                    return;
                  }

                  if (opening.launch?.valid() === false) {
                    refuse(
                      'Cancelled before its first job; the attempted agent is closing.',
                    );
                    dropChild(own);

                    return;
                  }

                  // The first prompt starts its first turn; the messages
                  // sent while it started go into that turn.
                  for (const [index, [from, text, part]] of held.entries()) {
                    if (index === 0) {
                      if (child !== undefined && opening.launch !== undefined) {
                        opening.launch.committed = true;
                      }

                      child?.conversation.deliver(from, text, part);
                    } else {
                      child?.conversation.tell(from, text);
                    }
                  }

                  validation.resolve(undefined);
                } else if (child !== undefined) {
                  refuse(
                    'Initialization failed before the first job; the attempted agent is closing.',
                  );

                  if (opening.checkStarted !== undefined) {
                    dropChild(own);

                    return;
                  }

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
      refuse(
        'The attempted agent could not be opened; no first job was delivered.',
      );
    } else {
      opening.launch?.signal.addEventListener('abort', cancelLaunch, {
        once: true,
      });
      cancelLaunch();
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
      validated: validation.promise,
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
    caller?: Caller,
  ): Promise<OpenAnswer> => {
    const session = conversationAt(key)?.session;
    const refused =
      (await startRefusal(key, conversationAt(key), args, 'agent')) ??
      fullRefusal(key);

    // Its session let go while it waited: what it asked goes nowhere.
    if (
      (caller !== undefined && stale(caller)) ||
      conversationAt(key)?.session !== session
    ) {
      return STALE;
    }

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

  const selectedCapabilities = async (
    agent: string,
    key: number,
  ): Promise<
    SelectionCapabilities | { readonly error: string } | undefined
  > => {
    // A configured refusal is known before probing; missing capability evidence is different.
    if (place.startupOf(agent)?.refused !== undefined) {
      return { error: 'The selected runtime configuration is unavailable.' };
    }

    const offer = await view.offer(agent, false, key);

    if (offer === undefined || 'error' in offer) {
      return undefined;
    }

    return {
      ...(offer.models.length === 0 ? {} : { models: offer.models }),
      ...(offer.modes === undefined ? {} : { modes: offer.modes }),
      ...(offer.efforts === undefined ? {} : { efforts: offer.efforts }),
    };
  };

  const refuseSelected = (
    run: SelectedRun,
    kind: 'lead' | 'member',
    name: string,
    reason: string,
  ) => {
    run.receipt = {
      ...run.receipt,
      roles: run.receipt.roles.map((role) =>
        role.role === kind && role.name === name
          ? { ...role, state: 'refused', note: reason }
          : role,
      ),
    };

    run.publish();
  };

  const confirmSelected = (
    run: SelectedRun,
    kind: 'lead' | 'member',
    name: string,
    conversation: Conversation,
  ): string | undefined => {
    const role = run.receipt.roles.find(
      (role) => role.role === kind && role.name === name,
    )!;
    const bounded = (value: string | undefined) =>
      value !== undefined && value.length > 0 && value.length <= 128
        ? value
        : null;
    const actual = {
      agent: bounded(conversation.session?.agent),
      model: bounded(conversation.session?.models()?.current),
      mode: bounded(conversation.session?.modes()?.current),
      effort: bounded(conversation.session?.efforts()?.current),
    };
    const soft =
      role.planned.effort !== undefined &&
      (conversation.effortRefused !== undefined ||
        role.planned.effort !== actual.effort);
    const confirmed = confirmSelectionRole(
      role,
      actual,
      soft
        ? 'The requested effort was not confirmed; the runtime effort remains advisory.'
        : null,
    );

    run.receipt = {
      ...run.receipt,
      roles: run.receipt.roles.map((one) => (one === role ? confirmed : one)),
    };

    run.publish();

    return confirmed.state === 'refused'
      ? (confirmed.note ?? 'The selected configuration was not confirmed.')
      : undefined;
  };

  const runSelectedTeamAt = async (
    key: number,
    args: RunTeamArgs,
    lists: string,
    launch: LaunchGuard,
  ): Promise<RunTeamAnswer> => {
    const found = (await teamsAt(key)).find((each) => each.name === args.team);

    if (!launch.valid()) {
      return { error: 'This launch was cancelled; no run started.' };
    }

    if (found === undefined) {
      return { error: `No team named ${args.team} · ${lists}` };
    }

    if ('problem' in found) {
      return { error: 'The saved team is invalid. No run started.' };
    }

    const policy = await policyNow();

    if ('error' in policy) {
      return policy;
    }

    const preliminary = freezeSelection(
      found.team,
      args.selection!,
      policy.policy,
      runtimeNames,
    );

    if ('error' in preliminary) {
      return preliminary;
    }

    const capabilities = new Map<string, SelectionCapabilities>();

    for (const agent of new Set([
      preliminary.frozen.team.lead.agent,
      ...preliminary.frozen.team.members.map((member) => member.agent),
    ])) {
      const known = await selectedCapabilities(agent, key);

      if (known !== undefined && 'error' in known) {
        const roles = [
          ...(preliminary.frozen.team.lead.agent === agent ? ['lead'] : []),
          ...preliminary.frozen.team.members
            .filter((member) => member.agent === agent)
            .map((member) => member.name),
        ];

        return {
          error: `${roles.join(', ')}.agent: ${known.error} No run started.`,
        };
      }

      if (known !== undefined) {
        capabilities.set(agent, known);
      }

      if (!launch.valid()) {
        return { error: 'This launch was cancelled; no run started.' };
      }
    }

    const chosen = freezeSelection(
      found.team,
      args.selection!,
      policy.policy,
      runtimeNames,
      capabilities,
    );

    if ('error' in chosen) {
      return chosen;
    }

    const frozen = chosen.frozen;
    const lead = frozen.team.lead;
    const opening: OpenArgs = { ...lead, prompt: args.job };
    const refused =
      (await startRefusal(
        key,
        conversationAt(key),
        opening,
        'agent',
        args.team,
      )) ?? fullRefusal(key);
    const agents = ownedBy(sessions.agents, key);

    if (!launch.valid()) {
      return { error: 'This launch was cancelled; no run started.' };
    }

    if (refused !== undefined || agents === undefined) {
      return { error: 'The selected lead cannot be admitted. No run started.' };
    }

    const id = crypto.randomUUID().slice(0, 8);
    const name = runName(agents, args.team);
    const write = conversationAt(key)?.captureServed();
    let leadWrite: ((call: ChordCall) => void) | undefined;
    const selected: SelectedRun = {
      frozen,
      receipt: selectionReceipt(
        id,
        { name: found.name, place: found.place },
        frozen,
      ),
      publish: () => {
        const failed = selected.receipt.roles.find(
          (role) => role.role === 'lead' && role.state === 'refused',
        );
        const call: ChordCall = {
          tool: 'run_team',
          input: args,
          asked: id,
          answer: {
            id,
            name,
            team: args.team,
            agent: lead.agent,
            receipt: selected.receipt,
          },
          ...(failed === undefined
            ? {}
            : {
                error: `Team launch ${id}: ${failed.note ?? 'The lead was refused before its first job.'}`,
              }),
        };

        write?.(call);
        leadWrite?.(call);
        port.redraw?.();
      },
    };

    runs.set(id, {
      ...found,
      team: frozen.team,
      job: args.job,
      selected,
    });

    const started = startChild(key, opening, {
      id,
      name,
      parent: () => conversationAt(key),
      from: MAIN,
      team: { name: args.team },
      part: teamPart(
        args.team,
        frozen.team,
        {
          lead: name,
          others: ownChildren(agents)
            .filter(isLead)
            .map((each) => each.name),
        },
        place.cwd,
      ),
      asked: `selected for team ${args.team}`,
      launch,
      checkStarted: (conversation) => {
        leadWrite = conversation.captureServed();

        return confirmSelected(selected, 'lead', 'lead', conversation);
      },
      refused: (reason) => refuseSelected(selected, 'lead', 'lead', reason),
    });

    selected.publish();

    const invalid = await started.validated;

    if (invalid !== undefined || !launch.committed) {
      return {
        error: `Team launch ${id} was refused before its first job; the attempted lead is closing.`,
        id,
        receipt: selected.receipt,
      };
    }

    const observed = selected.receipt.roles.find(
      (role) => role.role === 'lead',
    );

    return {
      ...started.opened,
      team: args.team,
      ...(typeof observed?.actual?.effort === 'string'
        ? { effort: observed.actual.effort }
        : {}),
      ...(typeof observed?.note === 'string' ? { note: observed.note } : {}),
      receipt: selected.receipt,
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
    { team, job, selection }: RunTeamArgs,
    lists: string,
    launch = captureLaunch(key),
  ): Promise<
    | Extract<RunTeamAnswer, { readonly error: string }>
    | {
        readonly ran: Exclude<RunTeamAnswer, { readonly error: string }>;
        readonly started: Promise<EffortStarted>;
      }
  > => {
    if (!launch.valid()) {
      return { error: 'This launch was cancelled; no run started.' };
    }

    if (selection !== undefined) {
      const selected = await runSelectedTeamAt(
        key,
        { team, job, selection },
        lists,
        launch,
      );

      return 'error' in selected
        ? selected
        : { ran: selected, started: Promise.resolve({}) };
    }

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
      (await startRefusal(key, conversationAt(key), args, 'agent', team)) ??
      fullRefusal(key);
    const agents = ownedBy(sessions.agents, key);

    if (!launch.valid()) {
      return { error: 'This launch was cancelled; no run started.' };
    }

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
      launch,
    });

    if (!launch.valid()) {
      return {
        error: `Team launch ${opened.id} was cancelled before its first job; the attempted lead is closing.`,
      };
    }

    runs.set(opened.id, { ...found, job });

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
    const launch = captureLaunch(key, caller);
    const lead =
      caller.agent === undefined ? undefined : childOf(key, caller.agent);
    const run = lead === undefined ? undefined : runs.get(lead.id);

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
    const refused = await startRefusal(
      key,
      lead.conversation,
      args,
      'agent',
      member,
    );
    const raced = occupied();

    if (raced !== undefined) {
      return { error: raced };
    }

    if (refused !== undefined) {
      if (run.selected !== undefined) {
        const safe = `${member} cannot be admitted on the selected configuration; no first job was delivered.`;

        refuseSelected(run.selected, 'member', member, safe);

        return { error: safe };
      }

      return { error: refused };
    }

    if (run.selected !== undefined) {
      const selected = run.selected;
      const policy = await policyNow();
      const capabilities = await selectedCapabilities(defined.agent, key);
      const invalid =
        'error' in policy
          ? policy.error
          : capabilities !== undefined && 'error' in capabilities
            ? `${member}.agent: ${capabilities.error}`
            : validateSelectedRole(
                member,
                defined,
                policy.policy,
                runtimeNames,
                capabilities,
                selected.frozen.selection.members?.[member],
                'member',
              );
      // A competing request's admission is not this role's startup failure.
      const raced = occupied();

      if (raced !== undefined) {
        return { error: raced };
      }

      const unavailable =
        invalid ??
        (!launch.valid()
          ? 'The member request was cancelled before admission.'
          : undefined);

      if (unavailable !== undefined) {
        refuseSelected(selected, 'member', member, unavailable);

        return { error: unavailable };
      }

      const attempt = startChild(key, args, {
        name: member,
        parent: () => lead.conversation,
        from: { name: lead.name, reachable: true },
        team: { name: run.name, lead: lead.id },
        part: teamPart(
          run.name,
          run.team,
          { member: defined, lead: lead.name },
          place.cwd,
        ),
        asked: `selected for team ${run.name}`,
        launch,
        checkStarted: (conversation) =>
          confirmSelected(selected, 'member', member, conversation),
        refused: (reason) => refuseSelected(selected, 'member', member, reason),
      });
      const failed = await attempt.validated;

      const observed = selected.receipt.roles.find(
        (role) => role.role === 'member' && role.name === member,
      );

      return failed === undefined && launch.committed
        ? {
            ...attempt.opened,
            ...(typeof observed?.actual?.effort === 'string'
              ? { effort: observed.actual.effort }
              : {}),
            ...(typeof observed?.note === 'string'
              ? { note: observed.note }
              : {}),
          }
        : {
            error: `${member} was refused before its first job; the attempted member is closing.`,
          };
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

  // The session main opens next resumes: the one `--resume` asks for, and
  // each `/resume` picks; the one `/clear` opens is new.
  let resuming = resume;

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
      mcpServersFrom,
    } = startupOf(agent) ?? {};
    const servers = mainServers ?? mcpServers.map(({ server }) => server);
    let releaseCurrentCaller = () => {};

    const conversation = new Conversation(
      (signal) => {
        if (refused !== undefined) {
          throw new Error(refused);
        }

        const next = resuming;
        // A token for each session main opens, `/clear`'s included, good
        // until that session's agent has gone.
        let live = true;
        const launch = {
          valid: () => live,
          signal: () => conversation.launchSignal,
        };
        const admitted = server?.admit({
          role: 'person',
          key,
          window: view,
          launch,
        });

        releaseCurrentCaller();

        // A cleared or closing session's calls stop now, not once its
        // process has gone (CHD-476).
        releaseCurrentCaller = () => {
          live = false;

          if (admitted !== undefined) {
            server?.revoke(admitted.token);
          }
        };

        const options = {
          agent,
          cwd,
          signal,
          ...(agentCommand === undefined ? {} : { agentCommand }),
          ...(next === undefined ? {} : { resume: next }),
          ...(servers.length === 0 ? {} : { mcpServers: servers }),
          ...(admitted === undefined ? {} : { chordServer: admitted.server }),
          ...(takes === false
            ? {
                noMcpServers: true,
                ...(mcpServersFrom === undefined
                  ? {}
                  : { noMcpServersFrom: mcpServersFrom }),
              }
            : {}),
        };

        resuming = undefined;

        const revoke = () => {
          live = false;

          if (admitted !== undefined) {
            server?.revoke(admitted.token);
          }
        };

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
        if (event.type === 'cleared' || event.type === 'closing') {
          releaseCurrentCaller();
        }

        port.watched?.(`main:${key}`, agent, event);
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
      (replay) => port.replayed(key, replay),
    );

    return conversation;
  };

  /** What chord's MCP server reads of the host, when a session calls. */
  const view: WindowView = {
    ...(resources === undefined
      ? {}
      : {
          budgets: (caller: Caller, agents?: readonly string[]) =>
            resources(
              agents,
              {
                cwd: place.cwd,
                commandOf: (runtime) => place.startupOf(runtime)?.agentCommand,
              },
              caller.signal ?? new AbortController().signal,
            ),
        }),
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
              children: agents.children
                .filter((child) => child.forkedFrom === undefined)
                .map((child) => ({
                  id: child.id,
                  name: child.name,
                  runtime: child.runtime,
                  model:
                    child.conversation.session?.models()?.current ??
                    child.model,
                })),
            },
            // A fork is a session of its own, beside main's (CHD-101).
            ...agents.children
              .filter((child) => child.forkedFrom !== undefined)
              .map((fork) => ({
                key: fork.key,
                runtime: fork.runtime,
                id: fork.conversation.session?.id,
                model:
                  fork.conversation.session?.models()?.current ?? fork.model,
                children: [],
              })),
          ];
    },
    runtimes: () => runtimeNames,
    offer,
    spawn: (caller, args) =>
      stale(caller) ? Promise.resolve(STALE) : spawn(caller, args),
    open: (key, args, caller) =>
      caller !== undefined && stale(caller)
        ? Promise.resolve(STALE)
        : openAgent(key, args, caller),
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
                    id: child.id,
                  },
                ],
        ),
      };
    },
    // As open_agent's, the answer waits on a lead given an effort.
    runTeam: async (caller, args) => {
      const launch = captureLaunch(caller.key, caller);
      const answer = await runTeamAt(
        caller.key,
        args,
        'list_teams lists them',
        launch,
      );

      if ('error' in answer) {
        return answer;
      }

      const started = await answer.started;

      if (
        !launch.committed &&
        (!launch.valid() || childOf(caller.key, answer.ran.id) === undefined)
      ) {
        return {
          error: `Team launch ${answer.ran.id} was cancelled before its first job; the attempted lead is closing.`,
        };
      }

      return { ...answer.ran, ...started };
    },
    teamPlaces: (caller, name) => teamPlaces(caller.key, name),
    claimSettingsBox: settingsBox,
    settingSaved: (path, change) => {
      told({ type: 'setting_saved', picked: settingPickedUp(path, change) });
    },
    settingsWhere: (caller) => ({
      agent: ownedBy(sessions.agents, caller.key)?.main.agent ?? 'the agent',
      configHome,
      cwd: place.cwd,
      home,
    }),
    askPerson: (caller, wait, signal) =>
      conversationAt(caller.key)?.ask(wait, signal) ??
      Promise.resolve(undefined),
    openMember: (caller, args) =>
      stale(caller) ? Promise.resolve(STALE) : openMember(caller, args),
    message: (caller, text, queued) =>
      stale(caller) ? STALE : message(caller, text, queued),
    tell: (caller, to, text, queued) =>
      stale(caller) ? STALE : tell(caller, to, text, queued),
    close: (caller, to) => (stale(caller) ? STALE : closeAgent(caller, to)),
    clear: (caller, to) =>
      stale(caller) ? Promise.resolve(STALE) : clearAgent(caller, to),
    monitor: (caller, args) =>
      stale(caller)
        ? STALE
        : startMonitorIn(sessions.agents, caller, args, place.cwd),
    stopMonitor: (caller, id) =>
      stale(caller) ? STALE : stopMonitorIn(sessions.agents, caller, id),
    monitors: (caller) => monitorsIn(sessions.agents, caller),
    served: (caller, call) => {
      if (caller.launch?.valid() === false || caller.signal?.aborted) {
        return;
      }

      return caller.task !== undefined
        ? children.get(caller.task)?.served(call)
        : caller.agent !== undefined
          ? childOf(caller.key, caller.agent)?.conversation.served(call)
          : conversationAt(caller.key)?.served(call);
    },
    servedLater: (caller) => {
      const { task } = caller;
      const child = task === undefined ? undefined : children.get(task);
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

  const sessions = new OpenAgents({
    conversation: conversationOf,
    heard: port.heard,
    closingHeard: port.closingHeard,
  });

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
    port.redraw?.();

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
        ? [
            {
              team: child.team,
              name: child.name,
              since: child.openedAt,
              id: child.id,
            },
          ]
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
    const launch = captureLaunch(agents?.main.key ?? -1);
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
      launch,
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
   * `/new`: an agent opened for main as `open_agent` opens one, of `named`
   * or of main's runtime (Q188), on what `open_agent` gives with none named
   * (Q189), and idle until the person's first prompt in its view (Q187). The
   * view goes to it at once; main hears of it ahead of its next prompt, the
   * call drawn as its own; or why not, if it was refused as `open_agent` is.
   */
  const newTyped = async (
    named: string,
    showFront: () => void,
  ): Promise<TeamShown> => {
    const main = sessions.agents.main;
    const said = (text: string): TeamShown => ({
      kind: 'said',
      text,
      failed: true,
    });

    if (main === undefined) {
      return said('This session has closed');
    }

    const args = { agent: named === '' ? main.agent : named, prompt: '' };
    const refused =
      (await startRefusal(main.key, conversationAt(main.key), args, 'agent')) ??
      fullRefusal(main.key);
    const agents = ownedBy(sessions.agents, main.key);

    if (agents === undefined || refused !== undefined) {
      return said(refused ?? 'This session has closed');
    }

    const { opened, started } = startChild(main.key, args, {
      name: childName(agents, undefined, args.agent),
      parent: () => conversationAt(main.key),
      from: MAIN,
      asked: 'asked by /new',
      idle: true,
    });
    const child = sessions.agents.children.find(
      (each) => each.id === opened.id,
    );

    if (child !== undefined) {
      sessions.pick(child.key);
      showFront();
    }

    conversationAt(main.key)?.aside(
      { name: 'chord' },
      `The person opened @${opened.name} (${opened.agent}) with /new; it ` +
        'has no prompt yet. It reports to you, and send_message reaches it.',
    );

    const call: ChordCall = {
      tool: 'open_agent',
      input: { agent: args.agent, typed: '/new' },
      answer: { ...opened, ...(await started) },
    };

    conversationAt(main.key)?.ranTyped(call);

    return { kind: 'ran', call };
  };

  /**
   * `/team stop`: the run `name` closed with its members, at
   * once, as the person typed it on purpose; `show` hears what it did
   * before main is told, as for `x`, so the command's line comes first.
   */
  const stopTyped = (
    name: string,
    show: (shown: TeamShown) => void,
    words: TeamWords,
  ) => {
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
        text: `No run named ${name} is open · ${words.noRun}`,
        failed: true,
      });
    }

    show({
      kind: 'said',
      text: stoppedLine(
        lead.name,
        membersOf(agents, lead.id).map((each) => each.name),
        words,
      ),
      failed: false,
    });
    closeByPerson(lead);
  };

  /**
   * `/team show`: team `name` as its file has it; while it runs in the
   * host, its first run as it stands now, the file as the run read it, which
   * `fill` turns into what is shown, there and then, saying what each of
   * its agents is doing.
   */
  const showTyped = async (
    name: string,
    fill: (now: TeamRunNow) => TeamShown,
  ): Promise<TeamShown> => {
    const agents = front();
    const running =
      agents === undefined
        ? undefined
        : ownChildren(agents).find(
            (child) =>
              isLead(child) && (child.id === name || child.name === name),
          );
    const associated = running === undefined ? undefined : runs.get(running.id);

    if (associated === undefined && agents !== undefined) {
      const transcript = stateOf(agents.main.key)?.transcript;
      const calls = [
        ...(transcript?.served ?? []),
        ...(transcript?.entries.flatMap((entry) =>
          entry.kind === 'tool' && entry.call.chord !== undefined
            ? [entry.call.chord]
            : [],
        ) ?? []),
      ];
      const call = calls.findLast(
        (call) => recordedSelection(call)?.runId === name,
      );

      if (call !== undefined) {
        return { kind: 'receipt', call };
      }
    }

    const found =
      associated === undefined
        ? await teamNamed(name)
        : { ...associated, shown: shownTeamFile(agents!.main.key, associated) };
    const refused = teamRefusal(name, found);

    if (agents === undefined || found === undefined || !('team' in found)) {
      return {
        kind: 'said',
        text: refused ?? 'This session has closed',
        failed: true,
      };
    }

    const lead = ownChildren(agents).find(
      (child) =>
        isLead(child) &&
        (child.team === name || child.id === name || child.name === name),
    );
    const run = lead === undefined ? undefined : runs.get(lead.id);

    if (lead === undefined || run === undefined) {
      return { kind: 'show', name, file: found.shown, team: found.team };
    }

    return fill({
      file: found.shown,
      lead,
      run,
      members: membersOf(agents, lead.id),
    });
  };

  return {
    sessions,
    view,
    resumeNext: (next: Resume) => {
      resuming = next;
    },
    conversation,
    conversationAt,
    front,
    childOf,
    ownChild,
    callerConversation,
    closeRuntimes,
    stopMonitor,
    offer,
    teamsAt,
    shownTeamFile,
    teamPlaces,
    policyNow,
    early,
    parts,
    clearing,
    runs,
    parentOf,
    noChild,
    tellEnded,
    keepSpend,
    retiredKey,
    keepChild,
    dropChild,
    closeByPerson,
    listTeams,
    runTyped,
    newTyped,
    stopTyped,
    showTyped,
    clearedHeard,
    deliverTo,
    MAIN,
    tell,
    closeAgent,
    tasksNamed,
    clearByPerson,
    clearAgent,
    message,
    children,
    startRefusal,
    childConversation,
    stale,
    STALE,
    spawn,
    captureLaunch,
    startChild,
    fullRefusal,
    openAgent,
    runTeamAt,
    openMember,
  };
}
