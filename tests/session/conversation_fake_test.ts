import { expect, test } from 'bun:test';
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
