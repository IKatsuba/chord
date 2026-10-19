/**
 * How a held box folds where the window has no room for all of it: its
 * lines from the top as many as fit, then a line saying how many more there
 * are (CHD-158 §8).
 */

/** The lines shown and those folded under `… N more lines`. */
export interface Folded {
  readonly shown: number;
  readonly more: number;
}

/**
 * `lines` in `room` rows: all of them where they fit, else as many as leave
 * a row for the line that counts the rest.
 */
export function foldOf(lines: number, room: number): Folded {
  if (lines <= room) {
    return { shown: lines, more: 0 };
  }

  const shown = Math.max(0, room - 1);

  return { shown, more: lines - shown };
}

/** `… 1 more line`, `… 2 more lines`. */
export function moreLines(more: number): string {
  return `… ${more} more ${more === 1 ? 'line' : 'lines'}`;
}
