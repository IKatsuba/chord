/**
 * What an agent says of the account its connection is signed in to
 * (CHD-629): its answer to `auth/status` and its `auth/status_update`
 * pushes, folded in the order they arrive, as ACP carries no revision.
 * Display only: never recorded, never in `-p`'s output.
 */
import type { AuthStatusResponse } from '@agentclientprotocol/sdk/unstable';

/** Where an agent's account stands, as chord heard it. */
export type AccountState =
  /** The agent does not advertise `auth.status`. */
  | { readonly phase: 'none' }
  /** Asked, nothing heard yet. */
  | { readonly phase: 'pending' }
  /** An answer or a push, the last of them. */
  | { readonly phase: 'heard'; readonly status: AuthStatusResponse }
  /** The request failed and nothing was heard. */
  | { readonly phase: 'failed' };

/** What changes it: the request sent, a status heard, the request failed. */
export type AccountEvent =
  | { readonly type: 'asked' }
  | { readonly type: 'heard'; readonly status: AuthStatusResponse }
  | { readonly type: 'failed' };

const STATES: readonly string[] = [
  'authenticated',
  'unauthenticated',
  'not_required',
  'unknown',
];

export const NO_ACCOUNT: AccountState = { phase: 'none' };

/**
 * `state` with `event` folded in: a status heard is the last word, a word
 * ACP's schema leaves open reading `unknown`; a failed request after a
 * status keeps the status, and one before any is `failed`.
 */
export function foldAccount(
  state: AccountState,
  event: AccountEvent,
): AccountState {
  switch (event.type) {
    case 'asked':
      return state.phase === 'none' ? { phase: 'pending' } : state;
    case 'heard':
      return {
        phase: 'heard',
        status: STATES.includes(event.status.state)
          ? event.status
          : { ...event.status, state: 'unknown' },
      };
    case 'failed':
      return state.phase === 'heard' ? state : { phase: 'failed' };
  }
}
