/**
 * What chord tells the terminal it is doing: one root record of the Program
 * Status Protocol (OSC 7501), which OpenTUI's `setProgramStatus` writes, for
 * every agent of the window at once (CHD-382, the owner's Q68).
 */

import type { ProgramStatus, ProgramStatusKind } from '@opentui/core';
import { type AskingWait, waitMessage } from './notify.ts';
import { type AgentWait, type Failure, failureOf } from './session/waits.ts';
import { notifiedName, type WindowAgents } from './session/window_agents.ts';

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

/**
 * The most a title may take, in UTF-8 bytes: 256 once base64-encoded, as it
 * goes on the wire; OpenTUI refuses a longer one (CHD-491).
 */
export const TITLE_BYTES = 192;

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
function agentStatus(wait: AgentWait, key: number): AgentStatus {
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
 * `text` as one line the protocol takes in a field of `limit` UTF-8 bytes:
 * every control character a space, as a notification's text is, and cut on
 * a character's edge, a joined emoji or an accent kept whole, so
 * `setProgramStatus` never refuses it.
 */
export function statusLine(text: string, limit: number): string {
  // eslint-disable-next-line no-control-regex
  const flat = text.replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ');
  const encoder = new TextEncoder();
  let bytes = 0;
  let cut = '';

  for (const { segment } of new Intl.Segmenter().segment(flat)) {
    bytes += encoder.encode(segment).length;

    if (bytes > limit) {
      break;
    }

    cut += segment;
  }

  return cut;
}

/** `text` as the record's message takes it. */
export function messageLine(text: string): string {
  return statusLine(text, MESSAGE_BYTES);
}

/**
 * The root record for every agent of the window: the first state in
 * `ORDER` any of them is in, and of those in it, the one the attention order
 * would name first, waiting longest, then main, then the list's order. Only blocked, done and
 * error say why, as a notification would (Q71). `title` names the main
 * session, as the person knows it; none while it has no name (CHD-491).
 */
export function programStatus<C>(
  agents: WindowAgents<C>,
  title?: string,
): ProgramStatus {
  const cut = title === undefined ? '' : statusLine(title, TITLE_BYTES);
  const named = cut.trim() === '' ? {} : { title: cut };
  const all = [
    ...(agents.main === undefined ? [] : [agents.main]),
    ...agents.children,
  ].map(({ key, wait }) => agentStatus(wait, key));
  const state =
    ORDER.find((each) => all.some((agent) => agent.state === each)) ?? 'idle';
  const first = all
    .filter((agent) => agent.state === state)
    .sort((a, b) => a.since - b.since || a.key - b.key)[0];

  if (first === undefined || state === 'idle' || state === 'working') {
    return { state, app: APP, ...named };
  }

  const name = notifiedName(agents, first.key) ?? '';
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
        ...named,
        ...(first.kind === undefined ? {} : { kind: first.kind }),
        message: messageLine(message),
      }
    : { state, app: APP, ...named, message: messageLine(message) };
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
