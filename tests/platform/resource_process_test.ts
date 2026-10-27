import { describe, expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import {
  COLLECTOR_BOUNDS,
  withResourceProcess,
} from '../../src/platform/resource_process.ts';

test('late read resolution after cancellation cannot publish and no group remains', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'chord-late-resource-'));
  const record = join(directory, 'events.jsonl');
  const controller = new AbortController();
  const pending = Promise.withResolvers<string>();
  const entered = Promise.withResolvers<void>();
  let published = false;
  let pid: number | undefined;
  const result = withResourceProcess(
    [
      process.execPath,
      new URL('../fixtures/resource_provider.ts', import.meta.url).pathname,
      'normal',
      record,
    ],
    { cwd: process.cwd(), signal: controller.signal },
    (group) => {
      pid = group.pid;

      entered.resolve();

      return pending.promise;
    },
  ).then((value) => {
    published = true;

    return value;
  });

  result.catch(() => {});

  try {
    await entered.promise;

    controller.abort();

    await expect(result).rejects.toThrow('cancelled');

    pending.resolve('late observation');

    await pending.promise;

    expect(published).toBe(false);
    expect(pid).toBeDefined();
    expect(() => process.kill(pid!, 0)).toThrow();
  } finally {
    pending.resolve('finished');

    await rm(directory, { recursive: true, force: true });
  }
});

test('cancellation while a successful read closes still revokes publication', async () => {
  const controller = new AbortController();
  const closing = Promise.withResolvers<void>();
  const release = Promise.withResolvers<void>();
  const result = withResourceProcess(
    [
      process.execPath,
      new URL('../fixtures/resource_provider.ts', import.meta.url).pathname,
      'normal',
    ],
    { cwd: process.cwd(), signal: controller.signal },
    (_group, _signal, onClose) => {
      onClose(() => {
        closing.resolve();

        return release.promise;
      });

      return Promise.resolve('finished observation');
    },
  );

  result.catch(() => {});

  await closing.promise;

  controller.abort();
  release.resolve();

  await expect(result).rejects.toThrow('cancelled');
});

test('total deadline while a successful read closes revokes publication', async () => {
  let enteredClose = false;
  let pid: number | undefined;
  const result = withResourceProcess(
    [
      process.execPath,
      new URL('../fixtures/resource_provider.ts', import.meta.url).pathname,
      'normal',
    ],
    {
      cwd: process.cwd(),
      signal: new AbortController().signal,
      bounds: { ...COLLECTOR_BOUNDS, totalMs: 250 },
    },
    (group, signal, onClose) => {
      pid = group.pid;

      onClose(
        () =>
          new Promise<void>((resolve) => {
            enteredClose = true;

            signal.addEventListener('abort', () => resolve(), { once: true });
          }),
      );

      return Promise.resolve('observation before deadline');
    },
  );

  await expect(result).rejects.toThrow('deadline');
  expect(enteredClose).toBe(true);
  expect(() => process.kill(pid!, 0)).toThrow();
});

describe('tester: collector failure isolation', () => {
  test('provider refusals stay sanitized and every failed read drains its group', async () => {
    for (const [status, kind] of [
      [401, 'authentication'],
      [403, 'authentication'],
      [429, 'rate-limit'],
      [500, 'protocol'],
    ] as const) {
      let pid: number | undefined;
      const result = withResourceProcess(
        [
          process.execPath,
          new URL('../fixtures/resource_provider.ts', import.meta.url).pathname,
          'normal',
        ],
        { cwd: process.cwd(), signal: new AbortController().signal },
        (group) => {
          pid = group.pid;

          return Promise.reject({
            status,
            message: 'excluded-provider-detail',
          });
        },
      );

      await expect(result).rejects.toMatchObject({ kind });
      await expect(result).rejects.not.toThrow('excluded-provider-detail');
      expect(() => process.kill(pid!, 0)).toThrow();
    }
  });

  test('missing executable is a startup failure with no raw executable path', async () => {
    const result = withResourceProcess(
      ['/nonexistent-resource-fixture/executable'],
      { cwd: process.cwd(), signal: new AbortController().signal },
      () => Promise.resolve('must not run'),
    );

    await expect(result).rejects.toMatchObject({
      kind: 'startup',
      message: 'The collector process failed to start.',
    });
  });
});
