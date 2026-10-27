/** Fixed fake-only states for captures and tests; no authentication or provider fallback. */
import type { ResourceRead } from '../session/resource_service.ts';
import type { ResourceSource } from '../session/resource_normalization.ts';

export const RESOURCE_FIXTURE_CASES = [
  'normal',
  'partial',
  'pending',
  'unavailable',
  'long',
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

export function fixtureResourceRead(
  agent: string,
  source: Omit<ResourceSource, 'receivedAt'>,
  scenario: ResourceFixtureCase,
  signal: AbortSignal,
): Promise<ResourceRead> {
  if (scenario === 'pending') {
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
      facts: {
        unavailable: {
          agent,
          reason:
            'Scripted unsupported provider version; current capacity unknown.',
        },
      },
      retry: 'configuration',
    });
  }

  const receivedAt = new Date(Date.now() - 12000).toISOString();
  const window = {
    windowRef: 'fixture-five-hour',
    models: null,
    usedPercent: 12.345,
    windowSeconds: 18000,
    resetsAt: new Date(Date.now() + 3600000).toISOString(),
    observedAt: null,
    receivedAt,
    state: 'unknown' as const,
    reason: 'Provider observation time unavailable.',
  };

  return Promise.resolve({
    facts: {
      observation: {
        observationRef: source.sourceRef,
        ...source,
        agent,
        source: 'fixture',
        sourceVersion: '1',
        coverage: 'unknown',
        externalActivity: 'unknown',
        billingKind: scenario === 'partial' ? 'unknown' : 'subscription',
        observedAt: null,
        reason:
          scenario === 'long'
            ? 'Scripted partial coverage warning: independent provider windows may omit external work, model applicability, provider observation times and current account association. Retained utilization is historical context and never proves available capacity or authorizes a different payment source. This deliberately long advisory verifies ordinary wrapping without hidden uncertainty.'
            : 'Scripted fixture; account and resource identity are unverified.',
        windows:
          scenario === 'partial'
            ? [
                window,
                {
                  ...window,
                  windowRef: 'fixture-weekly',
                  usedPercent: null,
                  windowSeconds: 604800,
                  resetsAt: null,
                  receivedAt: null,
                  reason:
                    'Partial observation; weekly utilization/reset unavailable.',
                },
              ]
            : [window],
      },
    },
  });
}
