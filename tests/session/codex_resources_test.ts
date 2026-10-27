import { afterEach, describe, expect, test } from 'bun:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { collectCodexResources } from '../../src/session/codex_resources.ts';
import { COLLECTOR_BOUNDS } from '../../src/platform/resource_process.ts';
import { until } from './conversation_fake.ts';

const fixture = new URL('../fixtures/resource_provider.ts', import.meta.url)
  .pathname;
const directories: string[] = [];
const source = { sourceRef: 'fixture-source', sessionRef: 'fixture-session' };

afterEach(async () => {
  await Promise.all(
    directories
      .splice(0)
      .map((directory) => rm(directory, { recursive: true, force: true })),
  );
});

async function record() {
  const directory = await mkdtemp(join(tmpdir(), 'chord-resource-peer-'));

  directories.push(directory);

  return join(directory, 'events.jsonl');
}

async function gone(file: string) {
  const entries = (await readFile(file, 'utf8'))
    .trim()
    .split('\n')
    .map((line) => JSON.parse(line) as { pid?: number; descendant?: number });

  for (const entry of entries) {
    const pid = entry.pid ?? entry.descendant;

    if (pid !== undefined) {
      expect(() => process.kill(pid, 0)).toThrow();
    }
  }
}

describe('public-stream Codex resource collector', () => {
  test('unchanged library sends only handshake/account/quota reads and retains two map buckets', async () => {
    const file = await record();
    const result = await collectCodexResources(
      [process.execPath, fixture, 'normal', file],
      {
        cwd: process.cwd(),
        signal: new AbortController().signal,
        source,
      },
    );

    expect('observation' in result && result.observation.windows.length).toBe(
      4,
    );
    expect(JSON.stringify(result)).not.toContain('excluded@example.test');

    const requests = (await readFile(file, 'utf8'))
      .trim()
      .split('\n')
      .slice(1)
      .map((line) => JSON.parse(line) as { method: string; params: unknown });

    expect(requests.map((request) => request.method)).toEqual([
      'initialize',
      'initialized',
      'account/read',
      'account/rateLimits/read',
    ]);
    expect(requests[2]!.params).toEqual({ refreshToken: false });
    expect(requests[0]!.params).toMatchObject({ capabilities: null });

    await gone(file);
  });

  for (const scenario of ['timeout', 'crash', 'term', 'stubborn']) {
    test(`${scenario} has a bounded failure and drains the entire owned group`, async () => {
      const file = await record();
      const result = collectCodexResources(
        [process.execPath, fixture, scenario, file],
        {
          cwd: process.cwd(),
          signal: new AbortController().signal,
          source,
          bounds: {
            ...COLLECTOR_BOUNDS,
            totalMs: 1500,
            initializeMs: 750,
            closeMs: 100,
            termMs: 100,
            killMs: 1500,
          },
        },
      );

      await expect(result).rejects.toThrow();
      await gone(file);

      if (scenario === 'term' || scenario === 'stubborn') {
        expect(await readFile(file, 'utf8')).toContain('SIGTERM');
      }
    });
  }

  test('in-flight cancellation revokes the result and drains a read already waiting on initialize', async () => {
    const file = await record();
    const controller = new AbortController();
    let published = false;
    const result = collectCodexResources(
      [process.execPath, fixture, 'timeout', file],
      {
        cwd: process.cwd(),
        signal: controller.signal,
        source,
      },
    ).then((value) => {
      published = true;

      return value;
    });

    result.catch(() => {});

    await until(
      () =>
        existsSync(file) && readFileSync(file, 'utf8').includes('initialize'),
    );

    controller.abort();

    await expect(result).rejects.toThrow('cancelled');
    expect(published).toBe(false);

    await gone(file);
  });

  test('cancellation before start launches nothing', async () => {
    const file = await record();
    const cancelled = AbortSignal.abort();

    await expect(
      collectCodexResources([process.execPath, fixture, 'normal', file], {
        cwd: process.cwd(),
        signal: cancelled,
        source,
      }),
    ).rejects.toThrow('cancelled');
    await expect(readFile(file)).rejects.toThrow();
  });
});

describe('Codex resource authentication relevance', () => {
  test('known API authentication is advisory and never requests subscription windows', async () => {
    const file = await record();
    const result = await collectCodexResources(
      [process.execPath, fixture, 'api-account', file],
      { cwd: process.cwd(), signal: new AbortController().signal, source },
    );

    expect(result).toMatchObject({
      unavailable: { agent: 'codex' },
      retry: 'configuration',
    });
    expect(await readFile(file, 'utf8')).not.toContain(
      'account/rateLimits/read',
    );

    await gone(file);
  });
});
