import { describe, expect, test } from 'bun:test';
import stringWidth from 'string-width';
import { CRASH_HINT, crashRows } from '../../../src/ui/app/crash.ts';

/** The error of the design's mocks (`docs/design/CHD-468.md`). */
function refused(): Error {
  const error = new Error(
    'codex not started: agents.codex.command in .chord/settings.json: expected a string, got a number',
  );

  error.stack = [
    String(error),
    ...[
      '<anonymous> (/$bunfs/root/chord:216192:24)',
      'start (/$bunfs/root/chord:214348:31)',
      'open (/$bunfs/root/chord:215693:23)',
      '<anonymous> (/$bunfs/root/chord:216811:20)',
      'commitHookEffectListMount (/$bunfs/root/chord:4702:34)',
      'commitPassiveMountOnFiber (/$bunfs/root/chord:5591:52)',
      'recursivelyTraversePassiveMountEffects (/$bunfs/root/chord:5582:36)',
      'commitPassiveMountOnFiber (/$bunfs/root/chord:5590:49)',
      'recursivelyTraversePassiveMountEffects (/$bunfs/root/chord:5582:36)',
      'commitPassiveMountOnFiber (/$bunfs/root/chord:5632:49)',
    ].map((frame) => `    at ${frame}`),
  ].join('\n');

  return error;
}

const text = (columns: number, rows: number) =>
  crashRows(refused(), columns, rows).map((row) => row.text);

test('at 80x24 the message wraps once, every frame fits, and the hint is last (CHD-468)', () => {
  const rows = crashRows(refused(), 80, 24);

  expect(rows.map((row) => row.text)).toStrictEqual([
    '',
    '  Error: codex not started: agents.codex.command in .chord/settings.json:',
    '  expected a string, got a number',
    '      at <anonymous> (/$bunfs/root/chord:216192:24)',
    '      at start (/$bunfs/root/chord:214348:31)',
    '      at open (/$bunfs/root/chord:215693:23)',
    '      at <anonymous> (/$bunfs/root/chord:216811:20)',
    '      at commitHookEffectListMount (/$bunfs/root/chord:4702:34)',
    '      at commitPassiveMountOnFiber (/$bunfs/root/chord:5591:52)',
    '      at recursivelyTraversePassiveMountEffects (/$bunfs/root/chord:5582:36)',
    '      at commitPassiveMountOnFiber (/$bunfs/root/chord:5590:49)',
    '      at recursivelyTraversePassiveMountEffects (/$bunfs/root/chord:5582:36)',
    '      at commitPassiveMountOnFiber (/$bunfs/root/chord:5632:49)',
    '',
    `  ${CRASH_HINT}`,
  ]);
  expect(rows.map((row) => row.role)).toStrictEqual([
    'blank',
    'error',
    'error',
    ...Array<'dim'>(10).fill('dim'),
    'blank',
    'dim',
  ]);
});

test('at 120x40 the message is one row and nothing is cut (CHD-468)', () => {
  const rows = text(120, 40);

  expect(rows).toHaveLength(14);
  expect(rows[1]).toBe(
    '  Error: codex not started: agents.codex.command in .chord/settings.json: expected a string, got a number',
  );
});

test('at 60x9 the frames go from the bottom, a row says how many, and a cut hint ends in … (CHD-468)', () => {
  expect(text(60, 9)).toStrictEqual([
    '',
    '  Error: codex not started: agents.codex.command in',
    '  .chord/settings.json: expected a string, got a number',
    '      at <anonymous> (/$bunfs/root/chord:216192:24)',
    '      at start (/$bunfs/root/chord:214348:31)',
    '      at open (/$bunfs/root/chord:215693:23)',
    '      … 7 more frames',
    '',
    '  any key to quit · chord prints the error to stderr as it …',
  ]);
});

test('at 40x4 the frames and blank rows are gone, and the last message row kept ends in … (CHD-468)', () => {
  expect(text(40, 4)).toStrictEqual([
    '  Error: codex not started:',
    '  agents.codex.command in',
    '  .chord/settings.json: expected a…',
    '  any key to quit · chord prints the er…',
  ]);
});

test('the rows go in the design’s order as the window shrinks, the hint last (CHD-468)', () => {
  // 2 message rows, 10 frames, 2 blank rows and the hint at 80.
  expect(text(80, 14)).toContain('      … 2 more frames');
  expect(text(80, 6).slice(3)).toStrictEqual([
    '      … 10 more frames',
    '',
    `  ${CRASH_HINT}`,
  ]);
  expect(text(80, 5)).toStrictEqual([
    '',
    '  Error: codex not started: agents.codex.command in .chord/settings.json:',
    '  expected a string, got a number',
    '',
    `  ${CRASH_HINT}`,
  ]);
  expect(text(80, 4)[0]).toStartWith('  Error:');
  expect(text(80, 2)).toStrictEqual([
    '  Error: codex not started: agents.codex.command in .chord/settings.json:…',
    `  ${CRASH_HINT}`,
  ]);
  expect(text(80, 1)).toStrictEqual([`  ${CRASH_HINT}`]);
});

test('a thrown value that is no Error is its String, with no frames (CHD-468)', () => {
  expect(
    crashRows('the session went away', 80, 24).map((row) => row.text),
  ).toStrictEqual(['', '  the session went away', '', `  ${CRASH_HINT}`]);
});

describe('CHD-468 tester: crash message and stack edges', () => {
  test('a multiline named error keeps its message lines once before its frames', () => {
    const error = new TypeError('first line\nsecond line');

    error.stack = `${String(error)}\n    at worker (/work/code.ts:4:2)`;

    expect(crashRows(error, 80, 24).map((row) => row.text)).toStrictEqual([
      '',
      '  TypeError: first line',
      '  second line',
      '      at worker (/work/code.ts:4:2)',
      '',
      `  ${CRASH_HINT}`,
    ]);
  });

  test('wide and combining characters wrap while a long frame stays one cut row', () => {
    const error = new Error('界e\u0301'.repeat(12));

    error.stack = `${String(error)}\n    at worker (/work/${'segment'.repeat(12)}.ts:4:2)`;

    const rows = crashRows(error, 12, 24);
    const frames = rows.filter((row) => row.text.startsWith('      at '));

    expect(frames).toHaveLength(1);
    expect(frames[0]?.text).toEndWith('…');
    expect(rows.filter((row) => row.role === 'error').length).toBeGreaterThan(
      1,
    );

    for (const row of rows) {
      expect(stringWidth(row.text)).toBeLessThanOrEqual(12);
    }
  });

  test('an Error without a stack still keeps the message and hint', () => {
    const error = new Error('no stack is available');

    delete error.stack;

    expect(crashRows(error, 80, 24).map((row) => row.text)).toStrictEqual([
      '',
      '  Error: no stack is available',
      '',
      `  ${CRASH_HINT}`,
    ]);
  });

  test('the hint survives every small height for an error without frames', () => {
    for (const height of [1, 2, 3, 4, 5, 6]) {
      const rows = crashRows('a long message '.repeat(20), 30, height);

      expect(rows.length).toBeLessThanOrEqual(height);
      expect(rows.at(-1)?.text).toBe('  any key to quit · chord pri…');
      expect(rows.at(-1)?.role).toBe('dim');

      if (height > 1) {
        expect(rows.at(-2)?.text).toEndWith('…');
      }
    }
  });
});
