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
import { findTeams, type FoundTeam, teamDirs, teamFile } from '../teams.ts';
import type { Conversation, ConversationEvent } from './conversation.ts';
import { OpenAgents, type OpenAgentsOptions } from './open_agents.ts';
import type { Place } from './place.ts';
import type { ListedTeam } from './team_command.ts';
import { ownedBy, type StartedAgents } from './window_agents.ts';

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
  };
}
