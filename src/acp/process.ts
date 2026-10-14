import { Readable } from 'node:stream';
import { parse } from 'shell-quote';
import { type Exit, spawnGroup, WINDOWS } from '../platform/process.ts';

/**
 * How long each step of a stop waits for the agent's exit before the next,
 * harder one: stdin ended, then SIGTERM to its group, then SIGKILL.
 */
export interface StopBounds {
  /** After stdin ends, which is how ACP tells an agent over stdio to go. */
  readonly exitMs?: number;
  /** After SIGTERM. */
  readonly termMs?: number;
  /** After SIGKILL, for the exit to be seen at all. */
  readonly killMs?: number;
}

const STOP_BOUNDS: Required<StopBounds> = {
  exitMs: 2000,
  termMs: 2000,
  killMs: 2000,
};

/** Thrown when an agent's exit was not seen even after it was killed. */
export class AgentExitError extends Error {
  constructor(readonly pids: readonly number[]) {
    super(`Agent process ${pids.join(', ')} did not exit after SIGKILL.`);

    this.name = 'AgentExitError';
  }
}

/** One agent process, its stdio and the one way it is stopped. */
export interface AgentProcess {
  readonly pid: number;
  /** What chord writes to the agent; the only writer stdin has. */
  readonly stdin: WritableStream<Uint8Array>;
  readonly stdout: ReadableStream<Uint8Array>;
  /** Settles once the agent's exit is seen, however it came. */
  readonly status: Promise<Exit>;
  /** The end of what it wrote to stderr, for a start that failed. */
  stderrTail(): string;
  /**
   * Stops it within the bounds whatever it answers, and returns once its exit
   * is seen; rejects with `AgentExitError` if that exit is not seen even after
   * SIGKILL. Idempotent.
   */
  stop(bounds?: StopBounds): Promise<void>;
}

export interface SpawnAgentOptions {
  /** A string is split as a shell would split it, without expanding anything. */
  readonly command: string | readonly string[];
  /** Laid over chord's own environment for the agent alone. */
  readonly env?: Readonly<Record<string, string>>;
  readonly cwd: string;
  /** Each piece of the agent's stderr as it comes; it never reaches the screen. */
  readonly onStderr?: (text: string) => void;
}

/** How much of the agent's stderr is kept for an error that quotes it. */
const STDERR_TAIL = 4096;

/**
 * The argv a command names. A command line is split by shell-quote as a shell
 * would, with `$NAME` left as written, since the shell that would expand it
 * already did for a flag, and a settings file names no shell.
 */
export function commandArgv(
  command: string | readonly string[],
): [string, ...string[]] {
  const words =
    typeof command === 'string'
      ? parse(command, (name) => `$${name}`).map((word) => {
          if (typeof word !== 'string') {
            throw new Error(
              `The agent command "${command}" holds shell syntax; ` +
                'give a plain command line.',
            );
          }

          return word;
        })
      : [...command];
  const [program, ...args] = words;

  if (program === undefined || program === '') {
    throw new Error('The agent command is empty.');
  }

  return [program, ...args];
}

/**
 * Starts an agent in a process group of its own, so a stop reaches what it
 * started too: npx starts the adapter as a child, and the adapter its tools.
 * Rejects once it is known not to have started.
 */
export async function spawnAgent(
  options: SpawnAgentOptions,
): Promise<AgentProcess> {
  const [program, ...args] = commandArgv(options.command);
  const group = spawnGroup(program, args, {
    cwd: options.cwd,
    ...(options.env === undefined ? {} : { env: options.env }),
    stdin: 'pipe',
    stdout: 'pipe',
    stderr: 'pipe',
  });

  try {
    await group.started;
  } catch (error) {
    throw new Error(
      `cannot start ${program}: ${
        error instanceof Error ? error.message : String(error)
      }`,
      { cause: error },
    );
  }

  const { child, exit } = group;
  const pid = group.pid ?? 0;
  let exited = false;
  const status = exit.finally(() => {
    exited = true;
  });

  let tail = '';

  child.stderr?.setEncoding('utf8').on('data', (text: string) => {
    tail = (tail + text).slice(-STDERR_TAIL);

    options.onStderr?.(text);
  });

  // stdin is ended on the child's own stream, past this one, so a stop ends
  // it even while a write the agent never reads is still waiting.
  const input = child.stdin;
  const stdin = new WritableStream<Uint8Array>({
    write: (chunk) =>
      new Promise<void>((resolve, reject) => {
        input?.write(chunk, (error) => (error ? reject(error) : resolve()));
      }),
    close: () =>
      new Promise<void>((resolve) => {
        input?.end(resolve);
      }),
    abort: () => {
      input?.destroy();
    },
  });
  // `node:stream/web`'s stream is the global one at run time; only the
  // types name them apart.
  const stdout = child.stdout
    ? (Readable.toWeb(child.stdout) as unknown as ReadableStream<Uint8Array>)
    : new ReadableStream<Uint8Array>();

  const seen = async (ms: number) =>
    exited || (await settledWithin(status, ms)) !== undefined;

  let stopping: Promise<void> | undefined;

  const stop = async (bounds: StopBounds) => {
    const { exitMs, termMs, killMs } = { ...STOP_BOUNDS, ...bounds };

    input?.end();

    const gone =
      (await seen(exitMs)) ||
      (group.signal('SIGTERM'), await seen(termMs)) ||
      (group.signal('SIGKILL'), await seen(killMs));

    if (!gone) {
      throw new AgentExitError([pid]);
    }

    // The agent can go and leave what it started behind in its group, still
    // holding an account or the pipes; nothing there outlives the session.
    if (!WINDOWS) {
      group.signal('SIGKILL');
    }
  };

  return {
    pid,
    stdin,
    stdout,
    status,
    stderrTail: () => tail,
    stop: (bounds = {}) => (stopping ??= stop(bounds)),
  };
}

/**
 * The promise's outcome, or `undefined` once `ms` pass without one, so a wait
 * on an agent that stopped answering is bounded.
 */
export function settledWithin<T>(
  promise: Promise<T>,
  ms: number,
): Promise<PromiseSettledResult<T> | undefined> {
  let timer: ReturnType<typeof setTimeout> | undefined;

  return Promise.race([
    promise.then(
      (value): PromiseSettledResult<T> => ({ status: 'fulfilled', value }),
      (reason: unknown): PromiseSettledResult<T> => ({
        status: 'rejected',
        reason,
      }),
    ),
    new Promise<undefined>((resolve) => {
      timer = setTimeout(() => resolve(undefined), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}
