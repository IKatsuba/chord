import { z } from '@zod/zod';
import { dirname, isAbsolute, join, relative, sep } from 'node:path';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { notFound } from './not_found.ts';
import { NOTIF_CHANNELS } from './notify.ts';
import { mergeTeamSelection, TeamSelection } from './session/budgets.ts';
import {
  DEFAULT_KEYMAP,
  type Keymap,
  readKeybindings,
} from './ui/shortcuts/bindings.ts';
import { THEME_SETTINGS, type ThemeSetting } from './ui/theme/theme.ts';

/**
 * What each agent starts with. Model, effort and mode ids are the agent's
 * own, so they are set per agent: one agent's `plan`, `opus` or `xhigh` means
 * nothing to another.
 */
const AgentSettings = z
  .strictObject({
    /**
     * Starts this command instead of chord's own, as `--agent-command`:
     * a line the shell splits, or the program and its arguments, as a list.
     */
    command: z.union([
      z.string().min(1),
      // The program, then its arguments as written, an empty one too.
      z.tuple([z.string().min(1)], z.string()),
    ]),
    /** The model each session starts on, as `--model`. */
    model: z.string().min(1),
    /**
     * The effort each session starts on, as `--effort`, among those the
     * model it starts on offers.
     */
    effort: z.string().min(1),
    /** The mode each session starts in, as `--permission-mode`. */
    permissionMode: z.string().min(1),
    /**
     * `false` gives each session no MCP servers at all, chord's own among
     * them, for an agent that refuses any (CHD-441); `true` gives them where
     * chord's own table sets `false` for the agent.
     */
    mcpServers: z.boolean(),
  })
  .partial();

/** How the prompt box edits: as it always has, or as vim does. */
export const EDITOR_MODES = ['normal', 'vim'] as const;

export type EditorMode = (typeof EDITOR_MODES)[number];

/** The keys read only from the user's file, which is the one chord writes. */
const USER_ONLY = [
  'theme',
  'editorMode',
  'mouse',
  'copyOnSelect',
  'offeredAgents',
] as const;

/** What `offeredAgents` holds: one or more agent names, in the order shown. */
const OfferedAgents = z.array(z.string().min(1)).min(1);

/** One settings file, as written. */
const SettingsFile = z
  .strictObject({
    /** The agent `chord` starts when none is named. */
    agent: z.string().min(1),
    agents: z.record(z.string(), AgentSettings),
    teamSelection: TeamSelection,
    /**
     * MCP servers handed to the agent for each session, by name, as
     * `.mcp.json` writes them; each is checked on its own by `src/mcp.ts`, so a
     * wrong one costs only itself.
     */
    mcpServers: z.record(z.string(), z.unknown()),
    /**
     * How the terminal is told chord waits on the person, named as Claude
     * Code names its key.
     */
    preferredNotifChannel: z.enum(NOTIF_CHANNELS),
    /**
     * The colours chord draws in, by Claude Code's ids; read only from the
     * user's file, as it is about a terminal and a person's eyes, not a project.
     */
    theme: z.enum(THEME_SETTINGS),
    /**
     * `vim` when the prompt box edits as vim does, as `/vim` leaves it; named
     * as Claude Code names its key, and read only from the user's file, as
     * it is about a person's hands, not a project.
     */
    editorMode: z.enum(EDITOR_MODES),
    /**
     * `false` leaves the mouse to the terminal: no reporting asked for, so the
     * wheel does what the terminal makes of it. Read only from the user's file,
     * as it is about a person's terminal and hands, not a project.
     */
    mouse: z.boolean(),
    /**
     * `false` keeps a drag's selection until ctrl+c copies it, rather than
     * copying it on release; named as Claude Code names its key, and read only
     * from the user's file, as `mouse` is.
     */
    copyOnSelect: z.boolean(),
    /**
     * The agents the start screen and `/new` offer, in the order they show;
     * read only from the user's file, as it is about what a person picks from,
     * not a project. Checked whole, so a bad name costs this key alone: an
     * issue on an item is one the file's parse cannot drop from a list
     * (the owner's Q327).
     */
    offeredAgents: z.custom<string[]>(
      (value) => OfferedAgents.safeParse(value).success,
      'expected a list of one or more agent names',
    ),
  })
  .partial();

/**
 * Each key's own schema, for a check of that key alone: `parseSettings`'s drop
 * loop would cost a whole file for a wrong item in a list.
 */
export const SETTING_SCHEMAS = SettingsFile.shape;

/** The same for each key of an agent's settings. */
export const AGENT_SETTING_SCHEMAS = AgentSettings.shape;

export type AgentSettings = z.infer<typeof AgentSettings>;
export type Settings = z.infer<typeof SettingsFile>;

/** Something wrong in a settings file, said in a line of its own. */
export interface SettingsProblem {
  readonly file: string;
  readonly message: string;
  /** Admission checks use structure rather than interpreting display prose. */
  readonly kind?: 'read' | 'parse' | 'validation' | 'scope';
  readonly key?: readonly string[];
}

/** The user's own settings file, which chord also writes; none without a home. */
export function userSettingsFile(
  configHome: string | undefined,
): string | undefined {
  return configHome === undefined
    ? undefined
    : join(configHome, 'chord', 'settings.json');
}

/**
 * The user's keybindings file, beside the settings file: chord's own, never
 * Claude Code's, though a block copied from Claude Code's reads the same.
 * Keys are about a person's hands, not a project, so there is no project
 * file.
 */
export function keybindingsFile(
  configHome: string | undefined,
): string | undefined {
  return configHome === undefined
    ? undefined
    : join(configHome, 'chord', 'keybindings.json');
}

/**
 * Reads the keybindings file over the defaults. A file that is not there is
 * no problem, and one that cannot be read leaves the defaults.
 */
export async function loadKeybindings(
  file: string | undefined,
): Promise<{ keymap: Keymap; problems: SettingsProblem[] }> {
  if (file === undefined) {
    return { keymap: DEFAULT_KEYMAP, problems: [] };
  }

  let text: string;

  try {
    text = await readFile(file, 'utf8');
  } catch (error) {
    if (notFound(error)) {
      return { keymap: DEFAULT_KEYMAP, problems: [] };
    }

    return {
      keymap: DEFAULT_KEYMAP,
      problems: [
        {
          file,
          message: `cannot be read (${
            error instanceof Error ? error.message : String(error)
          }); the file is ignored`,
        },
      ],
    };
  }

  const { keymap, problems } = readKeybindings(text);

  return {
    keymap,
    problems: problems.map((message) => ({ file, message })),
  };
}

/** Each settings file chord reads, lowest precedence first. */
export function settingsFiles({
  configHome,
  cwd,
}: {
  configHome: string | undefined;
  cwd: string;
}): string[] {
  const user = userSettingsFile(configHome);

  return [
    ...(user === undefined ? [] : [user]),
    join(cwd, '.chord', 'settings.json'),
  ];
}

/** What chord was given in place of a command, as a refusal says it. */
function given(value: unknown): string {
  if (Array.isArray(value)) {
    return value.length === 0
      ? 'an empty list'
      : value.every((item) => typeof item === 'string')
        ? 'a list whose program is empty'
        : 'a list with something not a string';
  }

  if (value === '') {
    return 'an empty string';
  }

  return value === null
    ? 'null'
    : `${/^[aeiou]/u.test(typeof value) ? 'an' : 'a'} ${typeof value}`;
}

/** The value at `path` in `value`, if there is one. */
function at(value: unknown, path: readonly PropertyKey[]): unknown {
  return path.reduce<unknown>(
    (parent, key) =>
      typeof parent === 'object' && parent !== null
        ? (parent as Record<PropertyKey, unknown>)[key]
        : undefined,
    value,
  );
}

function keyOf(path: readonly PropertyKey[]): string {
  return path.map(String).join('.');
}

/** Removes the value at `path`; false when there is nothing to remove it from. */
function drop(value: unknown, path: readonly PropertyKey[]): boolean {
  const last = path.at(-1);
  let parent = value;

  for (const key of path.slice(0, -1)) {
    parent = (parent as Record<PropertyKey, unknown>)[key];
  }

  if (last === undefined || typeof parent !== 'object' || parent === null) {
    return false;
  }

  delete (parent as Record<PropertyKey, unknown>)[last];

  return true;
}

/**
 * Reads one file's text. A key that is unknown or holds the wrong kind of
 * value is a problem and is left out, and the rest still counts, so one typo
 * does not cost every other setting; text that is not a JSON object counts
 * for nothing.
 */
export function parseSettings(
  file: string,
  text: string,
): {
  settings: Settings;
  problems: SettingsProblem[];
  /**
   * The agents whose `command` this file gives chord refused, each with
   * why: such an agent is not started at all, rather than on chord's own
   * command (CHD-466, the owner's Q52).
   */
  refused?: Record<string, string>;
} {
  let input: unknown;

  try {
    input = JSON.parse(text);
  } catch (error) {
    return {
      settings: {},
      problems: [
        {
          file,
          kind: 'parse',
          message: `not valid JSON (${
            error instanceof Error ? error.message : String(error)
          }); the file is ignored`,
        },
      ],
    };
  }

  const problems: SettingsProblem[] = [];
  const refused: Record<string, string> = {};
  const parsed = (settings: Settings) =>
    Object.keys(refused).length === 0
      ? { settings, problems }
      : { settings, problems, refused };

  // Each round drops what the last one found; nested records can hide a
  // problem behind another, so a few rounds may be needed.
  for (let round = 0; round < 8; round++) {
    const result = SettingsFile.safeParse(input);

    if (result.success) {
      return parsed(result.data);
    }

    for (const issue of result.error.issues) {
      const paths =
        issue.code === 'unrecognized_keys'
          ? issue.keys.map((key) => [...issue.path, key])
          : [issue.path];

      for (const path of paths) {
        const [first, agent, key] = path;
        const command =
          path.length === 3 &&
          first === 'agents' &&
          typeof agent === 'string' &&
          key === 'command'
            ? agent
            : undefined;

        if (command !== undefined) {
          refused[command] = `expected a string, got ${given(at(input, path))}`;
        }

        if (path.length === 0 || !drop(input, path)) {
          return {
            settings: {},
            problems: [
              ...problems,
              {
                file,
                kind: 'parse',
                message: 'not a JSON object; the file is ignored',
              },
            ],
          };
        }

        problems.push({
          file,
          kind: 'validation',
          key: path.map(String),
          // A refused command is not ignored: its agent will not start, which
          // the person learns before trying it.
          message:
            command !== undefined
              ? `"agents.${command}.command": ${refused[command]!} · ${command} will not start`
              : issue.code === 'unrecognized_keys'
                ? `unknown key "${keyOf(path)}", ignored`
                : `"${keyOf(path)}": ${issue.message.toLowerCase()}, ignored`,
        });
      }
    }
  }

  return {
    settings: {},
    problems: [
      ...problems,
      { file, kind: 'parse', message: 'the file is ignored' },
    ],
  };
}

/**
 * Later settings win, key by key, agent by agent within `agents` and server
 * by server within `mcpServers`.
 */
export function mergeSettings(...layers: readonly Settings[]): Settings {
  const merged: Settings = {};

  for (const layer of layers) {
    if (layer.teamSelection !== undefined) {
      merged.teamSelection = mergeTeamSelection(
        merged.teamSelection,
        layer.teamSelection,
      );
    }

    if (layer.agent !== undefined) {
      merged.agent = layer.agent;
    }

    if (layer.preferredNotifChannel !== undefined) {
      merged.preferredNotifChannel = layer.preferredNotifChannel;
    }

    if (layer.theme !== undefined) {
      merged.theme = layer.theme;
    }

    if (layer.editorMode !== undefined) {
      merged.editorMode = layer.editorMode;
    }

    if (layer.mouse !== undefined) {
      merged.mouse = layer.mouse;
    }

    if (layer.copyOnSelect !== undefined) {
      merged.copyOnSelect = layer.copyOnSelect;
    }

    if (layer.offeredAgents !== undefined) {
      merged.offeredAgents = layer.offeredAgents;
    }

    if (layer.mcpServers !== undefined) {
      merged.mcpServers = { ...merged.mcpServers, ...layer.mcpServers };
    }

    for (const [name, agent] of Object.entries(layer.agents ?? {})) {
      merged.agents = {
        ...merged.agents,
        [name]: { ...merged.agents?.[name], ...agent },
      };
    }
  }

  return merged;
}

/** One file's settings, kept apart so a value can be traced to its file. */
export interface SettingsLayer {
  readonly file: string;
  readonly settings: Settings;
  /** The agents whose command this file gives was refused, with why. */
  readonly refused?: Readonly<Record<string, string>>;
}

/**
 * Reads the user's file, then the project's, which overrides it. A file that
 * is not there is no problem: most people have neither. A `theme`, an
 * `editorMode`, a `mouse`, a `copyOnSelect` or an `offeredAgents` in the project's file is a problem and is left out; `home` shows the user's file
 * from `~` in what it says.
 */
export async function loadSettings(where: {
  configHome: string | undefined;
  cwd: string;
  home?: string;
}): Promise<{
  settings: Settings;
  layers: SettingsLayer[];
  problems: SettingsProblem[];
}> {
  const layers: SettingsLayer[] = [];
  const problems: SettingsProblem[] = [];

  for (const file of settingsFiles(where)) {
    let text: string;

    try {
      text = await readFile(file, 'utf8');
    } catch (error) {
      if (notFound(error)) {
        continue;
      }

      problems.push({
        file,
        kind: 'read',
        message: `cannot be read (${
          error instanceof Error ? error.message : String(error)
        }); the file is ignored`,
      });

      continue;
    }

    const parsed = parseSettings(file, text);
    const user = userSettingsFile(where.configHome);
    const settings: Settings = { ...parsed.settings };

    problems.push(...parsed.problems);

    for (const key of file === user ? [] : USER_ONLY) {
      if (settings[key] === undefined) {
        continue;
      }

      delete settings[key];
      problems.push({
        file,
        kind: 'scope',
        key: [key],
        message: `"${key}" is read only from ${
          user === undefined
            ? "the user's settings file"
            : shownPath(user, { cwd: where.cwd, home: where.home })
        }, ignored`,
      });
    }

    layers.push({
      file,
      settings,
      ...(parsed.refused === undefined ? {} : { refused: parsed.refused }),
    });
  }

  return {
    settings: mergeSettings(...layers.map((layer) => layer.settings)),
    layers,
    problems,
  };
}

/** Fresh configuration for selected admission; direct runs keep their path. */
export type TeamSelectionPolicy =
  { readonly policy: TeamSelection } | { readonly error: string };

export async function readTeamSelection(
  where: Parameters<typeof loadSettings>[0],
): Promise<TeamSelectionPolicy> {
  const loaded = await loadSettings(where);
  const invalid = loaded.problems.some(
    (problem) =>
      problem.kind === 'read' ||
      problem.kind === 'parse' ||
      (problem.kind === 'validation' && problem.key?.[0] === 'teamSelection'),
  );

  return invalid
    ? {
        error:
          'Team selection settings could not be validated. Correct the settings before selecting a team.',
      }
    : { policy: loaded.settings.teamSelection ?? {} };
}

/** What the command line gave; anything left out falls back to the files. */
export interface Flags {
  readonly agent?: string | undefined;
  readonly agentCommand?: string | undefined;
  readonly model?: string | undefined;
  readonly effort?: string | undefined;
  readonly permissionMode?: string | undefined;
}

/**
 * A value and what set it: the flag's name, or the settings file's path, so
 * an agent's refusal can point at the place to change it.
 */
export interface Sourced {
  readonly id: string;
  readonly from: string;
}

/** Why an agent is not started: its command, refused in `file`. */
export interface Refusal {
  readonly file: string;
  /** `expected a string, got a number`. */
  readonly cause: string;
}

/** What chord starts with once flags, files and its own default are weighed. */
export interface Startup {
  readonly agent: string;
  readonly agentCommand?: string | string[];
  /**
   * A file gave a command for the agent that chord refused: nothing starts
   * on it, not even chord's own command, unless a flag gives one.
   */
  readonly refused?: Refusal;
  readonly model?: Sourced;
  readonly effort?: Sourced;
  readonly permissionMode?: Sourced;
  /** What the files set the agent's `mcpServers` to, where one does. */
  readonly mcpServers?: boolean;
}

/** The flag's value, else the last file's that set the agent's `key`. */
function sourced(
  flag: { name: string; value: string | undefined },
  layers: readonly SettingsLayer[],
  agent: string,
  key: 'model' | 'effort' | 'permissionMode',
): Sourced | undefined {
  if (flag.value !== undefined) {
    return { id: flag.value, from: flag.name };
  }

  const layer = layers.findLast(
    (layer) => layer.settings.agents?.[agent]?.[key] !== undefined,
  );
  const id = layer?.settings.agents?.[agent]?.[key];

  return layer === undefined || id === undefined
    ? undefined
    : { id, from: layer.file };
}

/**
 * A flag beats the files, and a later file an earlier one. The agent's other
 * settings are looked up under the agent chosen, whichever said it.
 */
export function resolveStartup(
  flags: Flags,
  layers: readonly SettingsLayer[],
  defaultAgent: string,
): Startup {
  const settings = mergeSettings(...layers.map((layer) => layer.settings));
  const agent = flags.agent ?? settings.agent ?? defaultAgent;
  const agentCommand = flags.agentCommand ?? settings.agents?.[agent]?.command;
  // The last file to give the agent a command decides, as every setting
  // merges: a refused one refuses the agent, never falling back to chord's
  // own, and a later good one replaces it (the lead, on the owner's Q52).
  const last = layers.findLast(
    (layer) =>
      layer.refused?.[agent] !== undefined ||
      layer.settings.agents?.[agent]?.command !== undefined,
  );
  const cause = last?.refused?.[agent];
  const refused =
    flags.agentCommand === undefined && cause !== undefined
      ? { file: last!.file, cause }
      : undefined;
  const model = sourced(
    { name: '--model', value: flags.model },
    layers,
    agent,
    'model',
  );
  const effort = sourced(
    { name: '--effort', value: flags.effort },
    layers,
    agent,
    'effort',
  );
  const permissionMode = sourced(
    { name: '--permission-mode', value: flags.permissionMode },
    layers,
    agent,
    'permissionMode',
  );

  return {
    agent,
    ...(refused === undefined
      ? agentCommand === undefined
        ? {}
        : { agentCommand }
      : { refused }),
    ...(model === undefined ? {} : { model }),
    ...(effort === undefined ? {} : { effort }),
    ...(permissionMode === undefined ? {} : { permissionMode }),
    ...(settings.agents?.[agent]?.mcpServers === undefined
      ? {}
      : { mcpServers: settings.agents[agent].mcpServers }),
  };
}

/** `codex not started: agents.codex.command in <file>: expected a string, …`. */
export function refusalLine(
  agent: string,
  { file, cause }: Refusal,
  shown: { readonly cwd: string; readonly home: string | undefined },
): string {
  return `${agent} not started: agents.${agent}.command in ${shownPath(file, shown)}: ${cause}`;
}

/**
 * What a session resumed from another directory starts with. The agent and
 * its command stay those that found the session; its model, effort and mode
 * come from the files where it works, as had chord been started there, and a
 * flag still beats them.
 */
export function resumedStartup(
  found: Startup,
  flags: Flags,
  layers: readonly SettingsLayer[],
): Startup {
  const { model, effort, permissionMode, mcpServers } = resolveStartup(
    { ...flags, agent: found.agent },
    layers,
    found.agent,
  );

  return {
    agent: found.agent,
    ...(found.agentCommand === undefined
      ? {}
      : { agentCommand: found.agentCommand }),
    ...(model === undefined ? {} : { model }),
    ...(effort === undefined ? {} : { effort }),
    ...(permissionMode === undefined ? {} : { permissionMode }),
    ...(mcpServers === undefined ? {} : { mcpServers }),
  };
}

/**
 * What a session of `agent` starts with in a window `invoked` started: the
 * window's own startup for its agent, flags and all; any other agent's
 * command, model, effort and mode from the files alone, as the flags were given for
 * the agent the command line named and their ids are that agent's. Whether
 * it takes MCP servers no flag says, so the files say it for every agent,
 * the window's own too (CHD-441).
 */
export function startupOf(
  agent: string,
  invoked: Startup,
  layers: readonly SettingsLayer[],
): Startup {
  if (agent !== invoked.agent) {
    return resolveStartup({ agent }, layers, agent);
  }

  const { mcpServers } = resolveStartup({ agent }, layers, agent);

  return mcpServers === undefined ? invoked : { ...invoked, mcpServers };
}

/**
 * Every agent a window started on `invoked` can open a session of, by name:
 * that one, those the settings files give a command, then `registry`'s.
 */
export function knownAgents(
  invoked: Startup,
  layers: readonly SettingsLayer[],
  registry: readonly string[],
): string[] {
  return [
    ...new Set([
      invoked.agent,
      ...Object.keys(agentCommands(layers)),
      ...registry,
    ]),
  ];
}

/** The command the settings files start each agent with, where one does. */
export function agentCommands(
  layers: readonly SettingsLayer[],
): Record<string, string | string[]> {
  const settings = mergeSettings(...layers.map((layer) => layer.settings));

  return Object.fromEntries(
    Object.entries(settings.agents ?? {}).flatMap(([name, { command }]) =>
      command === undefined ? [] : [[name, command]],
    ),
  );
}

/**
 * The problems in `found` not already in `seen`: both readings take in the
 * user's file, and its problems are said once.
 */
export function unseenProblems(
  seen: readonly SettingsProblem[],
  found: readonly SettingsProblem[],
): SettingsProblem[] {
  return found.filter(
    (problem) =>
      !seen.some(
        (old) => old.file === problem.file && old.message === problem.message,
      ),
  );
}

/**
 * A path as the window shows it: under the working directory relative to it,
 * as the header already names that directory; under the home directory from
 * `~`; elsewhere whole. A screen never shows the person's home path.
 */
export function shownPath(
  file: string,
  { cwd, home }: { cwd: string; home: string | undefined },
): string {
  const under = (dir: string) => {
    const path = relative(dir, file);

    return path === '' || path.startsWith('..') ? undefined : path;
  };

  const inCwd = under(cwd);

  return inCwd ?? homePath(file, home);
}

/**
 * A path shortened against the home directory alone: `~` for the home
 * directory itself, from `~` under it, elsewhere whole. Where every path is
 * shown the same way, as `/resume`'s directories are, none is relative to
 * the working directory.
 */
export function homePath(file: string, home: string | undefined): string {
  if (home === undefined) {
    return file;
  }

  const path = relative(home, file);

  return path === ''
    ? '~'
    : path.startsWith('..') || isAbsolute(path)
      ? file
      : `~${sep}${path}`;
}

/** Where a starting value was set, as a refusal says it. */
export function setWhere(
  from: string,
  where: { cwd: string; home: string | undefined },
): string {
  return from.startsWith('-')
    ? `set by ${from}`
    : `set in ${shownPath(from, where)}`;
}

/** A problem as the transcript says it, the file shown as the window shows paths. */
export function problemNote(
  { file, message }: SettingsProblem,
  where: { cwd: string; home: string | undefined },
): string {
  return `${shownPath(file, where)}: ${message}`;
}

/**
 * The names `offeredAgents` gives that chord lacks, one problem each: the
 * start screen's note may count some of them rather than name them.
 */
export function unknownOffered(
  file: string,
  unknown: readonly string[],
): SettingsProblem[] {
  return unknown.map((name) => ({
    file,
    kind: 'validation',
    key: ['offeredAgents'],
    message: `"offeredAgents": no agent named ${name}, left out`,
  }));
}

/** A problem as stderr says it, naming the file. */
export function problemLine({ file, message }: SettingsProblem): string {
  return `chord: ${file}: ${message}`;
}

/** Sets `theme` in the user's file, as `saveSetting` sets a key. */
export function saveTheme(file: string, theme: ThemeSetting): Promise<void> {
  return saveSetting(file, 'theme', theme);
}

/** Sets `editorMode` in the user's file, as `/vim` leaves it. */
export function saveEditorMode(file: string, mode: EditorMode): Promise<void> {
  return saveSetting(file, 'editorMode', mode);
}

/**
 * Sets one of the keys chord writes in the user's file, keeping every other
 * key where it is.
 */
function saveSetting<K extends (typeof USER_ONLY)[number]>(
  file: string,
  key: K,
  value: NonNullable<Settings[K]>,
): Promise<void> {
  return saveSettingAt(file, [key], { set: value });
}

/** What a write does at a settings path. */
export type SettingChange =
  { readonly set: unknown } | { readonly remove: true };

/** What the writer says with no file to write. */
export const NO_SETTINGS_HOME =
  'No settings file without a home directory; nothing was saved';

/**
 * Names that reach an object's prototype rather than a key of it, so no path
 * may hold them, whatever a file or a caller says.
 */
const NOT_KEYS: ReadonlySet<string> = new Set([
  '__proto__',
  'constructor',
  'prototype',
]);

/** Whether a path can name a setting at all, whichever setting it is. */
export function canBeSettingPath(path: readonly string[]): boolean {
  return path.length > 0 && !path.some((key) => NOT_KEYS.has(key));
}

function isJsonObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * A value as the person reads it: JSON, so it is what will be written and one
 * line, with what JSON leaves raw and a terminal would act on (DEL, C1, line
 * separators, bidi overrides) escaped too.
 */
export function shownValue(value: unknown): string {
  return (JSON.stringify(value) ?? 'null').replace(
    /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu,
    (mark) =>
      Array.from(
        { length: mark.length },
        (_, unit) =>
          `\\u${mark.charCodeAt(unit).toString(16).padStart(4, '0')}`,
      ).join(''),
  );
}

/** A path's keys joined by dots, a key with anything else in it as JSON. */
export function shownSettingPath(path: readonly string[]): string {
  return path
    .map((key) => (/^[A-Za-z0-9_-]+$/u.test(key) ? key : shownValue(key)))
    .join('.');
}

/**
 * The user's file as an object, empty when it is not there. What is wrong
 * with one that is there is thrown, in the words a refusal ends with.
 */
export async function readSettingsObject(
  file: string,
): Promise<Record<string, unknown>> {
  let text: string;

  try {
    text = await readFile(file, 'utf8');
  } catch (error) {
    if (notFound(error)) {
      return {};
    }

    throw error;
  }

  let parsed: unknown;

  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error('it is not valid JSON');
  }

  if (!isJsonObject(parsed)) {
    throw new Error('it is not a JSON object');
  }

  return parsed;
}

/** The value at `path`, by the object's own keys alone. */
export function settingAt(value: unknown, path: readonly string[]): unknown {
  let held = value;

  for (const key of path) {
    if (!isJsonObject(held) || !Object.hasOwn(held, key)) {
      return undefined;
    }

    held = held[key];
  }

  return held;
}

/**
 * Why `path` cannot be written in `settings`: the first parent there that is
 * not an object. It is not the value at the path, so neither a set nor a
 * remove replaces it or calls the key absent.
 */
export function settingParentProblem(
  settings: Record<string, unknown>,
  path: readonly string[],
): string | undefined {
  let held = settings;

  for (const [depth, key] of path.slice(0, -1).entries()) {
    if (!Object.hasOwn(held, key)) {
      return undefined;
    }

    const next = held[key];

    if (!isJsonObject(next)) {
      return `its ${shownSettingPath(path.slice(0, depth + 1))} is not an object; edit it by hand`;
    }

    held = next;
  }

  return undefined;
}

/** Sets the leaf at `path`, making the parents it lacks. */
function setAt(
  settings: Record<string, unknown>,
  path: readonly string[],
  value: unknown,
): void {
  let parent = settings;

  for (const key of path.slice(0, -1)) {
    if (!Object.hasOwn(parent, key)) {
      parent[key] = {};
    }

    parent = parent[key] as Record<string, unknown>;
  }

  parent[path.at(-1)!] = value;
}

/** Removes the leaf at `path` and the parents that leaves empty. */
function removeAt(
  settings: Record<string, unknown>,
  path: readonly string[],
): void {
  for (let depth = path.length; depth > 0; depth--) {
    const parent = settingAt(settings, path.slice(0, depth - 1)) as Record<
      string,
      unknown
    >;

    delete parent[path[depth - 1]!];

    if (Object.keys(parent).length > 0) {
      return;
    }
  }
}

/**
 * Sets or removes the leaf at `path` in the user's file, keeping every other
 * key: the file is read, changed, and the object written whole with two-space
 * indents to a file beside it that is renamed over the old, so a crash cannot
 * leave half a file. A missing file, and its directory, are made. A file that
 * is not a JSON object, or a parent on the path that is not one, is never
 * overwritten: the write is refused instead. Removing what is not there
 * writes nothing.
 */
export async function saveSettingAt(
  file: string | undefined,
  path: readonly string[],
  change: SettingChange,
): Promise<void> {
  if (file === undefined) {
    throw new Error(NO_SETTINGS_HOME);
  }

  if (!canBeSettingPath(path)) {
    throw new Error(`No setting ${shownSettingPath(path)}`);
  }

  const settings = await readSettingsObject(file);
  const problem = settingParentProblem(settings, path);

  if (problem !== undefined) {
    throw new Error(problem);
  }

  if ('set' in change) {
    setAt(settings, path, change.set);
  } else if (settingAt(settings, path) === undefined) {
    return;
  } else {
    removeAt(settings, path);
  }

  await mkdir(dirname(file), { recursive: true });

  const temporary = `${file}.${crypto.randomUUID()}.tmp`;

  try {
    await writeFile(temporary, `${JSON.stringify(settings, null, 2)}\n`);
    await rename(temporary, file);
  } catch (error) {
    await rm(temporary).catch(() => {});

    throw error;
  }
}
