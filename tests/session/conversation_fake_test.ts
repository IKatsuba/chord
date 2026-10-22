import { describe, expect, setSystemTime, test } from 'bun:test';
import { until } from './conversation_fake.ts';

test('a wait that never ends gives up at its timeout on the monotonic clock, naming its check (CHD-501)', async () => {
  const started = performance.now();
  const reached: boolean[] = [];

  await expect(until(() => reached.length > 0, 100)).rejects.toThrow(
    /^timed out waiting for .*reached\.length > 0/,
  );
  expect(performance.now() - started).toBeLessThan(2_000);
});

test('a wait that ends goes on at once', async () => {
  let ready = false;

  setTimeout(() => {
    ready = true;
  }, 10);

  await until(() => ready);

  expect(ready).toBe(true);
});

describe('CHD-501 tester: bounded conversation waits ignore wall-clock changes', () => {
  test('both an old and a future frozen Date leave the real deadline running', async () => {
    const reached: boolean[] = [];

    try {
      for (const epoch of [0, 2_000_000_000_000]) {
        setSystemTime(new Date(epoch));

        const started = performance.now();

        await expect(until(() => reached.length > 0, 40)).rejects.toThrow(
          'timed out waiting for',
        );
        expect(performance.now() - started).toBeGreaterThanOrEqual(40);
        expect(performance.now() - started).toBeLessThan(2000);
      }
    } finally {
      setSystemTime();
    }
  });

  test('an assertion thrown by the check is returned unchanged, not turned into a timeout', async () => {
    const failure = new Error('check assertion failed');
    let calls = 0;

    await expect(
      until(() => {
        calls++;

        if (calls === 3) {
          throw failure;
        }

        return false;
      }, 1000),
    ).rejects.toBe(failure);
    expect(calls).toBe(3);
  });
});
