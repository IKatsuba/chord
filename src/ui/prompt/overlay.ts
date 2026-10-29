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
 * The rows a framed picker's frame, title, description, gap and hint take,
 * around its list.
 */
const PICKER_CHROME = 6;

/**
 * How many rows a framed picker's list may show in a layer of `room` rows:
 * `limit`, the picker's own, while its frame, title and hint fit around it,
 * and fewer once they would not, so they stay in sight (CHD-545). One at
 * least: its list scrolls.
 */
export function pickerRows(limit: number, room: number): number {
  return Math.max(1, Math.min(limit, room - PICKER_CHROME));
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
