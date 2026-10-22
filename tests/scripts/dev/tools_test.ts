import { describe, expect, test } from 'bun:test';
import {
  cp,
  mkdtemp,
  readdir,
  realpath,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { quote } from 'shell-quote';
import {
  check,
  chord,
  fmt,
  lint,
  qaPlace,
  type Run,
  spawn,
  type SuiteFiles,
  test as suite,
} from '../../../scripts/dev/tools.ts';

const bun = process.execPath;
const root = join(import.meta.dir, '..', '..', '..');

/**
 * The files `test` reads, as given: the record, what a run measured and
 * the test files on disk; what it removed and said, kept to be read.
 */
function files(
  record: Record<string, number> = {},
  measured: Record<string, number> | string | null = record,
  onDisk: string[] = Object.keys(record),
): SuiteFiles & { removed: string[]; said: string[] } {
  const removed: string[] = [];
  const said: string[] = [];
  const timings = (times: Record<string, number>) =>
    JSON.stringify({ version: 1, files: times });

  return {
    removed,
    said,
    read: (path) =>
      path === 'tests/timings.json'
        ? timings(record)
        : path === 'tests/timings.measured.json'
          ? // None, a text of its own, or times.
            measured === null
            ? undefined
            : typeof measured === 'string'
              ? measured
              : timings(measured)
          : undefined,
    remove: (path) => void removed.push(path),
    list: () => onDisk,
    say: (line) => void said.push(line),
  };
}

/** A `Run` that records each argv and answers `statuses` in turn, then 0. */
function faked(statuses: number[] = []): { run: Run; ran: string[][] } {
  const ran: string[][] = [];

  return {
    ran,
    run: (argv) => {
      ran.push([...argv]);

      return statuses.shift() ?? 0;
    },
  };
}

describe('chord', () => {
  test("runs src/main.tsx with React's production build", () => {
    const { run, ran } = faked([4]);

    expect(chord(false, ['codex', '-p', 'hi'], run)).toBe(4);
    expect(ran).toStrictEqual([
      [
        bun,
        '--define',
        'process.env.NODE_ENV:"production"',
        'src/main.tsx',
        'codex',
        '-p',
        'hi',
      ],
    ]);
  });

  test('--fake names the fake agent as the agent command', () => {
    const { run, ran } = faked();

    chord(true, ['-p', 'hi'], run);

    expect(ran).toStrictEqual([
      [
        bun,
        '--define',
        'process.env.NODE_ENV:"production"',
        'src/main.tsx',
        'fake',
        '--agent-command',
        quote([bun, join(root, 'tests', 'fixtures', 'fake_agent', 'main.ts')]),
        '-p',
        'hi',
      ],
    ]);
  });
});

test('test runs the whole suite on the timings, its arguments after', () => {
  const { run, ran } = faked();

  suite(['--update-timings'], run, files());

  expect(ran).toStrictEqual([
    [
      bun,
      'test',
      '--parallel',
      '--timeout=60000',
      '--timings=tests/timings.json',
      './tests/',
      '--update-timings',
    ],
  ]);
});

describe("the suite's timings (CHD-501)", () => {
  const A = 'tests/a_test.ts';
  const B = 'tests/ui/b_test.tsx';

  test('a whole run measures into the scratch file beside the record, removed first, and passes when they agree', () => {
    const { run, ran } = faked();
    const io = files(
      { [A]: 20_000, [B]: 40_000 },
      { [A]: 21_000, [B]: 38_000 },
    );

    expect(suite([], run, io)).toBe(0);
    expect(io.removed).toStrictEqual(['tests/timings.measured.json']);
    expect(ran[0]).toContain('--timings=tests/timings.measured.json');
    expect(
      ran[0]?.indexOf('--timings=tests/timings.measured.json'),
    ).toBeLessThan(ran[0]?.indexOf('--timings=tests/timings.json') ?? -1);
    expect(io.said).toStrictEqual([]);
  });

  test('a file over its budget fails the run, named with its time', () => {
    const { run } = faked();
    const io = files({ [A]: 85_000 }, { [A]: 91_000 });

    expect(suite([], run, io)).toBe(1);
    expect(io.said.join('\n')).toContain(`${A}  91.0 s`);
  });

  test('a file moved far from its record, one unrecorded and one gone fail it, with the way to refresh', () => {
    const { run } = faked();
    const io = files(
      { [A]: 20_000, 'tests/gone_test.ts': 5_000 },
      { [A]: 40_000, [B]: 3_000, 'tests/gone_test.ts': 5_000 },
      [A, B],
    );

    expect(suite([], run, io)).toBe(1);

    const said = io.said.join('\n');

    expect(said).toContain(`${A}  20.0 s recorded, 40.0 s now`);
    expect(said).toContain(`run but not in tests/timings.json:\n  ${B}`);
    expect(said).toContain('no longer a test file:\n  tests/gone_test.ts');
    expect(said).toContain('bun dev test --update-timings');
  });

  test("the tests' own failure is the status, the timings' report after it", () => {
    const { run } = faked([3]);
    const io = files({ [A]: 20_000 }, { [A]: 95_000 });

    expect(suite([], run, io)).toBe(3);
    expect(io.said.join('\n')).toContain(A);
  });

  test('a run with any argument is placed by the record and held to nothing', () => {
    for (const args of [
      ['-t', 'tabs'],
      ['-ttabs'],
      ['--changed'],
      ['./tests/a_test.ts'],
      ['--timeout', '60000'],
      ['--reporter', 'junit', '--reporter-outfile', 'x.xml'],
      ['--reporter=junit'],
      ['--help'],
    ]) {
      const { run, ran } = faked();
      const io = files({ [A]: 20_000 }, { [A]: 95_000 });

      expect(suite(args, run, io)).toBe(0);
      expect(ran[0]).not.toContain('--timings=tests/timings.measured.json');
      expect(io.removed).toStrictEqual([]);
      expect(io.said).toStrictEqual([]);
    }
  });

  test('a measurement missing, not JSON or without times fails the run, named, as no measurement is no pass', () => {
    for (const [measured, words] of [
      [null, 'tests/timings.measured.json is not there'],
      ['{"files":', 'tests/timings.measured.json is not JSON'],
      ['{"version":1}', "tests/timings.measured.json holds no file's time"],
    ] as const) {
      const io = files({ [A]: 20_000 }, measured);

      expect(suite([], faked().run, io)).toBe(1);
      expect(io.said).toStrictEqual([`timings: ${words}`]);
    }
  });

  test("the tests' own failure stays the status when the measurement is bad too", () => {
    for (const measured of [null, '{"files":']) {
      const io = files({ [A]: 20_000 }, measured);

      expect(suite([], faked([3]).run, io)).toBe(3);
      expect(io.said).toHaveLength(1);
    }
  });

  test('a refresh rewrites the record and is held to the budget only', () => {
    const { run, ran } = faked();
    const moved = files({ [A]: 80_000 }, undefined, [A, B]);

    expect(suite(['--update-timings'], run, moved)).toBe(0);
    expect(ran[0]).not.toContain('--timings=tests/timings.measured.json');
    expect(moved.removed).toStrictEqual([]);

    const over = files({ [A]: 92_000 });

    expect(suite(['--update-timings'], faked().run, over)).toBe(1);
    expect(over.said.join('\n')).toContain(`${A}  92.0 s`);
  });
});

test('lint and fmt run ESLint and Prettier over the tree', () => {
  const { run, ran } = faked();

  lint(['--fix'], run);
  fmt(run);

  expect(ran).toStrictEqual([
    [bun, 'run', 'eslint', '.', '--fix'],
    [bun, 'run', 'prettier', '--write', '.'],
  ]);
});

describe('check', () => {
  const STATIC = [
    [bun, 'run', 'tsc'],
    [bun, 'scripts/dev/covered.ts'],
    [bun, 'run', 'eslint', '.'],
    [bun, 'run', 'prettier', '--check', '.'],
    [bun, 'test', 'lint/'],
  ];

  test('runs the static steps, then the suite', () => {
    const { run, ran } = faked();

    expect(check({ static: false }, run, () => {}, files())).toBe(0);
    expect(ran).toStrictEqual([
      ...STATIC,
      [
        bun,
        'test',
        '--parallel',
        '--timeout=60000',
        '--timings=tests/timings.measured.json',
        '--timings=tests/timings.json',
        '--update-timings',
        './tests/',
      ],
    ]);
  });

  test('--static leaves the suite out', () => {
    const { run, ran } = faked();

    expect(check({ static: true }, run)).toBe(0);
    expect(ran).toStrictEqual(STATIC);
  });

  test("stops at the first failure, with that tool's status", () => {
    const { run, ran } = faked([0, 2]);

    expect(check({ static: false }, run, () => {})).toBe(2);
    expect(ran).toStrictEqual(STATIC.slice(0, 2));
  });

  test("a failing suite is the check's status", () => {
    const { run } = faked([0, 0, 0, 0, 0, 1]);

    expect(check({ static: false }, run, () => {}, files())).toBe(1);
  });

  test('a failing step is named with its status, as one may say nothing (CHD-467)', () => {
    const said: string[] = [];
    const { run } = faked([0, 1]);

    expect(check({ static: false }, run, (line) => said.push(line))).toBe(1);
    expect(said).toStrictEqual(['check: covered failed with status 1\n']);
  });
});

describe('spawn', () => {
  test("answers the command's exit status", () => {
    expect(spawn([bun, '-e', 'process.exit(3)'])).toBe(3);
    expect(spawn([bun, '-e', '0'])).toBe(0);
  });

  test('a command killed by a signal is 128 + its number', () => {
    expect(spawn([bun, '-e', "process.kill(process.pid, 'SIGTERM')"])).toBe(
      143,
    );
  });

  test('runs from the root', () => {
    expect(
      spawn([
        bun,
        '-e',
        `process.exit(process.cwd() === ${JSON.stringify(root)} ? 0 : 1)`,
      ]),
    ).toBe(0);
  });

  test('runs from a root whose name has a space', async () => {
    const dir = await realpath(await mkdtemp(join(tmpdir(), 'chord-tools-')));
    const checkout = join(dir, 'chord checkout');

    try {
      // tools.ts and the module it imports, as a checkout holds them.
      for (const file of ['tools.ts', 'timings.ts']) {
        await cp(
          join(root, 'scripts', 'dev', file),
          join(checkout, 'scripts', 'dev', file),
        );
      }

      await symlink(join(root, 'node_modules'), join(checkout, 'node_modules'));

      const moved = (await import(
        join(checkout, 'scripts', 'dev', 'tools.ts')
      )) as { spawn: Run };

      expect(
        moved.spawn([
          bun,
          '-e',
          `process.exit(process.cwd() === ${JSON.stringify(checkout)} ? 0 : 1)`,
        ]),
      ).toBe(0);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

test('qaPlace makes a capture directory afresh, emptying one left from before (CHD-427)', async () => {
  const dir = `/tmp/chord-qa.tools-test-${process.pid}`;

  try {
    qaPlace(dir);
    await writeFile(join(dir, 'left.txt'), 'from before');
    qaPlace(dir);

    expect(await readdir(dir)).toStrictEqual([]);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
