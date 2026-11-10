import { afterEach, describe, expect, jest, test } from 'bun:test';
import { reviewedPermission } from '../../../src/riff/review/permission.ts';
import type { ToolSession } from '../../../src/riff/tools/tools.ts';
import type { Finder } from '../../../src/platform/fff.ts';

afterEach(() => jest.useRealTimers());

const call = { toolCallId: 'held', title: 'Shell pwd' };
const caution = {
  outcome: 'caution',
  rationale: 'Destructive action.',
} as const;
const fixture = (ask: ToolSession['ask']): ToolSession => ({
  directory: '/project',
  finder: {} as Finder,
  ...(ask === undefined ? {} : { ask }),
});

test('review holds offer only allow once/deny with generic rationale and authoritative deadline', async () => {
  const before = Date.now();

  await reviewedPermission(
    fixture((_call, options, _signal, meta) => {
      const deadline = (meta?.['chord/permission'] as { deadlineAt: number })
        .deadlineAt;

      expect(deadline).toBeGreaterThanOrEqual(before + 300_000);
      expect(options.map(({ kind }) => kind)).toEqual([
        'allow_once',
        'reject_once',
      ]);
      expect(meta).toMatchObject({
        'chord/permission': {
          review: { outcome: 'caution', reason: 'Destructive action.' },
          deadlineAt: expect.any(Number),
        },
      });

      return Promise.resolve('allow');
    }),
    call,
    caution,
    new AbortController().signal,
  );
});

test('five-minute deadline withdraws the ask and denies even a late allow', async () => {
  jest.useFakeTimers();

  const waiting = Promise.withResolvers<AbortSignal>();
  const result = reviewedPermission(
    fixture((_call, _options, signal) => {
      waiting.resolve(signal);

      return new Promise((resolve) =>
        signal.addEventListener('abort', () => resolve('allow'), {
          once: true,
        }),
      );
    }),
    call,
    caution,
    new AbortController().signal,
  ).catch((error: unknown) => error);
  const signal = await waiting.promise;

  jest.advanceTimersByTime(300_000);

  expect(signal.aborted).toBe(true);
  expect(await result).toMatchObject({
    message: expect.stringContaining('Denied: no answer within 5 minutes.'),
  });
});

test('session-grant answers cannot authorize a review hold; absent answers explain the held action', async () => {
  for (const answer of ['allow_session', undefined]) {
    await expect(
      reviewedPermission(
        fixture(() => Promise.resolve(answer)),
        call,
        {
          outcome: 'unavailable',
          reason: 'fixture unavailable',
        },
        new AbortController().signal,
      ),
    ).rejects.toThrow('Safety reviewer unavailable; action held');
  }
});

describe('CHD-608 tester: review ask deadlines', () => {
  test('allow once immediately before the deadline succeeds without a remaining timer', async () => {
    jest.useFakeTimers();

    const answer = Promise.withResolvers<string>();
    let active: AbortSignal | undefined;
    const result = reviewedPermission(
      fixture((_call, _options, signal) => {
        active = signal;

        return answer.promise;
      }),
      call,
      caution,
      new AbortController().signal,
    );

    jest.advanceTimersByTime(299_999);
    answer.resolve('allow');
    await result;
    jest.advanceTimersByTime(1);

    expect(active?.aborted).toBe(false);
  });

  test('cancelling a turn withdraws its ask and rejects even a returned allow', async () => {
    const controller = new AbortController();
    let active: AbortSignal | undefined;
    const result = reviewedPermission(
      fixture((_call, _options, signal) => {
        active = signal;

        return new Promise((resolve) => {
          signal.addEventListener('abort', () => resolve('allow'), {
            once: true,
          });
        });
      }),
      call,
      caution,
      controller.signal,
    );

    controller.abort(new Error('fixture turn cancelled'));

    await expect(result).rejects.toThrow('fixture turn cancelled');
    expect(active?.aborted).toBe(true);
  });
});
