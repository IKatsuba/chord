/**
 * Closing an agent of the session's and quitting: what makes an agent busy,
 * so that closing it asks for a second press, and the status line's words
 * while that press is waited for.
 */
import { askedInput } from '../dialogs/state.ts';
import { mine } from '../prompt/queue.ts';
import type { SessionState } from './state.ts';

/**
 * Why a session is busy, the most pressing reason first: a person is asked
 * for something, prompts wait behind the turn, task agents it started run,
 * or the turn or a bash-mode command runs. The tasks come before the turn
 * as they say more: closing would stop them too.
 */
export type Busy =
  | { readonly kind: 'permission' }
  | { readonly kind: 'input' }
  | { readonly kind: 'queued'; readonly count: number }
  | { readonly kind: 'tasks'; readonly count: number }
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

/** What the agent is doing, after its name. */
function doing(busy: Busy): string {
  switch (busy.kind) {
    case 'permission':
      return 'waits for your permission';
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
    case 'working':
      return 'is working';
  }
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
  return `${name} ${doing(busy)} · ${key} again to stop it ` + 'and close';
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

/** ctrl+c's armed line. */
export function ctrlCArmedLine(): string {
  return 'Press ctrl+c again to quit';
}
