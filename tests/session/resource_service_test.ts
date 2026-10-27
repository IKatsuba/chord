import { describe, expect, test } from 'bun:test';
import { ResourceReadError } from '../../src/platform/resource_process.ts';
import {
  ResourceService,
  type ResourceRead,
  type ResourceStorage,
  type ResourceTarget,
} from '../../src/session/resource_service.ts';
import type { BudgetCacheFile } from '../../src/platform/budget_cache.ts';
import type {
  ActiveRun,
  UnboundObservation,
} from '../../src/session/budgets.ts';

const wall = Date.parse('2026-10-27T12:00:00Z');
const iso = (offset = 0) => new Date(wall + offset).toISOString();
const processRef = '00000000-0000-4000-8000-000000000001';
const observation = (offset = 0): UnboundObservation => ({
  observationRef: 'observation',
  sourceRef: 'source',
  sessionRef: 'session',
  source: 'fake',
  sourceVersion: '1',
  agent: 'codex',
  billingKind: 'subscription',
  coverage: 'unknown',
  externalActivity: 'unknown',
  observedAt: iso(offset),
  reason: 'Identity unverified.',
  windows: [
    {
      windowRef: 'five-hour',
      models: null,
      usedPercent: 12.345,
      windowSeconds: 18000,
      resetsAt: iso(3600000),
      observedAt: iso(offset),
      receivedAt: iso(offset),
      state: 'fresh',
      reason: null,
    },
  ],
});
const file = (value = observation()): BudgetCacheFile => ({
  schemaVersion: 1,
  processRef,
  writtenAt: iso(),
  pools: [],
  unbound: [value],
  unavailable: [],
  activeRuns: [],
});
const flush = async () => {
  for (let turn = 0; turn < 15; turn++) {
    await Promise.resolve();
  }
};

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });

  return { promise, resolve };
}

function setup(storage?: ResourceStorage) {
  let clock = { wall, monotonic: 0 };
  const service = new ResourceService({
    now: () => clock,
    every: () => () => {},
    ...(storage === undefined ? {} : { storage }),
  });

  return {
    service,
    clock: (offset: number, monotonic = offset) => {
      clock = { wall: wall + offset, monotonic };
    },
  };
}

function target(read: ResourceTarget['read'], key = 'codex'): ResourceTarget {
  return { key, agent: key, read };
}

describe('shared advisory resource service', () => {
  test('startup loads once; immediate reads neither collect nor re-read cache', async () => {
    const reads: boolean[] = [];
    const { service } = setup({
      read: (startup) => {
        reads.push(startup);

        return Promise.resolve({
          files: [file()],
          warnings: ['Incomplete fixture coverage.'],
        });
      },
      write: async () => {},
      close: async () => {},
    });

    await service.start();
    await service.start();

    expect(
      service.read({ intent: 'balanced' }).unbound[0]?.windows[0]?.usedPercent,
    ).toBe(12.345);
    expect(service.read().warnings).toEqual(['Incomplete fixture coverage.']);
    expect(reads).toEqual([true]);

    service.tick();
    await flush();

    expect(reads).toEqual([true, false]);

    await service.close();
  });

  test('shares one in-flight read; detaching one consumer does not cancel another', async () => {
    const pending = deferred<ResourceRead>();
    const { service } = setup();
    let calls = 0;
    let signal: AbortSignal | undefined;
    const source = target((input) => {
      calls++;

      signal = input;

      return Promise.resolve(pending.promise);
    });

    const first = new AbortController();
    const second = new AbortController();

    service.retain(source, first.signal);
    service.retain(source, second.signal);
    await flush();

    expect(calls).toBe(1);
    expect(service.read().unavailable[0]?.reason).toContain('pending');

    first.abort();

    expect(signal?.aborted).toBe(false);

    pending.resolve({ facts: { observation: observation() } });
    await flush();

    expect(service.read().unbound).toHaveLength(1);

    await service.close();
  });

  test('last consumer cancels; late old-generation result cannot publish into replacement', async () => {
    const pending = deferred<ResourceRead>();
    const { service, clock } = setup();
    const first = new AbortController();
    let signal: AbortSignal | undefined;
    let calls = 0;
    const source = target((input) => {
      calls++;

      signal = input;

      return Promise.resolve(
        calls === 1
          ? pending.promise
          : { facts: { observation: observation(120000) } },
      );
    });

    service.retain(source, first.signal);
    await flush();
    first.abort();

    expect(signal?.aborted).toBe(true);

    service.retain(source, new AbortController().signal);
    pending.resolve({ facts: { observation: observation() } });
    await flush();

    expect(service.read().unbound).toEqual([]);

    clock(120000);
    service.tick();
    await flush();

    expect(calls).toBe(2);
    expect(service.read().unbound[0]?.windows[0]?.receivedAt).toBe(iso(120000));

    await service.close();
  });

  test('invalid admission never starts a target and close rejects late publication', async () => {
    const { service } = setup();
    const pending = deferred<ResourceRead>();
    let calls = 0;
    const source = target(() => {
      calls++;

      return Promise.resolve(pending.promise);
    });

    const aborted = new AbortController();

    aborted.abort();
    service.retain(source, aborted.signal);
    service.retain(source, new AbortController().signal, () => false);
    await flush();

    expect(calls).toBe(0);

    service.retain(source, new AbortController().signal);
    await flush();

    const closing = service.close();

    pending.resolve({ facts: { observation: observation() } });
    await closing;

    expect(service.read().unbound).toEqual([]);
  });

  test('backoff is bounded and Retry-After only extends it', async () => {
    const { service, clock } = setup();
    let calls = 0;
    const source = target(() => {
      calls++;

      return Promise.resolve({
        facts: {
          unavailable: { agent: 'codex', reason: 'Temporary fixture failure.' },
        },
        retry: 'transient',
        ...(calls === 1 ? { retryAfterMs: 180000 } : {}),
      });
    });

    service.retain(source, new AbortController().signal);
    await flush();

    for (const [at, expected] of [
      [120000, 1],
      [180000, 2],
      [419999, 2],
      [420000, 3],
      [900000, 4],
      [1800000, 5],
      [2700000, 6],
    ] as const) {
      clock(at);
      service.tick();
      await flush();

      expect(calls).toBe(expected);
    }

    expect(service.read().unavailable[0]).toEqual({
      agent: 'codex',
      reason: 'Temporary fixture failure.',
    });
    expect(JSON.stringify(service.read())).not.toContain('retry');

    await service.close();
  });

  test('configuration failures wait for a new consumer session instead of retry loops', async () => {
    const { service, clock } = setup();
    let calls = 0;
    const source = target(() => {
      calls++;

      return Promise.resolve({
        facts: {
          unavailable: {
            agent: 'codex',
            reason: 'Unsupported fixture configuration.',
          },
        },
        retry: 'configuration',
      });
    });

    const controller = new AbortController();

    service.retain(source, controller.signal);
    await flush();
    clock(3600000);
    service.tick();
    await flush();

    expect(calls).toBe(1);

    controller.abort();
    service.retain(source, new AbortController().signal);
    await flush();

    expect(calls).toBe(2);

    await service.close();
  });

  test('retained cache uses first local anchor and rejects freshness after clock rollback', async () => {
    const { service, clock } = setup({
      read: () =>
        Promise.resolve({ files: [file(observation(5000))], warnings: [] }),
      write: async () => {},
      close: async () => {},
    });

    await service.start();

    expect(service.read().unbound[0]?.windows[0]?.state).toBe('fresh');

    clock(60000);

    expect(service.read().unbound[0]?.windows[0]?.state).toBe('stale');

    clock(30000, 61000);

    expect(service.read().unbound[0]?.windows[0]?.state).toBe('unknown');

    service.tick();
    await flush();

    expect(service.read().unbound[0]?.windows[0]?.state).toBe('unknown');

    await service.close();
  });

  test('partial refresh and failure retain original values/times, including unknown provider time', async () => {
    const { service, clock } = setup();
    let calls = 0;
    const source = target(() => {
      calls++;

      if (calls === 3) {
        return Promise.resolve({
          facts: {
            unavailable: {
              agent: 'codex',
              reason: 'Transient fixture read failed.',
            },
          },
        });
      }

      const value = observation(calls === 1 ? 0 : 120000);

      value.windows[0]!.observedAt = null;

      if (calls === 2) {
        value.windows[0]!.usedPercent = null;
        value.windows[0]!.resetsAt = null;
      }

      return Promise.resolve({ facts: { observation: value } });
    });

    service.retain(source, new AbortController().signal);
    await flush();
    clock(120000);
    service.tick();
    await flush();

    expect(service.read().unbound[0]?.windows[0]).toMatchObject({
      usedPercent: 12.345,
      receivedAt: iso(),
      observedAt: null,
      state: 'unknown',
    });

    clock(240000);
    service.tick();
    await flush();

    expect(service.read().unbound[0]?.windows[0]).toMatchObject({
      usedPercent: 12.345,
      receivedAt: iso(),
      observedAt: null,
      state: 'unknown',
    });

    clock(900000);

    expect(
      service
        .read()
        .unavailable.some((value) => value.reason.includes('historical')),
    ).toBe(true);

    await service.close();
  });

  test('heartbeat writes active roles; reading alone never re-dates them', async () => {
    const writes: BudgetCacheFile[] = [];
    const { service, clock } = setup({
      read: () => Promise.resolve({ files: [], warnings: [] }),
      write: (value) => {
        writes.push(value);

        return Promise.resolve();
      },
      close: async () => {},
    });
    const run: ActiveRun = {
      processRef,
      runRef: 'run',
      sessionRef: 'session',
      team: 'team',
      member: 'lead',
      agent: 'codex',
      model: null,
      resourceRefs: [],
      state: 'working',
      lastSeenAt: iso(),
    };

    service.active([run]);
    clock(46000);

    expect(service.read().activeRuns[0]?.state).toBe('stale');
    expect(service.read().activeRuns[0]?.lastSeenAt).toBe(iso());

    service.tick();
    await flush();

    expect(writes.at(-1)?.activeRuns[0]?.lastSeenAt).toBe(iso(46000));
    expect(service.read().activeRuns[0]?.state).toBe('working');

    await service.close();
  });
});

describe('resource service bounded failures', () => {
  test('one total deadline aborts a hung target and rejects its late result', async () => {
    const { service } = setup();
    const pending = deferred<ResourceRead>();
    const aborted = deferred<void>();
    let signal: AbortSignal | undefined;

    service.retain(
      target((input) => {
        signal = input;

        input.addEventListener('abort', () => aborted.resolve(), {
          once: true,
        });

        return Promise.resolve(pending.promise);
      }),
      new AbortController().signal,
    );

    const cleanup = deferred<void>();

    service.retain(
      target(
        (input) =>
          new Promise((_, reject) => {
            input.addEventListener(
              'abort',
              () => {
                reject(
                  new ResourceReadError(
                    'cleanup',
                    'Private fixture diagnostic must not escape.',
                  ),
                );
                cleanup.resolve();
              },
              { once: true },
            );
          }),
        'cleanup-on-deadline',
      ),
      new AbortController().signal,
    );
    await aborted.promise;
    await cleanup.promise;
    await flush();

    expect(service.read().warnings).toContain(
      'Resource collector cleanup failed; owned process exit is unverified.',
    );
    expect(JSON.stringify(service.read())).not.toContain(
      'Private fixture diagnostic',
    );

    expect(signal?.aborted).toBe(true);
    expect(service.read().unavailable[0]?.reason).toContain('deadline');

    pending.resolve({ facts: { observation: observation() } });
    await flush();

    expect(service.read().unbound).toEqual([]);

    await service.close();
  }, 25000);

  test('changed targets keep distinct source identity and invalid generations stop on tick', async () => {
    const { service } = setup();
    let valid = true;
    const old = deferred<ResourceRead>();
    let signal: AbortSignal | undefined;
    let unrelated = 0;
    const unused = target(() => {
      unrelated++;

      return Promise.resolve({ facts: { observation: observation() } });
    }, 'unrelated');

    service.retain(
      target((input) => {
        signal = input;

        return Promise.resolve(old.promise);
      }, 'old-config'),
      new AbortController().signal,
      () => valid,
    );
    await flush();

    valid = false;

    service.tick();
    service.retain(
      target(
        () =>
          Promise.resolve({
            facts: {
              observation: { ...observation(), sourceRef: 'new-source' },
            },
          }),
        'new-config',
      ),
      new AbortController().signal,
    );
    old.resolve({ facts: { observation: observation() } });
    await flush();

    expect(signal?.aborted).toBe(true);
    expect(service.read().unbound.map((value) => value.sourceRef)).toEqual([
      'new-source',
    ]);
    expect(unused.key).toBe('unrelated');
    expect(unrelated).toBe(0);

    await service.close();
  });

  test('reset and monotonic historical boundaries age independently without rereceipt', async () => {
    const value = observation();

    value.windows.push({
      ...value.windows[0]!,
      windowRef: 'weekly',
      resetsAt: iso(1000),
    });

    const { service, clock } = setup({
      read: () => Promise.resolve({ files: [file(value)], warnings: [] }),
      write: async () => {},
      close: async () => {},
    });

    await service.start();
    clock(1000);

    expect(
      service.read().unbound[0]?.windows.map((window) => window.state),
    ).toEqual(['fresh', 'stale']);

    clock(2000, 900000);

    expect(service.read().unbound[0]?.windows[0]?.reason).toContain(
      '15 minutes',
    );
    expect(service.read().unbound[0]?.windows[0]?.receivedAt).toBe(iso());

    await service.close();
  });

  test('malformed facts are incomplete rather than valid coverage', async () => {
    const { service } = setup();
    const invalid = {
      ...observation(),
      windows: Array.from({ length: 129 }, () => observation().windows[0]!),
    };

    service.retain(
      target(() => Promise.resolve({ facts: { observation: invalid } })),
      new AbortController().signal,
    );
    await flush();

    expect(service.read().unbound).toEqual([]);
    expect(service.read().unavailable[0]?.reason).toContain('incomplete');

    await service.close();
  });
});

describe('resource cache anchor continuity', () => {
  test('a disappearing and returning file keeps its original local freshness deadline', async () => {
    let files = [file(observation(5000))];
    const { service, clock } = setup({
      read: () => Promise.resolve({ files, warnings: [] }),
      write: async () => {},
      close: async () => {},
    });

    await service.start();

    files = [];

    clock(1000);
    service.tick();
    await flush();

    expect(service.read().unbound).toEqual([]);

    files = [file(observation(5000))];

    clock(2000);
    service.tick();
    await flush();
    clock(60000);

    expect(service.read().unbound[0]?.windows[0]?.state).toBe('stale');

    await service.close();
  });
});

describe('resource collector exit verification', () => {
  const cleanupTarget = () =>
    target(
      (signal) =>
        new Promise((_, reject) => {
          signal.addEventListener(
            'abort',
            () =>
              reject(
                new ResourceReadError(
                  'cleanup',
                  'Private fixture cleanup detail.',
                ),
              ),
            { once: true },
          );
        }),
    );

  test('last-consumer cancellation retains sanitized cleanup diagnostics without late facts', async () => {
    const { service } = setup();
    const controller = new AbortController();

    service.retain(cleanupTarget(), controller.signal);
    await flush();
    controller.abort();
    await flush();

    expect(service.read().warnings).toContain(
      'Resource collector cleanup failed; owned process exit is unverified.',
    );
    expect(service.read().unbound).toEqual([]);
    expect(JSON.stringify(service.read())).not.toContain('Private fixture');

    service.retain(
      target(
        () => Promise.resolve({ facts: { observation: observation() } }),
        'later-success',
      ),
      new AbortController().signal,
    );
    await flush();

    expect(service.read().unbound).toHaveLength(1);
    expect(service.read().warnings).toContain(
      'Resource collector cleanup failed; owned process exit is unverified.',
    );

    await service.close();
  });

  test('shutdown returns an explicit sanitized cleanup-failure warning', async () => {
    const { service } = setup();

    service.retain(cleanupTarget(), new AbortController().signal);
    await flush();

    const warnings = await service.close();

    expect(warnings).toContain(
      'Resource collector cleanup failed; owned process exit is unverified.',
    );
    expect(service.read().warnings).toEqual([...warnings]);
    expect(service.read().unbound).toEqual([]);
    expect(JSON.stringify(warnings)).not.toContain('Private fixture');
  });
});

describe('resource replacement eligibility', () => {
  test('replacement retries a configuration failure when the old generation invalidates before tick', async () => {
    const { service, clock } = setup();
    let valid = true;
    let calls = 0;
    const source = target(() => {
      calls++;

      return Promise.resolve<ResourceRead>(
        calls === 1
          ? {
              facts: {
                unavailable: {
                  agent: 'codex',
                  reason: 'Configuration unsupported.',
                },
              },
              retry: 'configuration',
            }
          : { facts: { observation: observation(120000) } },
      );
    });

    service.retain(source, new AbortController().signal, () => valid);
    await flush();

    valid = false;

    clock(120000);
    service.retain(source, new AbortController().signal);
    service.tick();
    await flush();

    expect(calls).toBe(2);
    expect(service.read().unavailable).toEqual([]);
    expect(service.read().unbound[0]?.windows[0]?.receivedAt).toBe(iso(120000));

    await service.close();
  });
});

describe('tester: resource recovery and retained time boundaries', () => {
  test('success resets transient backoff without shortening the next normal cadence', async () => {
    const { service, clock } = setup();
    let calls = 0;

    service.retain(
      target(() => {
        calls++;

        return Promise.resolve<ResourceRead>(
          calls % 2 === 1
            ? {
                facts: {
                  unavailable: {
                    agent: 'codex',
                    reason: 'Temporary fixture failure.',
                  },
                },
              }
            : {
                facts: {
                  observation: observation(calls === 2 ? 120000 : 360000),
                },
              },
        );
      }),
      new AbortController().signal,
    );
    await flush();

    for (const [at, count] of [
      [119999, 1],
      [120000, 2],
      [239999, 2],
      [240000, 3],
      [359999, 3],
      [360000, 4],
    ] as const) {
      clock(at);
      service.tick();
      await flush();

      expect(calls).toBe(count);
    }

    expect(service.read().unavailable).toEqual([]);
    expect(service.read().unbound[0]?.windows[0]?.receivedAt).toBe(iso(360000));

    await service.close();
  });

  test('invalid Retry-After values cannot poison or shorten the retry deadline', async () => {
    for (const retryAfterMs of [NaN, Infinity, -1, 0]) {
      const { service, clock } = setup();
      let calls = 0;

      service.retain(
        target(() => {
          calls++;

          return Promise.resolve({
            facts: {
              unavailable: {
                agent: 'codex',
                reason: 'Temporary fixture failure.',
              },
            },
            retryAfterMs,
          });
        }),
        new AbortController().signal,
      );
      await flush();
      clock(119999);
      service.tick();
      await flush();

      expect(calls).toBe(1);

      clock(120000);
      service.tick();
      await flush();

      expect(calls).toBe(2);

      await service.close();
    }
  });

  test('cache read recovery clears its warning without reviving retained observation times', async () => {
    let reads = 0;
    const { service, clock } = setup({
      read: () => {
        reads++;

        return reads === 2
          ? Promise.reject(new Error('Excluded raw cache diagnostic.'))
          : Promise.resolve({ files: [file()], warnings: [] });
      },
      write: async () => {},
      close: async () => {},
    });

    await service.start();
    clock(60000);
    service.tick();
    await flush();

    expect(service.read().warnings).toEqual([
      'Resource cache coverage is incomplete: cache read failed.',
    ]);
    expect(service.read().unbound[0]?.windows[0]).toMatchObject({
      state: 'stale',
      receivedAt: iso(),
    });

    service.tick();
    await flush();

    expect(service.read().warnings).toEqual([]);
    expect(service.read().unbound[0]?.windows[0]).toMatchObject({
      state: 'stale',
      observedAt: iso(),
      receivedAt: iso(),
    });

    await service.close();
  });

  test('a refreshed independent window cannot refresh omitted timestamped windows', async () => {
    const { service, clock } = setup();
    let calls = 0;

    service.retain(
      target(() => {
        calls++;

        const value = observation(calls === 1 ? 0 : 120000);

        if (calls === 2) {
          value.windows[0]!.windowRef = 'weekly';
        }

        return Promise.resolve({ facts: { observation: value } });
      }),
      new AbortController().signal,
    );
    await flush();
    clock(120000);
    service.tick();
    await flush();

    expect(service.read().unbound[0]?.windows).toMatchObject([
      {
        windowRef: 'five-hour',
        state: 'stale',
        observedAt: iso(),
        receivedAt: iso(),
      },
      {
        windowRef: 'weekly',
        state: 'fresh',
        observedAt: iso(120000),
        receivedAt: iso(120000),
      },
    ]);

    await service.close();
  });
});

describe('resource cache close diagnostics', () => {
  test('cache close failure is a fixed bounded warning without raw filesystem detail', async () => {
    const { service } = setup({
      read: () => Promise.resolve({ files: [], warnings: [] }),
      write: () => Promise.resolve(),
      close: () => Promise.reject(new Error('Private cache diagnostics.')),
    });

    const warnings = await service.close();

    expect(warnings).toEqual([
      'Resource cache cleanup could not be completed.',
    ]);
    expect(JSON.stringify(service.read())).not.toContain('Private cache');
  });
});
