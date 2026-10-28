/** An explicit source choice keeps fake windows isolated from installed provider authentication. */
import type { Budgets, ProviderLimits } from '../session/budgets.ts';
import type { ReadLimits } from '../session/resource_access.ts';
import { collectCodexResources } from '../session/codex_resources.ts';
import {
  resolveResourceExecutable,
  type ResourceExecutable,
  type ResourceProvider,
} from './resource_executable.ts';
import { ResourceReadError, resourceWait } from './resource_process.ts';
import { collectClaudeResources } from './resource_worker.ts';
import { fixtureLimits, type ResourceFixtureCase } from './resource_fixture.ts';

/** How long one provider may take before it is reported as not read. */
export const READ_TIMEOUT_MS = 10_000;

const PROVIDERS: readonly ResourceProvider[] = ['claude', 'codex'];

export interface ResourceCollectors {
  resolve(
    provider: ResourceProvider,
    cwd: string,
    customCommand: boolean,
    signal: AbortSignal,
  ): Promise<ResourceExecutable>;
  read(
    provider: ResourceProvider,
    path: string,
    cwd: string,
    signal: AbortSignal,
  ): Promise<ProviderLimits>;
}

const official: ResourceCollectors = {
  resolve: (provider, cwd, customCommand, signal) =>
    resolveResourceExecutable(provider, { cwd, signal, customCommand }),
  read: (provider, path, cwd, signal) =>
    provider === 'codex'
      ? collectCodexResources([path, 'app-server'], { cwd, signal })
      : collectClaudeResources(path, { cwd, signal }),
};

/** The window's limits read, and the close that waits out readers still cleaning up. */
export interface Resources {
  readonly read: ReadLimits;
  /** Every reader's cleanup failures, once each reader has finished. */
  close(): Promise<readonly string[]>;
}

export function createResources(options: {
  readonly collectors: 'official' | 'fixture' | ResourceCollectors;
  readonly fixtureCase?: ResourceFixtureCase;
  readonly timeoutMs?: number;
}): Resources {
  const collectors =
    options.collectors === 'official' ? official : options.collectors;
  const timeoutMs = options.timeoutMs ?? READ_TIMEOUT_MS;
  // An answer past its deadline does not wait for its reader's cleanup;
  // close does, so chord never exits ahead of a provider's process group.
  const running = new Set<Promise<void>>();
  const failures = new Set<string>();

  const readOne = async (
    agent: string,
    place: Parameters<ReadLimits>[1],
    signal: AbortSignal,
  ): Promise<ProviderLimits> => {
    if (agent !== 'claude' && agent !== 'codex') {
      return { agent, unavailable: 'No limits reader for this runtime.' };
    }

    if (collectors === 'fixture') {
      return fixtureLimits(agent, options.fixtureCase ?? 'normal', signal);
    }

    const executable = await collectors.resolve(
      agent,
      place.cwd,
      place.commandOf(agent) !== undefined,
      signal,
    );

    if ('unavailable' in executable) {
      return { agent, unavailable: executable.unavailable };
    }

    return collectors.read(agent, executable.path, place.cwd, signal);
  };

  const read: ReadLimits = async (agents, place, caller) => {
    const readAt = new Date().toISOString();
    const providers = await Promise.all(
      [...new Set(agents ?? PROVIDERS)].map(async (agent) => {
        const timeout = AbortSignal.timeout(timeoutMs);
        const signal = AbortSignal.any([caller, timeout]);

        const reading = readOne(agent, place, signal);
        const owned: Promise<void> = reading
          .then(
            () => {},
            (error: unknown) => {
              if (
                error instanceof ResourceReadError &&
                error.kind === 'cleanup'
              ) {
                failures.add(error.message);
              }
            },
          )
          .finally(() => running.delete(owned));

        running.add(owned);

        try {
          return await resourceWait(reading, signal);
        } catch (error) {
          if (caller.aborted) {
            throw error;
          }

          return {
            agent,
            unavailable: timeout.aborted
              ? `Timed out after ${timeoutMs / 1000} s.`
              : error instanceof ResourceReadError
                ? error.message
                : 'The limits could not be read.',
          };
        }
      }),
    );

    return { readAt, providers } satisfies Budgets;
  };

  return {
    read,
    close: async () => {
      while (running.size > 0) {
        await Promise.all(running);
      }

      return [...failures];
    },
  };
}
