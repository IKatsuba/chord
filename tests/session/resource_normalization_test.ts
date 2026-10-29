import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  normalizeClaude,
  normalizeCodex,
} from '../../src/session/resource_normalization.ts';
import { ProviderLimits } from '../../src/session/budgets.ts';

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
  test('Codex windows keep the provider bucket names, map over legacy, and no account fields', () => {
    const result = normalizeCodex(account, {
      rateLimits: bucket,
      rateLimitsByLimitId: { codex: bucket, codex_other: bucket },
    });

    expect(ProviderLimits.safeParse(result).success).toBe(true);
    expect(result).toEqual({
      agent: 'codex',
      windows: ['codex.primary', 'codex_other.primary'].map((name) => ({
        name,
        usedPercent: 12.345,
        windowSeconds: 3600,
        resetsAt: new Date(1_800_000_000_000).toISOString(),
        models: null,
      })),
    });
    expect(JSON.stringify(result)).not.toContain('excluded@example.test');
  });

  test('Codex legacy, empty map, malformed windows or buckets and unsupported auth', () => {
    expect(
      normalizeCodex(account, {
        rateLimits: bucket,
        rateLimitsByLimitId: null,
      }),
    ).toMatchObject({ agent: 'codex', windows: [{ name: 'primary' }] });
    expect(
      normalizeCodex(account, { rateLimits: bucket, rateLimitsByLimitId: {} }),
    ).toEqual({ agent: 'codex', windows: [] });
    expect(
      normalizeCodex(account, {
        rateLimits: {
          primary: { ...bucket.primary, usedPercent: 101 },
          secondary: bucket.primary,
        },
        rateLimitsByLimitId: null,
      }),
    ).toEqual({
      agent: 'codex',
      windows: [
        {
          name: 'primary',
          usedPercent: null,
          windowSeconds: null,
          resetsAt: null,
          models: null,
        },
        expect.objectContaining({ name: 'secondary', usedPercent: 12.345 }),
      ],
    });
    expect(
      normalizeCodex(account, {
        rateLimits: bucket,
        rateLimitsByLimitId: { codex: 'bad' },
      }),
    ).toEqual({
      agent: 'codex',
      unavailable: 'Malformed rate-limit snapshot.',
    });
    expect(normalizeCodex({ account: { type: 'apiKey' } }, {})).toHaveProperty(
      'unavailable',
    );
    expect(
      normalizeCodex(account, { rateLimitsByLimitId: 'bad' }),
    ).toHaveProperty('unavailable');
  });

  test('Claude names its windows, skips absent ones and keeps model scope, without session costs', () => {
    const result = normalizeClaude({
      rate_limits_available: true,
      session: { total_cost_usd: 1000 },
      rate_limits: {
        five_hour: { utilization: 0, resets_at: null },
        seven_day: { utilization: 100, resets_at: '2026-10-28T13:00:00Z' },
        seven_day_opus: null,
        model_scoped: [
          { display_name: 'Opus', utilization: 25.125, resets_at: null },
        ],
      },
    });

    expect(ProviderLimits.safeParse(result).success).toBe(true);
    expect(result).toEqual({
      agent: 'claude',
      windows: [
        {
          name: 'five_hour',
          usedPercent: 0,
          windowSeconds: 18000,
          resetsAt: null,
          models: null,
        },
        {
          name: 'seven_day',
          usedPercent: 100,
          windowSeconds: 604800,
          resetsAt: '2026-10-28T13:00:00.000Z',
          models: null,
        },
        {
          name: 'model_scoped',
          usedPercent: 25.125,
          windowSeconds: 604800,
          resetsAt: null,
          models: ['Opus'],
        },
      ],
    });
    expect(JSON.stringify(result)).not.toContain('total_cost');
  });

  test('Claude resets with an offset, with or without fractions, read in Z form', () => {
    const result = normalizeClaude({
      rate_limits_available: true,
      rate_limits: {
        five_hour: {
          utilization: 42,
          resets_at: '2026-10-29T14:40:00.454167+00:00',
        },
        seven_day: { utilization: 7, resets_at: '2026-11-04T01:00:00+00:00' },
        model_scoped: [
          {
            display_name: 'Opus',
            utilization: 3.5,
            resets_at: '2026-11-04T03:00:00+02:00',
          },
        ],
      },
    });

    expect(ProviderLimits.safeParse(result).success).toBe(true);
    expect(result).toEqual({
      agent: 'claude',
      windows: [
        {
          name: 'five_hour',
          usedPercent: 42,
          windowSeconds: 18000,
          resetsAt: '2026-10-29T14:40:00.454Z',
          models: null,
        },
        {
          name: 'seven_day',
          usedPercent: 7,
          windowSeconds: 604800,
          resetsAt: '2026-11-04T01:00:00.000Z',
          models: null,
        },
        {
          name: 'model_scoped',
          usedPercent: 3.5,
          windowSeconds: 604800,
          resetsAt: '2026-11-04T01:00:00.000Z',
          models: ['Opus'],
        },
      ],
    });
  });

  test('a malformed Claude reset still reads as an unknown window', () => {
    expect(
      normalizeClaude({
        rate_limits_available: true,
        rate_limits: {
          five_hour: { utilization: 1, resets_at: '2026-10-29 14:40:00+00:00' },
          seven_day: { utilization: 1, resets_at: '2026-10-29T14:40:00+0000' },
        },
      }),
    ).toEqual({
      agent: 'claude',
      windows: ['five_hour', 'seven_day'].map((name) => ({
        name,
        usedPercent: null,
        windowSeconds: null,
        resetsAt: null,
        models: null,
      })),
    });
  });

  test('Claude unavailable, malformed and empty sources', () => {
    expect(
      normalizeClaude({ rate_limits_available: false, rate_limits: null }),
    ).toHaveProperty('unavailable');
    expect(normalizeClaude({})).toHaveProperty('unavailable');
    expect(
      normalizeClaude({ rate_limits_available: true, rate_limits: {} }),
    ).toEqual({ agent: 'claude', windows: [] });
    expect(
      normalizeClaude({
        rate_limits_available: true,
        rate_limits: {
          five_hour: { utilization: -1, resets_at: 'malformed' },
          model_scoped: 'invalid',
        },
      }),
    ).toEqual({
      agent: 'claude',
      windows: ['five_hour', 'model_scoped'].map((name) => ({
        name,
        usedPercent: null,
        windowSeconds: null,
        resetsAt: null,
        models: null,
      })),
    });
  });
});

describe('tester: bounded provider limits without inference', () => {
  test('Codex keeps genuine zero while unknown duration and reset stay null', () => {
    expect(
      normalizeCodex(account, {
        rateLimits: {
          primary: { usedPercent: 0, windowDurationMins: null, resetsAt: null },
          secondary: null,
        },
        rateLimitsByLimitId: null,
      }),
    ).toEqual({
      agent: 'codex',
      windows: [
        {
          name: 'primary',
          usedPercent: 0,
          windowSeconds: null,
          resetsAt: null,
          models: null,
        },
      ],
    });
  });

  test('the quota map accepts 64 buckets and refuses 65 rather than silently clipping', () => {
    const limits = (length: number) => ({
      rateLimits: bucket,
      rateLimitsByLimitId: Object.fromEntries(
        Array.from({ length }, (_, index) => [`bucket${index}`, bucket]),
      ),
    });
    const accepted = normalizeCodex(account, limits(64));

    expect(ProviderLimits.safeParse(accepted).success).toBe(true);
    assert('windows' in accepted);
    expect(accepted.windows).toHaveLength(64);
    expect(accepted.windows.at(-1)?.name).toBe('bucket63.primary');

    expect(normalizeCodex(account, limits(65))).toEqual({
      agent: 'codex',
      unavailable: 'The quota map exceeds the supported bound.',
    });
  });

  test('malformed Claude availability never permits otherwise valid usage to become a limit', () => {
    for (const availability of [undefined, null, 'true', 1]) {
      expect(
        normalizeClaude({
          rate_limits_available: availability,
          rate_limits: { five_hour: { utilization: 0, resets_at: null } },
        }),
      ).toEqual({
        agent: 'claude',
        unavailable: 'Malformed experimental usage snapshot.',
      });
    }
  });
});

describe('tester: Claude reset offset boundaries', () => {
  test.each([
    ['2027-01-01T00:15:00.123456+05:30', '2026-12-31T18:45:00.123Z'],
    ['2026-12-31T23:15:00-03:30', '2027-01-01T02:45:00.000Z'],
  ])(
    'normalizes %s across the year boundary in fixed and model windows',
    (raw, reset) => {
      const result = normalizeClaude({
        rate_limits_available: true,
        rate_limits: {
          five_hour: { utilization: 0, resets_at: raw },
          seven_day_sonnet: { utilization: 100, resets_at: raw },
          model_scoped: [
            { display_name: 'Sonnet', utilization: 12.5, resets_at: raw },
          ],
        },
      });

      expect(ProviderLimits.safeParse(result).success).toBe(true);
      expect(result).toEqual({
        agent: 'claude',
        windows: [
          {
            name: 'five_hour',
            usedPercent: 0,
            windowSeconds: 18000,
            resetsAt: reset,
            models: null,
          },
          {
            name: 'seven_day_sonnet',
            usedPercent: 100,
            windowSeconds: 604800,
            resetsAt: reset,
            models: null,
          },
          {
            name: 'model_scoped',
            usedPercent: 12.5,
            windowSeconds: 604800,
            resetsAt: reset,
            models: ['Sonnet'],
          },
        ],
      });
    },
  );

  test('malformed resets leave fixed and model windows unknown without losing a valid sibling', () => {
    for (const raw of [
      '',
      '2026-02-30T14:40:00+00:00',
      '2026-10-29T14:40:00',
      '2026-10-29T14:40:00+00:60',
      1_800_000_000,
      undefined,
    ]) {
      expect(
        normalizeClaude({
          rate_limits_available: true,
          rate_limits: {
            five_hour: { utilization: 16, resets_at: raw },
            seven_day: { utilization: 25, resets_at: null },
            model_scoped: [
              { display_name: 'Sonnet', utilization: 16, resets_at: raw },
            ],
          },
        }),
      ).toEqual({
        agent: 'claude',
        windows: [
          {
            name: 'five_hour',
            usedPercent: null,
            windowSeconds: null,
            resetsAt: null,
            models: null,
          },
          {
            name: 'seven_day',
            usedPercent: 25,
            windowSeconds: 604800,
            resetsAt: null,
            models: null,
          },
          {
            name: 'model_scoped',
            usedPercent: null,
            windowSeconds: null,
            resetsAt: null,
            models: null,
          },
        ],
      });
    }
  });
});
