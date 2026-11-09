import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  cp,
  mkdtemp,
  readdir,
  readFile,
  mkdir,
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
  chordOnRiff,
  lint,
  qaPlace,
  type Run,
  spawn,
  spawnServing,
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
        '--define',
        'process.env.CHORD_RESOURCE_FIXTURE:"true"',
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

describe('chordOnRiff', () => {
  test('serves the fake provider, runs chord on riff with it, and stops it after', async () => {
    const order: string[] = [];
    const ran: [readonly string[], Readonly<Record<string, string>>][] = [];
    const status = await chordOnRiff(
      ['-p', 'hi'],
      (argv, env) => {
        order.push('run');
        ran.push([argv, env]);

        return Promise.resolve(3);
      },
      () => {
        order.push('serve');

        return Promise.resolve({
          url: 'http://localhost:1/v1',
          stop: () => {
            order.push('stop');

            return Promise.resolve();
          },
        });
      },
    );

    expect(status).toBe(3);
    expect(order).toEqual(['serve', 'run', 'stop']);
    expect(ran).toStrictEqual([
      [
        [
          bun,
          '--define',
          'process.env.NODE_ENV:"production"',
          '--define',
          'process.env.CHORD_RESOURCE_FIXTURE:"true"',
          'src/main.tsx',
          'riff',
          '--agent-command',
          quote([bun, join(root, 'src', 'main.tsx'), '--riff-agent']),
          '-p',
          'hi',
        ],
        { CHORD_RIFF_FAKE_PROVIDER: 'http://localhost:1/v1' },
      ],
    ]);
  });

  test('stops the provider when chord fails to start', async () => {
    let stopped = false;
    const failure = new Error('no such command');

    await expect(
      chordOnRiff(
        [],
        () => Promise.reject(failure),
        () =>
          Promise.resolve({
            url: 'http://localhost:1/v1',
            stop: () => {
              stopped = true;

              return Promise.resolve();
            },
          }),
      ),
    ).rejects.toBe(failure);
    expect(stopped).toBe(true);
  });
});

describe('spawnServing', () => {
  test("answers the command's status, with the env added, while this process still runs", async () => {
    let ticked = false;
    const tick = setTimeout(() => (ticked = true), 10);
    const status = await spawnServing(
      [
        process.execPath,
        '-e',
        'await Bun.sleep(100); process.exit(process.env.CHORD_X === "y" ? 5 : 1)',
      ],
      { CHORD_X: 'y' },
    );

    clearTimeout(tick);
    expect(status).toBe(5);
    expect(ticked).toBe(true);
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

test('lint runs ESLint over the tree', () => {
  const { run, ran } = faked();

  lint(['--fix'], run);

  expect(ran).toStrictEqual([[bun, 'run', 'eslint', '.', '--fix']]);
});

describe('check', () => {
  const STATIC = [
    [bun, 'check'],
    [bun, 'scripts/dev/covered.ts'],
    [bun, 'run', 'eslint', '.'],
    [bun, 'fmt', '--check', '.'],
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

describe('CHD-513 U1 tester: command status without timing gates', () => {
  for (const command of ['test', 'quality', 'quality --static']) {
    for (const failing of [false, true]) {
      test(`${command} keeps timing files untouched when its tests ${failing ? 'fail' : 'pass'}`, async () => {
        const checkout = await mkdtemp(join(tmpdir(), 'chord-status-'));
        const record = JSON.stringify({
          version: 1,
          files: { 'tests/example_test.ts': 1, 'tests/gone_test.ts': 95000 },
        });
        const measured = 'a measurement left by an earlier run\n';

        try {
          await cp(join(root, 'scripts'), join(checkout, 'scripts'), {
            recursive: true,
          });
          await symlink(
            join(root, 'node_modules'),
            join(checkout, 'node_modules'),
          );
          await mkdir(join(checkout, 'tests'));
          await mkdir(join(checkout, 'lint'));
          await writeFile(
            join(checkout, 'package.json'),
            JSON.stringify({
              type: 'module',
              version: '0.0.0',
              scripts: {
                dev: 'bun scripts/dev.ts',
                quality: 'bun scripts/quality.ts',
                check: 'bun -e "0"',
                eslint: 'bun -e "0"',
                fmt: 'bun -e "0"',
              },
            }),
          );
          // Isolate the suite's status from unrelated static tooling.
          await writeFile(
            join(checkout, 'scripts', 'dev', 'covered.ts'),
            'process.exit(0);\n',
          );
          await writeFile(
            join(checkout, 'lint', 'static_test.ts'),
            "import { test } from 'bun:test'; test('static fixture', () => {});\n",
          );
          await writeFile(
            join(checkout, 'tests', 'example_test.ts'),
            `import { expect, test } from 'bun:test'; test('suite fixture', () => expect(${failing}).toBe(false));\n`,
          );
          await writeFile(join(checkout, 'tests', 'timings.json'), record);
          await writeFile(
            join(checkout, 'tests', 'timings.measured.json'),
            measured,
          );

          const result = spawnSync(
            bun,
            command === 'test' ? ['dev', 'test'] : command.split(' '),
            {
              cwd: checkout,
              encoding: 'utf8',
              timeout: 20_000,
            },
          );

          expect(result.error).toBeUndefined();
          expect(result.status, result.stdout + result.stderr).toBe(
            failing && command !== 'quality --static' ? 1 : 0,
          );
          expect(result.stdout + result.stderr).not.toContain('timings:');
          expect(
            await readFile(join(checkout, 'tests', 'timings.json'), 'utf8'),
          ).toBe(record);
          expect(
            await readFile(
              join(checkout, 'tests', 'timings.measured.json'),
              'utf8',
            ),
          ).toBe(measured);
          expect((await readdir(join(checkout, 'tests'))).sort()).toStrictEqual(
            ['example_test.ts', 'timings.json', 'timings.measured.json'],
          );
        } finally {
          await rm(checkout, { recursive: true, force: true });
        }
      });
    }
  }
});

test('QA isolates resource sources even when the agent is named Codex without --fake', () => {
  const { run, ran } = faked();

  chord(false, ['codex'], run, true);

  expect(ran[0]).toContain('process.env.CHORD_RESOURCE_FIXTURE:"true"');
  expect(ran[0]?.at(-1)).toBe('codex');
});
