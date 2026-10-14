/**
 * Bash mode: a prompt started with `!` is a shell command, run here rather
 * than sent, as in Claude Code. What turns the mode on and off, and what a
 * run reads as in the transcript.
 */
import { cleanOutput, endNote, TRUNCATED } from '../../session/context.ts';
import type { ShellRun } from '../../session/transcript/types.ts';

/** What starts bash mode on an empty prompt, and starts a recalled command. */
export const BASH_PREFIX = '!';

/**
 * The command in a prompt as history keeps it, `!` first; undefined for one
 * that is not a command.
 */
export function bashCommand(text: string): string | undefined {
  return text.startsWith(BASH_PREFIX)
    ? text.slice(BASH_PREFIX.length)
    : undefined;
}

/** The draft as history keeps it: a command with its `!` back on. */
export function typedText(bash: boolean, draft: string): string {
  return bash ? BASH_PREFIX + draft : draft;
}

/**
 * Whether an edit to the prompt starts bash mode: an empty box that now
 * starts with `!`, typed or pasted. The rest is the command so far.
 */
export function entersBash(
  bash: boolean,
  draft: string,
  value: string,
): string | undefined {
  return !bash && draft === '' ? bashCommand(value) : undefined;
}

/**
 * How many output lines a run shows before `… +N lines`; more than a tool
 * call's three, since the person asked for this output to read it.
 */
export const SHELL_LINES = 10;

export interface ShellLine {
  readonly text: string;
  readonly stream: 'stdout' | 'stderr';
}

export interface ShellView {
  /** Output, stdout's then stderr's, folded unless expanded. */
  readonly lines: readonly ShellLine[];
  readonly hidden: number;
  /** The last line, under the output: how it ended, or that it runs. */
  readonly note?: { readonly text: string; readonly failed: boolean };
}

/** What a run shows in the transcript. */
export function shellView(
  run: ShellRun,
  expanded: boolean,
  /** The key that stops it, named while it runs; none when none is bound. */
  stopKey: string | undefined,
): ShellView {
  const lines = [
    ...outputLines(run.stdout, 'stdout'),
    ...(run.truncated ? [{ text: TRUNCATED, stream: 'stdout' as const }] : []),
    ...outputLines(run.stderr, 'stderr'),
  ];
  const shown = expanded ? lines : lines.slice(0, SHELL_LINES);
  const ended = endNote(run);
  const note = run.running
    ? {
        text:
          stopKey === undefined ? 'Running…' : `Running… (${stopKey} to stop)`,
        failed: false,
      }
    : ended !== undefined
      ? { text: ended, failed: !run.stopped }
      : lines.length === 0
        ? { text: '(No output)', failed: false }
        : undefined;

  return {
    lines: shown,
    hidden: lines.length - shown.length,
    ...(note === undefined ? {} : { note }),
  };
}

function outputLines(text: string, stream: 'stdout' | 'stderr'): ShellLine[] {
  const clean = cleanOutput(text);

  return clean === ''
    ? []
    : clean.split('\n').map((line) => ({ text: line, stream }));
}
