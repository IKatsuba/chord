/**
 * A host's agents, with no window: main and each child opened with a
 * conversation of its own, the teams they run, and what chord's MCP server
 * asks of them. The driver hears of it through its port, at once and in order:
 * the window turns that into the actions it dispatches, each as it comes.
 */
import { relative } from 'node:path';
import type { Wait } from '../notify.ts';
import { Runtimes, sessionProbe } from '../server/runtimes.ts';
import type { WindowView } from '../server/tools.ts';
import { homePath, type TeamSelectionPolicy } from '../settings.ts';
import {
  findTeams,
  type FoundTeam,
  type Team,
  teamDirs,
  teamFile,
} from '../teams.ts';
import { busyOf, type QueuedFrom } from './busy.ts';
import type { Conversation, ConversationEvent } from './conversation.ts';
import { OpenAgents, type OpenAgentsOptions } from './open_agents.ts';
import type { Place } from './place.ts';
import type { ListedTeam } from './team_command.ts';
import {
  type FrozenSelection,
  type SelectionReceipt,
  withSelectionCleanupWarning,
} from './team_selection.ts';
import type { MessageFrom, TeamPart, Transcript } from './transcript/types.ts';
import type { KeptPlace } from './usage.ts';
import {
  agentOf,
  type Child,
  childEnded,
  type ChildInfo,
  isLead,
  membersOf,
  ownedBy,
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
  /** Main's conversation, until the host makes its own. */
  readonly conversation: OpenAgentsOptions<Conversation>['conversation'];
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
  | { readonly type: 'agents_unfocused' };

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
  /** Stops the command running in session `key`; no window, none. */
  readonly stopCommand?: (key: number) => void;
}

export function createAgentsHost(
  {
    place,
    runtimes: runtimeNames,
    home,
    configHome,
    conversation: conversationOf,
  }: AgentsHostOptions,
  port: AgentsPort,
) {
  const sessions = new OpenAgents({
    conversation: conversationOf,
    heard: port.heard,
    closingHeard: port.closingHeard,
  });
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

  return {
    sessions,
    conversation,
    conversationAt,
    front,
    childOf,
    ownChild,
    callerConversation,
    closeRuntimes,
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
  };
}
