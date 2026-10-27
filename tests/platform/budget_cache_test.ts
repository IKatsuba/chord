import { afterEach, describe, expect, test } from 'bun:test';
import {
  mkdtemp,
  readFile,
  readdir,
  rm,
  stat,
  symlink,
  utimes,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  BudgetCache,
  BudgetCacheFile,
  CACHE_BYTES,
  CACHE_RETENTION_MS,
  foldBudgetCache,
  readBudgetCache,
} from '../../src/platform/budget_cache.ts';

const dirs: string[] = [];
const wall = Date.parse('2026-10-27T13:00:00Z');
const iso = (offset = 0) => new Date(wall + offset).toISOString();
const facts = () => ({
  writtenAt: iso(),
  pools: [],
  unbound: [],
  unavailable: [],
  activeRuns: [],
});

async function scratch() {
  const directory = await mkdtemp(join(tmpdir(), 'chord-resource-cache-'));

  dirs.push(directory);

  return directory;
}

afterEach(async () => {
  await Promise.all(
    dirs
      .splice(0)
      .map((directory) => rm(directory, { recursive: true, force: true })),
  );
});

describe('process resource cache', () => {
  test('close preserves current own facts and never cleans another writer', async () => {
    const directory = await scratch();
    const own = new BudgetCache(directory);
    const other = new BudgetCache(directory);

    await own.write(facts());
    await other.write({
      ...facts(),
      writtenAt: iso(-CACHE_RETENTION_MS - 1000),
    });

    const otherPath = join(other.directory, `${other.processRef}.json`);
    const old = new Date(iso(-CACHE_RETENTION_MS - 1000));

    await utimes(otherPath, old, old);
    await own.close(wall);

    expect(await readdir(own.directory)).toHaveLength(2);

    await other.close(wall);

    expect(await readdir(own.directory)).toEqual([`${own.processRef}.json`]);
  });

  test('serialized byte cap rejects large normalized facts without replacing the last file', async () => {
    const cache = new BudgetCache(await scratch());

    await cache.write(facts());

    const unavailable = Array.from({ length: 128 }, () => ({
      agent: 'a'.repeat(128),
      reason: '界'.repeat(500),
    }));

    const activeRuns = Array.from({ length: 256 }, (_, index) => ({
      processRef: cache.processRef,
      runRef: `run-${index}`,
      sessionRef: 'session',
      team: 'team',
      member: 'reviewer',
      agent: 'fake',
      model: 'model'.repeat(20),
      resourceRefs: [],
      state: 'planned' as const,
      lastSeenAt: iso(),
    }));

    await expect(
      cache.write({ ...facts(), unavailable, activeRuns }),
    ).rejects.toThrow('256 KiB');
    expect(
      (await readBudgetCache(cache.directory, wall)).files[0]!.unavailable,
    ).toEqual([]);
  });

  test('atomic private files retain only strict normalized facts and recreate when removed', async () => {
    const cache = new BudgetCache(await scratch());

    await cache.write(facts());

    const path = join(cache.directory, `${cache.processRef}.json`);

    expect((await stat(path)).mode & 0o777).toBe(0o600);
    expect(JSON.parse(await readFile(path, 'utf8'))).toEqual({
      ...facts(),
      schemaVersion: 1,
      processRef: cache.processRef,
    });

    await rm(path);
    await cache.write(facts());

    expect(await readdir(cache.directory)).toEqual([
      `${cache.processRef}.json`,
    ]);
    expect((await readBudgetCache(cache.directory, wall)).warnings).toEqual([]);

    await expect(
      cache.write({ ...facts(), raw: 'excluded' } as ReturnType<typeof facts>),
    ).rejects.toThrow();
  });

  test('partial, oversized and symlink files warn without reading external payloads', async () => {
    const cache = new BudgetCache(await scratch());

    await cache.write(facts());
    await writeFile(join(cache.directory, 'partial.json'), '{');
    await writeFile(
      join(cache.directory, 'large.json'),
      ' '.repeat(CACHE_BYTES + 1),
    );
    await symlink(
      join(cache.directory, 'partial.json'),
      join(cache.directory, 'link.json'),
    );

    const read = await readBudgetCache(cache.directory, wall);

    expect(read.files).toHaveLength(1);
    expect(read.warnings).toHaveLength(3);
    expect(read.warnings.join(' ')).not.toContain(cache.directory);
  });

  test('bounded scan and startup cleanup remove at most 32 doubly expired files', async () => {
    const cache = new BudgetCache(await scratch());

    await cache.write(facts());

    const old = iso(-CACHE_RETENTION_MS - 1000);
    const payload = JSON.stringify({
      ...facts(),
      schemaVersion: 1,
      processRef: cache.processRef,
      writtenAt: old,
    });

    for (let index = 0; index < 260; index++) {
      const path = join(cache.directory, `old-${index}.json`);

      await writeFile(path, payload);
      await utimes(path, new Date(old), new Date(old));
    }

    const read = await readBudgetCache(cache.directory, wall);

    expect((await readdir(cache.directory)).length).toBe(261 - 32);
    expect(read.warnings.join(' ')).toContain('more than 256 files');
  });

  test('expired embedded time with recent mtime is ignored without deletion', async () => {
    const cache = new BudgetCache(await scratch());

    await cache.write({ ...facts(), writtenAt: iso(-CACHE_RETENTION_MS - 1) });

    expect((await readBudgetCache(cache.directory, wall)).files).toEqual([]);
    expect(await readdir(cache.directory)).toHaveLength(1);
  });

  test('verified synthetic pools fold once; distinct accounts and unbound emitters stay separate', () => {
    const window = {
      windowRef: 'weekly',
      models: null,
      usedPercent: 31.234,
      windowSeconds: null,
      resetsAt: null,
      observedAt: null,
      receivedAt: iso(),
      state: 'unknown' as const,
      reason: null,
    };
    const pool = {
      poolRef: 'synthetic-pool',
      accountRef: 'synthetic-account',
      provider: 'fake',
      billing: 'subscription',
      source: 'fixture',
      sourceVersion: '1',
      identityObservedAt: iso(),
      identity: 'verified',
      coverage: 'account',
      externalActivity: 'unknown',
      windows: [window],
    };
    const unbound = {
      observationRef: 'observation',
      sourceRef: 'source',
      sessionRef: 'session',
      agent: 'fake',
      source: 'fixture',
      sourceVersion: '1',
      observedAt: null,
      billingKind: 'unknown',
      coverage: 'unknown',
      externalActivity: 'unknown',
      windows: [window],
      reason: 'Identity unavailable.',
    };
    const first = BudgetCacheFile.parse({
      ...facts(),
      schemaVersion: 1,
      processRef: '00000000-0000-4000-8000-000000000001',
      pools: [pool],
      unbound: [unbound],
    });
    const second = BudgetCacheFile.parse({
      ...first,
      processRef: '00000000-0000-4000-8000-000000000002',
      pools: [pool, { ...pool, accountRef: 'other-account' }],
    });
    const result = foldBudgetCache([first, second], {}, { wall, monotonic: 0 });

    expect(result.pools).toHaveLength(2);
    expect(result.unbound).toHaveLength(2);
    expect(result.preferences.intent).toBe('fixed');
    expect(result.pools[0]!.windows[0]).toMatchObject({
      usedPercent: 31.234,
      observedAt: null,
      state: 'unknown',
    });
  });
});
