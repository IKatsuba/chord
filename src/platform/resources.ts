/** An explicit source choice keeps fake windows isolated from installed provider authentication. */
import { createHash, randomUUID } from 'node:crypto';
import type {
  ResourceAccess,
  ResourceInterest,
} from '../session/resource_access.ts';
import type {
  ResourceSource,
  NormalizedResources,
} from '../session/resource_normalization.ts';
import {
  ResourceService,
  type ResourceTarget,
} from '../session/resource_service.ts';
import { collectCodexResources } from '../session/codex_resources.ts';
import { BudgetCache, readBudgetCache } from './budget_cache.ts';
import {
  resolveResourceExecutable,
  type ResourceExecutable,
  type ResourceProvider,
} from './resource_executable.ts';
import { collectClaudeResources } from './resource_worker.ts';
import {
  fixtureResourceRead,
  type ResourceFixtureCase,
} from './resource_fixture.ts';

export interface ResourceCollectors {
  resolve(
    provider: ResourceProvider,
    interest: ResourceInterest,
    signal: AbortSignal,
  ): Promise<ResourceExecutable>;
  read(
    provider: ResourceProvider,
    path: string,
    cwd: string,
    signal: AbortSignal,
    source: Omit<ResourceSource, 'receivedAt'>,
  ): Promise<NormalizedResources>;
}

const official: ResourceCollectors = {
  resolve: (provider, interest, signal) =>
    resolveResourceExecutable(provider, {
      cwd: interest.cwd,
      signal,
      customCommand: interest.command !== undefined,
    }),
  read: (provider, path, cwd, signal, source) =>
    provider === 'codex'
      ? collectCodexResources([path, 'app-server'], { cwd, signal, source })
      : collectClaudeResources(path, { cwd, signal, source }),
};

export function createResources(options: {
  readonly stateDirectory: string;
  readonly collectors: 'official' | 'fixture' | ResourceCollectors;
  readonly fixtureCase?: ResourceFixtureCase;
}): ResourceAccess {
  const cache = new BudgetCache(options.stateDirectory);
  const service = new ResourceService({
    processRef: cache.processRef,
    storage: {
      read: (startup) =>
        readBudgetCache(cache.directory, Date.now(), {
          cleanupExpired: startup,
        }),
      write: (file) => cache.write(file),
      close: (now) => cache.close(now),
    },
  });
  const targets = new Map<string, ResourceTarget>();
  const collectors =
    options.collectors === 'official' ? official : options.collectors;

  return {
    processRef: service.processRef,
    start: () => service.start(),
    read: (preferences) => service.read(preferences),
    active: (runs) => service.active(runs),
    close: () => service.close(),
    retain: (interest, signal, valid) => {
      const key = createHash('sha256')
        .update(
          JSON.stringify([
            interest.agent,
            interest.cwd,
            interest.command ?? null,
          ]),
        )
        .digest('hex');
      let target = targets.get(key);

      if (target === undefined) {
        const source = { sourceRef: randomUUID(), sessionRef: randomUUID() };

        target = {
          key,
          agent: interest.agent,
          read: async (readSignal) => {
            if (collectors === 'fixture') {
              return fixtureResourceRead(
                interest.agent,
                source,
                options.fixtureCase ?? 'normal',
                readSignal,
              );
            }

            if (interest.agent !== 'codex' && interest.agent !== 'claude') {
              return {
                facts: {
                  unavailable: {
                    agent: interest.agent,
                    reason: 'No supported resource collector for this runtime.',
                  },
                },
                retry: 'configuration',
              };
            }

            const executable = await collectors.resolve(
              interest.agent,
              interest,
              readSignal,
            );

            readSignal.throwIfAborted();

            if ('unavailable' in executable) {
              return {
                facts: {
                  unavailable: {
                    agent: interest.agent,
                    reason: executable.unavailable,
                  },
                },
                retry: executable.retry ?? 'configuration',
              };
            }

            const facts = await collectors.read(
              interest.agent,
              executable.path,
              interest.cwd,
              readSignal,
              { ...source, version: executable.version },
            );

            return 'unavailable' in facts && facts.retry !== undefined
              ? { facts, retry: facts.retry }
              : { facts };
          },
        };

        if (targets.size < 128) {
          targets.set(key, target);
        }
      }

      return service.retain(target, signal, valid);
    },
  };
}
