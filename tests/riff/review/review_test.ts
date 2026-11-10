import { afterEach, expect, jest, test } from 'bun:test';
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

      return new Promise(() => {});
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
