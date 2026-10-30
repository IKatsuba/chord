import type { z } from '@zod/zod';
import { TeamSelection } from './session/budgets.ts';
import {
  AGENT_SETTING_SCHEMAS,
  canBeSettingPath,
  SETTING_SCHEMAS,
  type SettingChange,
  shownSettingPath,
  shownValue,
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
