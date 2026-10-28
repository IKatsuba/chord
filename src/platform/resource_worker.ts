/** The same Chord entry, isolated from the terminal, owns the experimental SDK. */
import type { Query, SDKUserMessage } from '@anthropic-ai/claude-agent-sdk';
import { z } from '@zod/zod';
import { Transform } from 'node:stream';
import { json } from 'node:stream/consumers';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { ProviderLimits } from '../session/budgets.ts';
import { normalizeClaude } from '../session/resource_normalization.ts';
import { execPath } from './process.ts';
import {
  COLLECTOR_BOUNDS,
  type CollectorBounds,
  ResourceReadError,
  resourceSignal,
  resourceWait,
  withResourceProcess,
} from './resource_process.ts';

declare const CHORD_RESOURCE_COMPILED: boolean;

export const RESOURCE_WORKER_FLAG = '--chord-resource-worker';

const WorkerArguments = z.tuple([z.string().min(1).max(4096)]);

/** A bundle is not necessarily compiled; only the actual compile sets this define. */
export function resourceWorkerCommand(
  path: string,
): readonly [string, ...string[]] {
  const compiled =
    typeof CHORD_RESOURCE_COMPILED !== 'undefined' && CHORD_RESOURCE_COMPILED;

  return [
    execPath(),
    ...(compiled
      ? []
      : [fileURLToPath(new URL('../main.tsx', import.meta.url))]),
    RESOURCE_WORKER_FLAG,
    path,
  ];
}

export function collectClaudeResources(
  path: string,
  options: {
    readonly cwd: string;
    readonly signal: AbortSignal;
    readonly bounds?: CollectorBounds;
  },
): Promise<ProviderLimits> {
  return withResourceProcess(
    resourceWorkerCommand(path),
    options,
    async (group, signal) => {
      let bytes = 0;
      const bounded = new Transform({
        transform(chunk: Buffer, _encoding, callback) {
          bytes += chunk.length;

          callback(
            bytes > 256 * 1024
              ? new ResourceReadError(
                  'protocol',
                  'The isolated worker result exceeds its output bound.',
                )
              : null,
            chunk,
          );
        },
      });

      group.child.stdout!.pipe(bounded);

      try {
        const [result, exit] = await resourceWait(
          Promise.all([json(bounded), group.exit]),
          signal,
        );

        if (exit.code !== 0) {
          throw new ResourceReadError(
            'protocol',
            'The isolated Claude usage worker failed.',
          );
        }

        return ProviderLimits.parse(result);
      } finally {
        group.child.stdout!.unpipe(bounded);
        bounded.destroy();
      }
    },
  );
}

/** Zero input messages: this worker never supplies an inference prompt. */
function noMessages(untilClosed: Promise<void>): AsyncIterable<SDKUserMessage> {
  return {
    [Symbol.asyncIterator]: () => ({
      next: async () => {
        await untilClosed;

        return { done: true, value: undefined };
      },
    }),
  };
}

/** Called before CLI parsing; malformed private arguments never become a prompt. */
export async function runResourceWorker(
  args: readonly string[],
): Promise<void> {
  const parsed = WorkerArguments.safeParse(args);
  let result: ProviderLimits = {
    agent: 'claude',
    unavailable: 'Invalid isolated collector arguments.',
  };

  if (parsed.success) {
    const [path] = parsed.data;
    const input = Promise.withResolvers<void>();
    const controller = new AbortController();
    const deadline = resourceSignal(
      controller.signal,
      COLLECTOR_BOUNDS.totalMs,
    );
    let reading: Query | undefined;

    try {
      const { query } = await import('@anthropic-ai/claude-agent-sdk');

      reading = query({
        prompt: noMessages(input.promise),
        options: {
          cwd: process.cwd(),
          pathToClaudeCodeExecutable: path,
          abortController: controller,
          settingSources: [],
          persistSession: false,
          strictMcpConfig: true,
          mcpServers: {},
          tools: [],
          settings: { disableAllHooks: true },
          stderr: () => {},
        },
      });

      await resourceWait(
        reading.initializationResult(),
        resourceSignal(deadline, COLLECTOR_BOUNDS.initializeMs),
      );

      const usage = await resourceWait(
        reading.usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET({
          skipBehaviors: true,
        }),
        resourceSignal(deadline, COLLECTOR_BOUNDS.requestMs),
      );

      result = normalizeClaude(usage);
    } catch (error) {
      result = {
        agent: 'claude',
        unavailable:
          deadline.aborted ||
          (error instanceof DOMException && error.name === 'TimeoutError')
            ? 'The isolated usage read exceeded its deadline.'
            : 'The experimental usage getter is unavailable or unsupported.',
      };
    } finally {
      input.resolve();
      controller.abort();

      try {
        reading?.close();
      } catch {
        result = {
          agent: 'claude',
          unavailable: 'The experimental usage query could not close cleanly.',
        };
      }
    }
  }

  const serialized = JSON.stringify(ProviderLimits.parse(result));

  await new Promise<void>((resolve) =>
    process.stdout.write(serialized, () => resolve()),
  );

  // The supervisor verifies the entire group, including the SDK's native child.
  process.exit(0);
}
