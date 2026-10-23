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
  test as suite,
} from '../../../scripts/dev/tools.ts';

const bun = process.execPath;
const root = join(import.meta.dir, '..', '..', '..');

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

test("test runs the whole suite placed by the record's times, its arguments after, and answers the tests' status (CHD-513)", () => {
  const { run, ran } = faked([1]);

  expect(suite(['--shard=2/3'], run)).toBe(1);

  expect(ran).toStrictEqual([
    [
      bun,
      'test',
      '--parallel',
      '--timeout=60000',
      '--timings=tests/timings.json',
      './tests/',
      '--shard=2/3',
    ],
  ]);
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

    expect(check({ static: false }, run, () => {})).toBe(0);
    expect(ran).toStrictEqual([
      ...STATIC,
      [
        bun,
        'test',
        '--parallel',
        '--timeout=60000',
        '--timings=tests/timings.json',
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

    expect(check({ static: false }, run, () => {})).toBe(1);
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
      // tools.ts, as a checkout holds it.
      await cp(
        join(root, 'scripts', 'dev', 'tools.ts'),
        join(checkout, 'scripts', 'dev', 'tools.ts'),
      );

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
