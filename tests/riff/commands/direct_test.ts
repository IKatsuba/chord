import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import {
  runDirect,
  DIRECT_ENVIRONMENT,
  type DirectInvocation,
} from '../../../src/riff/commands/direct.ts';
import { commandEffect } from '../../../src/riff/commands/effect.ts';

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
  const ready = Promise.withResolvers<number>();
  const command = runDirect(
    [
      { executable: '/usr/bin/printf', argv: ['/usr/bin/printf', 'x'] },
      fixture('descendant'),
    ],
    {
      cwd: tmpdir(),
      onOutput: (_stream, text) => {
        ready.resolve(Number(text.trim()));
      },
    },
  );

  try {
    const pid = await ready.promise;

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
