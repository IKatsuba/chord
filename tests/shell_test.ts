import { expect, test } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { runShell } from '../src/shell.ts';

const SH = ['/bin/sh', '-c'] as const;

function collect(command: string, cwd = process.cwd()) {
  const out = { stdout: '', stderr: '' };
  const run = runShell(command, {
    cwd,
    shell: SH,
    onOutput: (stream, text) => (out[stream] += text),
  });

  return { out, run };
}

test('a command runs in the directory given, both streams heard', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-shell-'));

  try {
    await writeFile(`${dir}/marker.txt`, '');

    const { out, run } = collect('ls; echo oops >&2; exit 3', dir);

    expect(await run.ended).toStrictEqual({ code: 3 });
    expect(out).toStrictEqual({ stdout: 'marker.txt\n', stderr: 'oops\n' });
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('a stop ends the command and what it started, at once', async () => {
  const started = Date.now();
  const { out, run } = collect('echo before; sleep 30; echo after');

  // Wait until the shell is past its first line and into the sleep.
  while (out.stdout === '') {
    await new Promise((resolve) => setTimeout(resolve, 10));
  }

  run.stop();
  run.stop();

  expect(await run.ended).toStrictEqual({ stopped: true });
  expect(out.stdout).toStrictEqual('before\n');
  expect(
    Date.now() - started < 5000,
    'the sleep held the run open',
  ).toBeTruthy();
});

test.skipIf(process.platform === 'win32')(
  'a stop is over only once what the command started is gone, SIGTERM or not',
  async () => {
    // A sleep that shrugs off SIGTERM and lets go of the pipes, so the shell
    // and its output end long before it does.
    const { out, run } = collect(
      "(trap '' TERM; exec sleep 30) >/dev/null 2>&1 & echo $!; wait",
    );

    while (!out.stdout.includes('\n')) {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }

    const pid = Number(out.stdout.trim());

    try {
      await new Promise((resolve) => setTimeout(resolve, 150));
      run.stop();

      expect(await run.ended).toStrictEqual({ stopped: true });
      expect(!alive(pid), `the sleep (${pid}) outlived the stop`).toBeTruthy();
    } finally {
      if (alive(pid)) {
        process.kill(pid, 'SIGKILL');
      }
    }
  },
);

/** Whether `pid` is a process still, SIGCONT asking as harmlessly as any. */
function alive(pid: number): boolean {
  try {
    process.kill(pid, 'SIGCONT');

    return true;
  } catch {
    return false;
  }
}

test('a shell that does not start is an error, not a throw', async () => {
  const run = runShell('true', {
    cwd: process.cwd(),
    shell: ['/no/such/shell'],
    onOutput: () => {},
  });
  const end = await run.ended;

  expect(end.error !== undefined && end.error !== '', 'no error').toBeTruthy();
});

test.skipIf(process.platform === 'win32')(
  'a shell a signal ended reports the signal, and its code as $? reads it',
  async () => {
    const { run } = collect('kill -TERM $$');

    expect(await run.ended).toStrictEqual({ code: 143, signal: 'SIGTERM' });
  },
);

test("a monitor's stdout comes line by line, the last without its end", async () => {
  const lines: string[] = [];
  const run = runShell("printf 'one\\r\\ntwo\\nthree'; echo gone >&2", {
    cwd: process.cwd(),
    shell: SH,
    onLine: (line) => lines.push(line),
  });

  expect(await run.ended).toStrictEqual({ code: 0 });
  expect(lines).toStrictEqual(['one', 'two', 'three']);
});

test("a lone \\r stays in its line, as a progress bar's redraw", async () => {
  const lines: string[] = [];
  const run = runShell("printf '10%%\\r50%%\\r100%%\\ndone\\r\\n'", {
    cwd: process.cwd(),
    shell: SH,
    onLine: (line) => lines.push(line),
  });

  expect(await run.ended).toStrictEqual({ code: 0 });
  expect(lines).toStrictEqual(['10%\r50%\r100%', 'done']);
});
