import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import {
  runDirect,
  DIRECT_ENVIRONMENT,
  type DirectInvocation,
} from '../../../src/riff/commands/direct.ts';
import { commandEffect } from '../../../src/riff/commands/effect.ts';
import { until } from '../../session/conversation_fake.ts';

const fixturePath = fileURLToPath(
  new URL('./direct_fixture.ts', import.meta.url),
);
const fixture = (...args: string[]): DirectInvocation => ({
  executable: process.execPath,
  argv: [process.execPath, fixturePath, ...args],
});

function run(stages: readonly DirectInvocation[]) {
  let output = '';
  const command = runDirect(stages, {
    cwd: tmpdir(),
    onOutput: (_stream, text) => {
      output += text;
    },
  });

  return { command, output: () => output };
}

test('direct argv pipes canonical stages without a shell', async () => {
  const plan = commandEffect("printf '%s' 'three words' | wc -w");

  assert.equal(plan.kind, 'direct');

  const result = run(plan.stages);

  expect(await result.command.ended).toEqual({ code: 0 });
  expect(result.output().trim()).toBe('2');
});

test('basic environment replaces every inherited variable', async () => {
  const result = run([{ executable: '/usr/bin/env', argv: ['/usr/bin/env'] }]);

  expect(await result.command.ended).toEqual({ code: 0 });
  expect(result.output().trim().split('\n').sort()).toEqual(
    Object.entries(DIRECT_ENVIRONMENT)
      .map(([k, v]) => `${k}=${v}`)
      .sort(),
  );
});

test('prepared git invocation gets only its supplied fixed environment', async () => {
  const result = run([
    {
      executable: '/usr/bin/env',
      argv: ['/usr/bin/env'],
      environment: { ...DIRECT_ENVIRONMENT, GIT_TERMINAL_PROMPT: '0' },
    },
  ]);

  expect(await result.command.ended).toEqual({ code: 0 });
  expect(result.output().trim().split('\n').sort()).toEqual(
    [
      ...Object.entries(DIRECT_ENVIRONMENT).map(([k, v]) => `${k}=${v}`),
      'GIT_TERMINAL_PROMPT=0',
    ].sort(),
  );
});

test('64 KiB cap counts output relayed between stages too', async () => {
  const result = run([
    fixture('output', '40000'),
    { executable: '/bin/cat', argv: ['/bin/cat'] },
  ]);

  expect((await result.command.ended).error).toBe(
    'Direct command output exceeded 64 KiB',
  );
  expect(Buffer.byteLength(result.output())).toBeLessThanOrEqual(65536);
});

test('stderr shares the direct output cap', async () => {
  const result = run([fixture('stderr', '70000')]);

  expect((await result.command.ended).error).toBe(
    'Direct command output exceeded 64 KiB',
  );
  expect(Buffer.byteLength(result.output())).toBeLessThanOrEqual(65536);
});

test('exactly 64 KiB is admitted, last stage determines exit status', async () => {
  const result = run([fixture('output', '65536')]);

  expect(await result.command.ended).toEqual({ code: 0 });
  expect(Buffer.byteLength(result.output())).toBe(65536);
});

test('spawn failure drains already-started stages', async () => {
  const result = run([
    { executable: '/bin/sleep', argv: ['/bin/sleep', '60'] },
    {
      executable: '/no-such-direct-command',
      argv: ['/no-such-direct-command'],
    },
  ]);

  expect((await result.command.ended).error).toBeDefined();
});

test('stop kills a later stage grandchild and escalates TERM after 800ms', async () => {
  let ready = '';
  const command = runDirect(
    [
      { executable: '/usr/bin/printf', argv: ['/usr/bin/printf', 'x'] },
      fixture('descendant'),
    ],
    {
      cwd: tmpdir(),
      onOutput: (_stream, text) => {
        ready += text;
      },
    },
  );

  try {
    await until(() => /^\d+\n/.test(ready));

    const pid = Number(ready.trim());

    expect(Number.isInteger(pid)).toBe(true);

    const started = performance.now();

    command.stop();
    command.stop();
    expect(await command.ended).toEqual({ stopped: true });
    expect(performance.now() - started).toBeGreaterThanOrEqual(700);
    expect(() => process.kill(pid, 0)).toThrow();
  } finally {
    command.stop();
    await command.ended;
  }
});

test('invalid direct plan does not spawn', async () => {
  expect(await run([]).command.ended).toEqual({ error: 'Invalid direct plan' });
  expect(
    await run(Array.from({ length: 9 }, () => fixture('environment'))).command
      .ended,
  ).toEqual({ error: 'Invalid direct plan' });
});

describe('tester: direct execution caps and group isolation', () => {
  const program = (source: string): DirectInvocation => ({
    executable: process.execPath,
    argv: [process.execPath, '-e', source],
  });

  test('a UTF-8 output exactly at the byte cap is drained intact', async () => {
    const result = run([program("process.stdout.write('é'.repeat(32768))")]);

    expect(await result.command.ended).toEqual({ code: 0 });
    expect(result.output()).toBe('é'.repeat(32768));
    expect(Buffer.byteLength(result.output())).toBe(65536);
  });

  test('stdout and stderr consume one shared byte budget', async () => {
    const result = run([
      program(
        "process.stdout.write('x'.repeat(40000)); process.stderr.write('y'.repeat(40000))",
      ),
    ]);

    expect((await result.command.ended).error).toBe(
      'Direct command output exceeded 64 KiB',
    );
    expect(Buffer.byteLength(result.output())).toBeLessThanOrEqual(65536);
  });

  test('stopping one concurrent pipeline leaves the other running', async () => {
    const first = run([fixture('descendant')]);
    const second = run([fixture('descendant')]);
    let secondEnded = false;

    void second.command.ended.then(() => {
      secondEnded = true;
    });

    try {
      await until(
        () => /^\d+\n/.test(first.output()) && /^\d+\n/.test(second.output()),
      );

      first.command.stop();
      expect(await first.command.ended).toEqual({ stopped: true });
      expect(() => process.kill(Number(first.output().trim()), 0)).toThrow();
      expect(secondEnded).toBe(false);
      expect(process.kill(Number(second.output().trim()), 0)).toBe(true);

      second.command.stop();
      expect(await second.command.ended).toEqual({ stopped: true });
      expect(() => process.kill(Number(second.output().trim()), 0)).toThrow();
    } finally {
      first.command.stop();
      second.command.stop();
      await Promise.all([first.command.ended, second.command.ended]);
    }
  });

  test('an output callback failure kills the emitting group and descendant', async () => {
    let output = '';
    const command = runDirect([fixture('descendant')], {
      cwd: tmpdir(),
      onOutput: (_stream, text) => {
        output += text;

        if (/^\d+\n/.test(output)) {
          throw new Error('tester output sink failed');
        }
      },
    });

    try {
      expect((await command.ended).error).toBe('tester output sink failed');
      expect(output).toMatch(/^\d+\n/);
      expect(() => process.kill(Number(output.trim()), 0)).toThrow();
    } finally {
      command.stop();
      await command.ended;
    }
  });

  test('the output cap kills an upstream group and its descendant', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'chord-direct-cap-tester-'));
    const childFile = join(dir, 'child');
    const sink = program(`
      let pid = '';
      process.stdin.on('data', (chunk) => {
        pid += chunk.toString();
        if (/^\\d+\\n/.test(pid)) {
          require('node:fs').writeFileSync(${JSON.stringify(childFile)}, pid.trim());
          process.stdout.write('x'.repeat(70000));
        }
      });
    `);
    const result = run([fixture('descendant'), sink]);

    try {
      expect((await result.command.ended).error).toBe(
        'Direct command output exceeded 64 KiB',
      );
      expect(existsSync(childFile)).toBe(true);
      expect(() =>
        process.kill(Number(readFileSync(childFile, 'utf8')), 0),
      ).toThrow();
    } finally {
      result.command.stop();
      await result.command.ended;
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test('stop reaches an earlier stage whose leader left a pipe-free descendant', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'chord-direct-tester-'));
    const childFile = join(dir, 'child');
    const leaderFile = join(dir, 'leader');
    const childSource = `
      process.on('SIGTERM', () => {});
      require('node:fs').writeFileSync(${JSON.stringify(childFile)}, String(process.pid));
      setInterval(() => {}, 1000);
    `;
    const leaderSource = `
      const { spawn } = require('node:child_process');
      const child = spawn(process.execPath, ['-e', ${JSON.stringify(childSource)}], { stdio: 'ignore' });
      child.once('spawn', () => {
        require('node:fs').writeFileSync(${JSON.stringify(leaderFile)}, String(process.pid));
        process.exit(0);
      });
    `;
    const result = run([program(leaderSource), fixture('descendant')]);

    try {
      await until(
        () =>
          existsSync(childFile) &&
          existsSync(leaderFile) &&
          /^\d+\n/.test(result.output()),
      );

      const childPid = Number(readFileSync(childFile, 'utf8'));
      const leaderPid = Number(readFileSync(leaderFile, 'utf8'));

      await until(() => {
        try {
          process.kill(leaderPid, 0);

          return false;
        } catch {
          return true;
        }
      });

      result.command.stop();
      expect(await result.command.ended).toEqual({ stopped: true });
      expect(() => process.kill(childPid, 0)).toThrow();
      expect(() => process.kill(Number(result.output().trim()), 0)).toThrow();
      expect(() => process.kill(-leaderPid, 0)).toThrow();
    } finally {
      result.command.stop();
      await result.command.ended;
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
