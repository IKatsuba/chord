import { describe, expect, test } from 'bun:test';
import stringWidth from 'string-width';
import {
  hintRows,
  listLines,
  startLayout,
  versionLine,
  wordmarkColours,
} from '../../../src/ui/app/start_layout.ts';

const agents = { framed: false, hintRows: 1 };
const sessions = { framed: true, hintRows: 1 };

describe('startLayout', () => {
  test.each([
    [120, 40, 28, false, 1, 'full', 14, 4],
    [120, 40, 5, false, 1, 'full', 5, 9],
    [120, 40, 14, true, 1, 'full', 14, 3],
    [80, 24, 28, false, 1, 'compact', 12, 0],
    [80, 24, 14, true, 1, 'compact', 9, 0],
    [59, 40, 28, false, 2, 'compact', 28, 0],
    [39, 24, 28, false, 2, 'line', 15, 0],
    [30, 12, 14, true, 3, 'none', 1, 0],
    [30, 8, 28, false, 3, 'none', 1, 0],
  ] as const)(
    '%i×%i with %i lines, framed %p, %i hint rows: %s, %i rows, top %i',
    (columns, rows, lines, framed, hintRows, step, listRows, top) => {
      expect(
        startLayout({ columns, rows, lines, framed, hintRows }),
      ).toMatchObject({ step, listRows, top });
    },
  );

  test.each([
    [120, 32, 'full'],
    [120, 31, 'compact'],
    [60, 40, 'full'],
    [59, 40, 'compact'],
    [80, 18, 'compact'],
    [80, 17, 'line'],
    [40, 24, 'compact'],
    [39, 24, 'line'],
  ] as const)('%i×%i is %s', (columns, rows, step) => {
    expect(startLayout({ columns, rows, lines: 5, ...agents }).step).toBe(step);
  });

  test.each([
    [false, 1, 10, 'line'],
    [false, 1, 9, 'none'],
    [false, 2, 11, 'line'],
    [false, 2, 10, 'none'],
    [true, 1, 13, 'line'],
    [true, 1, 12, 'none'],
  ] as const)(
    'framed %p with %i hint rows at %i rows is %s',
    (framed, hintRows, rows, step) => {
      expect(
        startLayout({ columns: 39, rows, lines: 28, framed, hintRows }).step,
      ).toBe(step);
    },
  );

  test('the list never moves a window to another step', () => {
    for (const lines of [1, 5, 14, 15, 28, 1000]) {
      expect(
        startLayout({ columns: 120, rows: 32, lines, ...agents }).step,
      ).toBe('full');
      expect(
        startLayout({ columns: 120, rows: 31, lines, ...agents }).step,
      ).toBe('compact');
    }
  });

  test('the cap of 14 belongs to full alone', () => {
    expect(
      startLayout({ columns: 120, rows: 32, lines: 28, ...agents }).listRows,
    ).toBe(14);
    expect(
      startLayout({ columns: 120, rows: 31, lines: 28, ...agents }).listRows,
    ).toBe(19);
  });

  test('a list that exactly fits takes no row for what is hidden', () => {
    const fits = { columns: 80, rows: 24, ...agents };

    // 24 rows less 5 of art, a gap, 4 around the list and a margin.
    expect(startLayout({ ...fits, lines: 13 }).listRows).toBe(13);
    expect(startLayout({ ...fits, lines: 14 }).listRows).toBe(12);
    expect(
      startLayout({ columns: 120, rows: 40, lines: 14, ...agents }).listRows,
    ).toBe(14);
    expect(
      startLayout({ columns: 120, rows: 40, lines: 15, ...agents }).listRows,
    ).toBe(14);
  });

  test('none gives up the gap for the agents, and the frame keeps its row', () => {
    // Each is the smallest window that holds its whole page of one line.
    expect(
      startLayout({ columns: 30, rows: 5, lines: 1, ...agents }),
    ).toMatchObject({ step: 'none', listRows: 1, top: 0 });
    expect(
      startLayout({ columns: 30, rows: 9, lines: 1, ...sessions }),
    ).toMatchObject({ step: 'none', listRows: 1, top: 0 });
    expect(
      startLayout({ columns: 30, rows: 8, lines: 1, ...sessions }).listRows,
    ).toBe(1);
  });

  test('the list is never under one row, nor the top above the window', () => {
    for (const framed of [false, true]) {
      for (const hintRows of [1, 2, 3]) {
        for (const columns of [1, 30, 39, 40, 59, 60, 120]) {
          for (let rows = 1; rows <= 45; rows++) {
            for (const lines of [0, 1, 2, 14, 15, 28]) {
              const page = startLayout({
                columns,
                rows,
                lines,
                framed,
                hintRows,
              });

              expect(page.listRows).toBeGreaterThanOrEqual(1);
              expect(page.top).toBeGreaterThanOrEqual(0);
            }
          }
        }
      }
    }
  });

  test('no agents take one row', () => {
    expect(
      startLayout({ columns: 80, rows: 24, lines: 1, ...agents }),
    ).toMatchObject({ step: 'compact', listRows: 1, top: 6 });
  });

  test.each([
    [120, false, 62],
    [64, false, 62],
    [63, false, 61],
    [120, true, 84],
    [86, true, 84],
    [80, true, 78],
    [2, false, 1],
    [1, true, 1],
  ] as const)(
    '%i columns, framed %p: a column of %i',
    (columns, framed, column) => {
      expect(
        startLayout({ columns, rows: 40, lines: 5, framed, hintRows: 1 })
          .column,
      ).toBe(column);
    },
  );
});

describe('versionLine', () => {
  const base = { version: '0.65.0', directory: '~/src/app', width: 118 };

  test('the agents have the version and directory', () => {
    expect(versionLine(base)).toBe('v0.65.0 · ~/src/app');
  });

  test('resume names its agent after the version', () => {
    expect(versionLine({ ...base, agent: 'claude' })).toBe(
      'v0.65.0 · claude · ~/src/app',
    );
  });

  test('the directory is cut first, from the left, at a separator', () => {
    const line = versionLine({
      ...base,
      agent: 'claude',
      directory: '~/work/acme/services/billing/acme-api',
      width: 48,
    });

    expect(line).toBe('v0.65.0 · claude · …/services/billing/acme-api');
    expect(stringWidth(line)).toBeLessThanOrEqual(48);
  });

  test('a line that exactly fits is not cut', () => {
    expect(versionLine({ ...base, width: 19 })).toBe('v0.65.0 · ~/src/app');
    expect(versionLine({ ...base, width: 18 })).not.toContain('~/src/app');
  });

  test('a rest too wide stays whole for the text to cut', () => {
    expect(versionLine({ ...base, agent: 'claude', width: 10 })).toBe(
      'v0.65.0 · claude · …',
    );
  });
});

describe('CHD-564 tester: page space and display-width edges', () => {
  test('a wrapped resume hint gives up a list row before hiding the line', () => {
    const page = { columns: 39, lines: 28, framed: true, hintRows: 2 };

    expect(startLayout({ ...page, rows: 14 })).toMatchObject({
      step: 'line',
      listRows: 2,
      top: 0,
    });
    expect(startLayout({ ...page, rows: 13 })).toMatchObject({
      step: 'none',
      listRows: 3,
      top: 0,
    });
  });

  test('compact resume reserves the hidden-row indicator only after overflow', () => {
    const page = { columns: 80, rows: 24, ...sessions };

    expect(startLayout({ ...page, lines: 10 }).listRows).toBe(10);
    expect(startLayout({ ...page, lines: 11 }).listRows).toBe(9);
  });

  test('hint wrapping consumes list room without changing either column', () => {
    for (const framed of [false, true]) {
      const page = { columns: 120, rows: 31, lines: 100, framed };
      const shortHint = startLayout({ ...page, hintRows: 1 });
      const wrappedHint = startLayout({ ...page, hintRows: 3 });

      expect(wrappedHint.step).toBe(shortHint.step);
      expect(wrappedHint.column).toBe(shortHint.column);
      expect(wrappedHint.listRows).toBe(shortHint.listRows - 2);
    }
  });

  test('a wide-character directory fits exactly by cells, then loses its left', () => {
    const page = { version: '0.65.0', directory: '~/界/项目' };
    const whole = 'v0.65.0 · ~/界/项目';
    const width = stringWidth(whole);

    expect(versionLine({ ...page, width })).toBe(whole);

    const cut = versionLine({ ...page, width: width - 1 });

    expect(cut).toBe('v0.65.0 · …/项目');
    expect(stringWidth(cut)).toBeLessThanOrEqual(width - 1);
  });

  test('a wide-character agent keeps its name while the directory shrinks', () => {
    const line = versionLine({
      version: '0.65.0',
      agent: '界',
      directory: '~/work/services/app',
      width: 20,
    });

    expect(line).toBe('v0.65.0 · 界 · …/app');
    expect(stringWidth(line)).toBeLessThanOrEqual(20);
  });
});

describe('hintRows', () => {
  const hint = '↑↓ or j/k to move · Enter or 1–9 to select · Esc to cancel';

  test.each([
    [60, 1],
    [58, 1],
    [57, 2],
    [37, 2],
    [28, 3],
  ] as const)('at %i columns it takes %i rows', (width, rows) => {
    expect(hintRows(hint, width)).toBe(rows);
  });

  test('an empty hint and a window with no room stay countable', () => {
    expect(hintRows('', 10)).toBe(1);
    expect(hintRows('Esc', 0)).toBe(3);
  });
});

describe('wordmarkColours', () => {
  test.each([
    [['#89f5b3', '#47e7a5', '#15c7a2'], '#47e7a5', '#15c7a2'],
    [['#1e9a5e', '#147d55', '#0a5e57'], '#147d55', '#0a5e57'],
  ] as const)('truecolor %j: the middle and last stops', (stops, c1, c2) => {
    expect(wordmarkColours({ level: 'truecolor', stops })).toEqual([c1, c2]);
  });

  test('256 colours name the nearest of the cube', () => {
    expect(
      wordmarkColours({
        level: '256',
        stops: ['#89f5b3', '#47e7a5', '#15c7a2'],
      })?.every((each) => /^ansi256\(\d+\)$/.test(each)),
    ).toBe(true);
  });

  test('16 colours take the tone for both, and no colour has no wordmark', () => {
    expect(wordmarkColours({ level: '16', tone: 'green' })).toEqual([
      'green',
      'green',
    ]);
    expect(wordmarkColours({ level: 'none' })).toBeUndefined();
  });
});

describe('listLines', () => {
  const session = (label: string) => ({
    key: label,
    value: label,
    label: `today  ${label}`,
    hang: 7,
  });
  const long = 'a title long enough that a frame of forty has to wrap it';

  test('labels of one line count one each', () => {
    expect(listLines([session('a'), session('b')], 84)).toBe(2);
    expect(listLines([{ key: 'a', value: 'a', label: long }], 10)).toBe(1);
  });

  test('a label that wraps counts its lines, in the width given', () => {
    expect(listLines([session(long)], 84)).toBe(1);
    expect(listLines([session(long)], 40)).toBeGreaterThan(1);
  });

  test('an empty list takes the row that says so', () => {
    expect(listLines([], 84)).toBe(1);
  });
});
