/**
 * The rows of chord's crash screen (`docs/design/CHD-468.md`): the error's
 * message, its stack's frames, and the hint, laid out for a window, with
 * what a small one gives up first given up first.
 */
import cliTruncate from 'cli-truncate';
import stringWidth from 'string-width';
import wrapAnsi from 'wrap-ansi';

/** One row of the screen and what paints it. */
export interface CrashRow {
  readonly text: string;
  readonly role: 'error' | 'dim' | 'blank';
}

/** What the screen says to do, its last row. */
export const CRASH_HINT =
  'any key to quit · chord prints the error to stderr as it exits';

const INDENT = '  ';

/**
 * The frames of `error`'s stack, as the stack writes them; none for a
 * thrown value that is not an Error, or one with no stack.
 */
function framesOf(error: unknown): string[] {
  const stack = error instanceof Error ? error.stack : undefined;

  return (stack ?? '').split('\n').filter((line) => /^\s+at\s/.test(line));
}

/** `text` cut at `columns` with `…`, as a frame wider than the window is. */
function cut(text: string, columns: number): string {
  return stringWidth(text) > columns
    ? cliTruncate(text, columns, { position: 'end' })
    : text;
}

/**
 * The screen for `error` in a window of `columns` by `rows`: the message
 * word-wrapped two columns in, the frames cut at the edge, a blank row over
 * each, the hint last. A window too small for all of it gives up the
 * frames from the bottom, a row then saying how many more there are, then
 * that row, the blank rows, the top one first, and the message's rows from
 * the bottom, the last one kept ending in `…`; the hint goes last.
 */
export function crashRows(
  error: unknown,
  columns: number,
  rows: number,
): CrashRow[] {
  const blank: CrashRow = { text: '', role: 'blank' };
  const message = wrapAnsi(String(error), Math.max(1, columns - 2), {
    hard: true,
  })
    .split('\n')
    .map((line): CrashRow => ({ text: INDENT + line, role: 'error' }));
  const frames = framesOf(error).map((frame): CrashRow => ({
    text: cut(INDENT + frame, columns),
    role: 'dim',
  }));
  const hint: CrashRow = {
    text: cut(INDENT + CRASH_HINT, columns),
    role: 'dim',
  };
  const more = (count: number): CrashRow => ({
    text: cut(`      … ${count} more frame${count === 1 ? '' : 's'}`, columns),
    role: 'dim',
  });
  // The message, both blank rows and the hint, which every frame waits on.
  const fixed = message.length + 3;

  if (rows >= fixed + frames.length) {
    return [blank, ...message, ...frames, blank, hint];
  }

  if (frames.length > 0 && rows >= fixed + 1) {
    const shown = rows - fixed - 1;

    return [
      blank,
      ...message,
      ...frames.slice(0, shown),
      more(frames.length - shown),
      blank,
      hint,
    ];
  }

  if (rows >= fixed - 1) {
    return rows === fixed
      ? [blank, ...message, blank, hint]
      : [...message, blank, hint];
  }

  const kept = message.slice(0, Math.max(0, rows - 1));
  const last = kept.at(-1);

  if (last !== undefined && kept.length < message.length) {
    kept[kept.length - 1] = { ...last, text: cut(`${last.text}…`, columns) };
  }

  return [...kept, hint];
}
