/**
 * Runs one command in the session's directory through the user's shell —
 * bash mode's, or a monitor's — hands its output on as it comes, and stops
 * it, with whatever it started, on Esc or a monitor's stop.
 */
import process from 'node:process';
import { pipeline, type Readable } from 'node:stream';
import split from 'split2';
import {
  type Exit,
  type SignalName,
  spawnGroup,
  WINDOWS,
} from './platform/process.ts';

export interface ShellEnd {
  readonly code?: number;
  /** The signal that ended the shell, when it was not chord's stop. */
  readonly signal?: SignalName;
  readonly stopped?: boolean;
  readonly error?: string;
}

export interface ShellProcess {
  /** Stops the command and everything it started; idempotent. */
  stop(): void;
  /** Settles once its output has all been handed on; never rejects. */
  readonly ended: Promise<ShellEnd>;
  /**
   * Settles as the shell itself ends, before `ended` when what it started
   * still holds its output or is being reaped; never rejects.
   */
  readonly exited?: Promise<ShellEnd>;
  /**
   * That the shell itself did not start, known at once; why comes a tick
   * later, as `ended`'s error.
   */
  readonly failed?: string;
}

export interface ShellOptions {
  readonly cwd: string;
  /** The shell and the flag before the command; the user's own by default. */
  readonly shell?: readonly [string, ...string[]];
  /** Each piece of output as it comes, bash mode's. */
  readonly onOutput?: (stream: 'stdout' | 'stderr', text: string) => void;
  /**
   * Each line of stdout instead, a monitor's: split on `\n` or `\r\n`, a
   * lone `\r` kept in its line, the last one handed on without its end once
   * the command ends, and stderr not read at all.
   */
  readonly onLine?: (line: string) => void;
  /**
   * Whether what the command started goes with it when it ends on its own,
   * a monitor's: something that let go of the pipes would outlive the
   * monitor, and chord with it. Bash mode leaves it be.
   */
  readonly reap?: boolean;
}

/** How long a stopped command has to go before it is killed outright. */
const KILL_AFTER_MS = 2000;

/**
 * How long past the SIGKILL a stop waits for the group to be reaped: only
 * a process the kernel holds in an uninterruptible wait outlasts it.
 */
const GONE_AFTER_KILL_MS = 5000;

function defaultShell(): readonly [string, ...string[]] {
  return WINDOWS
    ? ['cmd.exe', '/d', '/s', '/c']
    : [process.env['SHELL'] || '/bin/sh', '-c'];
}

export function runShell(command: string, options: ShellOptions): ShellProcess {
  const [program, ...flags] = options.shell ?? defaultShell();
  const { onOutput, onLine } = options;
  // Its own process group, so a stop reaches what the shell started too: a
  // `sleep` left behind would hold the pipes open, and the run with them.
  const group = spawnGroup(program, [...flags, command], {
    cwd: options.cwd,
    stdin: 'ignore',
    stdout: 'pipe',
    stderr: onLine === undefined ? 'pipe' : 'ignore',
  });

  if (group.pid === undefined) {
    return {
      stop() {},
      ended: group.started.then(
        (): ShellEnd => ({}),
        (error: unknown): ShellEnd => ({ error: messageOf(error) }),
      ),
      failed: `${program} did not start`,
    };
  }

  const { child } = group;
  let stopped = false;
  let terminating = false;
  let killer: ReturnType<typeof setTimeout> | undefined;
  /** When the SIGKILL went to the group, once it has. */
  let killedAt: number | undefined;

  const kill = () => {
    killedAt = Date.now();

    group.signal('SIGKILL');
  };

  /** SIGTERM to the group, then SIGKILL to what is left; once. */
  const terminate = () => {
    if (terminating) {
      return;
    }

    terminating = true;

    if (group.signal('SIGTERM')) {
      killer = setTimeout(kill, KILL_AFTER_MS);
    } else {
      killedAt = Date.now();
    }
  };

  const output = Promise.all([
    onLine === undefined
      ? pipe(child.stdout, (text) => onOutput?.('stdout', text))
      : lines(child.stdout, onLine),
    onLine === undefined
      ? pipe(child.stderr, (text) => onOutput?.('stderr', text))
      : undefined,
  ]);
  const endOf = (exit: Exit): ShellEnd =>
    stopped
      ? { stopped }
      : exit.signal === undefined
        ? { code: exit.code }
        : { code: exit.code, signal: exit.signal };
  const failedWith = (error: unknown): ShellEnd =>
    stopped ? { stopped } : { error: messageOf(error) };
  const exited = group.exit.then(endOf, failedWith);

  /**
   * The shell and its pipes can end while something it started, which let
   * go of them and shrugged off SIGTERM, lives on in the group: a stop is
   * over only once the SIGKILL has had it too and it has been reaped.
   */
  const reaped = async <T>(end: T): Promise<T> => {
    if (!WINDOWS) {
      terminate();
      await groupGone();
    }

    return end;
  };

  const ended = (
    options.reap
      ? // A reaped command ends when its shell does, with that shell's code,
        // though what it started still holds stdout: that goes with the group,
        // and the output read to its end after.
        exited.then(reaped).then(async (end) => {
          await output.catch(() => undefined);

          return end;
        })
      : Promise.all([output, group.exit])
          .then(([, exit]) => endOf(exit), failedWith)
          .then((end) => (stopped ? reaped(end) : end))
  ).finally(() => clearTimeout(killer));

  /**
   * Until nothing is left in the group, reaped too, or long enough past the
   * SIGKILL that nothing ever will be. The wait counts from the SIGKILL
   * itself, not from when it was due: under load its timer fires late.
   */
  const groupGone = async () => {
    while (
      group.alive() &&
      (killedAt === undefined || Date.now() < killedAt + GONE_AFTER_KILL_MS)
    ) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  };

  return {
    stop() {
      if (stopped) {
        return;
      }

      stopped = true;

      terminate();
    },
    ended,
    exited,
  };
}

async function pipe(
  stream: Readable | null,
  onText: (text: string) => void,
): Promise<void> {
  for await (const text of stream?.setEncoding('utf8') ?? []) {
    onText(text as string);
  }
}

async function lines(
  stream: Readable | null,
  onLine: (line: string) => void,
): Promise<void> {
  if (stream === null) {
    return;
  }

  // pipeline, not pipe: a stdout that fails fails the lines too, where pipe
  // would leave them waiting for an end that never comes.
  for await (const line of pipeline(stream, split(), () => {})) {
    onLine(line as string);
  }
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
