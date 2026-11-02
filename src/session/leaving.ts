/**
 * One way out of a process that runs agents with no window, once, whatever
 * starts it, inside one deadline.
 */
import { settledWithin } from '../acp/process.ts';
import { killSpawnedGroups, type SignalName } from '../platform/process.ts';

/**
 * One agent takes at most 6 s to stop, and a conversation awaits its tasks
 * before its own session, so a hung task and a hung main take 12 s.
 */
export const LEAVE_MS = 15_000;

/** The most the answers to a client that may not be reading are waited for. */
export const DRAIN_MS = 500;

/** What started the way out. */
export type LeaveReason =
  /** The client closed stdin, or went. */
  | { readonly kind: 'eof' }
  /** The connection can no longer serve: an oversized line, stdout gone. */
  | { readonly kind: 'broken' }
  /** chord's own failure; the client is still there to be answered. */
  | { readonly kind: 'crash' }
  | { readonly kind: 'signal'; readonly signal: SignalName };

/** How the process ends. */
export type LeaveExit =
  { readonly code: number } | { readonly signal: SignalName };

/** Something to settle on the way out, beside the rest. */
export interface LeaveStep {
  /** Named on stderr when it failed, or had not settled at the deadline. */
  readonly name: string;
  run(): Promise<void> | void;
}

export interface LeaveOptions {
  /** Sends what the turn table gives for closing; only to a live connection. */
  answer(): void;
  /** Settles once those answers are written; best effort. */
  drained(): Promise<void>;
  /** Closes the connection, which has no drain of its own. */
  closeConnection(): Promise<void> | void;
  /** Each host's stop, and what else there is to close. */
  readonly steps: readonly LeaveStep[];
  /** One line for the person; must not throw into the way out. */
  stderr(line: string): void;
  /** Ends the process. */
  exit(how: LeaveExit): void;
  readonly leaveMs?: number;
  readonly drainMs?: number;
}

/** The one way out, and whether it has begun. */
export interface Leaving {
  /** New work is refused from the moment this holds. */
  started(): boolean;
  /** Runs it, once; a later call gets the first one's promise. */
  leave(reason: LeaveReason): Promise<void>;
}

export function createLeaving(options: LeaveOptions): Leaving {
  let leaving: Promise<void> | undefined;

  return {
    started: () => leaving !== undefined,
    leave: (reason) => {
      if (leaving !== undefined) {
        return leaving;
      }

      // Held before it runs: what it calls may ask or start it again.
      const { promise, resolve } = Promise.withResolvers<void>();

      leaving = promise;

      leave(reason, options, resolve);

      return promise;
    },
  };
}

function leave(
  reason: LeaveReason,
  options: LeaveOptions,
  resolve: () => void,
): void {
  const say = (line: string) => {
    try {
      options.stderr(line);
    } catch {
      // Nothing is left to tell, and the way out goes on.
    }
  };

  const open = new Set<string>();
  const failures: string[] = [];
  let ended = false;

  const end = (how: LeaveExit) => {
    ended = true;

    clearTimeout(deadline);

    options.exit(how);
    resolve();
  };

  // Armed first, so nothing below can hold the process past it.
  const deadline = setTimeout(() => {
    if (ended) {
      return;
    }

    say(`chord: not settled at the deadline: ${[...open].join(', ')}`);

    for (const pid of killSpawnedGroups()) {
      say(`chord: killed process group ${pid}`);
    }

    end(exitOf(reason, true));
  }, options.leaveMs ?? LEAVE_MS);

  const failed = (name: string, error: unknown) => {
    failures.push(name);

    say(
      `chord: ${name}: ${error instanceof Error ? error.message : String(error)}`,
    );
  };

  if (reason.kind === 'signal' || reason.kind === 'crash') {
    try {
      options.answer();
    } catch (error) {
      failed('answers', error);
    }
  }

  const connection: LeaveStep = {
    name: 'connection',
    run: async () => {
      await settledWithin(
        Promise.resolve().then(() => options.drained()),
        options.drainMs ?? DRAIN_MS,
      );
      await options.closeConnection();
    },
  };
  const steps = [connection, ...options.steps];

  // Each starts here, in this one tick, so a hung one holds up none of the
  // rest, and a failed one is kept beside what the others do.
  const settled = steps.map(async (step) => {
    open.add(step.name);

    try {
      await step.run();
    } catch (error) {
      failed(step.name, error);
    }

    open.delete(step.name);
  });

  void Promise.all(settled).then(() => {
    if (ended) {
      return;
    }

    killSpawnedGroups();
    end(exitOf(reason, failures.length > 0));
  });
}

function exitOf(reason: LeaveReason, unclean: boolean): LeaveExit {
  if (reason.kind === 'signal') {
    return { signal: reason.signal };
  }

  return { code: reason.kind === 'eof' && !unclean ? 0 : 1 };
}
