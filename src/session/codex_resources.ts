/** Official public-stream collector; the library owns JSONL framing and handshake. */
import { AppServerClient, StdioTransport } from 'codex-app-server-client';
import {
  COLLECTOR_BOUNDS,
  type CollectorBounds,
  resourceSignal,
  withResourceProcess,
} from '../platform/resource_process.ts';
import type { ProviderLimits } from './budgets.ts';
import { normalizeCodex } from './resource_normalization.ts';

export function collectCodexResources(
  command: readonly [string, ...string[]],
  options: {
    readonly cwd: string;
    readonly signal: AbortSignal;
    readonly bounds?: CollectorBounds;
  },
): Promise<ProviderLimits> {
  const bounds = options.bounds ?? COLLECTOR_BOUNDS;

  return withResourceProcess(
    command,
    options,
    async (group, signal, onClose) => {
      const transport = new StdioTransport({
        input: group.child.stdout!,
        output: group.child.stdin!,
        closeOutputOnClose: false,
      });
      const client = new AppServerClient({
        transport,
        defaultRequestTimeoutMs: bounds.requestMs,
      });

      onClose(() => client.close());

      await client.start();
      await client.initialize(
        {
          capabilities: null,
          clientInfo: {
            name: 'chord-resource-reader',
            title: 'Chord resource facts',
            version: '1',
          },
        },
        {
          request: {
            signal: resourceSignal(signal, bounds.initializeMs),
            timeoutMs: bounds.initializeMs,
          },
        },
      );

      const account = await client.account.read(
        { refreshToken: false },
        {
          signal: resourceSignal(signal, bounds.requestMs),
          timeoutMs: bounds.requestMs,
        },
      );

      if (account.account?.type !== 'chatgpt') {
        return normalizeCodex(account, undefined);
      }

      const limits = await client.account.rateLimitsRead({
        signal: resourceSignal(signal, bounds.requestMs),
        timeoutMs: bounds.requestMs,
      });

      signal.throwIfAborted();

      return normalizeCodex(account, limits);
    },
  );
}
