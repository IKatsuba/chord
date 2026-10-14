/**
 * The startup splash (docs/design/CHD-241.md): Chorded's mark, dim, drifting
 * round a small ellipse in the middle of the screen until the first session
 * is up, with one line under it.
 */
import stringWidth from 'string-width';
import { formatElapsed } from '../../session/elapsed.ts';
import type { Connection } from '../app/state.ts';
import { MARK, type MarkGrid, SPLASH_MARK } from '../header/mark.ts';

/** How long the mark stays in each place on its path. */
export const SPLASH_STEP_MS = 300;

/** From when a start is slow: the line counts seconds and names the keys. */
export const SLOW_START_MS = 5000;

/** The second line from `SLOW_START_MS` on. */
export const SLOW_HINT = 'esc for the window · ctrl+c to quit';

/** One place on the path: columns right of the centre, half rows down. */
export interface SplashPlace {
  readonly column: number;
  readonly half: number;
}

/**
 * The circle sampled every 45°, counter-clockwise from the top centre: the
 * column is −round(sin θ), the half row 2 − round(2 cos θ). Every step moves
 * one half row, so nothing stands still and nothing jumps two places.
 */
export const SPLASH_PATH: readonly SplashPlace[] = [
  { column: 0, half: 0 },
  { column: -1, half: 1 },
  { column: -1, half: 2 },
  { column: -1, half: 3 },
  { column: 0, half: 4 },
  { column: 1, half: 3 },
  { column: 1, half: 2 },
  { column: 1, half: 1 },
];

/** The half rows and columns the mark travels inside its box. */
const TRAVEL_HALVES = 4;
const TRAVEL_COLUMNS = 2;

/**
 * The mark that fits: the 8-row one from 24×16, the header's 4-row one from
 * 16×9, none below that.
 */
export function splashMark(
  columns: number,
  rows: number,
): MarkGrid | undefined {
  if (columns >= 24 && rows >= 16) {
    return SPLASH_MARK;
  }

  if (columns >= 16 && rows >= 9) {
    return MARK;
  }

  return undefined;
}

/**
 * The mark's box at `step` of its path: the grid with empty half rows above
 * and empty columns to its left, padded to the box, so the box never changes
 * size and the lines under it never move. An odd half row pairs the grid's
 * half rows the other way, which is what makes the vertical step smooth.
 */
export function splashFrame(grid: MarkGrid, step: number): MarkGrid {
  const place = SPLASH_PATH[step % SPLASH_PATH.length] ?? SPLASH_PATH[0]!;
  const width = (grid[0]?.length ?? 0) + TRAVEL_COLUMNS;
  const left = TRAVEL_COLUMNS / 2 + place.column;
  const empty = () => Array<number | null>(width).fill(null);
  const shifted = grid.map((line) => {
    const row = empty();

    line.forEach((t, column) => (row[left + column] = t));

    return row;
  });

  return [
    ...Array.from({ length: place.half }, empty),
    ...shifted,
    ...Array.from({ length: TRAVEL_HALVES - place.half }, empty),
  ];
}

/** What the splash knows of the start, for its two lines. */
export interface SplashFacts {
  readonly agent: string;
  /** Since the window opened. */
  readonly elapsed: number;
  /** An armed quit's question, which takes the first line. */
  readonly armed?: string | undefined;
  readonly closing: boolean;
}

/**
 * The two lines under the mark, in the status line's own words; the second
 * empty until the start is slow, so nothing above it moves when it comes.
 */
export function splashLines({
  agent,
  elapsed,
  armed,
  closing,
}: SplashFacts): readonly [string, string] {
  const slow = elapsed >= SLOW_START_MS;
  const first = closing
    ? `Stopping ${agent}…`
    : (armed ??
      (slow
        ? `Starting ${agent}… ${formatElapsed(elapsed)}`
        : `Starting ${agent}…`));

  return [first, slow ? SLOW_HINT : ''];
}

/** Where the splash's pieces go on a screen of `columns` by `rows`. */
export interface SplashLayout {
  /** Empty rows above the block. */
  readonly top: number;
  /** Empty columns left of the mark's box. */
  readonly markLeft: number;
  /** Empty columns left of each line. */
  readonly lineLefts: readonly [number, number];
}

/**
 * The block (the box, a blank row and the two lines, or the lines alone)
 * centred on the screen, rounding up and left as the frames do. Worked out
 * on every render, so a resize keeps it centred.
 */
export function splashLayout(
  columns: number,
  rows: number,
  grid: MarkGrid | undefined,
  lines: readonly [string, string],
): SplashLayout {
  const box =
    grid === undefined
      ? undefined
      : {
          width: (grid[0]?.length ?? 0) + TRAVEL_COLUMNS,
          height: (grid.length + TRAVEL_HALVES) / 2,
        };
  const height = (box === undefined ? 0 : box.height + 1) + lines.length;
  const centred = (width: number) =>
    Math.max(0, Math.floor((columns - width) / 2));

  return {
    top: Math.max(0, Math.floor((rows - height) / 2)),
    markLeft: box === undefined ? 0 : centred(box.width),
    lineLefts: [centred(stringWidth(lines[0])), centred(stringWidth(lines[1]))],
  };
}

/**
 * Whether the splash holds the screen: until the first session is up or has
 * failed, or Esc left it; a quit asked for meanwhile keeps it, to say so.
 */
export function splashShown(
  enabled: boolean,
  left: boolean,
  connection: Connection,
): boolean {
  return (
    enabled &&
    !left &&
    (connection.status === 'starting' || connection.status === 'closing')
  );
}
