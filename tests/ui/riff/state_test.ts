import { describe, expect, test } from 'bun:test';
import { initialRiff, reduceRiff } from '../../../src/ui/riff/state.ts';

describe('riff window state', () => {
  test('closing and reopening never reuses an attempt id', () => {
    const first = reduceRiff(initialRiff(), { type: 'open', now: 0 });
    const closed = reduceRiff(first, { type: 'close' });
    const next = reduceRiff(closed, { type: 'open', now: 1 });

    expect(next.flow?.attempt).toBeGreaterThan(first.flow?.attempt ?? 0);
  });

  test('closing a pending logout retains the signed-out fact', () => {
    const state = reduceRiff(
      reduceRiff(
        reduceRiff(initialRiff(), { type: 'logout', provider: 'grok' }),
        { type: 'signed_out' },
      ),
      { type: 'close' },
    );

    expect(state.signedOut).toBe(true);
    expect(state.logout).toBeUndefined();
  });
});
