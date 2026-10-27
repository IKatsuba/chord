import { expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { withResourceProcess } from '../../src/platform/resource_process.ts';

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
