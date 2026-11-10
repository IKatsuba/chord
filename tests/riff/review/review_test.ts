import { afterEach, describe, expect, jest, test } from 'bun:test';
import { review } from '../../../src/riff/review/review.ts';

afterEach(() => jest.useRealTimers());

test('clear and caution are final and never retried', async () => {
  for (const decision of [
    { outcome: 'clear' },
    { outcome: 'caution', rationale: 'danger' },
  ] as const) {
    let attempts = 0;
    const result = await review(
      () => {
        attempts++;

        return Promise.resolve(decision);
      },
      'input',
      new AbortController().signal,
    );

    expect(result).toEqual(decision);
    expect(attempts).toBe(1);
  }
});

test('malformed gets one format retry, then unavailable', async () => {
  for (const valid of [true, false]) {
    let attempts = 0;
    const result = await review(
      () => {
        attempts++;

        return Promise.resolve(
          valid && attempts === 2 ? { outcome: 'clear' as const } : undefined,
        );
      },
      'input',
      new AbortController().signal,
    );

    expect(attempts).toBe(2);
    expect(result.outcome).toBe(valid ? 'clear' : 'unavailable');
  }
});

test('a thrown failure gets one retry, then unavailable', async () => {
  let attempts = 0;
  const result = await review(
    () => {
      attempts++;

      throw new Error('fixture failure');
    },
    'input',
    new AbortController().signal,
  );

  expect(attempts).toBe(2);
  expect(result).toEqual({ outcome: 'unavailable', reason: 'fixture failure' });
});

test('two 30-second timeouts abort each attempt and return unavailable', async () => {
  jest.useFakeTimers();

  const signals: AbortSignal[] = [];
  const retried = Promise.withResolvers<void>();
  const result = review(
    (_input, signal) => {
      signals.push(signal);

      if (signals.length === 2) {
        retried.resolve();
      }

      return new Promise((_resolve, reject) => {
        signal.addEventListener('abort', () => reject(signal.reason), {
          once: true,
        });
      });
    },
    'input',
    new AbortController().signal,
  );

  jest.advanceTimersByTime(30_000);

  await retried.promise;

  expect(signals.length).toBe(2);
  expect(signals[0]?.aborted).toBe(true);

  jest.advanceTimersByTime(30_000);

  expect(await result).toEqual({
    outcome: 'unavailable',
    reason: 'The safety review timed out.',
  });
  expect(signals[1]?.aborted).toBe(true);
});

test('a timed-out attempt retains ownership through teardown before retry', async () => {
  jest.useFakeTimers();

  const teardown = Promise.withResolvers<void>();
  const aborted = Promise.withResolvers<void>();
  let attempts = 0;
  let complete = false;
  const result = review(
    async (_input, signal) => {
      attempts++;

      if (attempts === 1) {
        await new Promise<void>((resolve) => {
          signal.addEventListener(
            'abort',
            () => {
              aborted.resolve();
              resolve();
            },
            { once: true },
          );
        });

        await teardown.promise;

        throw signal.reason;
      }

      return { outcome: 'clear' };
    },
    'input',
    new AbortController().signal,
  ).then((outcome) => {
    complete = true;

    return outcome;
  });

  jest.advanceTimersByTime(30_000);

  await aborted.promise;

  expect(attempts).toBe(1);
  expect(complete).toBe(false);
  teardown.resolve();

  expect(await result).toEqual({ outcome: 'clear' });
  expect(attempts).toBe(2);
});

test('cancellation interrupts the review without retrying or yielding a verdict', async () => {
  const controller = new AbortController();
  let attempts = 0;
  const result = review(
    () => {
      attempts++;
      controller.abort(new Error('cancelled by fixture'));

      return Promise.resolve({ outcome: 'clear' as const });
    },
    'input',
    controller.signal,
  );

  await expect(result).rejects.toThrow('cancelled by fixture');
  expect(attempts).toBe(1);
});

describe('CHD-608 tester: review retry authority', () => {
  test('a pre-cancelled turn starts no attempt', async () => {
    const controller = new AbortController();
    let attempts = 0;

    controller.abort(new Error('already cancelled'));

    await expect(
      review(
        () => {
          attempts++;

          return Promise.resolve({ outcome: 'clear' });
        },
        'pending',
        controller.signal,
      ),
    ).rejects.toThrow('already cancelled');
    expect(attempts).toBe(0);
  });

  test('format and transport retry allowances remain separate and caution ends retries', async () => {
    for (const malformedFirst of [true, false]) {
      let attempts = 0;
      const outcome = await review(
        () => {
          attempts++;

          if (attempts === (malformedFirst ? 1 : 2)) {
            return Promise.resolve(undefined);
          }

          if (attempts < 3) {
            throw new Error('fixture transport');
          }

          return Promise.resolve({ outcome: 'caution', rationale: 'held' });
        },
        'pending',
        new AbortController().signal,
      );

      expect(outcome).toEqual({ outcome: 'caution', rationale: 'held' });
      expect(attempts).toBe(3);
    }
  });

  test('a clear decision returned after each deadline cannot authorize a call', async () => {
    jest.useFakeTimers();

    const retried = Promise.withResolvers<void>();
    let attempts = 0;
    const outcome = review(
      (_input, signal) => {
        attempts++;

        if (attempts === 2) {
          retried.resolve();
        }

        return new Promise((resolve) => {
          signal.addEventListener(
            'abort',
            () => resolve({ outcome: 'clear' }),
            {
              once: true,
            },
          );
        });
      },
      'pending',
      new AbortController().signal,
    );

    jest.advanceTimersByTime(30_000);
    await retried.promise;
    jest.advanceTimersByTime(30_000);

    expect((await outcome).outcome).toBe('unavailable');
    expect(attempts).toBe(2);
  });
});
