import { describe, expect, test } from 'bun:test';
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
          resetsAt: '2026-10-28T13:00:00Z',
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
