/** Replaceable, private process facts; no shared balance or liveness inference. */
import { z } from '@zod/zod';
import { constants } from 'node:fs';
import {
  mkdir,
  open,
  opendir,
  rename,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { notFound } from '../not_found.ts';
import {
  activeAt,
  ageWindow,
  type BudgetClock,
  type BudgetSnapshot,
  mergeWindows,
  ResourceFacts,
  type TeamSelection,
  type WindowSnapshot,
} from '../session/budgets.ts';

export const CACHE_FILES = 256;
export const CACHE_BYTES = 256 * 1024;
export const CACHE_RETENTION_MS = 24 * 60 * 60 * 1000;
export const CACHE_CLEANUP_FILES = 32;

export const BudgetCacheFile = z.strictObject({
  schemaVersion: z.literal(1),
  processRef: z.uuid(),
  writtenAt: z.iso.datetime(),
  ...ResourceFacts,
});

export type BudgetCacheFile = z.infer<typeof BudgetCacheFile>;

const INCOMPLETE = 'Resource cache coverage is incomplete';

/** Scans no more than 256 files, with a capped read even if a file grows. */
export async function readBudgetCache(
  directory: string,
  now: number,
  { cleanupExpired = true }: { readonly cleanupExpired?: boolean } = {},
): Promise<{ files: BudgetCacheFile[]; warnings: string[] }> {
  const files: BudgetCacheFile[] = [];
  const warnings = new Set<string>();
  let removed = 0;
  let scanned = 0;
  let entries;

  try {
    entries = await opendir(directory);
  } catch (error) {
    return {
      files,
      warnings: notFound(error) ? [] : [`${INCOMPLETE}: directory unreadable.`],
    };
  }

  try {
    for await (const entry of entries) {
      if (scanned++ >= CACHE_FILES) {
        warnings.add(`${INCOMPLETE}: more than 256 files.`);

        break;
      }

      if (!entry.name.endsWith('.json')) {
        continue;
      }

      const path = join(directory, entry.name);

      try {
        if (!entry.isFile()) {
          warnings.add(`${INCOMPLETE}: nonregular cache file skipped.`);

          continue;
        }

        const file = await open(
          path,
          constants.O_RDONLY | constants.O_NOFOLLOW,
        );
        let metadata;
        let parsed: ReturnType<typeof BudgetCacheFile.safeParse>;

        try {
          metadata = await file.stat();

          if (!metadata.isFile() || metadata.size > CACHE_BYTES) {
            warnings.add(
              `${INCOMPLETE}: oversized or nonregular file skipped.`,
            );

            continue;
          }

          const bytes = Buffer.alloc(CACHE_BYTES + 1);
          let length = 0;

          while (length < bytes.length) {
            const read = await file.read(
              bytes,
              length,
              bytes.length - length,
              length,
            );

            if (read.bytesRead === 0) {
              break;
            }

            length += read.bytesRead;
          }

          if (length > CACHE_BYTES) {
            warnings.add(`${INCOMPLETE}: growing oversized file skipped.`);

            continue;
          }

          parsed = BudgetCacheFile.safeParse(
            JSON.parse(bytes.toString('utf8', 0, length)),
          );
        } finally {
          await file.close();
        }

        if (!parsed.success) {
          warnings.add(`${INCOMPLETE}: malformed cache file skipped.`);

          continue;
        }

        const written = Date.parse(parsed.data.writtenAt);

        if (written > now + 5000) {
          warnings.add(`${INCOMPLETE}: future-dated cache file skipped.`);

          continue;
        }

        if (now - written > CACHE_RETENTION_MS) {
          if (
            cleanupExpired &&
            removed < CACHE_CLEANUP_FILES &&
            now - metadata.mtimeMs > CACHE_RETENTION_MS
          ) {
            const current = await stat(path);

            if (
              current.ino === metadata.ino &&
              current.mtimeMs === metadata.mtimeMs &&
              current.size === metadata.size
            ) {
              removed++;

              await rm(path);
            }
          }

          continue;
        }

        files.push(parsed.data);
      } catch {
        warnings.add(
          `${INCOMPLETE}: unreadable, malformed or unremovable file skipped.`,
        );
      }
    }
  } catch {
    warnings.add(`${INCOMPLETE}: directory scan failed.`);
  }

  return { files, warnings: [...warnings] };
}

/** One writer owns this UUID file, so shutdown never removes another's work. */
export class BudgetCache {
  readonly #directory: string;
  readonly processRef: string;

  constructor(stateDirectory: string, processRef = randomUUID()) {
    this.#directory = join(stateDirectory, 'resources');
    this.processRef = z.uuid().parse(processRef);
  }

  get directory(): string {
    return this.#directory;
  }

  async write(
    facts: Omit<BudgetCacheFile, 'schemaVersion' | 'processRef'>,
  ): Promise<void> {
    const normalized = BudgetCacheFile.parse({
      ...facts,
      schemaVersion: 1,
      processRef: this.processRef,
    });
    const serialized = JSON.stringify(normalized);

    if (Buffer.byteLength(serialized) > CACHE_BYTES) {
      throw new Error(
        'Resource cache write exceeds 256 KiB; coverage is incomplete.',
      );
    }

    await mkdir(this.#directory, { recursive: true, mode: 0o700 });

    const temporary = join(
      this.#directory,
      `${this.processRef}.${randomUUID()}.tmp`,
    );

    try {
      await writeFile(temporary, serialized, { mode: 0o600, flag: 'wx' });
      await rename(temporary, this.#path());
    } finally {
      await rm(temporary, { force: true });
    }
  }

  async close(now: number): Promise<void> {
    let file;

    try {
      file = await open(
        this.#path(),
        constants.O_RDONLY | constants.O_NOFOLLOW,
      );
    } catch (error) {
      if (notFound(error)) {
        return;
      }

      throw error;
    }

    try {
      const metadata = await file.stat();

      if (
        metadata.size > CACHE_BYTES ||
        now - metadata.mtimeMs <= CACHE_RETENTION_MS
      ) {
        return;
      }

      const bytes = Buffer.alloc(CACHE_BYTES + 1);
      const read = await file.read(bytes, 0, bytes.length, 0);
      const own = BudgetCacheFile.safeParse(
        JSON.parse(bytes.toString('utf8', 0, read.bytesRead)),
      );

      // Close may remove only its own expired file, never scan other writers.
      if (
        own.success &&
        own.data.processRef === this.processRef &&
        now - Date.parse(own.data.writtenAt) > CACHE_RETENTION_MS
      ) {
        const current = await stat(this.#path());

        if (
          current.ino === metadata.ino &&
          current.mtimeMs === metadata.mtimeMs &&
          current.size === metadata.size
        ) {
          await rm(this.#path());
        }
      }
    } finally {
      await file.close();
    }
  }

  #path(): string {
    return join(this.#directory, `${this.processRef}.json`);
  }
}

/** Verified identity folds once; unbound evidence stays scoped to its emitter. */
export function foldBudgetCache(
  files: readonly BudgetCacheFile[],
  preferences: TeamSelection,
  now: BudgetClock,
  warnings: readonly string[] = [],
  age: (window: WindowSnapshot, sourceKey: string) => WindowSnapshot = (
    window,
  ) => ageWindow(window, now),
): BudgetSnapshot {
  const pools = new Map<string, BudgetCacheFile['pools'][number]>();
  const unbound = new Map<string, BudgetCacheFile['unbound'][number]>();
  const active = new Map<string, BudgetCacheFile['activeRuns'][number]>();
  const unavailable = new Map<string, BudgetCacheFile['unavailable'][number]>();

  for (const file of [...files].sort((left, right) =>
    left.writtenAt.localeCompare(right.writtenAt),
  )) {
    for (const pool of file.pools) {
      const key = JSON.stringify([
        pool.provider,
        pool.billing,
        pool.accountRef,
        pool.poolRef,
        pool.source,
      ]);
      const old = pools.get(key);

      pools.set(key, {
        ...pool,
        windows: mergeWindows(old?.windows ?? [], pool.windows),
      });
    }

    for (const observation of file.unbound) {
      const key = JSON.stringify([
        file.processRef,
        observation.sourceRef,
        observation.sessionRef,
        observation.observationRef,
      ]);
      const old = unbound.get(key);

      unbound.set(key, {
        ...observation,
        windows: mergeWindows(old?.windows ?? [], observation.windows),
      });
    }

    for (const run of file.activeRuns) {
      active.set(
        JSON.stringify([run.processRef, run.runRef, run.member]),
        activeAt(run, now.wall),
      );
    }

    for (const missing of file.unavailable) {
      unavailable.set(JSON.stringify([missing.agent, missing.reason]), missing);
    }
  }

  const aged = <
    T extends { windows: BudgetCacheFile['pools'][number]['windows'] },
  >(
    observation: T,
    sourceKey: string,
  ): T => ({
    ...observation,
    windows: bounded(observation.windows, 128).map((window) =>
      age(window, sourceKey),
    ),
  });

  const completeness = new Set(warnings);
  const bounded = <T>(values: T[], limit: number): T[] => {
    if (values.length > limit) {
      completeness.add(`${INCOMPLETE}: folded facts exceed the output limit.`);
    }

    return values.slice(0, limit);
  };

  return {
    schemaVersion: 1,
    observedAt: new Date(now.wall).toISOString(),
    preferences: { ...preferences, intent: preferences.intent ?? 'fixed' },
    pools: bounded([...pools.entries()], 128).map(([key, pool]) =>
      aged(pool, key),
    ),
    unbound: bounded([...unbound.entries()], 128).map(([key, value]) =>
      aged(value, key),
    ),
    unavailable: bounded([...unavailable.values()], 128),
    activeRuns: bounded([...active.values()], 256),
    warnings: [...completeness].slice(0, 256),
  };
}
