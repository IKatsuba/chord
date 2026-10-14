/**
 * Closing a session and quitting with several open: what makes a session
 * busy, so that closing or quitting it asks for a second press, and the
 * status line's words while that press is waited for.
 */
import stringWidth from 'string-width';
import { askedInput } from '../dialogs/state.ts';
import { mine } from '../prompt/queue.ts';
import type { SessionState } from './state.ts';

/**
 * Why a session is busy, the most pressing reason first: a person is asked
 * for something, prompts wait behind the turn, task agents it started run,
 * or those and its long-lived agents at work, or the turn or a bash-mode
 * command runs. The agents come before the turn as they say more: closing
 * would stop them too.
 */
export type Busy =
  | { readonly kind: 'permission' }
  | { readonly kind: 'input' }
  | { readonly kind: 'queued'; readonly count: number }
  | { readonly kind: 'tasks'; readonly count: number }
  | { readonly kind: 'agents'; readonly count: number }
  | { readonly kind: 'working' };

/** How many task agents the session started are still running. */
export function runningTasks(transcript: SessionState['transcript']): number {
  return transcript.entries.filter(
    (entry) =>
      entry.kind === 'subagent' &&
      entry.subagent.task !== undefined &&
      entry.subagent.state === 'running',
  ).length;
}

/** A busy session as the armed lines name it: its tab's number and agent. */
export interface BusyTab {
  readonly number: number;
  readonly agent: string;
  readonly busy: Busy;
}

/** Why closing `session` would cut something short; none while it is idle. */
export function busyOf(
  session: Pick<SessionState, 'transcript' | 'queue'>,
): Busy | undefined {
  const { transcript, queue } = session;

  if (transcript.turn.status === 'awaiting_permission') {
    return { kind: 'permission' };
  }

  if (askedInput(transcript) !== undefined) {
    return { kind: 'input' };
  }

  // The person's own; a message queued goes with the work that sent it.
  const prompts = mine(queue).length;

  if (prompts > 0) {
    return { kind: 'queued', count: prompts };
  }

  const tasks = runningTasks(transcript);

  if (tasks > 0) {
    return { kind: 'tasks', count: tasks };
  }

  // A bash-mode command the session ran is its work as much as a turn is.
  const commandRuns = transcript.entries.some(
    (entry) => entry.kind === 'shell' && entry.run.running,
  );

  return transcript.turn.status === 'idle' && !commandRuns
    ? undefined
    : { kind: 'working' };
}

/**
 * Why a tab is busy, its long-lived children's work counted with its own: a
 * child that waits on the person is the tab waiting, and a child at work is
 * an agent working beside its task agents; none when closing it cuts
 * nothing short. An idle child loses nothing: its record stays.
 */
export function tabBusy(
  main: Pick<SessionState, 'transcript' | 'queue'>,
  children: readonly Pick<SessionState, 'transcript' | 'queue'>[],
): Busy | undefined {
  const own = busyOf(main);
  const theirs = children.map(busyOf).filter((busy) => busy !== undefined);

  for (const kind of ['permission', 'input'] as const) {
    if (own?.kind === kind || theirs.some((busy) => busy.kind === kind)) {
      return { kind };
    }
  }

  if (own?.kind === 'queued' || theirs.length === 0) {
    return own;
  }

  return {
    kind: 'agents',
    count: runningTasks(main.transcript) + theirs.length,
  };
}

/**
 * What the session is doing, after its name; the close line, about the one
 * on screen, says whose permission it waits for.
 */
function doing(busy: Busy, { yours }: { readonly yours: boolean }): string {
  switch (busy.kind) {
    case 'permission':
      return yours ? 'waits for your permission' : 'waits for permission';
    case 'input':
      return 'asks for input';
    case 'queued':
      return `has ${busy.count} ${
        busy.count === 1 ? 'prompt' : 'prompts'
      } queued`;
    case 'tasks':
      return `has ${busy.count} task ${
        busy.count === 1 ? 'agent' : 'agents'
      } running`;
    case 'agents':
      return `has ${busy.count} ${
        busy.count === 1 ? 'agent' : 'agents'
      } working`;
    case 'working':
      return 'is working';
  }
}

function named(tab: BusyTab): string {
  return `${tab.number} ${tab.agent}`;
}

/** The line a first `ctrl+x k` on a busy session leaves: `key` closes it. */
export function closeArmedLine(tab: BusyTab, key: string): string {
  return `${named(tab)} ${doing(tab.busy, {
    yours: true,
  })} · ${key} again to stop ${
    (tab.busy.kind === 'tasks' || tab.busy.kind === 'agents') &&
    tab.busy.count > 1
      ? 'them'
      : 'it'
  } and close`;
}

/**
 * The line a first `x` on a busy child in the list leaves: `parser is
 * working · x again to stop it and close`.
 */
export function agentCloseArmedLine(
  name: string,
  busy: Busy,
  key: string,
): string {
  return (
    `${name} ${doing(busy, { yours: true })} · ${key} again to stop it ` +
    'and close'
  );
}

/**
 * The line a first `x` on a busy team's lead leaves, its members closing
 * with it: `bugfix and its 3 members are working · x again to stop them and
 * close`.
 */
export function teamCloseArmedLine(
  name: string,
  members: number,
  key: string,
): string {
  return `${name} and its ${
    members === 1 ? 'member' : `${members} members`
  } are working · ${key} again to stop them and close`;
}

function sessionsBusy(count: number, { are }: { readonly are: boolean }) {
  return count === 1
    ? `1 session ${are ? 'is ' : ''}busy`
    : `${count} sessions ${are ? 'are ' : ''}busy`;
}

/**
 * The line a first ctrl+d or `/exit` leaves while sessions are busy: each
 * named with what it does, or, where that does not fit `width`, their count.
 */
export function quitArmedLine(busy: readonly BusyTab[], width: number): string {
  const again = ' · ctrl+d again to quit';

  // The sessions may have settled since the first press.
  if (busy.length === 0) {
    return 'Press ctrl+d again to quit';
  }

  const each = busy
    .map((tab) => `${named(tab)} ${doing(tab.busy, { yours: false })}`)
    .join(', ');
  const wide =
    busy.length === 1
      ? `${each}${again}`
      : `${sessionsBusy(busy.length, { are: true })}: ${each}${again}`;

  return stringWidth(wide) <= width
    ? wide
    : `${sessionsBusy(busy.length, { are: false })}${again}`;
}

/** ctrl+c's armed line, with the busy sessions counted once there are any. */
export function ctrlCArmedLine(busy: number): string {
  const line = 'Press ctrl+c again to quit';

  return busy === 0 ? line : `${line} · ${sessionsBusy(busy, { are: false })}`;
}
