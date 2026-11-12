import { describe, expect, test } from 'bun:test';
import { spawn as spawnChild, spawnSync } from 'node:child_process';
import { once } from 'node:events';
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
import { existsSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { quote } from 'shell-quote';
import {
  chord,
  chordOnRiff,
  chordWithRiff,
  qaPlace,
  type Run,
  type RunServing,
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
          '-p',
          'hi',
        ],
        {
          CHORD_RIFF_FAKE_PROVIDER: 'http://localhost:1/v1',
          CHORD_RIFF_QA: '',
        },
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

describe('chordWithRiff (CHD-604c)', () => {
  /** `chordWithRiff` with a recorded run and a provider that says when it stops. */
  async function served(
    fake: boolean,
    args: readonly string[],
    fixtureResources?: boolean,
  ) {
    const order: string[] = [];
    const ran: [readonly string[], Readonly<Record<string, string>>][] = [];
    const status = await chordWithRiff(
      fake,
      args,
      fixtureResources,
      (argv, env) => {
        order.push('run');
        ran.push([argv, env]);

        return Promise.resolve(5);
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

    return { status, order, ran };
  }

  test("--fake runs the fake agent with riff's provider served around it", async () => {
    const recorded = faked();

    chord(true, ['-p', 'hi'], recorded.run);

    expect(await served(true, ['-p', 'hi'])).toStrictEqual({
      status: 5,
      order: ['serve', 'run', 'stop'],
      ran: [
        [
          recorded.ran[0]!,
          {
            CHORD_RIFF_FAKE_PROVIDER: 'http://localhost:1/v1',
            CHORD_RIFF_QA: '',
          },
        ],
      ],
    });
  });

  test('--qa without --fake serves it too, on fixture resources', async () => {
    const recorded = faked();

    chord(false, ['-C', '/tmp/chord-qa'], recorded.run, true);

    const { ran } = await served(false, ['-C', '/tmp/chord-qa'], true);

    expect(ran).toStrictEqual([
      [
        recorded.ran[0]!,
        {
          CHORD_RIFF_FAKE_PROVIDER: 'http://localhost:1/v1',
          CHORD_RIFF_QA: '1',
        },
      ],
    ]);
  });
});

describe("a fake or QA run's state (CHD-616)", () => {
  const provider = () =>
    Promise.resolve({
      url: 'http://localhost:1/v1',
      stop: () => Promise.resolve(),
    });

  test('riff and chord are given the state place, made if missing', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'chord-state-'));
    const envs: Readonly<Record<string, string>>[] = [];
    const record = (
      _argv: readonly string[],
      env: Readonly<Record<string, string>>,
    ) => {
      envs.push(env);

      return Promise.resolve(0);
    };

    try {
      await chordOnRiff([], record, provider, true, join(dir, 'riff'));
      await chordWithRiff(
        true,
        [],
        undefined,
        record,
        provider,
        join(dir, 'chord'),
      );

      expect(envs.map((env) => env['XDG_STATE_HOME'])).toStrictEqual([
        join(dir, 'riff'),
        join(dir, 'chord'),
      ]);
      expect(existsSync(join(dir, 'riff'))).toBe(true);
      expect(existsSync(join(dir, 'chord'))).toBe(true);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("riff's child keeps its state where it is given, leaving the person's untouched", async () => {
    const person = mkdtempSync(join(tmpdir(), 'chord-person-'));
    const state = join(person, 'fake');
    const files = (dir: string): string[] =>
      existsSync(dir)
        ? readdirSync(dir, { recursive: true, withFileTypes: true })
            .filter((entry) => entry.isFile())
            .map((entry) => entry.name)
        : [];
    let out = '';
    // Each child's process group: none outlives the test. riff's agent keeps
    // a group of its own and ends when chord's end closes its stdin
    // (src/riff/serve.ts).
    const groups: number[] = [];
    const end = (group: number) => {
      try {
        process.kill(-group, 'SIGKILL');
      } catch {
        // Gone already.
      }
    };

    // As spawnServing does, on a stand-in for the person's own places, ended
    // well inside the test's timeout, so the provider's stop still runs.
    const run: RunServing = async ([command, ...args], env) => {
      const child = spawnChild(command ?? '', args, {
        cwd: root,
        detached: true,
        stdio: ['ignore', 'pipe', 'ignore'],
        env: {
          ...process.env,
          HOME: join(person, 'home'),
          XDG_STATE_HOME: join(person, 'state'),
          XDG_CONFIG_HOME: join(person, 'config'),
          XDG_DATA_HOME: join(person, 'data'),
          XDG_CACHE_HOME: join(person, 'cache'),
          ...env,
        },
      });

      const group = child.pid;

      if (group !== undefined) {
        groups.push(group);
      }

      child.stdout.on('data', (chunk: Buffer) => (out += chunk.toString()));

      const deadline = setTimeout(() => {
        if (group !== undefined) {
          end(group);
        }
      }, 30_000);

      try {
        const [status] = (await once(child, 'exit')) as [number | null];

        return status ?? 1;
      } finally {
        clearTimeout(deadline);
      }
    };

    try {
      expect(
        await chordOnRiff(['-p', 'hi'], run, undefined, false, state),
      ).toBe(0);
      expect(out).toContain('Hello from riff.');
      expect(files(join(person, 'state'))).toStrictEqual([]);
      expect(files(join(state, 'chord', 'riff', 'sidecars'))).toHaveLength(1);
    } finally {
      groups.forEach(end);
      rmSync(person, { recursive: true, force: true });
    }
  });

  test('none given, the environment keeps its own', async () => {
    const envs: Readonly<Record<string, string>>[] = [];

    await chordOnRiff(
      [],
      (_argv, env) => {
        envs.push(env);

        return Promise.resolve(0);
      },
      provider,
    );

    expect(envs[0]).not.toHaveProperty('XDG_STATE_HOME');
  });
});

describe('CHD-616 tester: state reuse and failed launches', () => {
  test('both launchers reuse existing state without clearing earlier files', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-kept-state-'));
    const state = join(dir, 'state with spaces');
    let calls = 0;
    let stopped = 0;
    const provider = () =>
      Promise.resolve({
        url: 'http://localhost:1/v1',
        stop: () => {
          stopped++;

          return Promise.resolve();
        },
      });
    const run: RunServing = async (_args, env) => {
      expect(env['XDG_STATE_HOME']).toBe(state);
      expect(await readFile(join(state, 'earlier'), 'utf8')).toBe('kept');

      if (calls > 0) {
        expect(await readFile(join(state, `run-${calls}`), 'utf8')).toBe(
          'saved',
        );
      }

      calls++;

      await writeFile(join(state, `run-${calls}`), 'saved');

      return 0;
    };

    try {
      await mkdir(state);
      await writeFile(join(state, 'earlier'), 'kept');
      await chordOnRiff([], run, provider, false, state);
      await chordOnRiff([], run, provider, false, state);
      await chordWithRiff(true, [], false, run, provider, state);

      expect(calls).toBe(3);
      expect(stopped).toBe(3);
      expect((await readdir(state)).toSorted()).toStrictEqual([
        'earlier',
        'run-1',
        'run-2',
        'run-3',
      ]);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  test('a failed child launch still stops the fake provider and keeps existing state', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-failed-state-'));
    const failure = new Error('Fixture child failed to start.');
    let stopped = 0;

    try {
      await writeFile(join(dir, 'earlier'), 'kept');

      await expect(
        chordOnRiff(
          [],
          () => Promise.reject(failure),
          () =>
            Promise.resolve({
              url: 'http://localhost:1/v1',
              stop: () => {
                stopped++;

                return Promise.resolve();
              },
            }),
          false,
          dir,
        ),
      ).rejects.toBe(failure);

      expect(stopped).toBe(1);
      expect(await readFile(join(dir, 'earlier'), 'utf8')).toBe('kept');
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  test('an unusable state path fails before a fake provider starts', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-invalid-state-'));
    let started = 0;

    try {
      await writeFile(join(dir, 'file'), 'kept');

      await expect(
        chordOnRiff(
          [],
          () => Promise.resolve(0),
          () => {
            started++;

            return Promise.resolve({
              url: 'http://localhost:1/v1',
              stop: () => Promise.resolve(),
            });
          },
          false,
          join(dir, 'file', 'state'),
        ),
      ).rejects.toBeInstanceOf(Error);

      expect(started).toBe(0);
      expect(await readFile(join(dir, 'file'), 'utf8')).toBe('kept');
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
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
