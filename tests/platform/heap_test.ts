import { afterEach, describe, expect, test } from 'bun:test';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import {
  HEAP_SIGNAL,
  type HeapFiles,
  type HeapStats,
  snapshotOnSignal,
  writeHeapSnapshot,
} from '../../src/platform/heap.ts';

const dirs: string[] = [];

async function scratch(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), 'chord-heap-'));

  dirs.push(dir);

  return dir;
}

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

describe('writeHeapSnapshot', () => {
  test('a V8 snapshot and its counts, named by the pid and the time', async () => {
    const dir = join(await scratch(), 'heaps');
    const files = await writeHeapSnapshot(
      dir,
      new Date('2026-10-12T13:40:10.009Z'),
    );
    const base = join(dir, `chord-${process.pid}-2026-10-12T13-40-10-009Z`);

    expect(files).toEqual({
      snapshot: `${base}.heapsnapshot`,
      stats: `${base}.json`,
    });
    expect((await readdir(dir)).sort()).toEqual(
      [`${base}.heapsnapshot`, `${base}.json`].map((file) =>
        file.slice(dir.length + 1),
      ),
    );

    // The shape DevTools and memlab read.
    const snapshot = JSON.parse(await readFile(files.snapshot, 'utf8')) as {
      snapshot: { meta: { node_fields: string[] }; node_count: number };
      nodes: number[];
    };

    expect(snapshot.snapshot.meta.node_fields).toContain('self_size');
    expect(snapshot.nodes.length).toBe(
      snapshot.snapshot.node_count * snapshot.snapshot.meta.node_fields.length,
    );

    const stats = JSON.parse(await readFile(files.stats, 'utf8')) as HeapStats;

    expect(stats.pid).toBe(process.pid);
    expect(stats.memory.rss).toBeGreaterThan(0);
    expect(stats.heap.objectTypeCounts['Function']).toBeGreaterThan(0);
  });
});

describe('snapshotOnSignal', () => {
  test('the signal writes a snapshot and leaves chord running', async () => {
    const dir = await scratch();
    const { promise, resolve } = Promise.withResolvers<HeapFiles>();
    const off = snapshotOnSignal(() => dir, resolve);

    try {
      process.kill(process.pid, HEAP_SIGNAL);

      const files = await promise;

      expect(files.snapshot.startsWith(dir)).toBe(true);
      expect(await readdir(dir)).toHaveLength(2);
    } finally {
      off();
    }

    expect(process.listenerCount(HEAP_SIGNAL)).toBe(0);
  });

  test('a failure is left in the directory, not on the terminal', async () => {
    const dir = await scratch();
    const { promise, resolve } = Promise.withResolvers<void>();
    const off = snapshotOnSignal(
      () => dir,
      () => {
        resolve();

        throw new Error('the disk is full');
      },
    );

    try {
      process.kill(process.pid, HEAP_SIGNAL);
      await promise;

      let error = '';

      while (!error.includes('the disk is full')) {
        await Bun.sleep(10);

        error = await readFile(join(dir, 'heap-error.txt'), 'utf8').catch(
          () => '',
        );
      }

      expect(error).toContain('Error: the disk is full');
    } finally {
      off();
    }
  });
});
