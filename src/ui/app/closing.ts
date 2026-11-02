/**
 * Closing an agent of the session's and quitting: the status line's words
 * while the second press is waited for.
 */
import type { Busy } from '../../session/busy.ts';

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
