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
 * how many; `extra` is the rows its description wraps to past one. None
 * where not one choice fits: the list goes, and with it its keys, as a
 * transient list's do with no row to show.
 */
export function framedRows(
  limit: number,
  room: number,
  count: number,
  extra = 0,
): number {
  const fit = (around: number) =>
    Math.max(0, Math.min(limit, room - PICKER_CHROME - extra - around));
  const rows = fit(0);

  return count > rows ? fit(1) : rows;
}

/**
 * How many of its rows a framed picker's body shows in `room` rows, its
 * content `height` rows tall with its parts at `parts` (each its top row and
 * its rows): all of them where they fit, none to cut; cut, down to the last
 * row a part draws, so a gap between two parts is not left at the bottom
 * (CHD-545).
 */
export function cutRows(
  room: number,
  height: number,
  parts: readonly (readonly [number, number])[],
): number | undefined {
  if (height <= room) {
    return undefined;
  }

  for (let rows = Math.max(0, Math.floor(room)); rows > 0; rows--) {
    const last = rows - 1;

    if (parts.some(([top, size]) => last >= top && last < top + size)) {
      return rows;
    }
  }

  return 0;
}
