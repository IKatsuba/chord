/**
 * What each session holds: its working directory, its MCP servers, and the
 * model, mode and effort it runs with, with the config options that offer
 * them. Here rather than in `main.ts` because the scenarios that move a mode
 * read and write them too.
 */
import { EventEmitter, once } from 'node:events';
import * as acp from '@agentclientprotocol/sdk';
import {
  DIMCODE_PERMISSION,
  NO_CONFIG,
  NO_MODES,
  TOKENS_ONLY,
  UNPRICED_MODEL,
} from './options.ts';

/** Each session's working directory, which its commands run in. */
export const cwds = new Map<string, string>();

/** The MCP servers each session was opened with, as they arrived. */
export const mcpServers = new Map<string, acp.McpServer[]>();

/**
 * How each session was last opened: the request, and its `_meta` as it
 * arrived, none when it had none.
 */
export const openedWith = new Map<
  string,
  { readonly method: string; readonly meta?: unknown }
>();

/** Claude Code's first three modes, in its order. */
export const AVAILABLE_MODES: acp.SessionMode[] = [
  { id: 'default', name: 'Default' },
  { id: 'acceptEdits', name: 'Accept edits' },
  { id: 'plan', name: 'Plan' },
];

/** Each session's mode. */
export const modes = new Map<string, string>();
/** Each session's model, once one was asked for. */
export const models = new Map<string, string>();
/** Each session's effort, once one was asked for. */
export const efforts = new Map<string, string>();
/** Each session's dimcode `permission`, once moved from its start. */
export const permissions = new Map<string, string>();

/** dimcode's `permission` values, `read-only` refusing its agent tool. */
export const DIMCODE_PERMISSIONS = [
  { value: 'read-only', name: 'Read only' },
  { value: 'workspace-write', name: 'Workspace write' },
  { value: 'full-access', name: 'Full access' },
];

/** The efforts every session offers, `medium` until set. */
export const AVAILABLE_EFFORTS = [
  { value: 'low', name: 'Low' },
  { value: 'medium', name: 'Medium' },
  { value: 'high', name: 'High' },
];

/**
 * The models every session offers, the first in use until switched. With
 * real ones, the README's screenshots' two come after (CHD-407).
 */
export const AVAILABLE_MODELS = TOKENS_ONLY
  ? [
      { value: 'gpt-5.3-codex', name: 'GPT-5.3 Codex' },
      { value: 'claude-haiku-4-5', name: 'Claude Haiku 4.5' },
      { value: 'claude-opus-5-5', name: 'Claude Opus 5.5' },
      { value: 'gpt-6.1-sol', name: 'GPT-6.1 Sol' },
      ...(UNPRICED_MODEL
        ? [{ value: 'fake-unpriced', name: 'Fake Unpriced' }]
        : []),
    ]
  : [
      { value: 'fake-large', name: 'Fake Large with a 1M context window' },
      { value: 'fake-small', name: 'Fake Small' },
    ];

export const FIRST_MODEL = AVAILABLE_MODELS[0]?.value ?? 'fake-large';
export const locked = new Set<string>();

/** Each session's cost so far, in USD, as its usage updates have said it. */
export const costs = new Map<string, number>();

/**
 * Says each session's id as a `_session/steering` request for it arrives,
 * before it is answered, for a turn that waits on a message steered in.
 */
export const steers = new EventEmitter();

/**
 * Listens, from now, for a message steered into session `sessionId`, so
 * one that comes before the wait is not missed: `steered` settles once one
 * has, and rejects once `signal` aborts or `stop` is called, which also
 * stops listening. Its rejection is handled here, so a turn that ends before
 * awaiting it raises none.
 */
export function steeredInto(
  sessionId: string,
  signal: AbortSignal,
): { readonly steered: Promise<unknown>; stop(): void } {
  const done = new AbortController();
  const steered = once(steers, sessionId, {
    signal: AbortSignal.any([signal, done.signal]),
  });

  steered.catch(() => {});

  return { steered, stop: () => done.abort() };
}

/**
 * How many `session/cancel`s each session got with no turn of its playing,
 * which `cancels` tells.
 */
export const strayCancels = new Map<string, number>();

/**
 * A model, the modes and an effort chosen through config options, as current
 * ACP agents send them; the modes also go the older way, in `session/new`'s
 * `modes`.
 */
export function configOptions(sessionId: string): acp.SessionConfigOption[] {
  const effort: acp.SessionConfigOption[] = NO_CONFIG
    ? []
    : [
        {
          id: 'effort',
          name: 'Effort',
          category: 'thought_level',
          type: 'select',
          currentValue: efforts.get(sessionId) ?? 'medium',
          options: AVAILABLE_EFFORTS,
        },
      ];

  const mode: acp.SessionConfigOption[] = NO_MODES
    ? []
    : [
        {
          id: 'mode',
          name: 'Mode',
          category: 'mode',
          type: 'select',
          currentValue: modes.get(sessionId) ?? 'default',
          options: AVAILABLE_MODES.map(({ id, name }) => ({ value: id, name })),
        },
      ];

  // dimcode's own option, with no category, as dimcode sends it (CHD-434).
  const permission: acp.SessionConfigOption[] =
    DIMCODE_PERMISSION === undefined
      ? []
      : [
          {
            id: 'permission',
            name: 'Permission',
            type: 'select',
            currentValue: permissions.get(sessionId) ?? DIMCODE_PERMISSION,
            options: DIMCODE_PERMISSIONS,
          },
        ];

  return [
    {
      id: 'model',
      name: 'Model',
      category: 'model',
      type: 'select',
      currentValue: models.get(sessionId) ?? FIRST_MODEL,
      options: AVAILABLE_MODELS,
    },
    ...mode,
    ...effort,
    ...permission,
  ];
}
