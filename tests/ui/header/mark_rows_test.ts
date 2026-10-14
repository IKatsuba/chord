import { expect, test } from 'bun:test';
import { MARK, type MarkGrid } from '../../../src/ui/header/mark.ts';
import {
  markPaint,
  markRows,
  type MarkSegment,
  type MarkStops,
} from '../../../src/ui/header/mark_rows.ts';
import { SHAPE } from './mark_spec.ts';

// Every number below is docs/design/CHD-201.md's, from a supersampled
// rasterisation of the same path, not from the generated module.

const DARK: MarkStops = ['#89f5b3', '#47e7a5', '#15c7a2'];
const LIGHT: MarkStops = ['#1e9a5e', '#147d55', '#0a5e57'];

const DARK_256 = `
121  .   .   .
 85  85  .   .
 85  85  85  .
 .   78  78  78
 .   78  78  78
 78  78  43  .
 78  43  .   .
 43  .   .   .`;

const LIGHT_256 = `
29  .  .  .
29 29  .  .
29 29 29  .
 . 29 29 29
 . 29 29 29
29 29 29  .
29 29  .  .
23  .  .  .`;

/** One of the spec's maps as half rows of xterm indices. */
function table(text: string): (number | null)[][] {
  return text
    .trim()
    .split('\n')
    .map((line) =>
      line
        .trim()
        .split(/\s+/)
        .map((cell) => (cell === '.' ? null : Number(cell))),
    );
}

/** Each filled half cell's xterm index under `stops`. */
function indices(grid: MarkGrid, stops: MarkStops): (number | null)[][] {
  const paint = markPaint(stops, '256');

  return grid.map((line) =>
    line.map((t) =>
      t === null ? null : Number(/\((\d+)\)/.exec(paint(t))?.[1] ?? Number.NaN),
    ),
  );
}

function text(rows: MarkSegment[][]): string[] {
  return rows.map((row) => row.map((segment) => segment.text).join(''));
}

test('the mark is 4 rows of 4 columns, as the spec draws it', () => {
  expect(text(markRows(MARK, { level: 'none' }))).toStrictEqual(SHAPE);
});

test('a half cell sits on the diagonal at its centre', () => {
  // The mark's top-left half cell is 12.5 units square, its centre at
  // (6.25, 6.25) on the 54.367 × 100 viewBox.
  const span = 54.367 ** 2 + 100 ** 2;

  expect(
    Math.abs(
      (MARK[0]?.[0] ?? Number.NaN) - (6.25 * 54.367 + 6.25 * 100) / span,
    ),
  ).toBeLessThanOrEqual(1e-4);
});

test('at 256 colours the dark mark takes the spec’s xterm indices', () => {
  expect(indices(MARK, DARK)).toStrictEqual(table(DARK_256));
});

test('at 256 colours the light mark takes the spec’s xterm indices', () => {
  expect(indices(MARK, LIGHT)).toStrictEqual(table(LIGHT_256));
});

test('256 colours go by OKLab, so #147d55 is green, not teal', () => {
  // chalk's rgbToAnsi256 gives 30, #008787.
  expect(markPaint(LIGHT, '256')(0.55)).toStrictEqual('ansi256(29)');
  expect(markPaint(DARK, '256')(0)).toStrictEqual('ansi256(121)');
  expect(markPaint(DARK, '256')(0.55)).toStrictEqual('ansi256(78)');
  expect(markPaint(DARK, '256')(1)).toStrictEqual('ansi256(43)');
});

test('the gradient’s ends and middle are the stops’ colours', () => {
  for (const stops of [DARK, LIGHT]) {
    const paint = markPaint(stops, 'truecolor');

    expect([paint(0), paint(0.55), paint(1)]).toStrictEqual([...stops]);
  }
});

test('a cell between the gradient’s ends is ▀ on the bottom’s colour', () => {
  expect(
    markRows([[0], [1]], { level: 'truecolor', stops: DARK }),
  ).toStrictEqual([
    [{ text: '▀', color: '#89f5b3', backgroundColor: '#15c7a2' }],
  ]);
});

test('two halves of one colour are █, and one style is one segment', () => {
  expect(
    markRows(
      [
        [0, 0, null, 0],
        [0, 0, 0, 1],
      ],
      { level: '256', stops: DARK },
    ),
  ).toStrictEqual([
    [
      { text: '██▄', color: 'ansi256(121)' },
      { text: '▀', color: 'ansi256(121)', backgroundColor: 'ansi256(43)' },
    ],
  ]);
});

test('a half filled alone keeps the terminal’s background', () => {
  const rows = markRows(MARK, { level: 'truecolor', stops: DARK });
  const halves = rows
    .flat()
    .filter(
      (segment) => segment.text.includes('▄') && !segment.text.includes('█'),
    );

  expect(halves.length > 0).toBeTruthy();

  for (const segment of halves) {
    expect(segment.backgroundColor).toStrictEqual(undefined);
  }
});

test('at 16 colours the mark is one tone, every full cell █', () => {
  const rows = markRows(MARK, { level: '16', tone: 'greenBright' });

  expect(text(rows)).toStrictEqual(SHAPE);

  for (const segment of rows.flat()) {
    expect(segment.backgroundColor).toStrictEqual(undefined);
    expect(segment.color).toStrictEqual(
      segment.text.trim() === '' ? undefined : 'greenBright',
    );
  }
});

test('with no colour the mark is plain ▀ ▄ █', () => {
  for (const segment of markRows(MARK, { level: 'none' }).flat()) {
    expect(segment).toStrictEqual({ text: segment.text });
    expect(/^[▀▄█ ]+$/.test(segment.text)).toBeTruthy();
  }
});
