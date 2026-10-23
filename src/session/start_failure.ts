/**
 * Why an agent did not start, as chord knows it from the protocol and the
 * process it ran, never from the words: the step that failed, how the
 * process ended, the error's code, the end of its stderr, and the package a
 * registry agent ran (CHD-454).
 */
import { AgentGone } from '../acp/connection.ts';
import type { Tail } from '../acp/process.ts';
import type { Exit } from '../platform/process.ts';

/** What chord asked last when the agent's start failed. */
export type StartStep =
  'initialize' | 'session/new' | 'session/load' | 'session/resume';

/** Why the agent did not start. */
export interface StartFailure {
  readonly step: StartStep;
  /** How its process ended, when it ended before answering `step`. */
  readonly exit?: Exit;
  /**
   * Its connection closed before it answered `step`, and no exit was seen
   * by the time its last words came: it may live on.
   */
  readonly closed?: true;
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
  const stderr = gone?.stderr;

  return new StartFailed(
    {
      step,
      ...(gone === undefined
        ? {}
        : gone.exit === undefined
          ? { closed: true }
          : { exit: gone.exit }),
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

/** The way chord says the agent's start failed, after `<agent> did not start: `. */
export function stepWords(
  message: string,
  failure: StartFailure | undefined,
): string {
  if (failure === undefined) {
    return message;
  }

  const { step, exit, code } = failure;

  if (failure.closed) {
    return `it closed its connection before answering ${step}.`;
  }

  if (exit !== undefined) {
    return exit.signal === undefined
      ? `it exited with code ${exit.code} before answering ${step}.`
      : `it was stopped by ${exit.signal} before answering ${step}.`;
  }

  if (code === undefined || code === AUTH_REQUIRED) {
    // A command not found, or a sign-in, which says it its own way (CHD-435).
    return message;
  }

  if (code === METHOD_NOT_FOUND && step !== 'initialize') {
    return 'it does not serve ACP sessions: not an ACP agent, or not at this version.';
  }

  return `it refused ${step}: ${message}`;
}

/** ACP's `authRequired`, which CHD-435's sign-in says. */
const AUTH_REQUIRED = -32000;

/** JSON-RPC's method not found. */
const METHOD_NOT_FOUND = -32601;

/** JSON-RPC's invalid params. */
const INVALID_PARAMS = -32602;

/** The line that names what chord ran for a registry agent. */
export function pinLine(pinned: string): string {
  return `chord ran ${pinned}, the version the ACP Registry names.`;
}

/** The line before the end of the agent's stderr. */
export const STDERR_HEADING = 'The end of its stderr:';

/** How many lines of the tail were left out, before it. */
export function cutLine(cut: number): string {
  return `… +${cut} ${cut === 1 ? 'line' : 'lines'}`;
}

/** What setting zeroclaw's default agent takes, said to the person. */
const ZEROCLAW_DEFAULT =
  '[acp] default_agent = "<alias>" in ZeroClaw\'s config, or start it with zeroclaw acp --agent <alias>.';

/**
 * The way on chord knows for `agent`'s failure: zeroclaw's, which refuses a
 * session -32602 for want of an agent alias with several and no default
 * (Q177); none for any other.
 */
export function wayOnFor(
  agent: string,
  failure: StartFailure | undefined,
): string | undefined {
  return agent === 'zeroclaw' &&
    failure?.code === INVALID_PARAMS &&
    failure.step !== 'initialize'
    ? `Set a default agent: ${ZEROCLAW_DEFAULT}`
    : undefined;
}

/**
 * The block under the headline as plain lines, in order: the pin, the end
 * of stderr with what was cut, and the way on; none when it has nothing.
 */
export function failureLines(
  agent: string,
  failure: StartFailure | undefined,
): string[] {
  const way = wayOnFor(agent, failure);
  const stderr = failure?.stderr;

  return [
    ...(failure?.pinned === undefined ? [] : [pinLine(failure.pinned)]),
    ...(stderr === undefined
      ? []
      : [
          STDERR_HEADING,
          ...(stderr.cut === 0 ? [] : [`  ${cutLine(stderr.cut)}`]),
          ...stderr.lines.map((line) => `  ${line}`),
        ]),
    ...(way === undefined ? [] : [way]),
  ];
}

/**
 * What an agent that opened `agent` is told of why it did not start, after
 * the step: the pin, the tail's last line, and the way on, the person's.
 */
export function failureNote(
  agent: string,
  failure: StartFailure | undefined,
): string {
  const last = failure?.stderr?.lines.at(-1)?.trim();

  return [
    ...(failure?.pinned === undefined ? [] : [pinLine(failure.pinned)]),
    ...(last === undefined ? [] : [`Its stderr ended: "${last}".`]),
    ...(wayOnFor(agent, failure) === undefined
      ? []
      : [`The person sets a default agent: ${ZEROCLAW_DEFAULT}`]),
  ]
    .map((sentence) => ` ${sentence}`)
    .join('');
}

/** `words` ending a sentence: a stop added unless one ends it. */
export function sentence(words: string): string {
  return /[.!?]$/.test(words) ? words : `${words}.`;
}
