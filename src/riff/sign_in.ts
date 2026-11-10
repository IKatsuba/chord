/** The window's sign-in flow; effects live in sign_in_run.ts. */
import type { SecretProvider } from '../platform/secrets.ts';

export type SignInWay = 'browser' | 'code';

export type SignInChoice =
  | 'retry'
  | 'browser'
  | 'code'
  | 'another_plan'
  | 'new_code'
  | 'retry_store'
  | 'open'
  | 'copy_address'
  | 'copy_code';

type Attempt = {
  readonly provider: SecretProvider;
  readonly way: SignInWay;
};

export type SignInStep =
  | { readonly kind: 'provider' }
  | { readonly kind: 'way'; readonly provider: SecretProvider }
  | ({ readonly kind: 'starting' | 'finishing' | 'saving' } & Attempt)
  | ({ readonly kind: 'browser'; readonly address: string } & Attempt)
  | ({
      readonly kind: 'code';
      readonly address: string;
      readonly code: string;
      readonly expiresAt: number;
    } & Attempt)
  | ({ readonly kind: 'success'; readonly store: string } & Attempt)
  | ({
      readonly kind: 'failure';
      readonly code: string;
      readonly message: string;
    } & Attempt)
  | ({ readonly kind: 'expired'; readonly message: string } & Attempt)
  | { readonly kind: 'cancelled' }
  | {
      readonly kind: 'port_taken';
      readonly provider: 'codex';
      readonly way: 'browser';
    }
  | {
      readonly kind: 'reading_store';
      readonly provider: SecretProvider | undefined;
      readonly store: string;
      readonly message?: string;
    }
  | {
      readonly kind: 'no_store' | 'store_slow';
      readonly provider: SecretProvider | undefined;
      readonly store: string;
      readonly message: string;
    };

export interface SignInState {
  readonly attempt: number;
  readonly step: SignInStep;
}

export type SignInProgress =
  | Extract<SignInStep, Attempt>
  | Extract<
      SignInStep,
      { readonly kind: 'no_store' | 'store_slow' | 'reading_store' }
    >;

export type SignInEvent =
  | { readonly type: 'open' }
  | {
      readonly type: 'read_store';
      readonly provider: SecretProvider | undefined;
      readonly store: string;
    }
  | { readonly type: 'provider'; readonly provider: SecretProvider }
  | { readonly type: 'way'; readonly way: SignInWay }
  | { readonly type: 'choose'; readonly choice: SignInChoice }
  | { readonly type: 'back' }
  | { readonly type: 'store_ready'; readonly attempt: number }
  | {
      readonly type: 'progress';
      readonly attempt: number;
      readonly step: SignInProgress;
    };

export const initialSignIn = (): SignInState => ({
  attempt: 0,
  step: { kind: 'provider' },
});

const codes = (suffix: string) => [
  `LIBFX_CHATGPT_${suffix}`,
  `LIBFX_GROK_${suffix}`,
];

/** F's recovery table reads only the public error code, never its words. */
export function failureChoices(
  code: string,
  way: SignInWay,
): readonly SignInChoice[] {
  if (codes('SIGN_IN_STATE_MISMATCH').includes(code)) {
    return [];
  }

  if (codes('DEVICE_CODE_EXPIRED').includes(code)) {
    return ['new_code'];
  }

  if (codes('SIGN_IN_INVALID_ADDRESS').includes(code)) {
    return ['retry'];
  }

  if (
    codes('SIGN_IN_DENIED').includes(code) ||
    code === 'LIBFX_GROK_ACCOUNT_UNAVAILABLE'
  ) {
    return ['retry', 'another_plan'];
  }

  if (codes('SIGN_IN_EXPIRED').includes(code)) {
    return ['retry', 'code', 'another_plan'];
  }

  if (codes('DEVICE_CODE_UNAVAILABLE').includes(code)) {
    return ['retry', 'browser', 'another_plan'];
  }

  return ['retry', way === 'browser' ? 'code' : 'browser', 'another_plan'];
}

export function signInChoices(step: SignInStep): readonly SignInChoice[] {
  switch (step.kind) {
    case 'browser':
      return ['open', 'copy_address', 'code'];
    case 'code':
      return ['open', 'copy_code', 'copy_address'];
    case 'port_taken':
      return ['code', 'browser'];
    case 'failure':
      return failureChoices(step.code, step.way);
    case 'expired':
      return step.way === 'code'
        ? ['new_code']
        : ['retry', 'code', 'another_plan'];
    case 'no_store':
    case 'store_slow':
      return ['retry_store'];
    default:
      return [];
  }
}

/** A device page counts partial remaining minutes as a whole minute. */
export function signInMinutes(expiresAt: number, now: number): number {
  return Math.max(0, Math.ceil((expiresAt - now) / 60_000));
}

export function signInReduce(
  state: SignInState,
  event: SignInEvent,
): SignInState {
  const { step } = state;
  const next = (value: SignInStep): SignInState => ({
    attempt: state.attempt + 1,
    step: value,
  });

  switch (event.type) {
    case 'open':
      return next({ kind: 'provider' });
    case 'read_store':
      return next({
        kind: 'reading_store',
        provider: event.provider,
        store: event.store,
      });
    case 'provider':
      return step.kind === 'provider'
        ? next({ kind: 'way', provider: event.provider })
        : state;
    case 'way':
      return step.kind === 'way'
        ? next({ kind: 'starting', provider: step.provider, way: event.way })
        : state;
    case 'back':
      if (step.kind === 'way') {
        return next({ kind: 'provider' });
      }

      if (step.kind === 'port_taken' || step.kind === 'expired') {
        return next({ kind: 'way', provider: step.provider });
      }

      return next({ kind: 'cancelled' });
    case 'choose': {
      if (
        !signInChoices(step).includes(event.choice) ||
        !('provider' in step)
      ) {
        return state;
      }

      if (event.choice === 'another_plan') {
        return next({ kind: 'provider' });
      }

      if (event.choice === 'retry_store' && 'store' in step) {
        return next({
          kind: 'reading_store',
          provider: step.provider,
          store: step.store,
          ...('message' in step ? { message: step.message } : {}),
        });
      }

      if (
        event.choice === 'browser' ||
        event.choice === 'code' ||
        event.choice === 'new_code' ||
        event.choice === 'retry'
      ) {
        const way =
          event.choice === 'new_code'
            ? 'code'
            : event.choice === 'retry' && 'way' in step
              ? step.way
              : event.choice;

        if (
          (way === 'browser' || way === 'code') &&
          step.provider !== undefined
        ) {
          return next({ kind: 'starting', provider: step.provider, way });
        }
      }

      return state;
    }
    case 'store_ready':
      return state.attempt === event.attempt && step.kind === 'reading_store'
        ? {
            ...state,
            step:
              step.provider === undefined
                ? { kind: 'provider' }
                : { kind: 'way', provider: step.provider },
          }
        : state;
    case 'progress':
      if (
        event.attempt !== state.attempt ||
        [
          'provider',
          'way',
          'cancelled',
          'success',
          'failure',
          'expired',
          'port_taken',
          'no_store',
          'store_slow',
        ].includes(step.kind)
      ) {
        return state;
      }

      if ('provider' in step && step.provider !== event.step.provider) {
        return state;
      }

      if (
        event.step.kind === 'failure' &&
        codes('SIGN_IN_STATE_MISMATCH').includes(event.step.code)
      ) {
        return state;
      }

      return { ...state, step: event.step };
  }
}
