import { describe, expect, test } from 'bun:test';
import {
  BUDGET_MS,
  compare,
  fails,
  isTestFile,
  MOVED,
  readTimings,
  reportLines,
  wholeSuite,
} from '../../../scripts/dev/timings.ts';

const A = 'tests/a_test.ts';

describe('which run is the whole suite', () => {
  test('none, flags that filter nothing, and a refresh are', () => {
    expect(wholeSuite([])).toBe(true);
    expect(wholeSuite(['--update-timings'])).toBe(true);
    expect(wholeSuite(['--reporter=junit', '--reporter-outfile=x.xml'])).toBe(
      true,
    );
  });

  test('a name pattern, changed files, a path, a bail or a shard are not', () => {
    for (const args of [
      ['-t', 'tabs'],
      ['--test-name-pattern=tabs'],
      ['--changed'],
      ['--changed=main'],
      ['./tests/a_test.ts'],
      ['--bail'],
      ['--shard=1/2'],
      ['--only'],
      ['--no-isolate'],
    ]) {
      expect(wholeSuite(args)).toBe(false);
    }
  });
});

test("a timings file's times; none from none, or from one without files", () => {
  expect(
    readTimings(JSON.stringify({ version: 1, files: { [A]: 1200 } })),
  ).toStrictEqual({ [A]: 1200 });
  expect(readTimings(undefined)).toStrictEqual({});
  expect(readTimings('{"version":1}')).toStrictEqual({});
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
