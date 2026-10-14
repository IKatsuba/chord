import { differenceEuclidean, formatHex, interpolate, nearest } from 'culori';
import type { MarkGrid } from './mark.ts';

/** The mark's gradient: its colours at 0, at `MIDDLE` and at 1. */
export type MarkStops = readonly [string, string, string];

/** Where the gradient's middle stop sits, as Chorded's brand sets it. */
export const MIDDLE = 0.55;

/**
 * How the mark is painted: the gradient per half cell, in hex or in the
 * nearest of xterm's 256 colours; one named tone, where only 16 colours are
 * to be had; or no colour at all.
 */
export type MarkColour =
  | { readonly level: 'truecolor' | '256'; readonly stops: MarkStops }
  | { readonly level: '16'; readonly tone: string }
  | { readonly level: 'none' };

/** A run of cells in one style, with colours as chord's palette names them. */
export interface MarkSegment {
  readonly text: string;
  readonly color?: string;
  readonly backgroundColor?: string;
}

const CUBE = [0, 95, 135, 175, 215, 255];

// xterm's 6×6×6 cube and grey ramp, 16 to 255. 0 to 15 are left out because
// terminal themes redefine them.
const XTERM = Array.from({ length: 240 }, (_, offset) => {
  const index = offset + 16;

  if (index >= 232) {
    const grey = (8 + 10 * (index - 232)) / 255;

    return {
      index,
      colour: { mode: 'rgb' as const, r: grey, g: grey, b: grey },
    };
  }

  const at = (step: number) => (CUBE[step] ?? 0) / 255;

  return {
    index,
    colour: {
      mode: 'rgb' as const,
      r: at(Math.floor(offset / 36)),
      g: at(Math.floor(offset / 6) % 6),
      b: at(offset % 6),
    },
  };
});

// Nearest by distance in OKLab: chalk's own rgbToAnsi256 rounds each channel
// to a sixth of the range, but the cube's levels are not evenly spaced, so it
// turns Chorded's light-background green #147d55 teal.
const nearestXterm = nearest(
  XTERM,
  differenceEuclidean('oklab'),
  (entry) => entry.colour,
);

/**
 * The colour of each place on the gradient, as chalk names it: the hex, or the
 * nearest xterm colour's index.
 */
export function markPaint(
  stops: MarkStops,
  level: 'truecolor' | '256',
): (t: number) => string {
  const [from, middle, to] = stops;
  // SVG's linearGradient interpolates in sRGB, as culori's 'rgb' does.
  const gradient = interpolate([from, [middle, MIDDLE], to], 'rgb');

  return (t) => {
    const hex = formatHex(gradient(t));

    if (level === 'truecolor') {
      return hex;
    }

    return `ansi256(${nearestXterm(hex, 1)[0]?.index ?? 16})`;
  };
}

/**
 * The mark as rows of styled runs, one row per two half rows. A cell with
 * both halves filled is `█` where they take one colour, otherwise `▀` with
 * the bottom half's colour behind it; a cell with one half filled is `▀` or
 * `▄` on the terminal's own background; an empty one is a space.
 */
export function markRows(grid: MarkGrid, colour: MarkColour): MarkSegment[][] {
  const paint =
    colour.level === 'none'
      ? () => undefined
      : colour.level === '16'
        ? () => colour.tone
        : markPaint(colour.stops, colour.level);
  const rows: MarkSegment[][] = [];

  for (let half = 0; half < grid.length; half += 2) {
    const top = grid[half] ?? [];
    const bottom = grid[half + 1] ?? [];
    const row: MarkSegment[] = [];

    for (let column = 0; column < top.length; column++) {
      const cell = markCell(top[column] ?? null, bottom[column] ?? null, paint);
      const last = row.at(-1);

      if (
        last !== undefined &&
        last.color === cell.color &&
        last.backgroundColor === cell.backgroundColor
      ) {
        row[row.length - 1] = { ...last, text: last.text + cell.text };
      } else {
        row.push(cell);
      }
    }

    rows.push(row);
  }

  return rows;
}

function markCell(
  top: number | null,
  bottom: number | null,
  paint: (t: number) => string | undefined,
): MarkSegment {
  const upper = top === null ? undefined : paint(top);
  const lower = bottom === null ? undefined : paint(bottom);

  if (top !== null && bottom !== null) {
    return upper === lower ? styled('█', upper) : styled('▀', upper, lower);
  }

  if (top !== null) {
    return styled('▀', upper);
  }

  return bottom === null ? { text: ' ' } : styled('▄', lower);
}

function styled(
  text: string,
  color: string | undefined,
  backgroundColor?: string,
): MarkSegment {
  return {
    text,
    ...(color === undefined ? {} : { color }),
    ...(backgroundColor === undefined ? {} : { backgroundColor }),
  };
}
