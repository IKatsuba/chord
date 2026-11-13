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
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { quote } from 'shell-quote';
import {
  chord,
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

describe("a fake or QA run's state (CHD-616)", () => {
  /** A `Run` that records each env it is given. */
  function envs(): {
    run: Run;
    given: (Readonly<Record<string, string>> | undefined)[];
  } {
    const given: (Readonly<Record<string, string>> | undefined)[] = [];

    return {
      given,
      run: (_argv, env) => {
        given.push(env);

        return 0;
      },
    };
  }

  test('chord is given the state place, made if missing', () => {
    const dir = mkdtempSync(join(tmpdir(), 'chord-state-'));
    const { run, given } = envs();

    try {
      chord(true, [], run, false, join(dir, 'fake'));

      expect(given).toStrictEqual([{ XDG_STATE_HOME: join(dir, 'fake') }]);
      expect(existsSync(join(dir, 'fake'))).toBe(true);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test('a state place already there keeps what it holds', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-kept-state-'));
    const state = join(dir, 'state with spaces');

    try {
      await mkdir(state);
      await writeFile(join(state, 'earlier'), 'kept');
      chord(true, [], envs().run, false, state);

      expect(await readFile(join(state, 'earlier'), 'utf8')).toBe('kept');
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  test('an unusable state path fails before chord runs', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-invalid-state-'));
    const { run, given } = envs();

    try {
      await writeFile(join(dir, 'file'), 'kept');

      expect(() =>
        chord(true, [], run, false, join(dir, 'file', 'state')),
      ).toThrow();
      expect(given).toStrictEqual([]);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  test('none given, the environment keeps its own', () => {
    const { run, given } = envs();

    chord(true, [], run);

    expect(given[0]).not.toHaveProperty('XDG_STATE_HOME');
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

  test('runs with the env given added to its own', () => {
    expect(
      spawn([bun, '-e', 'process.exit(process.env.CHORD_X === "y" ? 5 : 1)'], {
        CHORD_X: 'y',
      }),
    ).toBe(5);
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

test("qaPlace makes a capture's state beside it afresh too (CHD-616)", async () => {
  const dir = `/tmp/chord-qa.tools-test-${process.pid}`;
  const state = `${dir}.state`;

  try {
    qaPlace(dir, state);
    await writeFile(join(state, 'left.json'), '{}');
    qaPlace(dir, state);

    expect(await readdir(state)).toStrictEqual([]);
    expect(await readdir(dir)).toStrictEqual([]);
  } finally {
    await rm(dir, { recursive: true, force: true });
    await rm(state, { recursive: true, force: true });
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
              name: '@chorded/chord',
              type: 'module',
              version: '0.0.0',
              scripts: {
                dev: 'bun scripts/dev.ts',
                check: 'bun -e "0"',
                eslint: 'bun -e "0"',
                fmt: 'bun -e "0"',
              },
            }),
          );
          await writeFile(
            join(checkout, 'steps.ts'),
            `const bun = process.execPath;
export default {
  checks: [
    { name: 'static tests', static: true, run: [bun, 'test', 'lint/'] },
    { name: 'the suite', run: [bun, 'scripts/dev.ts', 'test'] },
  ],
  lint: [],
  release: [{ name: 'publish', npm: ['@chorded/chord'], tag: 'v{version}' }],
};\n`,
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
            command === 'test'
              ? ['dev', 'test']
              : ['dev', 'quality', 'chord', ...command.split(' ').slice(1)],
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
