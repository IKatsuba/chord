import { describe, expect, test } from 'bun:test';
import {
  BUDGET_MS,
  compare,
  fails,
  isTestFile,
  MOVED,
  readTimings,
  reportLines,
} from '../../../scripts/dev/timings.ts';

const A = 'tests/a_test.ts';

test("a timings file's times; one missing, not JSON or without times is an error naming it", () => {
  expect(
    readTimings('t.json', JSON.stringify({ version: 1, files: { [A]: 1200 } })),
  ).toStrictEqual({ [A]: 1200 });
  expect(() => readTimings('t.json', undefined)).toThrow(
    'timings: t.json is not there',
  );
  expect(() => readTimings('t.json', '{"version":')).toThrow(
    'timings: t.json is not JSON',
  );
  expect(() => readTimings('t.json', '{"version":1}')).toThrow(
    "timings: t.json holds no file's time",
  );

  for (const files of [{}, [], [1200]]) {
    expect(() => readTimings('t.json', JSON.stringify({ files }))).toThrow(
      "timings: t.json holds no file's time",
    );
  }

  for (const [ms, said] of [
    ['slow', '"slow"'],
    [-1, '-1'],
    [null, 'null'],
  ] as const) {
    expect(() =>
      readTimings('t.json', JSON.stringify({ files: { [A]: ms } })),
    ).toThrow(`timings: t.json holds ${said} as ${A}'s time`);
  }

  // Infinity and NaN are not JSON's, but a text may still say 1e999.
  expect(() => readTimings('t.json', `{"files":{"${A}":1e999}}`)).toThrow(
    `timings: t.json holds null as ${A}'s time`,
  );
});

test("a test file is named as Bun's runner finds one", () => {
  for (const path of [A, 'tests/b_test.tsx', 'x.test.ts', 'x_spec.js']) {
    expect(isTestFile(path)).toBe(true);
  }

  for (const path of ['tests/ui/app/render.tsx', 'tests/timings.json']) {
    expect(isTestFile(path)).toBe(false);
  }
});

describe('a run against the record', () => {
  test('over the budget is a file past it, not one at it', () => {
    const report = compare(
      { [A]: 1, 'tests/b_test.ts': 1 },
      { [A]: BUDGET_MS + 1, 'tests/b_test.ts': BUDGET_MS },
      [A, 'tests/b_test.ts'],
    );

    expect(report.over).toStrictEqual([{ file: A, ms: BUDGET_MS + 1 }]);
  });

  test('moved is both the share and the ms, either way', () => {
    const at = 40_000;
    const by = Math.max(MOVED.ms, MOVED.share * at);

    // Slower or faster by exactly the threshold moves; a ms short does not.
    expect(compare({ [A]: at }, { [A]: at + by }, [A]).moved).toHaveLength(1);
    expect(compare({ [A]: at }, { [A]: at - by }, [A]).moved).toHaveLength(1);
    expect(compare({ [A]: at }, { [A]: at + by - 1 }, [A]).moved).toHaveLength(
      0,
    );
    // A small file's large share is not a move under the ms.
    expect(compare({ [A]: 2_000 }, { [A]: 8_000 }, [A]).moved).toHaveLength(0);
    // A large file's ms is not a move under the share.
    expect(compare({ [A]: 200_000 }, { [A]: 215_000 }, [A]).moved).toHaveLength(
      0,
    );
  });

  test('unrecorded is a test file on disk the record lacks; gone, one recorded no longer there', () => {
    const report = compare({ [A]: 1, 'tests/gone_test.ts': 1 }, {}, [
      A,
      'tests/new_test.ts',
    ]);

    expect(report.unrecorded).toStrictEqual(['tests/new_test.ts']);
    expect(report.gone).toStrictEqual(['tests/gone_test.ts']);
  });

  test('a refresh is held to the budget only', () => {
    const report = compare(
      { [A]: 1, 'tests/gone_test.ts': 1 },
      { [A]: BUDGET_MS + 1 },
      [A, 'tests/new_test.ts'],
      { refreshing: true },
    );

    expect(report).toStrictEqual({
      over: [{ file: A, ms: BUDGET_MS + 1 }],
      moved: [],
      unrecorded: [],
      gone: [],
    });
  });

  test('a run that agrees fails nothing and says nothing', () => {
    const report = compare({ [A]: 30_000 }, { [A]: 31_000 }, [A]);

    expect(fails(report)).toBe(false);
    expect(reportLines(report)).toStrictEqual([]);
  });

  test('a file over the budget alone is told to split, not to refresh', () => {
    const lines = reportLines(
      compare({ [A]: BUDGET_MS }, { [A]: BUDGET_MS + 5_000 }, [A]),
    );

    expect(lines.join('\n')).toContain('split it');
    expect(lines.join('\n')).not.toContain('--update-timings');
  });
});

describe('CHD-501 tester: timing record edges', () => {
  test('zero and fractional times survive reading; malformed roots and entries name the artifact', () => {
    expect(
      readTimings(
        'measured.json',
        '{"files":{"zero_test.ts":0,"part_test.ts":0.5}}',
      ),
    ).toStrictEqual({ 'zero_test.ts': 0, 'part_test.ts': 0.5 });

    for (const text of ['null', '[]', 'false', '{"files":null}']) {
      expect(() => readTimings('measured.json', text)).toThrow(
        "timings: measured.json holds no file's time",
      );
    }

    for (const value of ['true', '"12"', '{}', '[]', '-1e999']) {
      expect(() =>
        readTimings('measured.json', `{"files":{"bad_test.ts":${value}}}`),
      ).toThrow(/measured\.json.*bad_test\.ts/);
    }
  });

  test('a zero baseline still needs the full time threshold and refresh keeps the exact budget', () => {
    expect(compare({ [A]: 0 }, { [A]: MOVED.ms - 1 }, [A]).moved).toStrictEqual(
      [],
    );
    expect(compare({ [A]: 0 }, { [A]: MOVED.ms }, [A]).moved).toStrictEqual([
      { file: A, recorded: 0, measured: MOVED.ms },
    ]);
    expect(
      fails(compare({}, { [A]: BUDGET_MS }, [A], { refreshing: true })),
    ).toBe(false);
    expect(
      fails(compare({}, { [A]: BUDGET_MS + 1 }, [A], { refreshing: true })),
    ).toBe(true);
  });

  test('reports are path ordered without changing the recorded, measured or disk inputs', () => {
    const recorded = Object.freeze({
      'z_test.ts': 30_000,
      'a_test.ts': 30_000,
    });
    const measured = Object.freeze({
      'z_test.ts': 100_000,
      'a_test.ts': 100_000,
    });
    const disk = Object.freeze([
      'z_test.ts',
      'new-z_test.ts',
      'a_test.ts',
      'new-a_test.ts',
    ]);
    const report = compare(recorded, measured, disk);

    expect(report.over.map(({ file }) => file)).toStrictEqual([
      'a_test.ts',
      'z_test.ts',
    ]);
    expect(report.moved.map(({ file }) => file)).toStrictEqual([
      'a_test.ts',
      'z_test.ts',
    ]);
    expect(report.unrecorded).toStrictEqual(['new-a_test.ts', 'new-z_test.ts']);
    expect(disk).toStrictEqual([
      'z_test.ts',
      'new-z_test.ts',
      'a_test.ts',
      'new-a_test.ts',
    ]);
  });
});
