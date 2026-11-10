/** Sign-in belongs to the session in view; changing view keeps its attempt. */
import type { SecretProvider } from '../../platform/secrets.ts';
import {
  initialSignIn,
  signInReduce,
  type SignInEvent,
  type SignInState,
} from '../../riff/sign_in.ts';

export interface RiffNotice {
  readonly at: number;
  readonly title?: string;
  readonly text?: string;
  readonly command?: string;
  readonly error?: boolean;
}

export interface RiffState {
  readonly attempt: number;
  readonly provider?: SecretProvider;
  readonly signedOut: boolean;
  readonly flow?: SignInState;
  readonly since: number;
  readonly notices: readonly RiffNotice[];
  readonly hiddenErrors: readonly string[];
  readonly logout?: {
    readonly provider: SecretProvider;
    readonly pending: boolean;
    readonly message?: string;
  };
}

export const initialRiff = (): RiffState => ({
  attempt: 0,
  signedOut: false,
  since: 0,
  notices: [],
  hiddenErrors: [],
});

export type RiffAction =
  | { readonly type: 'open'; readonly now: number }
  | {
      readonly type: 'event';
      readonly event: SignInEvent;
      readonly now: number;
    }
  | { readonly type: 'notice'; readonly notice: RiffNotice }
  | { readonly type: 'provider'; readonly provider: SecretProvider }
  | { readonly type: 'signed_out' }
  | { readonly type: 'start_failed' }
  | { readonly type: 'hide_error'; readonly turnId: string }
  | { readonly type: 'close' }
  | { readonly type: 'logout'; readonly provider: SecretProvider }
  | { readonly type: 'logout_pending'; readonly now: number }
  | { readonly type: 'logout_failed'; readonly message: string };

export function reduceRiff(state: RiffState, action: RiffAction): RiffState {
  switch (action.type) {
    case 'open': {
      const { logout: _, ...rest } = state;

      return {
        ...rest,
        flow: signInReduce(
          state.flow ?? { ...initialSignIn(), attempt: state.attempt },
          { type: 'open' },
        ),
        attempt: state.attempt + 1,
        since: action.now,
      };
    }
    case 'event': {
      if (state.flow === undefined) {
        return state;
      }

      const flow = signInReduce(state.flow, action.event);

      return flow === state.flow
        ? state
        : {
            ...state,
            flow,
            attempt: flow.attempt,
            since:
              flow.attempt === state.flow.attempt ? state.since : action.now,
          };
    }
    case 'notice':
      return { ...state, notices: [...state.notices, action.notice] };
    case 'hide_error':
      return { ...state, hiddenErrors: [...state.hiddenErrors, action.turnId] };
    case 'provider':
      return { ...state, provider: action.provider, signedOut: false };
    case 'signed_out':
      return { ...state, signedOut: true };
    case 'start_failed': {
      const { flow: _, logout: __, ...rest } = state;

      return { ...rest, signedOut: false };
    }
    case 'close': {
      const { flow: _, logout: __, ...rest } = state;

      return rest;
    }
    case 'logout':
      return {
        ...state,
        logout: { provider: action.provider, pending: false },
      };
    case 'logout_pending':
      return state.logout === undefined
        ? state
        : {
            ...state,
            since: action.now,
            logout: { ...state.logout, pending: true },
          };
    case 'logout_failed':
      return state.logout === undefined
        ? state
        : {
            ...state,
            logout: {
              ...state.logout,
              pending: false,
              message: action.message,
            },
          };
  }
}

export const providerName = (provider: SecretProvider) =>
  provider === 'codex' ? 'ChatGPT' : 'Grok';
