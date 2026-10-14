/**
 * A look inside chord's heap while it runs: a snapshot in the V8 format,
 * which Chrome's DevTools and memlab open, through `Bun.generateHeapSnapshot`,
 * and JSC's own counts beside it from `bun:jsc`.
 */
import { heapStats } from 'bun:jsc';
import { mkdir, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import process from 'node:process';

/** The signal that has a running chord write a snapshot. */
export const HEAP_SIGNAL = 'SIGUSR2';

/** The files one snapshot leaves. */
export interface HeapFiles {
  /** The snapshot, `.heapsnapshot`. */
  readonly snapshot: string;
  /** JSC's counts and the process's memory, `.json`, taken after it. */
  readonly stats: string;
}

/**
 * What the `.json` beside a snapshot holds: the process's memory as the
 * system sees it and JSC's heap as `bun:jsc` counts it, by object type.
 */
export interface HeapStats {
  readonly pid: number;
  readonly at: string;
  readonly memory: NodeJS.MemoryUsage;
  readonly heap: ReturnType<typeof heapStats>;
}

/** The process's memory and JSC's counts, now. */
export function heapNow(now: Date = new Date()): HeapStats {
  return {
    pid: process.pid,
    at: now.toISOString(),
    memory: process.memoryUsage(),
    heap: heapStats(),
  };
}

/**
 * Writes a snapshot of the heap and its counts into `dir`, named by the pid
 * and the time, so snapshots of one chord sort in the order they were taken
 * and two chords' never meet. Each file is written beside its name and
 * renamed onto it, so a file under its name is whole. The snapshot collects
 * the garbage first, so the counts after it are what was still held.
 */
export async function writeHeapSnapshot(
  dir: string,
  now: Date = new Date(),
): Promise<HeapFiles> {
  const base = join(
    dir,
    `chord-${process.pid}-${now.toISOString().replace(/[:.]/g, '-')}`,
  );
  const files = {
    snapshot: `${base}.heapsnapshot`,
    stats: `${base}.json`,
  };

  await mkdir(dir, { recursive: true });
  // An ArrayBuffer rather than the string, which would be a second copy of
  // a snapshot as large as the heap, inside the heap being looked at.
  await writeWhole(
    files.snapshot,
    new Uint8Array(Bun.generateHeapSnapshot('v8', 'arraybuffer')),
  );
  await writeWhole(
    files.stats,
    `${JSON.stringify(heapNow(new Date()), null, 2)}\n`,
  );

  return files;
}

async function writeWhole(path: string, data: string | Uint8Array) {
  await writeFile(`${path}.part`, data);
  await rename(`${path}.part`, path);
}

/**
 * Has `HEAP_SIGNAL` write a snapshot into the directory `dir` names, asked
 * for each time so a missing home fails the snapshot and not chord's start.
 * Nothing is written to the terminal, which the window owns: a failure is
 * left as `heap-error.txt` in that directory, or nowhere when there is
 * none. A signal while a snapshot is being written is dropped, as the one
 * under way already has what it would. Without the listener, the signal's
 * default action would kill chord. Returns the function that takes it off.
 */
export function snapshotOnSignal(
  dir: () => string,
  written: (files: HeapFiles) => void = () => {},
): () => void {
  let writing = false;

  const handler = async () => {
    if (writing) {
      return;
    }

    writing = true;

    let into: string | undefined;

    try {
      into = dir();

      written(await writeHeapSnapshot(into));
    } catch (error) {
      if (into !== undefined) {
        await writeFile(
          join(into, 'heap-error.txt'),
          `${new Date().toISOString()} ${
            error instanceof Error
              ? (error.stack ?? error.message)
              : String(error)
          }\n`,
        ).catch(() => {});
      }
    } finally {
      writing = false;
    }
  };

  process.on(HEAP_SIGNAL, handler);

  return () => void process.off(HEAP_SIGNAL, handler);
}
