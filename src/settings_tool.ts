import type { z } from '@zod/zod';
import { lstat, readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { notFound } from './not_found.ts';
import { TeamSelection } from './session/budgets.ts';
import {
  AGENT_SETTING_SCHEMAS,
  canBeSettingPath,
  loadSettings,
  mergeSettings,
  NO_SETTINGS_HOME,
  parseSettings,
  readSettingsObject,
  SETTING_SCHEMAS,
  settingAt,
  type SettingChange,
  settingParentProblem,
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
      return `No setting ${shown}`.trimEnd();
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

/** The keys whose values may carry a secret, whatever holds them. */
const SECRET_KEYS: ReadonlySet<string> = new Set([
  'env',
  'headers',
  'command',
  'args',
  'url',
]);

/** Every leaf hidden, a list's or an object's shape kept. */
function maskedLeaves(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(maskedLeaves);
  }

  return isObject(value)
    ? Object.fromEntries(
        Object.entries(value).map(([key, held]) => [key, maskedLeaves(held)]),
      )
    : MASK;
}

/**
 * Every value under a secret key's name hidden, whatever the depth or shape.
 * Below the top level a key named `mcpServers` is an agent's switch, so
 * anything but a boolean there is hidden too, whatever holds it.
 */
function maskedByName(value: unknown, top = true): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => maskedByName(item, false));
  }

  return isObject(value)
    ? Object.fromEntries(
        Object.entries(value).map(([key, held]) => [
          key,
          SECRET_KEYS.has(key)
            ? maskedLeaves(held)
            : key === 'mcpServers' && !top && typeof held !== 'boolean'
              ? MASK
              : maskedByName(held, false),
        ]),
      )
    : value;
}

/** A server of the wrong shape holds no name to mask by, so it is hidden whole. */
function maskedServer(server: unknown): unknown {
  return isObject(server) ? server : MASK;
}

/**
 * Settings with what may be secret hidden, so a file of the wrong shape hides
 * what the right one would: by key name, and whole where an `mcpServers` or a
 * server in it is of the wrong shape. Field names on a real server the names do
 * not cover read as written. Done before any path is walked: a path below a
 * leaf is not set.
 */
export function maskedSettings(settings: unknown): unknown {
  const masked = maskedByName(settings);

  if (!isObject(masked) || !Object.hasOwn(masked, 'mcpServers')) {
    return masked;
  }

  const servers = masked['mcpServers'];

  return {
    ...masked,
    mcpServers: Array.isArray(servers)
      ? servers.map(maskedServer)
      : isObject(servers)
        ? Object.fromEntries(
            Object.entries(servers).map(([name, server]) => [
              name,
              maskedServer(server),
            ]),
          )
        : MASK,
  };
}

/**
 * The name of the link a project's settings file is reached through, if one
 * is: a repository may plant one, and chord's server runs outside any agent's
 * sandbox, so the tool does not read through it. Only the project's own two
 * names are looked at, so a working directory under a link is no refusal, and
 * neither is opened: `lstat` reads no content and sees a dangling link too.
 */
async function projectLink(cwd: string): Promise<string | undefined> {
  const directory = join(cwd, '.chord');

  for (const name of [directory, join(directory, 'settings.json')]) {
    const found = await lstat(name).catch(() => undefined);

    if (found === undefined) {
      return undefined;
    }

    if (found.isSymbolicLink()) {
      return name;
    }
  }

  return undefined;
}

/**
 * The home an answer's paths are shown from: where `HOME` is unset, the one
 * the config directory was found under all the same, as the model is never
 * told it.
 */
export function shownHome(where: SettingsWhere): string {
  return where.home ?? homedir();
}

/** A file as written and what its row says of it, or that it is not there. */
async function writtenFile(file: string | undefined): Promise<{
  readonly written: unknown;
  readonly state: string;
  readonly text?: string;
}> {
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
      return { written: null, state: 'not a JSON object', text };
    }

    const keys = Object.keys(written).length;

    return { written, state: `${keys} ${keys === 1 ? 'key' : 'keys'}`, text };
  } catch {
    return { written: null, state: 'not valid JSON', text };
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

/** The user's file alone, as a read takes it with the project's left out. */
function userLayer(
  file: string | undefined,
  { state, text }: Awaited<ReturnType<typeof writtenFile>>,
): { readonly settings: unknown; readonly problems: SettingsProblem[] } {
  if (file !== undefined && text !== undefined) {
    const { settings, problems } = parseSettings(file, text);

    return { settings: mergeSettings(settings), problems };
  }

  return {
    settings: {},
    problems:
      file !== undefined && state === 'cannot be read'
        ? [{ file, kind: 'read', message: state }]
        : [],
  };
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
      readonly files: {
        readonly user: string;
        readonly project: string;
        readonly projectLinked?: true;
      };
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
  const link = await projectLink(where.cwd);
  // Whatever a linked file holds stays out, the problems it would cost too.
  const project =
    link === undefined
      ? await writtenFile(projectFile)
      : { written: null, state: 'a symbolic link, not read' };
  const loaded =
    link === undefined
      ? await loadSettings({
          configHome: where.configHome,
          cwd: where.cwd,
          home,
        })
      : userLayer(userFile, user);
  const atPath = (value: unknown) => settingAt(maskedSettings(value), path);

  return {
    answer: {
      user: atPath(user.written),
      project: link === undefined ? atPath(project.written) : null,
      effective: atPath(loaded.settings),
      problems: [
        ...loaded.problems
          .filter((problem) => concerns(problem, path))
          .map((problem) => ({
            file: shownPath(problem.file, shown),
            message: readProblem(problem),
          })),
        ...(link === undefined
          ? []
          : [
              {
                file: shownPath(projectFile, shown),
                message: `${shownPath(link, shown)} is a symbolic link, so it was not read: project and effective omit it. A start still follows the link`,
              },
            ]),
      ],
    },
    files: {
      user:
        userFile === undefined
          ? user.state
          : `${shownPath(userFile, shown)} · ${user.state}`,
      project: `${shownPath(projectFile, shown)} · ${project.state}`,
      ...(link === undefined ? {} : { projectLinked: true as const }),
    },
  };
}

/** What a `set` or `remove` answers, while the box is open and once answered. */
export interface SettingsChanged {
  readonly path: readonly string[];
  /** The value in the file, masked as a read is, absent where it holds none. */
  readonly before?: unknown;
  readonly after?: unknown;
  /** The user's file, as the window shows it. */
  readonly file: string;
  /** Not there yet while the person is asked. */
  readonly saved?: boolean;
  /** Nothing to do: nothing was asked or written. */
  readonly unchanged?: true;
  readonly takesEffect: TakesEffect;
  /** The project's file, as shown, where it holds this key and so wins. */
  readonly shadowedBy?: string;
}

/**
 * What a system error says, without the person's home: the model is told
 * paths as the window shows them.
 */
function withoutHome(error: unknown, home: string): string {
  const message = error instanceof Error ? error.message : String(error);

  return message.replaceAll(home, '~');
}

/** A write that failed, as a refusal says it. */
export function saveFailure(
  shownFile: string,
  error: unknown,
  home: string,
): string {
  return notSavedLine(shownFile, withoutHome(error, home));
}

/**
 * The checks a `set` or `remove` passes before the person is asked, in the
 * design's order, and what it would do: the first refusal, or the change.
 */
export async function plannedSetting(
  where: SettingsWhere,
  path: readonly string[],
  change: SettingChange,
  knownAgents: readonly string[],
): Promise<
  | { readonly error: string }
  | { readonly answer: SettingsChanged; readonly file: string }
> {
  const refused = settingRefusal(path, change, knownAgents);

  if (refused !== undefined) {
    return { error: refused };
  }

  const file = userSettingsFile(where.configHome);

  if (file === undefined) {
    return { error: NO_SETTINGS_HOME };
  }

  const named = classifySetting(path) as WritableSetting;
  const home = shownHome(where);
  const shown = { cwd: where.cwd, home };
  const shownFile = shownPath(file, shown);
  let settings: Record<string, unknown>;

  try {
    settings = await readSettingsObject(file);
  } catch (error) {
    return { error: saveFailure(shownFile, error, home) };
  }

  const parent = settingParentProblem(settings, path);

  if (parent !== undefined) {
    return { error: notSavedLine(shownFile, parent) };
  }

  const held = settingAt(settings, path);
  // As a read shows it: a key under a secret's name, or holding one, is masked
  // here too, for the row and the agent alike. `held` says what is unchanged.
  const before = settingAt(maskedSettings(settings), path);
  const after = 'set' in change ? change.set : undefined;
  const project = settingsFiles(where).at(-1)!;
  const { layers } = await loadSettings({
    configHome: where.configHome,
    cwd: where.cwd,
    home,
  });
  // What the project's file's check dropped does not win, so it does not count.
  const shadowed =
    !named.userOnly &&
    settingAt(
      layers.find((layer) => layer.file === project)?.settings,
      path,
    ) !== undefined;

  return {
    file,
    answer: {
      path,
      ...(before === undefined ? {} : { before }),
      ...(after === undefined ? {} : { after }),
      file: shownFile,
      ...(isDeepStrictEqual(held, after)
        ? { saved: false, unchanged: true as const }
        : {}),
      takesEffect: named.takesEffect,
      ...(shadowed ? { shadowedBy: shownPath(project, shown) } : {}),
    },
  };
}

/** The note a planned change goes by: on the row and, capitalised, the box. */
export function changeWord(
  answer: Pick<SettingsChanged, 'before' | 'after'>,
): 'change' | 'set' | 'remove' {
  return answer.after === undefined
    ? 'remove'
    : answer.before === undefined
      ? 'set'
      : 'change';
}
