/**
 * How tall the layer over the transcript may be, its bottom edge on screen
 * row `edge`: every row from the window's top down to it (CHD-545).
 */
export function overlayRoom(edge: number): number {
  return Math.max(0, Math.trunc(edge));
}

/** The dim rule on top of a frameless list, across `width` cells. */
export function overlayRule(width: number): string {
  return '─'.repeat(Math.max(0, width));
}

/**
 * The rows a framed picker takes around its list: its frame's two, the
 * title, a one-line description, the gap above the list, the gap above the
 * hint and the hint.
 */
const PICKER_CHROME = 7;

/**
 * How many rows the list of a framed picker with `count` choices may show
 * in a layer of `room` rows: `limit`, the picker's own, while all of it
 * fits, and fewer once its title and hint would leave the layer, so they
 * stay in sight (CHD-545). Hidden choices take a row of their own that says
 * how many; `extra` is the rows its description wraps to past one. One at
 * least: its list scrolls.
 */
export function framedRows(
  limit: number,
  room: number,
  count: number,
  extra = 0,
): number {
  const fit = (around: number) =>
    Math.max(1, Math.min(limit, room - PICKER_CHROME - extra - around));
  const rows = fit(0);

  return count > rows ? fit(1) : rows;
}

/**
 * The rows under the layer while the prompt is one line: the gap row, the
 * prompt's three and the status line.
 */
const BELOW = 5;

/**
 * The window's height a picker laid out by it is told, in a layer of
 * `room` rows of a window `windowRows` high: the window's, until a taller
 * prompt or the rows under it leave the layer less (CHD-545).
 */
export function layoutRows(room: number, windowRows: number): number {
  return Math.min(windowRows, room + BELOW);
}
