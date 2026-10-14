/**
 * A terminal an agent ran a command in, as its tool call draws it under `⎿`:
 * the latest lines of what it wrote while folded, all of it on ctrl+o, and how
 * it ended when that is news, as Claude Code draws a Bash call.
 */
import { TRUNCATED } from '../../../session/context.ts';
import type { Terminal } from '../../../session/transcript/types.ts';

/** As many output lines as a folded terminal shows: its latest ones. */
export const TERMINAL_LINES = 3;

export interface TerminalView {
  /** What it wrote, its last lines unless expanded. */
  readonly lines: readonly string[];
  /** Lines before the shown ones that did not fit. */
  readonly hidden: number;
  /** Under the output: a failing exit and its code, or that it wrote nothing. */
  readonly note?: { readonly text: string; readonly failed: boolean };
}

/**
 * What `terminal` shows. A running command's newest lines are the ones to
 * see, so the fold keeps the end rather than the start. One that has written
 * nothing yet shows nothing, so the call keeps its own working line.
 */
export function terminalView(
  terminal: Terminal,
  expanded: boolean,
): TerminalView {
  const lines = outputLines(terminal.output);
  const shown = expanded
    ? [...(terminal.truncated ? [TRUNCATED] : []), ...lines]
    : lines.slice(-TERMINAL_LINES);
  const note =
    endNote(terminal) ??
    (terminal.exited && lines.length === 0
      ? { text: '(No output)', failed: false }
      : undefined);

  return {
    lines: shown,
    hidden: expanded ? 0 : lines.length - shown.length,
    ...(note === undefined ? {} : { note }),
  };
}

/** Whether a view has anything to draw. */
export function isEmpty(view: TerminalView): boolean {
  return view.lines.length === 0 && view.note === undefined;
}

function endNote(
  terminal: Terminal,
): { text: string; failed: boolean } | undefined {
  if (terminal.signal !== undefined) {
    const signal = outputLines(terminal.signal).join(' ');

    return {
      text: signal === '' ? 'Killed' : `Killed by ${signal}`,
      failed: true,
    };
  }

  return terminal.exitCode === undefined || terminal.exitCode === 0
    ? undefined
    : { text: `Exit code ${terminal.exitCode}`, failed: true };
}

/**
 * The output's lines. The reducer keeps it as a screen would leave it, with
 * no escape or control character but the newline, so only the blank a
 * command leaves after its last line goes.
 */
function outputLines(output: string): string[] {
  const text = output.replace(/\s+$/, '');

  return text === '' ? [] : text.split('\n');
}
