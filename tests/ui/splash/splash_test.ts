import { expect, test } from 'bun:test';
import { MARK, SPLASH_MARK } from '../../../src/ui/header/mark.ts';
import { markRows } from '../../../src/ui/header/mark_rows.ts';
import {
  SLOW_HINT,
  SLOW_START_MS,
  SPLASH_PATH,
  splashFrame,
  splashLayout,
  splashLines,
  splashMark,
  splashShown,
} from '../../../src/ui/splash/splash.ts';

function text(step: number, grid = SPLASH_MARK): string[] {
  return markRows(splashFrame(grid, step), { level: 'none' }).map((row) =>
    row.map((segment) => segment.text).join(''),
  );
}

test('the path is the circle every 45°, counter-clockwise from the top', () => {
  SPLASH_PATH.forEach((place, step) => {
    const angle = (step * Math.PI) / 4;

    expect(place).toStrictEqual({
      column: -Math.round(Math.sin(angle)) || 0,
      half: 2 - Math.round(2 * Math.cos(angle)),
    });
  });

  // Left first.
  expect(SPLASH_PATH[1]?.column).toStrictEqual(-1);
});

test('every step moves one half row and at most one column', () => {
  SPLASH_PATH.forEach((place, step) => {
    const next = SPLASH_PATH[(step + 1) % SPLASH_PATH.length]!;

    expect(Math.abs(next.half - place.half)).toStrictEqual(1);
    expect(Math.abs(next.column - place.column) <= 1).toBeTruthy();
  });
});

test('the box keeps its size at every step, so the lines never move', () => {
  for (const [grid, size] of [
    [SPLASH_MARK, [10, 11]],
    [MARK, [6, 6]],
  ] as const) {
    for (let step = 0; step < SPLASH_PATH.length; step++) {
      const rows = text(step, grid);

      expect(rows.length).toStrictEqual(size[0]);
      rows.forEach((row) => expect(row.length).toStrictEqual(size[1]));
    }
  }
});

test('the top centre is the mark one column in', () => {
  expect(text(0)).toStrictEqual([
    ' ██▄       ',
    ' ████▄     ',
    ' ██████▄   ',
    '  ▀██████▄ ',
    '  ▄██████▀ ',
    ' ██████▀   ',
    ' ████▀     ',
    ' ██▀       ',
    '           ',
    '           ',
  ]);
});

test('an odd half row is a drawing of its own, not the rows moved', () => {
  expect(text(1)).toStrictEqual([
    '▄▄         ',
    '███▄       ',
    '█████▄     ',
    '▀██████▄   ',
    '  ███████  ',
    '▄██████▀   ',
    '█████▀     ',
    '███▀       ',
    '▀▀         ',
    '           ',
  ]);
  expect(text(5, MARK)).toStrictEqual([
    '      ',
    '  ▄   ',
    '  ██▄ ',
    '   ███',
    '  ██▀ ',
    '  ▀   ',
  ]);
});

test('the mark is 8 rows from 24×16, 4 from 16×9, none below', () => {
  expect(splashMark(120, 40)).toStrictEqual(SPLASH_MARK);
  expect(splashMark(80, 24)).toStrictEqual(SPLASH_MARK);
  expect(splashMark(24, 16)).toStrictEqual(SPLASH_MARK);
  expect(splashMark(24, 15)).toStrictEqual(MARK);
  expect(splashMark(44, 12)).toStrictEqual(MARK);
  expect(splashMark(16, 9)).toStrictEqual(MARK);
  expect(splashMark(15, 40)).toStrictEqual(undefined);
  expect(splashMark(40, 8)).toStrictEqual(undefined);
});

test('the lines say the start, then its seconds and the keys once slow', () => {
  const facts = { agent: 'claude', elapsed: 0, closing: false };

  expect(splashLines(facts)).toStrictEqual(['Starting claude…', '']);
  expect(splashLines({ ...facts, elapsed: SLOW_START_MS - 1 })).toStrictEqual([
    'Starting claude…',
    '',
  ]);
  expect(splashLines({ ...facts, elapsed: 12_400 })).toStrictEqual([
    'Starting claude… 12s',
    SLOW_HINT,
  ]);
  expect(SLOW_HINT).toStrictEqual('esc for the window · ctrl+c to quit');
});

test('an armed quit and the stop take the first line', () => {
  const facts = { agent: 'claude', elapsed: 12_000, closing: false };
  const armed = 'Press ctrl+c again to quit';

  expect(splashLines({ ...facts, armed })).toStrictEqual([armed, SLOW_HINT]);
  expect(splashLines({ ...facts, elapsed: 0, armed })).toStrictEqual([
    armed,
    '',
  ]);
  expect(splashLines({ ...facts, armed, closing: true })).toStrictEqual([
    'Stopping claude…',
    SLOW_HINT,
  ]);
});

test('the block is centred, rounding up and left, as the frames are', () => {
  const quick = splashLines({ agent: 'claude', elapsed: 0, closing: false });
  const slow = splashLines({
    agent: 'claude',
    elapsed: 12_000,
    closing: false,
  });

  expect(splashLayout(80, 24, SPLASH_MARK, quick)).toStrictEqual({
    top: 5,
    markLeft: 34,
    lineLefts: [32, 40],
  });
  expect(splashLayout(120, 40, SPLASH_MARK, quick).top).toStrictEqual(13);
  expect(splashLayout(120, 40, SPLASH_MARK, quick).markLeft).toStrictEqual(54);
  expect(splashLayout(44, 12, MARK, slow)).toStrictEqual({
    top: 1,
    markLeft: 19,
    lineLefts: [12, 4],
  });
  expect(splashLayout(40, 7, undefined, slow)).toStrictEqual({
    top: 2,
    markLeft: 0,
    lineLefts: [10, 2],
  });
  // A line wider than the screen starts at its left edge.
  expect(splashLayout(20, 7, undefined, slow).lineLefts).toStrictEqual([0, 0]);
});

test('the splash holds the screen until the start ends or esc leaves it', () => {
  const starting = { status: 'starting' } as const;

  expect(splashShown(true, false, starting)).toBeTruthy();
  expect(splashShown(true, false, { status: 'closing' })).toBeTruthy();
  expect(!splashShown(true, false, { status: 'ready' })).toBeTruthy();
  expect(
    !splashShown(true, false, { status: 'failed', message: 'boom' }),
  ).toBeTruthy();
  expect(!splashShown(true, true, starting)).toBeTruthy();
  expect(!splashShown(false, false, starting)).toBeTruthy();
});
