/** Fixed fake-only states for captures and tests; no authentication or provider fallback. */
import type { ProviderLimits } from '../session/budgets.ts';

export const RESOURCE_FIXTURE_CASES = [
  'normal',
  'partial',
  'timeout',
  'unavailable',
] as const;

export type ResourceFixtureCase = (typeof RESOURCE_FIXTURE_CASES)[number];

/** The private capture flag selects fixtures as a whole, never a fallback reader. */
export function resourceSourceMode(
  flag: string | undefined,
): 'official' | 'fixture' {
  return flag === 'true' ? 'fixture' : 'official';
}

export function resourceFixtureCase(
  value: string | undefined,
): ResourceFixtureCase {
  return RESOURCE_FIXTURE_CASES.find((item) => item === value) ?? 'normal';
}

export function fixtureLimits(
  agent: string,
  scenario: ResourceFixtureCase,
  signal: AbortSignal,
): Promise<ProviderLimits> {
  if (scenario === 'timeout') {
    // Never answers: the read's own deadline reports it.
    return new Promise((_, reject) => {
      if (signal.aborted) {
        reject(signal.reason);

        return;
      }

      signal.addEventListener('abort', () => reject(signal.reason), {
        once: true,
      });
    });
  }

  if (scenario === 'unavailable') {
    return Promise.resolve({
      agent,
      unavailable: 'Scripted unavailable provider.',
    });
  }

  const window = {
    name: 'five_hour',
    usedPercent: 12.345,
    windowSeconds: 18000,
    resetsAt: new Date(Date.now() + 3600000).toISOString(),
    models: null,
  };

  return Promise.resolve({
    agent,
    windows:
      scenario === 'partial'
        ? [
            window,
            {
              name: 'seven_day',
              usedPercent: null,
              windowSeconds: 604800,
              resetsAt: null,
              models: null,
            },
          ]
        : [window],
  });
}
