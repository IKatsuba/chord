import { expect, test } from 'bun:test';
import { readFile } from 'node:fs/promises';
import { initWasm } from '@resvg/resvg-wasm';
import { formatModule } from '../../../scripts/format.ts';
import {
  coverage,
  markGrid,
  markModule,
  ROWS,
  SPLASH_ROWS,
  THRESHOLD,
  viewBox,
} from '../../../scripts/dev/mark.ts';
import {
  MARK,
  type MarkGrid,
  SPLASH_MARK,
} from '../../../src/ui/header/mark.ts';
import { markRows } from '../../../src/ui/header/mark_rows.ts';
import { SHAPE, SPLASH_SHAPE } from './mark_spec.ts';

// The generator, run afresh from scripts/mark.svg: without this a broken
// rasteriser would pass beside a stale module.

await initWasm(
  await readFile(
    new URL(import.meta.resolve('@resvg/resvg-wasm/index_bg.wasm')),
  ),
);

const SVG = await readFile(
  new URL('../../../scripts/mark.svg', import.meta.url),
  'utf8',
);
const BOX = viewBox(SVG);
const COVERED = coverage(SVG, ROWS);
const FRESH = markGrid(COVERED, ROWS, BOX);
const SPLASH_COVERED = coverage(SVG, SPLASH_ROWS);
const SPLASH_FRESH = markGrid(SPLASH_COVERED, SPLASH_ROWS, BOX);

function text(grid: (number | null)[][]): string[] {
  return markRows(grid, { level: 'none' }).map((row) =>
    row.map((segment) => segment.text).join(''),
  );
}

test('the viewBox is read as written, not rounded', () => {
  expect(BOX).toStrictEqual({ width: 54.367, height: 100 });
});

test('the SVG rasterises to the spec’s shape', () => {
  expect(text(FRESH)).toStrictEqual(SHAPE);
});

test('the SVG rasterises to the splash’s shape at 8 rows', () => {
  expect(text(SPLASH_FRESH)).toStrictEqual(SPLASH_SHAPE);
});

test('no half cell sits near the threshold', () => {
  // Antialiasing in another resvg could not move the grid.
  for (const share of [...COVERED.flat(), ...SPLASH_COVERED.flat()]) {
    expect(
      Math.abs(share - THRESHOLD) > 0.05,
      `coverage ${share}`,
    ).toBeTruthy();
  }
});

test('each filled half cell is on the diagonal at its centre', () => {
  const span = BOX.width ** 2 + BOX.height ** 2;

  for (const [grid, rows] of [
    [FRESH, ROWS],
    [SPLASH_FRESH, SPLASH_ROWS],
  ] as const) {
    const unit = BOX.height / (2 * rows);

    grid.forEach((line, row) =>
      line.forEach((t, column) => {
        if (t !== null) {
          const x = (column + 0.5) * unit;
          const y = (row + 0.5) * unit;

          expect(
            Math.abs(t - (x * BOX.width + y * BOX.height) / span),
          ).toBeLessThanOrEqual(1e-4);
        }
      }),
    );
  }
});

test('the committed module is what the generator writes', async () => {
  expect<MarkGrid>(FRESH).toStrictEqual(MARK);
  expect<MarkGrid>(SPLASH_FRESH).toStrictEqual(SPLASH_MARK);

  expect(await formatModule(markModule(FRESH, SPLASH_FRESH))).toStrictEqual(
    await readFile(
      new URL('../../../src/ui/header/mark.ts', import.meta.url),
      'utf8',
    ),
  );
});
