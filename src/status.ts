/**
 * What chord tells the terminal it is doing: one root record of the Program
 * Status Protocol (OSC 7501), which OpenTUI's `setProgramStatus` writes, for
 * every agent of every tab at once (CHD-382, the owner's Q68).
 */

import type { ProgramStatus, ProgramStatusKind } from '@opentui/core';
import { type AskingWait, waitMessage } from './notify.ts';
import {
  type Failure,
  failureOf,
  notifiedName,
  type TabWait,
  type Tabs,
} from './session/tabs.ts';

/** The protocol's states that one agent can be in. */
type AgentState = 'blocked' | 'error' | 'working' | 'done' | 'idle';

/** Which agent's state the record takes, the first first (Q68, Q74). */
const ORDER: readonly AgentState[] = [
  'blocked',
  'error',
  'working',
  'done',
  'idle',
];

/** Every report names chord, as a report replaces its record whole. */
const APP = 'chord';

/** The most a message may take, in UTF-8 bytes, as the protocol bounds it. */
export const MESSAGE_BYTES = 2048;

interface AgentStatus {
  readonly state: AgentState;
  readonly kind?: ProgramStatusKind;
  readonly failure?: Failure;
  readonly asking?: AskingWait;
  /** Since when, which of several in one state is the oldest. */
  readonly since: number;
  readonly key: number;
}

/** What one wait on the person is, as the protocol's kinds name it. */
function kindOf(wait: AskingWait): ProgramStatusKind {
  return wait.kind === 'permission'
    ? 'permission'
    : wait.mode === 'url'
      ? 'auth'
      : 'question';
}

/**
 * One agent's state: asked something; failed or gone; a turn running; a
 * turn ended that the person has not seen; else idle. A monitor or task
 * running between turns leaves it idle (Q69).
 */
function agentStatus(wait: TabWait, key: number): AgentStatus {
  if (wait.asking !== undefined) {
    return {
      state: 'blocked',
      kind: kindOf(wait.asking.on),
      asking: wait.asking.on,
      since: wait.asking.since,
      key,
    };
  }

  const failure = wait.exited
    ? 'exited'
    : (failureOf(wait) ?? wait.ended?.failure);

  if (failure !== undefined) {
    return {
      state: 'error',
      failure,
      since: wait.unseen?.since ?? wait.stopped ?? 0,
      key,
    };
  }

  if (wait.working !== undefined) {
    return { state: 'working', since: wait.working, key };
  }

  if (wait.unseen?.kind === 'replied' || wait.ended !== undefined) {
    return {
      state: 'done',
      since: wait.unseen?.since ?? wait.stopped ?? 0,
      key,
    };
  }

  return { state: 'idle', since: 0, key };
}

/** What the record says of an agent's failure. */
function failureMessage(failure: Failure, agent: string): string {
  return failure === 'exited'
    ? `${agent} exited`
    : failure === 'start'
      ? `${agent} failed to start`
      : `${agent}'s turn failed`;
}

/**
 * `text` as one line the protocol takes: every control character a space,
 * as a notification's text is, and cut to `MESSAGE_BYTES` on a character's
 * edge, so `setProgramStatus` never refuses it.
 */
export function messageLine(text: string): string {
  // eslint-disable-next-line no-control-regex
  const flat = text.replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ');
  const encoder = new TextEncoder();
  let bytes = 0;
  let cut = '';

  for (const character of flat) {
    bytes += encoder.encode(character).length;

    if (bytes > MESSAGE_BYTES) {
      break;
    }

    cut += character;
  }

  return cut;
}

/**
 * The root record for every agent of every tab: the first state in `ORDER`
 * any of them is in, and of those in it, the one the attention order would
 * name first, waiting longest, then further left. Only blocked, done and
 * error say why, as a notification would (Q71).
 */
export function programStatus<C>(tabs: Tabs<C>): ProgramStatus {
  const all = tabs.tabs
    .flatMap((tab) => [tab, ...tab.children])
    .map(({ key, wait }) => agentStatus(wait, key));
  const state =
    ORDER.find((each) => all.some((agent) => agent.state === each)) ?? 'idle';
  const first = all
    .filter((agent) => agent.state === state)
    .sort((a, b) => a.since - b.since || a.key - b.key)[0];

  if (first === undefined || state === 'idle' || state === 'working') {
    return { state, app: APP };
  }

  const name = notifiedName(tabs, first.key) ?? '';
  const message =
    first.asking !== undefined
      ? waitMessage(first.asking, name)
      : first.failure !== undefined
        ? failureMessage(first.failure, name)
        : waitMessage({ kind: 'turn_ended' }, name);

  return state === 'blocked'
    ? {
        state,
        app: APP,
        ...(first.kind === undefined ? {} : { kind: first.kind }),
        message: messageLine(message),
      }
    : { state, app: APP, message: messageLine(message) };
}

/** Every field a report may carry. */
const FIELDS = [
  'state',
  'id',
  'app',
  'title',
  'message',
  'kind',
  'progress',
] as const;

/** Whether two reports say the same, so a caller sends only a change. */
export function sameStatus(a: ProgramStatus, b: ProgramStatus): boolean {
  const field = (status: ProgramStatus, name: (typeof FIELDS)[number]) =>
    (status as Partial<Record<(typeof FIELDS)[number], unknown>>)[name];

  return FIELDS.every((name) => field(a, name) === field(b, name));
}
