import { expect, setSystemTime, test } from 'bun:test';
import { until } from './render.tsx';

test('a wait under a system time a test set still gives up at its timeout (CHD-501)', async () => {
  // Set, the system time stands still: a deadline on it would never come.
  setSystemTime(new Date('2026-10-22T12:00:00Z'));

  const started = performance.now();

  try {
    await expect(until('what never comes', () => false, 100)).rejects.toThrow(
      'timed out waiting for what never comes',
    );
  } finally {
    setSystemTime();
  }

  expect(performance.now() - started).toBeLessThan(2_000);
});
