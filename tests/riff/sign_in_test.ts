import { describe, expect, test } from 'bun:test';
import {
  failureChoices,
  initialSignIn,
  signInChoices,
  signInMinutes,
  signInReduce,
  type SignInState,
} from '../../src/riff/sign_in.ts';

const attempt = (way: 'browser' | 'code' = 'browser') =>
  signInReduce(
    signInReduce(initialSignIn(), { type: 'provider', provider: 'codex' }),
    { type: 'way', way },
  );

describe('riff sign-in state machine', () => {
  test('provider, way, browser, finishing, saved success', () => {
    let state = attempt();
    const id = state.attempt;

    for (const step of [
      { kind: 'browser', address: 'https://example.invalid/sign-in' },
      { kind: 'finishing' },
      { kind: 'saving' },
      { kind: 'success', store: 'fixture store' },
    ] as const) {
      state = signInReduce(state, {
        type: 'progress',
        attempt: id,
        step: { ...step, provider: 'codex', way: 'browser' },
      });

      expect(state.step.kind).toBe(step.kind);
    }
  });

  test('cancelled and superseded attempts drop late progress', () => {
    const first = attempt();
    const cancelled = signInReduce(first, { type: 'back' });
    const late = {
      type: 'progress',
      attempt: first.attempt,
      step: {
        kind: 'success',
        provider: 'codex',
        way: 'browser',
        store: 'fixture store',
      },
    } as const;

    expect(signInReduce(cancelled, late)).toBe(cancelled);

    const second = signInReduce(
      signInReduce(signInReduce(cancelled, { type: 'open' }), {
        type: 'provider',
        provider: 'grok',
      }),
      { type: 'way', way: 'code' },
    );

    expect(signInReduce(second, late)).toBe(second);
    expect(signInReduce(second, { ...late, attempt: second.attempt })).toBe(
      second,
    );
  });

  test('a stale browser state leaves the wait untouched', () => {
    const starting = attempt();
    const waiting = signInReduce(starting, {
      type: 'progress',
      attempt: starting.attempt,
      step: {
        kind: 'browser',
        provider: 'codex',
        way: 'browser',
        address: 'https://example.invalid',
      },
    });

    expect(
      signInReduce(waiting, {
        type: 'progress',
        attempt: waiting.attempt,
        step: {
          kind: 'failure',
          provider: 'codex',
          way: 'browser',
          code: 'LIBFX_CHATGPT_SIGN_IN_STATE_MISMATCH',
          message: 'fixture',
        },
      }),
    ).toBe(waiting);
  });

  test.each([
    ['SIGN_IN_EXPIRED', ['retry', 'code', 'another_plan']],
    ['DEVICE_CODE_EXPIRED', ['new_code']],
    ['DEVICE_CODE_UNAVAILABLE', ['retry', 'browser', 'another_plan']],
    ['SIGN_IN_DENIED', ['retry', 'another_plan']],
    ['SIGN_IN_INVALID_ADDRESS', ['retry']],
    ['SIGN_IN_FAILED', ['retry', 'browser', 'another_plan']],
  ] as const)('F table: %s', (suffix, choices) => {
    for (const prefix of ['LIBFX_CHATGPT_', 'LIBFX_GROK_']) {
      expect(failureChoices(`${prefix}${suffix}`, 'code')).toEqual(choices);
    }
  });

  test('Grok account unavailable and unknown errors follow F, not the message', () => {
    expect(failureChoices('LIBFX_GROK_ACCOUNT_UNAVAILABLE', 'browser')).toEqual(
      ['retry', 'another_plan'],
    );

    const state = attempt();
    const failed = signInReduce(state, {
      type: 'progress',
      attempt: state.attempt,
      step: {
        kind: 'failure',
        provider: 'codex',
        way: 'browser',
        code: 'unknown',
        message: 'DEVICE_CODE_EXPIRED',
      },
    });

    expect(signInChoices(failed.step)).toEqual([
      'retry',
      'code',
      'another_plan',
    ]);
  });

  test('port taken offers code and a fresh browser attempt; Esc returns to way', () => {
    const state = attempt();
    const taken = signInReduce(state, {
      type: 'progress',
      attempt: state.attempt,
      step: { kind: 'port_taken', provider: 'codex', way: 'browser' },
    });

    expect(signInChoices(taken.step)).toEqual(['code', 'browser']);
    expect(signInReduce(taken, { type: 'back' }).step).toEqual({
      kind: 'way',
      provider: 'codex',
    });

    const code = signInReduce(taken, { type: 'choose', choice: 'code' });

    expect(code.attempt).toBeGreaterThan(taken.attempt);
    expect(code.step).toEqual({
      kind: 'starting',
      provider: 'codex',
      way: 'code',
    });
  });

  test.each(['no_store', 'store_slow'] as const)(
    'G: %s retries only the store, with a fresh id',
    (kind) => {
      const reading = signInReduce(initialSignIn(), {
        type: 'read_store',
        provider: 'grok',
        store: 'fixture store',
      });
      const failed = signInReduce(reading, {
        type: 'progress',
        attempt: reading.attempt,
        step: {
          kind,
          provider: 'grok',
          store: 'fixture store',
          message: 'fixture store failed',
        },
      });

      expect(signInChoices(failed.step)).toEqual(['retry_store']);

      const retry = signInReduce(failed, {
        type: 'choose',
        choice: 'retry_store',
      });

      expect(retry.attempt).toBeGreaterThan(failed.attempt);
      expect(retry.step.kind).toBe('reading_store');
      expect(signInReduce(failed, { type: 'choose', choice: 'code' })).toBe(
        failed,
      );
    },
  );

  test('expiry offers a new code; countdown uses whole remaining minutes', () => {
    const state: SignInState = {
      attempt: 2,
      step: {
        kind: 'expired',
        provider: 'grok',
        way: 'code',
        message: 'fixture expired',
      },
    };

    expect(signInChoices(state.step)).toEqual(['new_code']);
    expect(
      signInReduce(state, { type: 'choose', choice: 'new_code' }).step,
    ).toEqual({ kind: 'starting', provider: 'grok', way: 'code' });
    expect(signInMinutes(60_001, 0)).toBe(2);
    expect(signInMinutes(60_000, 0)).toBe(1);
    expect(signInMinutes(0, 1)).toBe(0);
  });

  test('store retry before provider selection preserves its explanation and returns to A', () => {
    const reading = signInReduce(initialSignIn(), {
      type: 'read_store',
      provider: undefined,
      store: 'fixture store',
    });
    const failed = signInReduce(reading, {
      type: 'progress',
      attempt: reading.attempt,
      step: {
        kind: 'no_store',
        provider: undefined,
        store: 'fixture store',
        message: 'fixture recovery',
      },
    });
    const retry = signInReduce(failed, {
      type: 'choose',
      choice: 'retry_store',
    });

    expect(retry.step).toEqual({
      kind: 'reading_store',
      provider: undefined,
      store: 'fixture store',
      message: 'fixture recovery',
    });
    expect(
      signInReduce(retry, { type: 'store_ready', attempt: reading.attempt }),
    ).toBe(retry);
    expect(
      signInReduce(retry, { type: 'store_ready', attempt: retry.attempt }).step,
    ).toEqual({ kind: 'provider' });
    expect(
      failureChoices('LIBFX_CHATGPT_SIGN_IN_STATE_MISMATCH', 'browser'),
    ).toEqual([]);
  });
});
