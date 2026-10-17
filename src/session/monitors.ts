/**
 * Monitors: a command an agent started through chord's `monitor` tool, whose
 * stdout lines reach that agent later as messages. Here are the numbers
 * CHD-243 settled, a line as an event carries it, an event's caps, the
 * flood watch, the words of an end, what a resumed session's past says of
 * its monitors, and `MonitorRun`, which runs one command and batches its
 * lines. Delivering them is the conversation's, which owns the queue.
 */
import stripAnsi from 'strip-ansi';
import { runShell, type ShellEnd, type ShellProcess } from '../shell.ts';
import { formatElapsed } from './elapsed.ts';
import type { PastAction } from './session.ts';
import type { MonitorEnd, PastMonitor } from './transcript/types.ts';

/** How long lines gather from a batch's first, fixed: never pushed back. */
export const BATCH_MS = 200;
/** An event's lines at most; past them lines are counted, not sent. */
export const EVENT_LINES = 100;
/** An event's bytes at most, so 100 long lines are not one huge turn. */
export const EVENT_BYTES = 16 * 1024;
/** A line's characters at most, so one minified line takes no whole event. */
export const LINE_CHARS = 1000;
/** A monitor printing more than these within `FLOOD_MS` is stopped. */
export const FLOOD_LINES = 1000;
export const FLOOD_BYTES = 256 * 1024;
export const FLOOD_MS = 10_000;
/** Monitors running in a session at most, its agents' counted together. */
export const MAX_MONITORS = 8;
export const DEFAULT_TIMEOUT_MS = 600_000;
export const MIN_TIMEOUT_MS = 1000;
export const MAX_TIMEOUT_MS = 3_600_000;
/** A description's characters at most: it is on every event. */
export const DESCRIPTION_CHARS = 60;

/** What `monitor` was asked. */
export interface MonitorArgs {
  readonly command: string;
  readonly description: string;
  readonly timeoutMs?: number | undefined;
}

/** A monitor started: its id in the session, and what it runs. */
export interface MonitorInfo {
  /** `m1`, `m2`, … in the session's start order, across `--resume`. */
  readonly id: string;
  readonly description: string;
  readonly command: string;
  /** When it started, epoch milliseconds. */
  readonly startedAt: number;
  readonly timeoutMs: number;
}

/** A monitor still running, as the screen's list reads it. */
export interface RunningMonitor extends MonitorInfo {
  /** The batches it has handed on so far. */
  readonly events: number;
}

/**
 * A monitor that has ended in the session, as the background view reads it:
 * how, when, and the batches it handed on by then. The agent's own
 * `stop_monitor` and the person's `x` both end it `stopped`.
 */
export interface EndedMonitor extends RunningMonitor {
  readonly end: MonitorEnd;
  /** When it ended, epoch milliseconds; a stop's is when it was asked. */
  readonly endedAt: number;
}

/**
 * Why `monitor` refuses what it was asked, with `running` monitors already
 * in the session; none when it may start. Refused, never clamped, so the
 * agent never thinks it has what it does not.
 */
export function monitorRefusal(
  args: MonitorArgs,
  running: number,
): string | undefined {
  if (running >= MAX_MONITORS) {
    return (
      `This session has ${MAX_MONITORS} monitors running; ` +
      'stop_monitor one first'
    );
  }

  const description = args.description.trim();

  if (
    description === '' ||
    /[\r\n]/.test(description) ||
    [...description].length > DESCRIPTION_CHARS
  ) {
    return (
      `description is at most ${DESCRIPTION_CHARS} characters on one ` +
      'line; it is shown on every event'
    );
  }

  const timeout = args.timeoutMs;

  if (
    timeout !== undefined &&
    (!Number.isInteger(timeout) ||
      timeout < MIN_TIMEOUT_MS ||
      timeout > MAX_TIMEOUT_MS)
  ) {
    return (
      `timeout_ms is between ${MIN_TIMEOUT_MS} and ${MAX_TIMEOUT_MS} ` +
      `(${timeoutWords(MAX_TIMEOUT_MS)})`
    );
  }

  return args.command.trim() === '' ? 'command is empty' : undefined;
}

/** `10m`, `1h`, `1m 30s`: a timeout as the agent and the person read it. */
export function timeoutWords(ms: number): string {
  return formatElapsed(ms).replace(/ 0[sm]$/, '');
}

/** A line as an event carries it: escapes stripped, cut past the limit. */
export function eventLine(raw: string): string {
  const characters = [...stripAnsi(raw)];

  return characters.length <= LINE_CHARS
    ? characters.join('')
    : `${characters.slice(0, LINE_CHARS).join('')}… (+${
        characters.length - LINE_CHARS
      } characters)`;
}

/** The lines of one message, and how many more there were. */
export interface EventLines {
  readonly lines: readonly string[];
  /** The lines' UTF-8 bytes, a newline each. */
  readonly bytes: number;
  /** Lines past the caps, counted and not sent. */
  readonly dropped: number;
}

export const NO_LINES: EventLines = { lines: [], bytes: 0, dropped: 0 };

const encoder = new TextEncoder();

/**
 * `event` with `lines` after it, as many as the caps let in; the rest, and
 * `dropped` more, are counted. Once one is left out, every later one is, so
 * what is sent is the first lines, unbroken: a batch's first line is
 * usually the error, the rest its trace.
 */
export function withLines(
  event: EventLines,
  lines: readonly string[],
  dropped = 0,
): EventLines {
  const kept = [...event.lines];
  let bytes = event.bytes;
  let left = event.dropped;

  for (const line of lines) {
    const size = encoder.encode(line).length + 1;

    if (left > 0 || kept.length >= EVENT_LINES || bytes + size > EVENT_BYTES) {
      left += 1;
    } else {
      kept.push(line);

      bytes += size;
    }
  }

  return { lines: kept, bytes, dropped: left + dropped };
}

/** A message's text: its lines, what was not sent, then chord's sentence. */
export function eventText(event: EventLines, sentence?: string): string {
  return [
    ...event.lines,
    ...(event.dropped === 0
      ? []
      : [
          `… ${count(event.dropped)} more ${
            event.dropped === 1 ? 'line' : 'lines'
          } not delivered (an event carries at most ${EVENT_LINES})`,
        ]),
    ...(sentence === undefined ? [] : [sentence]),
  ].join('\n');
}

function count(value: number): string {
  return value.toLocaleString('en-US');
}

/**
 * The lines a monitor printed within the last `FLOOD_MS`, sliding, and
 * whether they are more than a monitor may print.
 */
export class FloodWatch {
  readonly #seen: { readonly at: number; readonly bytes: number }[] = [];
  #bytes = 0;

  /** A line of `bytes` came at `at`; what it floods by, if anything. */
  add(at: number, bytes: number): 'lines' | 'bytes' | undefined {
    this.#seen.push({ at, bytes });

    this.#bytes += bytes;

    while (this.#seen.length > 0 && this.#seen[0]!.at <= at - FLOOD_MS) {
      this.#bytes -= this.#seen.shift()!.bytes;
    }

    return this.#seen.length > FLOOD_LINES
      ? 'lines'
      : this.#bytes > FLOOD_BYTES
        ? 'bytes'
        : undefined;
  }
}

/** An end as its message's header and the wrapper's `from` say it. */
export function endWord(end: MonitorEnd): string {
  switch (end.kind) {
    case 'exit':
      return `exit code ${end.code}`;
    case 'signal':
      return `killed by ${end.signal}`;
    case 'timed_out':
      return 'timed out';
    case 'stopped':
      return 'stopped';
    case 'flooded':
      return 'flooded';
  }
}

/** chord's sentence for an end, last in its message, after `ranMs`. */
export function endSentence(end: MonitorEnd, ranMs: number): string {
  const after = formatElapsed(ranMs);

  switch (end.kind) {
    case 'exit': {
      const meaning =
        end.code === 127
          ? ' (command not found)'
          : end.code === 126
            ? ' (not executable)'
            : '';

      return `Exited with code ${end.code}${meaning} after ${after}.`;
    }
    case 'signal':
      return `Killed by ${end.signal} after ${after}.`;
    case 'timed_out':
      return `Timed out after ${timeoutWords(
        end.timeoutMs,
      )} (timeout_ms ${end.timeoutMs}); chord stopped it.`;
    case 'stopped':
      return `The person stopped it after ${after}.`;
    case 'flooded':
      return (
        `chord stopped it: ${
          end.by === 'lines'
            ? `${count(FLOOD_LINES)} lines`
            : `${FLOOD_BYTES / 1024} KiB`
        } in ${FLOOD_MS / 1000}s is more than a monitor may print. Filter ` +
        'its output (grep --line-buffered) and start it again.'
      );
  }
}

/** What a session's past says of its monitors. */
export interface MonitorsPast {
  /** The highest id's number, which the next one goes on from. */
  readonly last: number;
  /** How each that ended did, by id, as its end's word says it. */
  readonly ended: ReadonlyMap<string, string>;
  /** Those running when it was left, in start order, which nothing restarts. */
  readonly left: readonly PastMonitor[];
}

/**
 * The monitors a session's past started, from the `monitor` calls chord
 * served, and how each ended: an end message, or the agent's own
 * `stop_monitor`. One with neither was running when the session was left,
 * as a close or a quit stops monitors without a word.
 */
export function monitorsPast(actions: readonly PastAction[]): MonitorsPast {
  const started: PastMonitor[] = [];
  const ended = new Map<string, string>();

  for (const action of actions) {
    if (action.type === 'served' && action.call.error === undefined) {
      const answer = action.call.answer;
      const id =
        isRecord(answer) && typeof answer.id === 'string'
          ? answer.id
          : undefined;

      if (id === undefined) {
        continue;
      }

      const description = isRecord(answer) ? answer.description : undefined;

      if (action.call.tool === 'monitor' && typeof description === 'string') {
        started.push({ id, description });
      } else if (action.call.tool === 'stop_monitor') {
        ended.set(id, 'stopped');
      }
    }

    const end = action.type === 'prompt' ? action.from?.monitor : undefined;

    if (end?.end !== undefined) {
      ended.set(end.id, endWord(end.end));
    }
  }

  return {
    last: Math.max(0, ...started.map(({ id }) => Number(id.slice(1)) || 0)),
    ended,
    left: started.filter(({ id }) => !ended.has(id)),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

/** The note after a resumed past that names the monitors it left running. */
export function leftRunningLine(monitors: readonly PastMonitor[]): string {
  const names = new Intl.ListFormat('en-GB', { type: 'conjunction' }).format(
    monitors.map(({ description }) => description),
  );

  return `${names} ${
    monitors.length === 1 ? 'was' : 'were'
  } running when this session was left and ${
    monitors.length === 1 ? 'is' : 'are'
  } not restarted`;
}

/** Starts a monitor's command, handing on each stdout line. */
export type RunCommand = (
  command: string,
  cwd: string,
  onLine: (line: string) => void,
) => ShellProcess;

/**
 * Through the person's shell, stderr dropped, as `src/shell.ts` runs it, and
 * whatever it started gone when it ends.
 */
export const runMonitorCommand: RunCommand = (command, cwd, onLine) =>
  runShell(command, { cwd, onLine, reap: true });

/** Where a running monitor's batches and its end go. */
export interface MonitorHooks {
  /** A batch, gathered over `BATCH_MS`, ready to go to the agent. */
  event(lines: EventLines): void;
  /**
   * It ended on its own, by its timeout, a flood or the person's stop, with
   * the lines not handed on yet; never after a silent stop.
   */
  ended(end: MonitorEnd, rest: EventLines): void;
}

/** Who stops a monitor: the person says so; the agent and a close do not. */
export type StoppedBy = 'person' | 'agent' | 'close';

/**
 * One monitor's command, running: its lines batched over a fixed window,
 * the flood watched, its timeout kept, and its end told once.
 */
export class MonitorRun {
  readonly info: MonitorInfo;
  readonly #process: ShellProcess;
  readonly #hooks: MonitorHooks;
  readonly #flood = new FloodWatch();
  #events = 0;
  #batch: EventLines | undefined;
  #flush: ReturnType<typeof setTimeout> | undefined;
  readonly #timeout: ReturnType<typeof setTimeout>;
  /** Why chord stopped it, or `silent` when nobody is told. */
  #stopping: MonitorEnd | 'silent' | undefined;
  /** How its shell ended, while what that shell started is being reaped. */
  #exit: MonitorEnd | undefined;
  /** Settles once its command and all it started are gone. */
  readonly ended: Promise<void>;

  private constructor(
    info: MonitorInfo,
    hooks: MonitorHooks,
    cwd: string,
    run: RunCommand,
  ) {
    this.info = info;
    this.#hooks = hooks;
    this.#process = run(info.command, cwd, (line) => this.#line(line));
    this.#timeout = setTimeout(
      () => this.#stop({ kind: 'timed_out', timeoutMs: info.timeoutMs }),
      info.timeoutMs,
    );

    void this.#process.exited?.then((end) => this.#exited(end));

    this.ended = this.#process.ended.then((end) => this.#ended(end));
  }

  /** Starts `info`'s command; a shell that does not start is its refusal. */
  static start(
    info: MonitorInfo,
    hooks: MonitorHooks,
    cwd: string,
    run: RunCommand = runMonitorCommand,
  ): MonitorRun | { readonly error: string } {
    const monitor = new MonitorRun(info, hooks, cwd, run);
    const failed = monitor.#process.failed;

    if (failed !== undefined) {
      monitor.#stopping = 'silent';

      clearTimeout(monitor.#timeout);

      return { error: `Could not start the command: ${failed}` };
    }

    return monitor;
  }

  get running(): RunningMonitor {
    return { ...this.info, events: this.#events };
  }

  /** Stops it and all it started; the person's stop is told to the agent. */
  stop(by: StoppedBy): void {
    this.#stop(by === 'person' ? { kind: 'stopped' } : 'silent');
  }

  #stop(why: MonitorEnd | 'silent'): void {
    // Its shell's end is told already; only a silent stop takes its place.
    if (
      this.#stopping !== undefined ||
      (this.#exit !== undefined && why !== 'silent')
    ) {
      return;
    }

    this.#stopping = why;

    clearTimeout(this.#timeout);
    clearTimeout(this.#flush);
    this.#process.stop();
  }

  #line(raw: string): void {
    if (this.#stopping !== undefined) {
      return;
    }

    const flooded = this.#flood.add(Date.now(), encoder.encode(raw).length + 1);

    // The line that flooded goes in the sample, which shows what to filter.
    this.#batch = withLines(this.#batch ?? NO_LINES, [eventLine(raw)]);

    if (flooded !== undefined) {
      this.#stop({ kind: 'flooded', by: flooded });

      return;
    }

    this.#flush ??= setTimeout(() => {
      const batch = this.#batch;

      this.#flush = undefined;
      this.#batch = undefined;

      if (batch !== undefined && this.#stopping === undefined) {
        this.#events += 1;

        this.#hooks.event(batch);
      }
    }, BATCH_MS);
  }

  /**
   * Its shell has ended, by itself unless chord stopped it: that is the end
   * the agent hears, whatever its leftovers take to go, so no timeout or
   * flood while they are reaped replaces it. Lines still in the pipe are
   * batched as before.
   */
  #exited(end: ShellEnd): void {
    if (this.#stopping !== undefined || this.#exit !== undefined) {
      return;
    }

    clearTimeout(this.#timeout);

    this.#exit = endOfShell(end);
  }

  #ended(end: ShellEnd): void {
    clearTimeout(this.#timeout);
    clearTimeout(this.#flush);

    const why = this.#stopping ?? this.#exit;
    const rest = this.#batch ?? NO_LINES;

    this.#stopping = 'silent';
    this.#batch = undefined;

    if (why === 'silent') {
      return;
    }

    this.#hooks.ended(why ?? endOfShell(end), rest);
  }
}

function endOfShell(end: ShellEnd): MonitorEnd {
  return end.signal === undefined
    ? // A status that could not be read has no code; it ended all the same.
      { kind: 'exit', code: end.code ?? 1 }
    : { kind: 'signal', signal: end.signal };
}
