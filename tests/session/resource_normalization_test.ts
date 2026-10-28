import { describe, expect, test } from 'bun:test';
import {
  normalizeClaude,
  normalizeCodex,
} from '../../src/session/resource_normalization.ts';
import { UnboundObservation } from '../../src/session/budgets.ts';

const source = {
  sourceRef: 'fixture-source',
  sessionRef: 'fixture-session',
  receivedAt: '2026-10-27T13:00:00.000Z',
};
const account = {
  account: { type: 'chatgpt', email: 'excluded@example.test' },
};
const bucket = {
  primary: {
    usedPercent: 12.345,
    windowDurationMins: 60,
    resetsAt: 1_800_000_000,
  },
  secondary: null,
};

describe('official resource normalization', () => {
  test('all-null, empty and wholly malformed source windows are unavailable', () => {
    for (const windows of [
      {},
      { primary: null, secondary: null },
      {
        primary: {
          usedPercent: null,
          windowDurationMins: null,
          resetsAt: null,
        },
        secondary: null,
      },
      {
        primary: { usedPercent: null, windowDurationMins: 60, resetsAt: null },
        secondary: null,
      },
      { primary: { usedPercent: 101 }, secondary: 'malformed' },
    ]) {
      expect(
        normalizeCodex(
          account,
          { rateLimits: windows, rateLimitsByLimitId: null },
          source,
        ),
      ).toHaveProperty('unavailable');
    }

    for (const rateLimits of [
      {},
      { five_hour: null, seven_day: null },
      { five_hour: { utilization: null, resets_at: null } },
      {
        five_hour: { utilization: -1, resets_at: 'malformed' },
        model_scoped: 'invalid',
      },
    ]) {
      expect(
        normalizeClaude(
          { rate_limits_available: true, rate_limits: rateLimits },
          source,
        ),
      ).toHaveProperty('unavailable');
    }
  });

  test('valid reset alone remains partial timing evidence without a capacity claim', () => {
    const codex = normalizeCodex(
      account,
      {
        rateLimits: {
          primary: {
            usedPercent: null,
            windowDurationMins: null,
            resetsAt: 1_800_000_000,
          },
          secondary: null,
        },
        rateLimitsByLimitId: null,
      },
      source,
    );
    const claude = normalizeClaude(
      {
        rate_limits_available: true,
        rate_limits: {
          five_hour: { utilization: null, resets_at: '2026-10-28T13:00:00Z' },
        },
      },
      source,
    );

    for (const result of [codex, claude]) {
      if ('observation' in result) {
        expect(result.observation.windows[0]).toMatchObject({
          usedPercent: null,
          observedAt: null,
          state: 'unknown',
        });
        expect(result.observation.windows[0]!.resetsAt).not.toBeNull();
      } else {
        throw new Error('Expected explicit partial timing facts.');
      }
    }
  });

  test('Codex reports the executable version it was read from as its source version', () => {
    const limits = { rateLimits: bucket, rateLimitsByLimitId: null };
    const read = normalizeCodex(account, limits, {
      ...source,
      version: '0.164.0',
    });
    const unread = normalizeCodex(account, limits, source);

    expect(read).toHaveProperty('observation.sourceVersion', '0.164.0');
    expect(unread).toHaveProperty('observation.sourceVersion', 'unknown');
  });

  test('Codex prefers all map buckets, without adding the legacy duplicate or exporting account IDs', () => {
    const result = normalizeCodex(
      account,
      {
        rateLimits: bucket,
        rateLimitsByLimitId: {
          'private-bucket-a': bucket,
          'private-bucket-b': bucket,
        },
      },
      source,
    );

    expect('observation' in result).toBe(true);

    if ('observation' in result) {
      expect(UnboundObservation.safeParse(result.observation).success).toBe(
        true,
      );
      expect(result.observation.windows).toHaveLength(4);
      expect(result.observation.windows[0]).toMatchObject({
        usedPercent: 12.345,
        windowSeconds: 3600,
        observedAt: null,
        state: 'unknown',
        models: null,
      });
      expect(result.observation.windows[1]!.usedPercent).toBeNull();
      expect(JSON.stringify(result)).not.toContain('private-bucket');
      expect(JSON.stringify(result)).not.toContain('excluded@example.test');
      expect(
        new Set(result.observation.windows.map((window) => window.windowRef))
          .size,
      ).toBe(4);
    }
  });

  test('legacy/null/empty maps stay distinct and unsupported auth never becomes zero capacity', () => {
    const legacy = normalizeCodex(
      account,
      { rateLimits: bucket, rateLimitsByLimitId: null },
      source,
    );

    expect('observation' in legacy && legacy.observation.windows.length).toBe(
      2,
    );
    expect(
      normalizeCodex(
        account,
        { rateLimits: bucket, rateLimitsByLimitId: {} },
        source,
      ),
    ).toHaveProperty('unavailable');
    expect(
      normalizeCodex({ account: { type: 'apiKey' } }, {}, source),
    ).toHaveProperty('unavailable');
    expect(
      normalizeCodex(account, { rateLimitsByLimitId: 'bad' }, source),
    ).toHaveProperty('unavailable');
  });

  test('malformed windows do not invent utilization or erase valid independent windows', () => {
    const result = normalizeCodex(
      account,
      {
        rateLimits: {
          primary: { ...bucket.primary, usedPercent: 101 },
          secondary: bucket.primary,
        },
        rateLimitsByLimitId: null,
      },
      source,
    );

    if ('observation' in result) {
      expect(result.observation.windows[0]!.usedPercent).toBeNull();
      expect(result.observation.windows[0]!.reason).toContain('Malformed');
      expect(result.observation.windows[1]!.usedPercent).toBe(12.345);
    } else {
      throw new Error('Expected independent window observations.');
    }
  });

  test('Claude preserves incomplete windows and model scope uncertainty without storing session costs', () => {
    const result = normalizeClaude(
      {
        rate_limits_available: true,
        session: { total_cost_usd: 1000 },
        rate_limits: {
          five_hour: { utilization: 0, resets_at: null },
          seven_day: { utilization: 100, resets_at: '2026-10-28T13:00:00Z' },
          model_scoped: [
            {
              display_name: 'private-model-label',
              utilization: 25.125,
              resets_at: null,
            },
          ],
        },
      },
      source,
    );

    if ('observation' in result) {
      expect(UnboundObservation.safeParse(result.observation).success).toBe(
        true,
      );
      expect(result.observation.windows).toHaveLength(6);
      expect(result.observation.windows[0]).toMatchObject({
        usedPercent: 0,
        resetsAt: null,
        state: 'unknown',
        observedAt: null,
      });
      expect(result.observation.windows[1]!.usedPercent).toBe(100);
      expect(result.observation.windows[5]).toMatchObject({
        usedPercent: 25.125,
        models: null,
      });
      expect(JSON.stringify(result)).not.toContain('private-model-label');
      expect(JSON.stringify(result)).not.toContain('total_cost');
    } else {
      throw new Error('Expected unbound subscription observations.');
    }
  });

  test('Claude unavailable/partial/malformed sources retain specific advisory reasons', () => {
    expect(
      normalizeClaude(
        { rate_limits_available: false, rate_limits: null },
        source,
      ),
    ).toHaveProperty('unavailable');
    expect(normalizeClaude({}, source)).toHaveProperty('unavailable');

    const partial = normalizeClaude(
      {
        rate_limits_available: true,
        rate_limits: {
          five_hour: { utilization: 0, resets_at: null },
          model_scoped: 'invalid',
        },
      },
      source,
    );

    if ('observation' in partial) {
      expect(partial.observation.windows[0]!.usedPercent).toBe(0);
      expect(partial.observation.windows.at(-1)!.reason).toContain(
        'incomplete',
      );
    } else {
      throw new Error('Expected partial unknown windows.');
    }
  });
});

describe('resource retry classification', () => {
  test('unsupported auth/scope is configuration failure while malformed snapshots remain transient', () => {
    expect(
      normalizeCodex({ account: { type: 'apiKey' } }, {}, source),
    ).toHaveProperty('retry', 'configuration');
    expect(
      normalizeClaude(
        { rate_limits_available: false, rate_limits: null },
        source,
      ),
    ).toHaveProperty('retry', 'configuration');
    expect(normalizeClaude({}, source)).not.toHaveProperty('retry');
  });
});
