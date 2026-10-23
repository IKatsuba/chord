import { which } from '@david/which';
import { quote } from 'shell-quote';
import { Table } from '@cliffy/table';
import stringWidth from 'string-width';
import wrapAnsi from 'wrap-ansi';
import { CLI_AGENTS, type CliAgent } from './clis.ts';
import { REGISTRY_AGENTS, type RegistryAgent } from './registry.ts';

/**
 * The registry calls Claude's and Codex's adapters `claude-acp` and
 * `codex-acp`; chord has always started them as `claude` and `codex`, and
 * those names stay, in the registry's place.
 */
const ALIASES: Readonly<Record<string, string>> = {
  claude: 'claude-acp',
  codex: 'codex-acp',
};

/** chord opens on Claude Code, the client it is modelled on. */
export const DEFAULT_AGENT = 'claude';

/** An agent chord can start by name. */
export interface KnownAgent {
  /** What `chord <name>` and the settings files call it. */
  readonly name: string;
  /** What the registry or the agent calls it, for people. */
  readonly title: string;
  readonly start: AgentStart;
  /**
   * What starts it: npx or uvx with the registry's package, or `cli`, a
   * command the person installs themselves.
   */
  readonly runner: 'npx' | 'uvx' | 'cli';
  /** Where the agent says to install it, when it says. */
  readonly install: string | undefined;
  /** `false` where chord's own table gives the agent no MCP servers. */
  readonly mcpServers?: false;
  /** The registry's package and version, `package@version`, that npx or uvx runs. */
  readonly pinned?: string;
}

/** How an agent's process is started. */
export interface AgentStart {
  /**
   * A string is split the way a shell would (`src/acp/process.ts`); an argv
   * is taken whole.
   */
  readonly command: string | readonly string[];
  /** Laid over chord's own environment for the agent alone. */
  readonly env: Readonly<Record<string, string>>;
}

const BY_ID = new Map<string, string>(
  Object.entries(ALIASES).map(([alias, id]) => [id, alias]),
);

function fromRegistry(agent: RegistryAgent): KnownAgent {
  const pinned = `${agent.package}@${agent.version}`;

  return {
    name: BY_ID.get(agent.id) ?? agent.id,
    title: agent.name,
    start: {
      command:
        agent.runner === 'npx'
          ? ['npx', '-y', pinned, ...agent.args]
          : ['uvx', pinned, ...agent.args],
      env: agent.env,
    },
    runner: agent.runner,
    install: agent.website ?? agent.repository,
    pinned,
  };
}

function fromCli(agent: CliAgent): KnownAgent {
  return {
    name: agent.name,
    title: agent.title,
    start: { command: agent.argv, env: {} },
    runner: 'cli',
    install: agent.install,
    ...(agent.mcpServers === undefined ? {} : { mcpServers: agent.mcpServers }),
  };
}

const REGISTERED = REGISTRY_AGENTS.map(fromRegistry);

/**
 * The registry's agents, then the table's. A name in both is the registry's:
 * its entry pins a version and needs nothing installed but npx or uvx
 * (`docs/decisions.md`, "Agents started by their own CLI").
 */
const AGENTS: readonly KnownAgent[] = [
  ...REGISTERED,
  ...CLI_AGENTS.filter(
    ({ name }) => !REGISTERED.some((agent) => agent.name === name),
  ).map(fromCli),
];

/**
 * Whether a session of `agent` is given MCP servers: as its
 * `agents.<name>.mcpServers` setting says, `set`, else as chord's own table
 * says, else yes (CHD-441).
 */
export function takesMcpServers(agent: string, set?: boolean): boolean {
  return set ?? findAgent(agent)?.mcpServers ?? true;
}

/** Every agent chord can start by name: the registry's, then the table's. */
export function listAgents(): readonly KnownAgent[] {
  return AGENTS;
}

/** The agent a name means, or undefined for one chord does not know. */
export function findAgent(name: string): KnownAgent | undefined {
  return AGENTS.find((agent) => agent.name === name);
}

/**
 * How `name` starts: `override`, as `--agent-command` or the settings' command
 * gives it, with no environment of the registry's, or the registry's entry.
 * Throws for a name chord does not know and nothing overrides.
 */
export function agentStart(
  name: string,
  override?: string | readonly string[],
): AgentStart {
  if (override !== undefined) {
    return { command: override, env: {} };
  }

  const agent = findAgent(name);

  if (agent === undefined) {
    throw new Error(`Unknown agent "${name}".`);
  }

  return agent.start;
}

/**
 * What a registry agent runs through: chord fetches the agent itself, so what
 * a person lacks is the runner, and the agent's own site would not give it.
 */
const runners: Readonly<Record<'npx' | 'uvx', string>> = {
  npx: 'npx comes with Node.js: https://nodejs.org/en/download',
  uvx: 'uvx comes with uv: https://docs.astral.sh/uv/getting-started/installation/',
};

/** Finds a command on PATH, or undefined; tests give a PATH of their own. */
export type Lookup = (command: string) => Promise<string | undefined>;

const onPath: Lookup = (command) => which(command);

/**
 * The line chord refuses `name` with when the command its start runs is not
 * on PATH, or undefined when it is there. A command that overrides the name
 * is the person's own, so it is left to fail as it would.
 */
export async function missingCommand(
  name: string,
  override: string | readonly string[] | undefined,
  lookup: Lookup = onPath,
): Promise<string | undefined> {
  const agent = findAgent(name);

  if (override !== undefined || agent === undefined) {
    return undefined;
  }

  const [command] = agent.start.command;

  if (command === undefined || (await lookup(command)) !== undefined) {
    return undefined;
  }

  const line = `chord: ${name} runs "${command}", which is not on PATH`;

  if (agent.runner !== 'cli') {
    return `${line}; ${runners[agent.runner]}`;
  }

  return agent.install === undefined
    ? `${line}.`
    : `${line}; install it from ${agent.install}`;
}

/** The start as one line a person could type, for `chord agents`. */
/** A command as a line: given as one, or its words quoted as a shell would. */
export function commandLine(command: string | readonly string[]): string {
  return typeof command === 'string' ? command : quote([...command]);
}

export function startLine({ command, env }: AgentStart): string {
  const words = typeof command === 'string' ? [command] : command;

  return [
    ...Object.entries(env).map(([key, value]) => `${key}=${value}`),
    ...words,
  ].join(' ');
}

/** An agent as `chord agents` lists it. */
export interface ListedAgent {
  readonly name: string;
  /** None for a name the settings files alone define. */
  readonly title: string | undefined;
  /** What starts it, as a person would type it. */
  readonly start: string;
  /**
   * Where that comes from: the registry's npx or uvx, the agent's own CLI
   * from the table, or a command in the settings files, which wins over both.
   */
  readonly from: 'npx' | 'uvx' | 'cli' | 'settings';
  /** For the agent's own CLI, whether PATH has its command. */
  readonly found?: boolean;
}

/**
 * Every agent chord can start, as `chord agents` lists them: the registry's
 * and the table's, each on the settings files' command where they give one,
 * then the names only the settings files define, in their order.
 */
export async function listedAgents(
  commands: Readonly<Record<string, string | readonly string[]>>,
  lookup: Lookup = onPath,
): Promise<ListedAgent[]> {
  const known = await Promise.all(
    AGENTS.map(async ({ name, title, start, runner }): Promise<ListedAgent> => {
      const command = commands[name];

      if (command !== undefined) {
        return { name, title, start: commandLine(command), from: 'settings' };
      }

      const [first] = start.command;

      return {
        name,
        title,
        start: startLine(start),
        from: runner,
        ...(runner === 'cli' && first !== undefined
          ? { found: (await lookup(first)) !== undefined }
          : {}),
      };
    }),
  );
  const theirs = Object.entries(commands)
    .filter(([name]) => findAgent(name) === undefined)
    .map(([name, command]): ListedAgent => ({
      name,
      title: undefined,
      start: commandLine(command),
      from: 'settings',
    }));

  return [...known, ...theirs];
}

/** What chord calls an agent with no title, as the settings files alone define it. */
export const SETTINGS_ONLY = 'from settings';

/**
 * An agent's title and, for its own CLI when PATH lacks it, that: how `/new`
 * describes it, so it says what `chord agents` does.
 */
export function agentNote({ title, from, found }: ListedAgent): string {
  const shown = title ?? SETTINGS_ONLY;

  return from === 'cli' && found === false ? `${shown} · not on PATH` : shown;
}

/** What `chord agents` says of where an agent's start comes from. */
function mark({ from, found }: ListedAgent): string {
  switch (from) {
    case 'cli':
      return found ? 'own CLI · found' : 'own CLI · not on PATH';
    case 'settings':
      return 'settings';
    default:
      return from;
  }
}

const PADDING = 2;

/** Narrower than this, a start line is wrapped no further; the terminal does. */
const MIN_START = 20;

/**
 * `chord agents`' lines in columns: name, title, where the start comes from,
 * and the start last, as it is the one that runs long. On a terminal `width`
 * wide the start wraps within its column, so the names still read down the
 * left; without one, piped, each agent stays one line for grep and awk.
 */
export function agentTable(
  listed: readonly ListedAgent[],
  width?: number,
): string {
  const rows = listed.map((agent) => [
    agent.name,
    agent.title ?? SETTINGS_ONLY,
    mark(agent),
    agent.start,
  ]);
  const before = [0, 1, 2].reduce(
    (sum, column) =>
      sum + Math.max(...rows.map((row) => stringWidth(row[column]!))) + PADDING,
    0,
  );
  const room =
    width === undefined ? undefined : Math.max(width - before, MIN_START);

  return new Table()
    .body(
      room === undefined
        ? rows
        : rows.map((row) => [
            ...row.slice(0, 3),
            wrapAnsi(row[3]!, room, { hard: true }),
          ]),
    )
    .padding(PADDING)
    .toString()
    .split('\n')
    .map((line) => line.trimEnd())
    .join('\n');
}
