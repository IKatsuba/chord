/**
 * Why an agent did not start, as chord knows it from the protocol and the
 * process it ran, never from the words: the step that failed, how the
 * process ended, the error's code, the end of its stderr, and the package a
 * registry agent ran (CHD-454).
 */
import { AgentGone } from '../acp/connection.ts';
import type { Exit } from '../platform/process.ts';

/** What chord asked last when the agent's start failed. */
export type StartStep =
  'initialize' | 'session/new' | 'session/load' | 'session/resume';

/** How many of stderr's last lines a start failure keeps. */
export const STDERR_LINES = 6;

/** The end of a stream, its last lines, and how many lines came before. */
export interface Tail {
  readonly lines: readonly string[];
  /** Non-empty lines left out before `lines`. */
  readonly cut: number;
}

/** Why the agent did not start. */
export interface StartFailure {
  readonly step: StartStep;
  /** How its process ended, when it ended before answering `step`. */
  readonly exit?: Exit;
  /** The JSON-RPC code of the agent's refusal of `step`. */
  readonly code?: number;
  /** The end of what it wrote to stderr, when it wrote anything. */
  readonly stderr?: Tail;
  /** The package and version chord ran, for an agent of the registry's. */
  readonly pinned?: string;
}

/** A start that failed; its message is the failure's own words. */
export class StartFailed extends Error {
  constructor(
    readonly failure: StartFailure,
    options: ErrorOptions & { readonly message: string },
  ) {
    super(options.message, { cause: options.cause });

    this.name = 'StartFailed';
  }
}

/**
 * `text`'s last `count` non-empty lines, each as it was written, its indent
 * kept, and how many non-empty lines came before them: of `total`, when
 * `text` is the end of more, whose first line may be the end of one.
 */
export function tailOf(
  text: string,
  count = STDERR_LINES,
  total?: number,
): Tail {
  const held = text.split(/\r?\n/).filter((line) => line.trim() !== '');
  const whole =
    total === undefined || total <= held.length ? held : held.slice(1);
  const lines = whole.slice(-count).map((line) => line.trimEnd());

  return {
    lines,
    cut: Math.max((total ?? held.length) - lines.length, 0),
  };
}

/**
 * `error`, which ended the start at `step`, as a `StartFailed`: its exit and
 * stderr when the agent's process went, its code when the agent refused.
 * The message stays the error's own.
 */
export function startFailed(
  error: unknown,
  step: StartStep,
  pinned: string | undefined,
): StartFailed {
  const gone = goneOf(error);
  // The refusal's own code, under what chord made of it (CHD-435's sign-in).
  const code =
    gone === undefined
      ? causes(error).flatMap((each) =>
          'code' in each && typeof each.code === 'number' ? [each.code] : [],
        )[0]
      : undefined;
  const stderr =
    gone === undefined
      ? undefined
      : tailOf(gone.stderr, STDERR_LINES, gone.stderrLines);

  return new StartFailed(
    {
      step,
      ...(gone === undefined ? {} : { exit: gone.exit }),
      ...(code === undefined ? {} : { code }),
      ...(stderr === undefined || stderr.lines.length === 0 ? {} : { stderr }),
      ...(pinned === undefined ? {} : { pinned }),
    },
    {
      message: error instanceof Error ? error.message : String(error),
      cause: error,
    },
  );
}

/** The failure `error` or one of its causes says the start ended with. */
export function startFailureOf(error: unknown): StartFailure | undefined {
  return causes(error).find((each) => each instanceof StartFailed)?.failure;
}

function goneOf(error: unknown): AgentGone | undefined {
  return causes(error).find((each) => each instanceof AgentGone);
}

/** `error` and the errors it was caused by, outermost first. */
function causes(error: unknown): Error[] {
  const found: Error[] = [];

  for (
    let each: unknown = error;
    each instanceof Error && !found.includes(each);
    each = each.cause
  ) {
    found.push(each);
  }

  return found;
}
