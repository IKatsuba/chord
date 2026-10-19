import { expect, test } from 'bun:test';
import process from 'node:process';
import { steeredInto, steers } from './sessions.ts';

test('a wait for a steered message settles on one, and stops listening (CHD-470)', async () => {
  const waiting = steeredInto('s1', new AbortController().signal);

  steers.emit('s1');
  await waiting.steered;
  waiting.stop();
  expect(steers.listenerCount('s1')).toBe(0);
});

test('a wait the turn ends before awaiting stops listening and raises nothing unhandled (CHD-470)', async () => {
  const unhandled: unknown[] = [];
  const heard = (reason: unknown) => unhandled.push(reason);

  process.on('unhandledRejection', heard);

  try {
    // Cancelled while it set up, never awaited.
    const turn = new AbortController();
    const cancelled = steeredInto('s2', turn.signal);

    turn.abort();
    cancelled.stop();

    // Its setup threw: stopped, never awaited.
    steeredInto('s3', new AbortController().signal).stop();

    await new Promise((resolve) => setTimeout(resolve, 20));

    expect(unhandled).toStrictEqual([]);
    expect(steers.listenerCount('s2') + steers.listenerCount('s3')).toBe(0);
    await expect(cancelled.steered).rejects.toThrow();
  } finally {
    process.off('unhandledRejection', heard);
  }
});
