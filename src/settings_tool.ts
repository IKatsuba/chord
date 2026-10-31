import type { z } from '@zod/zod';
import { homedir } from 'node:os';
import { isDeepStrictEqual } from 'node:util';
import { parsedEntry } from './mcp.ts';
import { TeamSelection } from './session/budgets.ts';
import {
  AGENT_SETTING_SCHEMAS,
  canBeSettingPath,
  loadSettings,
  NO_SETTINGS_HOME,
  readSettingsObject,
  SETTING_SCHEMAS,
  settingAt,
  type SettingChange,
  type Settings,
  type SettingsLayer,
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

/** The keys whose values may carry a secret, whatever holds them. */
const SECRET_KEYS: ReadonlySet<string> = new Set([
  'env',
  'headers',
  'command',
  'args',
  'url',
]);

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

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

/** Every value under a secret key's name hidden, at any depth. */
function maskedByName(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(maskedByName);
  }

  return isObject(value)
    ? Object.fromEntries(
        Object.entries(value).map(([key, held]) => [
          key,
          SECRET_KEYS.has(key) ? maskedLeaves(held) : maskedByName(held),
        ]),
      )
    : value;
}

/**
 * Checked settings as a read shows them. The settings schema does not look
 * inside a server, so each goes through its transport's shape here: a field of
 * no known name, `token` or `Env`, is gone with its value, and a server that
 * fails is left out. Masked before any path is walked: a path below a leaf is
 * not set.
 */
function shownSettings({ mcpServers, ...rest }: Settings): unknown {
  return maskedByName({
    ...rest,
    ...(mcpServers === undefined
      ? {}
      : {
          mcpServers: Object.fromEntries(
            Object.entries(mcpServers).flatMap(([name, entry]) => {
              const parsed = parsedEntry(entry);

              return parsed.success ? [[name, parsed.data]] : [];
            }),
          ),
        }),
  });
}

/**
 * The home an answer's paths are shown from: where `HOME` is unset, the one
 * the config directory was found under all the same, as the model is never
 * told it.
 */
export function shownHome(where: SettingsWhere): string {
  return where.home ?? homedir();
}

/** `1 key`, `3 keys`. */
function keysWord(count: number): string {
  return `${count} ${count === 1 ? 'key' : 'keys'}`;
}

/** The kind of parse problem a file has, in the words a read says it by. */
function parseWords(problem: SettingsProblem): string {
  return problem.message.startsWith('not valid JSON')
    ? 'not valid JSON'
    : problem.message.startsWith('not a JSON object')
      ? 'not a JSON object'
      : 'cannot be used';
}

/**
 * What a read says of one file's problems, by kind and count alone: a
 * problem's message and key quote the file's own names and the parser's words,
 * and a read carries nothing of a file the schema did not check.
 */
function problemWords(problems: readonly SettingsProblem[]): string[] {
  const count = (kind: SettingsProblem['kind']) =>
    problems.filter((problem) => problem.kind === kind).length;
  const parse = problems.find(({ kind }) => kind === 'parse');
  const invalid = count('validation');
  const scoped = count('scope');

  return [
    ...(count('read') === 0 ? [] : ['cannot be read; ignored']),
    ...(parse === undefined ? [] : [`${parseWords(parse)}; ignored`]),
    ...(invalid === 0 ? [] : [`${keysWord(invalid)} ignored`]),
    ...(scoped === 0
      ? []
      : [`${keysWord(scoped)} only the user's file may set; ignored`]),
  ];
}

/** What a file's row says of it, from what the load left. */
function fileState(
  layer: SettingsLayer | undefined,
  problems: readonly SettingsProblem[],
): string {
  if (problems.some(({ kind }) => kind === 'read')) {
    return 'cannot be read';
  }

  if (layer === undefined) {
    return 'not there';
  }

  const parse = problems.find(({ kind }) => kind === 'parse');

  return parse === undefined
    ? keysWord(Object.keys(layer.settings).length)
    : parseWords(parse);
}

/** A `settings` read: the answer the agent gets. */
export interface SettingsRead {
  /** The file's checked settings, masked; null where it could not be used. */
  readonly user: unknown;
  readonly project: unknown;
  /** The merged, checked settings, masked. */
  readonly effective: unknown;
  /** Per file, by kind and count, with no name from the file. */
  readonly problems: readonly {
    readonly file: string;
    readonly message: string;
  }[];
}

/**
 * The `settings` tool's read, of every key or of the one at `path`, and what
 * the row says of each file. It loads as a start does, following links, and
 * answers only from what the schema checked: no raw file is parsed for it.
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
  const { settings, layers, problems } = await loadSettings({
    configHome: where.configHome,
    cwd: where.cwd,
    home,
  });
  const layerOf = (file: string | undefined) =>
    layers.find((layer) => layer.file === file);
  const problemsOf = (file: string | undefined) =>
    problems.filter((problem) => problem.file === file);
  // A file the load could not use is none, not one that is fine and empty.
  const shownLayer = (file: string | undefined) => {
    const layer = layerOf(file);

    return layer === undefined ||
      problemsOf(file).some(({ kind }) => kind === 'parse')
      ? null
      : shownSettings(layer.settings);
  };

  return {
    answer: {
      user: settingAt(shownLayer(userFile), path),
      project: settingAt(shownLayer(projectFile), path),
      effective: settingAt(shownSettings(settings), path),
      problems: [userFile, projectFile].flatMap((file) =>
        problemWords(problemsOf(file)).map((message) => ({
          file: shownPath(file!, shown),
          message,
        })),
      ),
    },
    files: {
      user:
        userFile === undefined
          ? 'no home directory'
          : `${shownPath(userFile, shown)} · ${fileState(layerOf(userFile), problemsOf(userFile))}`,
      project: `${shownPath(projectFile, shown)} · ${fileState(layerOf(projectFile), problemsOf(projectFile))}`,
    },
  };
}

/** What a `set` or `remove` answers, while the box is open and once answered. */
export interface SettingsChanged {
  readonly path: readonly string[];
  /** The value the schema checked in the file, absent where it holds none. */
  readonly before?: unknown;
  readonly after?: unknown;
  /** The user's file, as the window shows it. */
  readonly file: string;
  /** Not there yet while the person is asked. */
  readonly saved?: boolean;
  /** Nothing to do: nothing was asked or written. */
  readonly unchanged?: true;
  readonly takesEffect: TakesEffect;
  /** The project's file, as shown, where its checked settings hold this key. */
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

  const after = 'set' in change ? change.set : undefined;
  const projectFile = settingsFiles(where).at(-1)!;
  const { layers } = await loadSettings({
    configHome: where.configHome,
    cwd: where.cwd,
    home,
  });
  const layerAt = (layerFile: string) =>
    layers.find((layer) => layer.file === layerFile)?.settings;
  // From the checked layer, so a bad value reads as not set and no raw value
  // goes in an answer; a set replaces it, and a remove has nothing to remove.
  const held = settingAt(layerAt(file), path);
  const userLayer = layerAt(file);
  const before =
    userLayer === undefined
      ? undefined
      : settingAt(shownSettings(userLayer), path);
  const shadowed =
    !named.userOnly && settingAt(layerAt(projectFile), path) !== undefined;

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
      ...(shadowed ? { shadowedBy: shownPath(projectFile, shown) } : {}),
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
