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

describe('tester: sign-in reducer boundaries', () => {
  test('Esc fences late progress at every stage', () => {
    const steps: SignInState['step'][] = [
      { kind: 'provider' },
      { kind: 'way', provider: 'codex' },
      ...(['starting', 'finishing', 'saving'] as const).map((kind) => ({
        kind,
        provider: 'codex' as const,
        way: 'browser' as const,
      })),
      {
        kind: 'browser',
        provider: 'codex',
        way: 'browser',
        address: 'https://example.invalid',
      },
      {
        kind: 'code',
        provider: 'grok',
        way: 'code',
        address: 'https://example.invalid',
        code: 'FIXTURE',
        expiresAt: 60_000,
      },
      { kind: 'port_taken', provider: 'codex', way: 'browser' },
      { kind: 'expired', provider: 'grok', way: 'code', message: 'expired' },
      {
        kind: 'failure',
        provider: 'codex',
        way: 'browser',
        code: 'unknown',
        message: 'fixture',
      },
      ...(['reading_store', 'no_store', 'store_slow'] as const).map((kind) => ({
        kind,
        provider: undefined,
        store: 'fixture store',
        message: 'fixture recovery',
      })),
    ];

    for (const step of steps) {
      const state = { attempt: 10, step };
      const backed = signInReduce(state, { type: 'back' });
      const expected: SignInState['step'] =
        step.kind === 'way'
          ? { kind: 'provider' }
          : step.kind === 'expired' || step.kind === 'port_taken'
            ? { kind: 'way', provider: step.provider }
            : { kind: 'cancelled' };

      expect(backed.step).toEqual(expected);
      expect(backed.attempt).toBe(11);

      for (const id of [state.attempt, backed.attempt]) {
        expect(
          signInReduce(backed, {
            type: 'progress',
            attempt: id,
            step: {
              kind: 'success',
              provider: 'codex',
              way: 'browser',
              store: 'fixture store',
            },
          }),
        ).toBe(backed);
        expect(signInReduce(backed, { type: 'store_ready', attempt: id })).toBe(
          backed,
        );
      }
    }
  });

  test('same-provider retries reject the previous attempt and invalid choices', () => {
    const first = attempt();
    const failed = signInReduce(first, {
      type: 'progress',
      attempt: first.attempt,
      step: {
        kind: 'failure',
        provider: 'codex',
        way: 'browser',
        code: 'LIBFX_CHATGPT_SIGN_IN_DENIED',
        message: 'DEVICE_CODE_EXPIRED',
      },
    });

    expect(signInChoices(failed.step)).toEqual(['retry', 'another_plan']);
    expect(signInReduce(failed, { type: 'choose', choice: 'new_code' })).toBe(
      failed,
    );

    const retry = signInReduce(failed, { type: 'choose', choice: 'retry' });

    expect(retry.attempt).toBe(first.attempt + 1);
    expect(retry.step).toEqual({
      kind: 'starting',
      provider: 'codex',
      way: 'browser',
    });
    expect(
      signInReduce(retry, {
        type: 'progress',
        attempt: first.attempt,
        step: {
          kind: 'success',
          provider: 'codex',
          way: 'browser',
          store: 'fixture store',
        },
      }),
    ).toBe(retry);
    expect(signInReduce(retry, { type: 'provider', provider: 'grok' })).toBe(
      retry,
    );
    expect(signInReduce(retry, { type: 'way', way: 'code' })).toBe(retry);
  });

  test('store retries preserve cause and provider while rejecting stale readiness', () => {
    for (const provider of [undefined, 'codex', 'grok'] as const) {
      for (const kind of ['no_store', 'store_slow'] as const) {
        const state: SignInState = {
          attempt: 9,
          step: {
            kind,
            provider,
            store: 'fixture store',
            message: 'fixture recovery',
          },
        };
        const retry = signInReduce(state, {
          type: 'choose',
          choice: 'retry_store',
        });

        expect(retry.step).toEqual({
          kind: 'reading_store',
          provider,
          store: 'fixture store',
          message: 'fixture recovery',
        });
        expect(
          signInReduce(retry, { type: 'store_ready', attempt: state.attempt }),
        ).toBe(retry);
        expect(
          signInReduce(retry, { type: 'store_ready', attempt: retry.attempt })
            .step,
        ).toEqual(
          provider === undefined
            ? { kind: 'provider' }
            : { kind: 'way', provider },
        );
      }
    }
  });

  test('expiry choices and countdown boundaries remain independent of wording', () => {
    for (const provider of ['CHATGPT', 'GROK']) {
      expect(
        failureChoices(`LIBFX_${provider}_DEVICE_CODE_EXPIRED`, 'browser'),
      ).toEqual(['new_code']);
      expect(
        failureChoices(`LIBFX_${provider}_SIGN_IN_STATE_MISMATCH`, 'code'),
      ).toEqual([]);
      expect(failureChoices('unknown', 'code')).toEqual([
        'retry',
        'browser',
        'another_plan',
      ]);
    }

    for (const [remaining, minutes] of [
      [-1, 0],
      [0, 0],
      [1, 1],
      [59_999, 1],
      [60_000, 1],
      [60_001, 2],
    ] as const) {
      expect(signInMinutes(100_000 + remaining, 100_000)).toBe(minutes);
    }
  });
});
