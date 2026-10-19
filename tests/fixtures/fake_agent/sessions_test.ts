import { describe, expect, test } from 'bun:test';
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

describe('CHD-470 tester: steering waiter isolation and cancellation', () => {
  test('an already cancelled turn installs no steering or error listener', async () => {
    const errors = steers.listenerCount('error');
    const turn = new AbortController();

    turn.abort();

    const waiting = steeredInto('tester-pre-cancelled', turn.signal);

    try {
      await expect(waiting.steered).rejects.toThrow();
      expect(steers.listenerCount('tester-pre-cancelled')).toBe(0);
      expect(steers.listenerCount('error')).toBe(errors);
    } finally {
      waiting.stop();
    }
  });

  test('steering one session leaves another pending until that turn is cancelled', async () => {
    const errors = steers.listenerCount('error');
    const first = steeredInto('tester-first', new AbortController().signal);
    const turn = new AbortController();
    const second = steeredInto('tester-second', turn.signal);
    let settled = false;

    void second.steered.then(
      () => {
        settled = true;
      },
      () => {
        settled = true;
      },
    );

    try {
      steers.emit('tester-first');
      await first.steered;
      await Promise.resolve();
      expect(settled).toBe(false);
      expect(steers.listenerCount('tester-second')).toBe(1);
      turn.abort();
      await expect(second.steered).rejects.toThrow();
      expect(steers.listenerCount('tester-first')).toBe(0);
      expect(steers.listenerCount('tester-second')).toBe(0);
      expect(steers.listenerCount('error')).toBe(errors);
    } finally {
      first.stop();
      second.stop();
    }
  });

  test('repeated cleanup of an abandoned setup does not detach a new waiter for the same session', async () => {
    const errors = steers.listenerCount('error');
    const old = steeredInto('tester-reused', new AbortController().signal);
    const current = steeredInto('tester-reused', new AbortController().signal);

    try {
      old.stop();
      old.stop();
      await expect(old.steered).rejects.toThrow();
      expect(steers.listenerCount('tester-reused')).toBe(1);
      steers.emit('tester-reused');
      await current.steered;
      expect(steers.listenerCount('tester-reused')).toBe(0);
      expect(steers.listenerCount('error')).toBe(errors);
    } finally {
      old.stop();
      current.stop();
    }
  });
});
