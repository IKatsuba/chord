/** Approved collector ownership: unchanged libraries, bounded waits and group signals. */
import { performance } from 'node:perf_hooks';
import { RpcRequestTimeoutError } from 'codex-app-server-client';
import { setTimeout as delay } from 'node:timers/promises';
import { settledWithin } from '../acp/process.ts';
import { type GroupProcess, spawnGroup } from './process.ts';

export class ResourceReadError extends Error {
  constructor(
    readonly kind:
      | 'timeout'
      | 'cancelled'
      | 'startup'
      | 'authentication'
      | 'rate-limit'
      | 'protocol'
      | 'cleanup',
    message: string,
  ) {
    super(message);
  }
}

export interface CollectorBounds {
  readonly totalMs: number;
  readonly initializeMs: number;
  readonly requestMs: number;
  readonly closeMs: number;
  readonly termMs: number;
  readonly killMs: number;
}

export const COLLECTOR_BOUNDS: CollectorBounds = {
  totalMs: 20_000,
  initializeMs: 8000,
  requestMs: 3000,
  closeMs: 500,
  termMs: 500,
  killMs: 500,
};

/** Rejects the wait; its owner still closes the library and verifies the group. */
export function resourceWait<T>(
  promise: Promise<T>,
  signal: AbortSignal,
): Promise<T> {
  if (signal.aborted) {
    promise.catch(() => {});

    return Promise.reject(signal.reason);
  }

  return new Promise<T>((resolve, reject) => {
    const aborted = () => reject(signal.reason);

    signal.addEventListener('abort', aborted, { once: true });
    promise
      .then(resolve, reject)
      .finally(() => signal.removeEventListener('abort', aborted));
  });
}

export function resourceSignal(
  signal: AbortSignal,
  milliseconds: number,
): AbortSignal {
  return AbortSignal.any([signal, AbortSignal.timeout(milliseconds)]);
}

async function groupGone(
  group: GroupProcess,
  milliseconds: number,
): Promise<boolean> {
  const until = performance.now() + milliseconds;

  while (group.alive() && performance.now() < until) {
    await delay(Math.min(10, Math.max(1, until - performance.now())));
  }

  return !group.alive();
}

async function closeResourceGroup(
  group: GroupProcess,
  close: () => Promise<void>,
  bounds: CollectorBounds,
): Promise<void> {
  await settledWithin(
    Promise.all([
      Promise.resolve()
        .then(close)
        .catch(() => {}),
      new Promise<void>((resolve) => {
        if (group.child.stdin === null || group.child.stdin.destroyed) {
          resolve();
        } else {
          group.child.stdin.end(resolve);
        }
      }),
      groupGone(group, bounds.closeMs),
    ]),
    bounds.closeMs,
  );

  if (!(await groupGone(group, 0))) {
    group.signal('SIGTERM');

    if (!(await groupGone(group, bounds.termMs))) {
      group.signal('SIGKILL');

      await groupGone(group, bounds.killMs);
    }
  }

  const exited = await settledWithin(group.exit, 0);

  group.child.stdin?.destroy();
  group.child.stdout?.destroy();

  if (group.alive() || exited === undefined) {
    throw new ResourceReadError(
      'cleanup',
      'Collector cleanup could not verify process-group exit.',
    );
  }
}

/** No request rejection, direct-child exit or library close alone proves cleanup. */
export async function withResourceProcess<T>(
  command: readonly [string, ...string[]],
  options: {
    readonly cwd: string;
    readonly signal: AbortSignal;
    readonly bounds?: CollectorBounds;
  },
  read: (
    group: GroupProcess,
    signal: AbortSignal,
    onClose: (close: () => Promise<void>) => void,
  ) => Promise<T>,
): Promise<T> {
  const bounds = options.bounds ?? COLLECTOR_BOUNDS;
  const deadline = AbortSignal.timeout(bounds.totalMs);
  const signal = AbortSignal.any([options.signal, deadline]);

  if (signal.aborted) {
    throw new ResourceReadError(
      'cancelled',
      'Resource read cancelled before startup.',
    );
  }

  const group = spawnGroup(command[0], command.slice(1), {
    cwd: options.cwd,
    stdin: 'pipe',
    stdout: 'pipe',
    stderr: 'ignore',
  });
  let close = () => Promise.resolve();
  let result: T;

  try {
    try {
      await resourceWait(group.started, signal);
    } catch (error) {
      if (signal.aborted) {
        throw error;
      }

      throw new ResourceReadError(
        'startup',
        'The collector process failed to start.',
      );
    }

    result = await resourceWait(
      read(group, signal, (callback) => {
        close = callback;
      }),
      signal,
    );
  } catch (error) {
    if (error instanceof ResourceReadError) {
      throw error;
    }

    let cause = error;
    const seen = new Set<unknown>();
    let timedOut = deadline.aborted;

    while (cause instanceof Error && !seen.has(cause)) {
      seen.add(cause);

      timedOut ||=
        cause instanceof RpcRequestTimeoutError ||
        (cause instanceof DOMException && cause.name === 'TimeoutError');
      cause = cause.cause;
    }

    if (timedOut) {
      throw new ResourceReadError(
        'timeout',
        'Resource acquisition exceeded its deadline.',
      );
    }

    if (options.signal.aborted) {
      throw new ResourceReadError('cancelled', 'Resource read cancelled.');
    }

    const status =
      typeof error === 'object' && error !== null
        ? 'status' in error
          ? error.status
          : 'code' in error
            ? error.code
            : undefined
        : undefined;

    throw status === 401 || status === 403
      ? new ResourceReadError(
          'authentication',
          'The provider refused the existing authentication.',
        )
      : status === 429
        ? new ResourceReadError(
            'rate-limit',
            'The provider rate-limited the resource read.',
          )
        : new ResourceReadError(
            'protocol',
            'The collector failed to return supported resource facts.',
          );
  } finally {
    await closeResourceGroup(group, close, bounds);
  }

  if (options.signal.aborted) {
    throw new ResourceReadError('cancelled', 'Resource read cancelled.');
  }

  if (deadline.aborted) {
    throw new ResourceReadError(
      'timeout',
      'Resource acquisition exceeded its deadline.',
    );
  }

  return result;
}
