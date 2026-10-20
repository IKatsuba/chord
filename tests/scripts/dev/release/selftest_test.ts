import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawn } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { join } from 'node:path';
import { selftest } from '../../../../scripts/dev/release/selftest.ts';
import { type Scratch, scratch } from './scratch.ts';

// The self-test in a process of its own, on a fake chord and a fake tmux
// whose window never shows anything, ended by a signal while it waits.

const SCRIPTS = join(import.meta.dir, '..', '..', '..', '..', 'scripts');

let at: Scratch;

beforeEach(() => {
  at = scratch();

  writeFileSync(
    join(at.root, 'package.json'),
    JSON.stringify({ version: '9.9.9' }),
  );
  writeFileSync(
    join(at.root, 'chord'),
    '#!/bin/bash\ncase "$1" in --version) echo 9.9.9 ;; *) echo "Hello, world." ;; esac\n',
    { mode: 0o755 },
  );
  at.fake(
    'tmux',
    `echo "$*" >>"$STATE/tmux.log"
case "$3" in new-session) touch "$STATE/started" ;; esac
`,
  );
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

test('a signal while it waits ends its tmux and removes its scratch, and ends the run by that signal', async () => {
  const child = spawn(
    process.execPath,
    [
      '-e',
      `import { release } from ${JSON.stringify(join(SCRIPTS, 'dev', 'release', 'lib.ts'))};
import { selftest } from ${JSON.stringify(join(SCRIPTS, 'dev', 'release', 'selftest.ts'))};
await selftest({ ...release(), root: ${JSON.stringify(at.root)} }, 'chord');`,
    ],
    {
      env: { ...at.release.env, STATE: at.place },
      stdio: ['ignore', 'ignore', 'pipe'],
    },
  );
  const ended = new Promise<NodeJS.Signals | null>((resolve) =>
    child.on('close', (_code, signal) => resolve(signal)),
  );
  let stderr = '';

  child.stderr.on('data', (bytes: Buffer) => {
    stderr += bytes.toString();
  });

  // Under a loaded suite the child's start took up to 11 s, against 1 s
  // alone, and always came (CHD-467): a deadline that leaves room for it,
  // and a child gone before its window fails at once.
  const deadline = performance.now() + 30_000;

  try {
    while (!existsSync(join(at.place, 'started'))) {
      if (child.exitCode !== null || child.signalCode !== null) {
        await ended;

        throw new Error(
          `self-test exited before its window started: code ${child.exitCode}, signal ${child.signalCode}; stderr:\n${stderr}`,
        );
      }

      if (performance.now() >= deadline) {
        throw new Error(
          `self-test window did not start within 30 s; stderr:\n${stderr}`,
        );
      }

      await sleep(50);
    }
  } catch (error) {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL');
    }

    await ended;

    throw error;
  }

  child.kill('SIGTERM');

  expect(await ended).toBe('SIGTERM');

  const tmux = readFileSync(join(at.place, 'tmux.log'), 'utf8')
    .split('\n')
    .filter(Boolean);
  const project = /-c (\S+)\/project /.exec(
    tmux.find((line) => line.includes('new-session')) ?? '',
  )?.[1];

  expect(tmux.at(-1)).toMatch(/^-L chord-selftest-\d+ kill-server$/);
  expect(project).toBeDefined();
  expect(existsSync(project!)).toBeFalse();
});

describe('tester: self-test completion and cleanup', () => {
  function projectDirectory(): string {
    const tmux = readFileSync(join(at.place, 'tmux.log'), 'utf8');
    const directory = /-c (\S+)\/project /.exec(tmux)?.[1];

    expect(directory).toBeDefined();

    return directory!;
  }

  test('success removes owned scratch and restores all signal listeners', async () => {
    at.fake(
      'tmux',
      `echo "$*" >>"$STATE/tmux.log"
case "$3" in capture-pane) printf 'for shortcuts\\nHello, world.\\n' ;; esac
`,
    );

    const signals = ['SIGINT', 'SIGTERM', 'SIGHUP'] as const;
    const before = signals.map((signal) => process.listenerCount(signal));

    await selftest(
      { ...at.release, env: { ...at.release.env, STATE: at.place } },
      'chord',
    );

    expect(existsSync(projectDirectory())).toBeFalse();
    expect(readFileSync(join(at.place, 'tmux.log'), 'utf8')).toMatch(
      /kill-server\n$/,
    );
    expect(at.out).toEqual([`self-tested ${join(at.root, 'chord')}`]);
    expect(at.sleeps).toEqual([2000]);
    expect(signals.map((signal) => process.listenerCount(signal))).toEqual(
      before,
    );
  });

  test('a window timeout preserves its screen and removes owned scratch', async () => {
    at.fake(
      'tmux',
      `echo "$*" >>"$STATE/tmux.log"
case "$3" in capture-pane) echo 'fixture startup stalled' ;; esac
`,
    );

    const signals = ['SIGINT', 'SIGTERM', 'SIGHUP'] as const;
    const before = signals.map((signal) => process.listenerCount(signal));

    await expect(
      selftest(
        { ...at.release, env: { ...at.release.env, STATE: at.place } },
        'chord',
      ),
    ).rejects.toThrow(
      `${join(at.root, 'chord')}'s window never showed "for shortcuts"; stderr:  screen:\nfixture startup stalled`,
    );
    expect(at.sleeps).toEqual(Array<number>(60).fill(500));
    expect(existsSync(projectDirectory())).toBeFalse();
    expect(readFileSync(join(at.place, 'tmux.log'), 'utf8')).toMatch(
      /kill-server\n$/,
    );
    expect(signals.map((signal) => process.listenerCount(signal))).toEqual(
      before,
    );
  });

  for (const signal of ['SIGINT', 'SIGHUP'] as const) {
    test(`${signal} removes owned tmux and scratch and is re-raised`, async () => {
      const child = spawn(
        process.execPath,
        [
          '-e',
          `import { release } from ${JSON.stringify(join(SCRIPTS, 'dev', 'release', 'lib.ts'))};
import { selftest } from ${JSON.stringify(join(SCRIPTS, 'dev', 'release', 'selftest.ts'))};
await selftest({ ...release(), root: ${JSON.stringify(at.root)} }, 'chord');`,
        ],
        {
          env: { ...at.release.env, STATE: at.place },
          stdio: ['ignore', 'ignore', 'pipe'],
        },
      );
      const ended = new Promise<NodeJS.Signals | null>((resolve) =>
        child.on('close', (_code, received) => resolve(received)),
      );
      let stderr = '';

      child.stderr.on('data', (bytes: Buffer) => {
        stderr += bytes.toString();
      });

      try {
        const deadline = performance.now() + 30_000;

        while (!existsSync(join(at.place, 'started'))) {
          if (child.exitCode !== null || child.signalCode !== null) {
            await ended;

            throw new Error(
              `self-test exited before its window started: code ${child.exitCode}, signal ${child.signalCode}; stderr:\n${stderr}`,
            );
          }

          if (performance.now() >= deadline) {
            throw new Error(
              `self-test window did not start within 30 s; stderr:\n${stderr}`,
            );
          }

          await sleep(50);
        }

        child.kill(signal);

        expect(await ended).toBe(signal);
        expect(existsSync(projectDirectory())).toBeFalse();
        expect(readFileSync(join(at.place, 'tmux.log'), 'utf8')).toMatch(
          /kill-server\n$/,
        );
      } finally {
        if (child.exitCode === null && child.signalCode === null) {
          child.kill('SIGKILL');
        }

        await ended;
      }
    });
  }
});
