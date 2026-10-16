import { afterEach, beforeEach, expect, test } from 'bun:test';
import { spawn } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { join } from 'node:path';
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
    child.on('exit', (_code, signal) => resolve(signal)),
  );

  for (let tries = 0; !existsSync(join(at.place, 'started')); tries++) {
    expect(tries).toBeLessThan(200);
    await sleep(50);
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
