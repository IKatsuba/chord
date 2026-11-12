import { findAgent, takesMcpServers } from '../agents.ts';
import { type DefinedServer, type Ignored, loadMcpServers } from '../mcp.ts';
import {
  type Flags,
  loadSettings,
  readTeamSelection,
  refusalLine,
  resolveStartup,
  resumedStartup,
  setWhere,
  type SettingsProblem,
  shownPath,
  type Sourced,
  type Startup,
  startupOf,
  type TeamSelectionPolicy,
  unseenProblems,
} from '../settings.ts';
import type { TeamSelection } from './budgets.ts';
import type { Starting } from './conversation.ts';

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
  readonly teamSelection?: TeamSelection;
  readonly selectionPolicy?: () => Promise<TeamSelectionPolicy>;
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

/** How chord was started, which every directory it reads is read under. */
export interface PlaceStartup {
  readonly configHome: string | undefined;
  readonly home: string | undefined;
  readonly invokedAs: Startup;
  readonly flags: Flags;
}

/** What `readPlace` reads a directory with. */
export interface PlaceReading extends PlaceStartup {
  /** The directory `loaded` read, which is not read again. */
  readonly loadedAt: string;
  readonly loaded: Awaited<ReturnType<typeof loadSettings>>;
  /** The problems already said; those newly found join them. */
  readonly problems: SettingsProblem[];
  readonly report: (found: SettingsProblem[]) => Promise<void>;
}

/**
 * What a session working in `dir` starts with: a session resumed by id
 * may work elsewhere, and its directory's project file and `.mcp.json`
 * are the ones that speak for it. Each problem is said once, however
 * many directories read the user's file.
 */
export async function readPlace(
  dir: string,
  {
    configHome,
    home,
    invokedAs,
    flags,
    loadedAt,
    loaded,
    problems,
    report,
  }: PlaceReading,
) {
  const there =
    dir === loadedAt
      ? loaded
      : await loadSettings({
          configHome,
          cwd: dir,
          ...(home === undefined ? {} : { home }),
        });
  const mcp = await loadMcpServers({ layers: there.layers, cwd: dir });
  const added = unseenProblems(problems, [...there.problems, ...mcp.problems]);

  await report(added);
  problems.push(...added);

  return {
    cwd: dir,
    layers: there.layers,
    channel: there.settings.preferredNotifChannel,
    teamSelection: there.settings.teamSelection,
    mcp,
    ...resumedStartup(invokedAs, flags, there.layers),
  };
}

/** A directory read, as the window takes it: paths as it shows them. */
export function placeOf(
  {
    cwd,
    layers,
    mcp,
    model,
    effort,
    permissionMode,
    teamSelection,
  }: Awaited<ReturnType<typeof readPlace>>,
  { configHome, home, invokedAs, flags }: PlaceStartup,
): Place {
  const shown = { cwd, home };
  const starting = (value: Sourced | undefined) =>
    value === undefined
      ? undefined
      : { id: value.id, from: setWhere(value.from, shown) };

  return {
    cwd,
    selectionPolicy: () =>
      readTeamSelection({
        configHome,
        cwd,
        ...(home === undefined ? {} : { home }),
      }),
    ...(teamSelection === undefined ? {} : { teamSelection }),
    startupOf: (name) => {
      const found = startupOf(
        name,
        {
          ...invokedAs,
          ...(model === undefined ? {} : { model }),
          ...(effort === undefined ? {} : { effort }),
          ...(permissionMode === undefined ? {} : { permissionMode }),
        },
        layers,
        flags,
      );
      // The window's own agent starts as it was invoked, but this place's
      // files may refuse its command, unless a flag gave it one.
      const refused =
        found.refused ??
        (name === invokedAs.agent && flags.agentCommand === undefined
          ? resolveStartup({ agent: name }, layers, name).refused
          : undefined);

      if (refused !== undefined) {
        return { refused: refusalLine(name, refused, shown) };
      }

      return found.agentCommand === undefined && findAgent(name) === undefined
        ? undefined
        : {
            agentCommand: found.agentCommand,
            ...(takesMcpServers(name, found.mcpServers)
              ? {}
              : { mcpServers: false as const }),
            starting: {
              model: starting(found.model),
              effort: starting(found.effort),
              mode: starting(found.permissionMode),
            },
          };
    },
    mcpServers: mcp.servers.map((defined) => ({
      ...defined,
      from: shownPath(defined.from, shown),
    })),
    mcpIgnored: mcp.ignored.map((lost) => ({
      ...lost,
      from: shownPath(lost.from, shown),
    })),
  };
}
