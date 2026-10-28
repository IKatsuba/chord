import { describe, expect, test } from 'bun:test';
import {
  Budgets,
  ProviderLimits,
  ResourceWindow,
} from '../../src/session/budgets.ts';

const window = {
  name: 'primary',
  usedPercent: 0,
  windowSeconds: null,
  resetsAt: null,
  models: null,
};

describe('tester: plain provider-limit answer boundaries', () => {
  test('real zero, full usage and unknown usage remain distinct without legacy fields', () => {
    for (const usedPercent of [0, 100, null]) {
      expect(ResourceWindow.parse({ ...window, usedPercent }).usedPercent).toBe(
        usedPercent,
      );
    }

    const answer = {
      readAt: '2026-10-28T12:00:00Z',
      providers: [{ agent: 'codex', windows: [window] }],
    };

    expect(Budgets.parse(answer)).toEqual(answer);

    for (const obsolete of [
      'activeRuns',
      'preferences',
      'freshness',
      'warnings',
    ]) {
      expect(Budgets.safeParse({ ...answer, [obsolete]: [] }).success).toBe(
        false,
      );
    }

    expect(
      ProviderLimits.safeParse({
        agent: 'claude',
        windows: [],
        unavailable: 'Conflicting state.',
      }).success,
    ).toBe(false);
  });

  test('provider and window count caps accept their boundary and reject overflow', () => {
    const provider = {
      agent: 'codex',
      windows: Array.from({ length: 256 }, () => window),
    };

    expect(ProviderLimits.safeParse(provider).success).toBe(true);
    expect(
      ProviderLimits.safeParse({
        ...provider,
        windows: [...provider.windows, window],
      }).success,
    ).toBe(false);

    const answer = {
      readAt: '2026-10-28T12:00:00Z',
      providers: Array.from({ length: 128 }, () => ({
        agent: 'codex',
        windows: [],
      })),
    };

    expect(Budgets.safeParse(answer).success).toBe(true);
    expect(
      Budgets.safeParse({
        ...answer,
        providers: [...answer.providers, { agent: 'claude', windows: [] }],
      }).success,
    ).toBe(false);
  });

  test('invalid percentages and durations cannot silently become known limits', () => {
    for (const usedPercent of [-1, 101, Infinity, NaN]) {
      expect(ResourceWindow.safeParse({ ...window, usedPercent }).success).toBe(
        false,
      );
    }

    for (const windowSeconds of [0, -1, Infinity, NaN]) {
      expect(
        ResourceWindow.safeParse({ ...window, windowSeconds }).success,
      ).toBe(false);
    }
  });
});
