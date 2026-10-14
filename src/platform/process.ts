/**
 * Processes as chord starts and stops them, on `node:child_process`: a child
 * in a process group of its own, so a signal reaches whatever it started too,
 * and the binary's own path.
 */
import { type ChildProcess, type IOType, spawn } from 'node:child_process';
import { constants } from 'node:os';
import process from 'node:process';

/** Windows has no process groups; a signal there reaches the child alone. */
export const WINDOWS = process.platform === 'win32';

/** A signal by name, as `kill(1)` and an exit name them. */
export type SignalName = NodeJS.Signals;

/** How a process ended. */
export interface Exit {
  /**
   * Its exit code, or, when a signal ended it, 128 and the signal's number,
   * as a shell's `$?` reads it.
   */
  readonly code: number;
  readonly signal?: SignalName;
}

export interface GroupOptions {
  readonly cwd: string;
  /** Laid over chord's own environment for the child alone. */
  readonly env?: Readonly<Record<string, string>>;
  readonly stdin: IOType;
  readonly stdout: IOType;
  readonly stderr: IOType;
}

/** A child leading a process group of its own. */
export interface GroupProcess {
  /** Its stdio; a stream is `null` where its option is not `pipe`. */
  readonly child: ChildProcess;
  /** Undefined when it did not start. */
  readonly pid: number | undefined;
  /**
   * Settles once it is running; rejects with why it did not start, which
   * comes a tick after `pid` already said so.
   */
  readonly started: Promise<void>;
  /** Settles once it exits; rejects as `started` does. */
  readonly exit: Promise<Exit>;
  /** Signals its group; whether anything in it was there to take it. */
  signal(name: SignalName): boolean;
  /**
   * Whether anything is left in its group: a process that has died but is
   * not reaped yet counts, so a wait on this lasts until the reaping.
   */
  alive(): boolean;
}

/**
 * Starts `program` leading a process group of its own, so that a signal to
 * the group reaches what it started too: npx's adapter, a shell's `sleep`.
 */
export function spawnGroup(
  program: string,
  args: readonly string[],
  options: GroupOptions,
): GroupProcess {
  const child = spawn(program, args, {
    cwd: options.cwd,
    env: { ...process.env, ...options.env },
    stdio: [options.stdin, options.stdout, options.stderr],
    detached: !WINDOWS,
    windowsHide: true,
  });
  const failed = new Promise<never>((_, reject) => {
    child.once('error', reject);
  });

  const started = Promise.race([
    new Promise<void>((resolve) => child.once('spawn', resolve)),
    failed,
  ]);
  const exit = Promise.race([
    new Promise<Exit>((resolve) =>
      child.once('exit', (code, signal) =>
        resolve(exitOf(code, signal as SignalName | null)),
      ),
    ),
    failed,
  ]);

  // A pipe the child closed fails a write with EPIPE; unheard, that error
  // would end chord. The exit is what tells of it.
  for (const stream of [child.stdin, child.stdout, child.stderr]) {
    stream?.on('error', () => {});
  }

  // Each is someone's to await, or not: an agent's start is, a shell's exit
  // may never be.
  started.catch(() => {});

  exit.catch(() => {});

  const { pid } = child;
  const send = (name: SignalName | 0): boolean => {
    if (pid === undefined) {
      return false;
    }

    if (WINDOWS) {
      return name === 0 ? process.kill(pid, 0) : child.kill(name);
    }

    return process.kill(-pid, name);
  };

  return {
    child,
    pid,
    started,
    exit,
    signal: (name) => {
      try {
        return send(name);
      } catch {
        return false;
      }
    },
    alive: () => {
      try {
        return send(0);
      } catch (error) {
        // macOS refuses even signal 0 to a group left with only processes
        // that died and wait to be reaped, where none at all is ESRCH.
        return (error as NodeJS.ErrnoException).code === 'EPERM';
      }
    },
  };
}

function exitOf(code: number | null, signal: SignalName | null): Exit {
  return signal === null
    ? { code: code ?? 1 }
    : { code: 128 + (constants.signals[signal] ?? 0), signal };
}

/**
 * The program running chord: `bun` running the source, or the compiled
 * binary itself.
 */
export function execPath(): string {
  return process.execPath;
}
