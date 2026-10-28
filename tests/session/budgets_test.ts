import { describe, expect, test } from 'bun:test';
import {
  activeAt,
  ageWindow,
  failedWindows,
  mergeWindows,
  WindowSnapshot,
  type WindowSnapshot as Window,
} from '../../src/session/budgets.ts';

const wall = Date.parse('2026-10-27T13:00:00Z');
const iso = (offset: number) => new Date(wall + offset).toISOString();
const now = { wall, monotonic: 100_000 };

function window(overrides: Partial<Window> = {}): Window {
  return {
    windowRef: 'weekly',
    models: null,
    usedPercent: 12.345,
    windowSeconds: 604800,
    resetsAt: iso(100_000),
    observedAt: iso(-10_000),
    receivedAt: iso(-5000),
    state: 'fresh',
    reason: null,
    ...overrides,
  };
}

describe('resource windows', () => {
  test('preserves precision and endpoints, rejecting malformed values and extra fields', () => {
    for (const usedPercent of [0, 12.345, 100, null]) {
      expect(WindowSnapshot.parse(window({ usedPercent })).usedPercent).toBe(
        usedPercent,
      );
    }

    for (const usedPercent of [-1, 101, NaN, Infinity, '12']) {
      expect(
        WindowSnapshot.safeParse({ ...window(), usedPercent }).success,
      ).toBe(false);
    }

    expect(
      WindowSnapshot.safeParse({ ...window(), rawAccount: 'excluded' }).success,
    ).toBe(false);
    expect(
      WindowSnapshot.safeParse(window({ resetsAt: 'invalid' })).success,
    ).toBe(false);
  });

  test('new receipt without provider observation remains unknown, with original utilization', () => {
    expect(
      ageWindow(window({ observedAt: null, receivedAt: iso(0) }), now),
    ).toMatchObject({
      usedPercent: 12.345,
      observedAt: null,
      receivedAt: iso(0),
      state: 'unknown',
    });
    expect(
      ageWindow(window({ observedAt: null }), { ...now, wall: wall + 900_000 })
        .state,
    ).toBe('stale');
  });

  test('freshness has independent observation, reset and historical receipt boundaries', () => {
    expect(ageWindow(window({ observedAt: iso(-59_999) }), now).state).toBe(
      'fresh',
    );
    expect(ageWindow(window({ observedAt: iso(-60_000) }), now).state).toBe(
      'stale',
    );
    expect(ageWindow(window({ resetsAt: iso(0) }), now).state).toBe('stale');
    expect(ageWindow(window({ resetsAt: null }), now).state).toBe('fresh');
    expect(ageWindow(window({ receivedAt: iso(-900_000) }), now).state).toBe(
      'stale',
    );
    expect(ageWindow(window({ usedPercent: null }), now).state).toBe('unknown');
  });

  test('clock skew and rollback never extend freshness; monotonic elapsed time ages facts', () => {
    expect(ageWindow(window({ observedAt: iso(5001) }), now).state).toBe(
      'unknown',
    );
    expect(ageWindow(window({ observedAt: iso(5000) }), now).state).toBe(
      'fresh',
    );
    expect(
      ageWindow(window({ observedAt: iso(5000), receivedAt: iso(0) }), {
        wall: wall + 60_000,
        monotonic: 160_000,
      }).state,
    ).toBe('stale');
    expect(
      ageWindow(window(), { wall: wall - 1, monotonic: 100_001 }, now).state,
    ).toBe('unknown');
    expect(ageWindow(window(), { wall, monotonic: 160_000 }, now).state).toBe(
      'stale',
    );
  });

  test('slightly future observation and receipt expire 60 seconds after first evaluation', () => {
    const future = window({ observedAt: iso(5000), receivedAt: iso(5000) });

    expect(ageWindow(future, now, now).state).toBe('fresh');
    expect(
      ageWindow(future, { wall: wall + 59_999, monotonic: 159_999 }, now).state,
    ).toBe('fresh');
    expect(
      ageWindow(future, { wall: wall + 60_000, monotonic: 160_000 }, now),
    ).toMatchObject({
      state: 'stale',
      observedAt: iso(5000),
      receivedAt: iso(5000),
    });
  });

  test('partial updates do not refresh omitted or newer windows and failures retain original times', () => {
    const weekly = window();
    const short = window({
      windowRef: 'short',
      models: ['model-a'],
      observedAt: iso(-20_000),
    });
    const newer = { ...short, usedPercent: 40, observedAt: iso(-1000) };

    expect(
      mergeWindows(
        [weekly, short],
        [newer, { ...weekly, observedAt: iso(-30_000) }],
      ),
    ).toEqual([weekly, newer]);

    const [failed] = failedWindows([weekly], 'Refresh failed.');

    expect(failed).toEqual({
      ...weekly,
      state: 'stale',
      reason: 'Refresh failed.',
    });
    expect(ageWindow(failed!, now).state).toBe('stale');
  });

  test('heartbeat staleness means possibly active, without turning planned members into spending', () => {
    const run = {
      processRef: 'process',
      runRef: 'run',
      sessionRef: 'session',
      team: 'team',
      member: 'reviewer',
      agent: 'fake',
      model: null,
      resourceRefs: [],
      state: 'planned' as const,
      lastSeenAt: iso(-44_999),
    };

    expect(activeAt(run, wall).state).toBe('planned');
    expect(activeAt({ ...run, lastSeenAt: iso(-45_000) }, wall).state).toBe(
      'stale',
    );
    expect(
      activeAt({ ...run, state: 'ended', lastSeenAt: iso(-45_000) }, wall)
        .state,
    ).toBe('ended');
  });
});
