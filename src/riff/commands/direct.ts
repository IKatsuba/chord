/**
 * Adapted from vercel-labs/fx v0.0.16,
 * src/core/permissions/direct_command.zig, Apache-2.0.
 * chord uses node streams and spawnGroup, and streams through its terminal.
 * Node cannot join a process group: stages lead separate groups, all stopped
 * together, including descendants, on cancellation, failure or the output cap.
 */
import { Buffer } from 'node:buffer';
import { Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { StringDecoder } from 'node:string_decoder';
import { spawnGroup, type GroupProcess } from '../../platform/process.ts';
import type { ShellEnd, ShellOptions, ShellProcess } from '../../shell.ts';

export const DIRECT_OUTPUT_BYTES = 65_536;
export const DIRECT_ENVIRONMENT = Object.freeze({
  PATH: '/usr/bin:/bin',
  LC_ALL: 'C',
  LANG: 'C',
});

/** A fixed argv from the planner, with git already prepared by safe_git. */
export interface DirectInvocation {
  executable: string;
  argv: readonly string[];
  environment?: Readonly<Record<string, string>>;
}

/** Owns every stage until output is drained and its leader has exited. */
export function runDirect(
  stages: readonly DirectInvocation[],
  options: Pick<ShellOptions, 'cwd' | 'onOutput' | 'reap'>,
): ShellProcess {
  const groups: GroupProcess[] = [];
  let stopping = false;
  let finished = false;
  let killedAt: number | undefined;
  let failure: string | undefined;
  let cleanupTimedOut = false;
  let admitted = 0;
  let escalation: ReturnType<typeof setTimeout> | undefined;
  const terminate = () => {
    if (stopping || finished) {
      return;
    }

    stopping = true;

    for (const group of groups) {
      group.signal('SIGTERM');
    }

    escalation = setTimeout(() => {
      killedAt = performance.now();

      for (const group of groups) {
        group.signal('SIGKILL');
      }
    }, 800);
  };

  const fail = (message: string) => {
    failure ??= message;

    terminate();
  };

  const budget = (chunk: Buffer): boolean => {
    if (stopping) {
      return false;
    }

    if (chunk.length > DIRECT_OUTPUT_BYTES - admitted) {
      fail('Direct command output exceeded 64 KiB');

      return false;
    }

    admitted += chunk.length;

    return true;
  };

  const collect = async (group: GroupProcess, stream: 'stdout' | 'stderr') => {
    const decoder = new StringDecoder('utf8');
    const source = group.child[stream]!;

    for await (const chunk of source) {
      if (budget(chunk as Buffer)) {
        const text = decoder.write(chunk as Buffer);

        if (text) {
          options.onOutput?.(stream, text);
        }
      }
    }

    const tail = decoder.end();

    if (tail) {
      options.onOutput?.(stream, tail);
    }
  };

  const ended = (async (): Promise<ShellEnd> => {
    if (stages.length === 0 || stages.length > 8) {
      finished = true;

      return { error: 'Invalid direct plan' };
    }

    try {
      for (const stage of stages) {
        const group = spawnGroup(stage.executable, stage.argv.slice(1), {
          cwd: options.cwd,
          env: stage.environment ?? DIRECT_ENVIRONMENT,
          inheritEnv: false,
          stdin: groups.length === 0 ? 'ignore' : 'pipe',
          stdout: 'pipe',
          stderr: 'pipe',
        });

        groups.push(group);
        await group.started;

        if (stopping) {
          break;
        }
      }

      const workers: Promise<unknown>[] = [];

      for (const [index, group] of groups.entries()) {
        workers.push(collect(group, 'stderr'));

        const next = groups[index + 1];

        if (next) {
          const charge = new Transform({
            transform(chunk: Buffer, _encoding, callback) {
              callback(null, budget(chunk) ? chunk : undefined);
            },
          });

          workers.push(
            pipeline(group.child.stdout!, charge, next.child.stdin!).catch(
              (error: unknown) => {
                // A downstream filter may close its input early (head, grep).
                if (
                  (error as NodeJS.ErrnoException).code !== 'EPIPE' &&
                  (error as NodeJS.ErrnoException).code !==
                    'ERR_STREAM_PREMATURE_CLOSE'
                ) {
                  throw error;
                }
              },
            ),
          );
        } else {
          workers.push(collect(group, 'stdout'));
        }
      }

      // Observe worker failures immediately so an unread pipe cannot wedge a child.
      await Promise.all(
        workers.map((worker) =>
          worker.catch((error: unknown) => {
            fail(
              error instanceof Error ? error.message : 'Direct output failed',
            );
          }),
        ),
      );

      const exits = await Promise.all(groups.map((group) => group.exit));

      return failure !== undefined
        ? { error: failure }
        : stopping
          ? { stopped: true }
          : exits.at(-1)!;
    } catch (error) {
      fail(error instanceof Error ? error.message : 'Direct command failed');

      return { error: failure! };
    } finally {
      // A successful capture must also stop children detached from its pipes.
      if (options.reap && groups.some((group) => group.alive())) {
        terminate();
      }

      if (stopping) {
        // Same bounded group-reaping contract as chord's shell runner; count
        // from the actual KILL so event-loop load cannot shorten the grace.
        while (
          groups.some((group) => group.alive()) &&
          (killedAt === undefined || performance.now() < killedAt + 5000)
        ) {
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      }

      await Promise.allSettled(groups.map((group) => group.exit));

      if (escalation !== undefined) {
        clearTimeout(escalation);
      }

      finished = true;

      cleanupTimedOut = stopping && groups.some((group) => group.alive());
    }
  })().then((end) =>
    cleanupTimedOut ? { error: 'Direct process group cleanup timed out' } : end,
  );

  return { stop: terminate, ended };
}
