import type { z } from '@zod/zod';
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { notFound } from './not_found.ts';
import { TeamSelection } from './session/budgets.ts';
import {
  AGENT_SETTING_SCHEMAS,
  canBeSettingPath,
  loadSettings,
  SETTING_SCHEMAS,
  settingAt,
  type SettingChange,
  type SettingsProblem,
  settingsFiles,
  shownPath,
  shownSettingPath,
  shownValue,
  userSettingsFile,
} from './settings.ts';

/** When a saved setting reaches the window it was saved from. */
export type TakesEffect = 'now' | 'next start';

/** A key the tool may write, and what a write of it means. */
export interface WritableSetting {
  readonly kind: 'leaf';
  /** Only the user's file holds it, so no project's file can shadow it. */
  readonly userOnly: boolean;
  readonly takesEffect: TakesEffect;
  /** The key's own schema, its value required. */
  readonly schema: z.ZodType;
  /** The agent names a value gives, which chord has to know. */
  readonly agentsIn?: (value: unknown) => readonly string[];
}

/** What a settings path names, for the tool. */
export type SettingClass =
  | WritableSetting
  /** Kind C: read, but a person edits it by hand. */
  | { readonly kind: 'hand' }
  /** A parent of writable leaves, with the leaves it could have named. */
  | { readonly kind: 'parent'; readonly leaves: readonly string[] }
  | { readonly kind: 'unknown' };

const UNKNOWN: SettingClass = { kind: 'unknown' };
const HAND: SettingClass = { kind: 'hand' };

const oneAgent = (value: unknown) => [value as string];

const prefer = TeamSelection.shape.prefer.unwrap().shape;

/** The top-level leaves: the design's allowlist, closed to any other key. */
const TOP_LEVEL: Readonly<Record<string, WritableSetting>> = {
  theme: {
    kind: 'leaf',
    userOnly: true,
    takesEffect: 'now',
    schema: SETTING_SCHEMAS.theme.unwrap(),
  },
  editorMode: {
    kind: 'leaf',
    userOnly: true,
    takesEffect: 'now',
    schema: SETTING_SCHEMAS.editorMode.unwrap(),
  },
  mouse: {
    kind: 'leaf',
    userOnly: true,
    takesEffect: 'next start',
    schema: SETTING_SCHEMAS.mouse.unwrap(),
  },
  copyOnSelect: {
    kind: 'leaf',
    userOnly: true,
    takesEffect: 'next start',
    schema: SETTING_SCHEMAS.copyOnSelect.unwrap(),
  },
  offeredAgents: {
    kind: 'leaf',
    userOnly: true,
    takesEffect: 'now',
    schema: SETTING_SCHEMAS.offeredAgents.unwrap(),
    agentsIn: (value) => value as string[],
  },
  preferredNotifChannel: {
    kind: 'leaf',
    userOnly: false,
    takesEffect: 'next start',
    schema: SETTING_SCHEMAS.preferredNotifChannel.unwrap(),
  },
  agent: {
    kind: 'leaf',
    userOnly: false,
    takesEffect: 'next start',
    schema: SETTING_SCHEMAS.agent.unwrap(),
    agentsIn: oneAgent,
  },
};

const AGENT_KEYS: Readonly<Record<string, WritableSetting>> = {
  model: {
    kind: 'leaf',
    userOnly: false,
    takesEffect: 'next start',
    schema: AGENT_SETTING_SCHEMAS.model.unwrap(),
  },
  effort: {
    kind: 'leaf',
    userOnly: false,
    takesEffect: 'next start',
    schema: AGENT_SETTING_SCHEMAS.effort.unwrap(),
  },
};

const INTENT: WritableSetting = {
  kind: 'leaf',
  userOnly: false,
  takesEffect: 'now',
  schema: TeamSelection.shape.intent.unwrap(),
};

const PREFER_KEYS: Readonly<Record<string, WritableSetting>> = {
  agent: {
    kind: 'leaf',
    userOnly: false,
    takesEffect: 'now',
    schema: prefer.agent.unwrap(),
    agentsIn: oneAgent,
  },
  model: {
    kind: 'leaf',
    userOnly: false,
    takesEffect: 'now',
    schema: prefer.model.unwrap(),
  },
};

function agentClass(rest: readonly string[], name: string): SettingClass {
  const [key, ...deeper] = rest;

  if (key === undefined) {
    const shown = shownSettingPath(['agents', name]);

    return { kind: 'parent', leaves: [`${shown}.model`, `${shown}.effort`] };
  }

  if (key === 'command' || key === 'permissionMode' || key === 'mcpServers') {
    return HAND;
  }

  return deeper.length === 0 && Object.hasOwn(AGENT_KEYS, key)
    ? AGENT_KEYS[key]!
    : UNKNOWN;
}

function teamSelectionClass(rest: readonly string[]): SettingClass {
  const [key, leaf, ...deeper] = rest;

  if (key === 'constraints') {
    return HAND;
  }

  if (key === undefined) {
    return {
      kind: 'parent',
      leaves: [
        'teamSelection.intent',
        'teamSelection.prefer.agent',
        'teamSelection.prefer.model',
      ],
    };
  }

  if (key === 'intent') {
    return leaf === undefined ? INTENT : UNKNOWN;
  }

  if (key !== 'prefer') {
    return UNKNOWN;
  }

  if (leaf === undefined) {
    return {
      kind: 'parent',
      leaves: ['teamSelection.prefer.agent', 'teamSelection.prefer.model'],
    };
  }

  return deeper.length === 0 && Object.hasOwn(PREFER_KEYS, leaf)
    ? PREFER_KEYS[leaf]!
    : UNKNOWN;
}

/** What `path` names. A new key is closed until it is named above. */
export function classifySetting(path: readonly string[]): SettingClass {
  if (!canBeSettingPath(path)) {
    return UNKNOWN;
  }

  const [first, second, ...rest] = path as [string, ...string[]];

  if (first === 'mcpServers') {
    return HAND;
  }

  if (first === 'teamSelection') {
    return teamSelectionClass(path.slice(1));
  }

  if (first === 'agents') {
    return second === undefined
      ? {
          kind: 'parent',
          leaves: ['agents.<name>.model', 'agents.<name>.effort'],
        }
      : agentClass(rest, second);
  }

  return second === undefined && Object.hasOwn(TOP_LEVEL, first)
    ? TOP_LEVEL[first]!
    : UNKNOWN;
}

/** `a`, `a or b`, `a, b or c`. */
function either(words: readonly string[]): string {
  return words.length < 2
    ? words.join('')
    : `${words.slice(0, -1).join(', ')} or ${words.at(-1)!}`;
}

/** Why a path alone is not one the tool writes, as the refusal says it. */
function pathRefusal(
  path: readonly string[],
  named: SettingClass,
): string | undefined {
  const shown = shownSettingPath(path);

  switch (named.kind) {
    case 'unknown':
      return `No setting ${shown}`;
    case 'hand':
      return `chord does not write ${shown}; edit the settings file by hand`;
    case 'parent':
      return `${shown} is not one setting; name ${either(named.leaves)}`;
    case 'leaf':
      return undefined;
  }
}

/**
 * The first thing wrong with a write that reading no file can tell: the
 * allowlist, the key's own schema, then the names chord knows. A remove has
 * no value to check, and defines nothing, so a stale agent's key can leave.
 */
export function settingRefusal(
  path: readonly string[],
  change: SettingChange,
  knownAgents: readonly string[],
): string | undefined {
  const named = classifySetting(path);
  const refused = pathRefusal(path, named);

  if (refused !== undefined || named.kind !== 'leaf' || 'remove' in change) {
    return refused;
  }

  const checked = named.schema.safeParse(change.set);

  if (!checked.success) {
    const given =
      change.set === undefined ? 'left out' : shownValue(change.set);

    return `${shownSettingPath(path)} cannot be ${given}: ${checked.error.issues[0]?.message ?? 'invalid'}`;
  }

  const agents = [
    ...(path[0] === 'agents' ? [path[1]!] : []),
    ...(named.agentsIn?.(change.set) ?? []),
  ];
  const stranger = agents.find((name) => !knownAgents.includes(name));

  return stranger === undefined
    ? undefined
    : `chord knows no agent named ${shownValue(stranger)}; list_agents names every one`;
}

/** A refusal about the file, its name as shown and why in the writer's words. */
export function notSavedLine(shownFile: string, why: string): string {
  return `${shownFile} was not saved: ${why}`;
}

/** Where a window's settings files are, and how it shows them. */
export interface SettingsWhere {
  readonly configHome: string | undefined;
  readonly cwd: string;
  readonly home: string | undefined;
}

const MASK = '***';

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** `env` or `headers`: key names kept, every value hidden, whatever its shape. */
function maskedSecrets(value: unknown): unknown {
  return isObject(value)
    ? Object.fromEntries(Object.keys(value).map((key) => [key, MASK]))
    : MASK;
}

/** One server, a list that a wrong file gave in place of one included. */
function maskedServer(server: unknown): unknown {
  if (Array.isArray(server)) {
    return server.map(maskedServer);
  }

  if (!isObject(server)) {
    return server;
  }

  const masked = { ...server };

  for (const key of ['env', 'headers']) {
    if (Object.hasOwn(masked, key)) {
      masked[key] = maskedSecrets(masked[key]);
    }
  }

  return masked;
}

/**
 * A settings object with every MCP server's `env` and `headers` hidden. Done
 * before any path is walked, so no path reads under a mask.
 */
export function maskedSettings(settings: unknown): unknown {
  if (!isObject(settings) || !Object.hasOwn(settings, 'mcpServers')) {
    return settings;
  }

  const servers = settings['mcpServers'];

  return {
    ...settings,
    // A shape no server can be read from still may hold what it would have.
    mcpServers: isObject(servers)
      ? Object.fromEntries(
          Object.entries(servers).map(([name, server]) => [
            name,
            maskedServer(server),
          ]),
        )
      : Array.isArray(servers)
        ? maskedServer(servers)
        : MASK,
  };
}

/**
 * The home an answer's paths are shown from: where `HOME` is unset, the one
 * the config directory was found under all the same, as the model is never
 * told it.
 */
function shownHome(where: SettingsWhere): string {
  return where.home ?? homedir();
}

/** A file as written and what its row says of it, or that it is not there. */
async function writtenFile(
  file: string | undefined,
): Promise<{ readonly written: unknown; readonly state: string }> {
  if (file === undefined) {
    return { written: null, state: 'no home directory' };
  }

  let text: string;

  try {
    text = await readFile(file, 'utf8');
  } catch (error) {
    return {
      written: null,
      state: notFound(error) ? 'not there' : 'cannot be read',
    };
  }

  try {
    const written: unknown = JSON.parse(text);

    if (!isObject(written)) {
      return { written: null, state: 'not a JSON object' };
    }

    const keys = Object.keys(written).length;

    return { written, state: `${keys} ${keys === 1 ? 'key' : 'keys'}` };
  } catch {
    return { written: null, state: 'not valid JSON' };
  }
}

/**
 * A problem as a read says it: never the parser's words, which quote what it
 * choked on and may be a masked value, nor a system error's, which names the
 * person's home.
 */
function readProblem(problem: SettingsProblem): string {
  if (problem.kind === 'read') {
    return 'cannot be read; the file is ignored';
  }

  return problem.message.startsWith('not valid JSON')
    ? 'not valid JSON; the file is ignored'
    : problem.message;
}

/** Whether a problem is of the key at `path`, or of a whole file. */
function concerns(problem: SettingsProblem, path: readonly string[]): boolean {
  const { key } = problem;

  if (key === undefined || path.length === 0) {
    return true;
  }

  return path.slice(0, key.length).every((part, index) => part === key[index]);
}

/** A `settings` read: the answer the agent gets. */
export interface SettingsRead {
  /** The file as written, masked; null where there is none to read. */
  readonly user: unknown;
  readonly project: unknown;
  /** The merged, checked settings, masked. */
  readonly effective: unknown;
  readonly problems: readonly {
    readonly file: string;
    readonly message: string;
  }[];
}

/**
 * The `settings` tool's read, of every key or of the one at `path`, and what
 * the row says of each file. Reads are not the writes' business: every key
 * reads, an unknown one too, and only a name that can be no key is refused.
 */
export async function readSettingsTool(
  where: SettingsWhere,
  path: readonly string[] = [],
): Promise<
  | {
      readonly answer: SettingsRead;
      readonly files: { readonly user: string; readonly project: string };
    }
  | { readonly error: string }
> {
  if (path.length > 0 && !canBeSettingPath(path)) {
    return { error: `No setting ${shownSettingPath(path)}` };
  }

  const home = shownHome(where);
  const shown = { cwd: where.cwd, home };
  const userFile = userSettingsFile(where.configHome);
  const projectFile = settingsFiles(where).at(-1)!;
  const user = await writtenFile(userFile);
  const project = await writtenFile(projectFile);
  const loaded = await loadSettings({
    configHome: where.configHome,
    cwd: where.cwd,
    home,
  });
  const atPath = (value: unknown) => settingAt(maskedSettings(value), path);

  return {
    answer: {
      user: atPath(user.written),
      project: atPath(project.written),
      effective: atPath(loaded.settings),
      problems: loaded.problems
        .filter((problem) => concerns(problem, path))
        .map((problem) => ({
          file: shownPath(problem.file, shown),
          message: readProblem(problem),
        })),
    },
    files: {
      user:
        userFile === undefined
          ? user.state
          : `${shownPath(userFile, shown)} · ${user.state}`,
      project: `${shownPath(projectFile, shown)} · ${project.state}`,
    },
  };
}
