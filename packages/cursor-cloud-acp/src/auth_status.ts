/**
 * What `auth/status` answers for a resolution of the key (CHD-630, "The
 * account"): the account Cursor names for it, and where the key came from.
 * No field carries the key or any part of it.
 */
import type {
  AuthAccount,
  AuthStatusResponse,
} from '@agentclientprotocol/sdk/unstable';
import type { SDKUser } from '@cursor/sdk';
import type { FoundKey } from './credentials.ts';

/** No key, or one Cursor refuses. */
export const UNAUTHENTICATED: AuthStatusResponse = { state: 'unauthenticated' };

/** The keychain failed, or Cursor did not answer for the key. */
export const UNKNOWN: AuthStatusResponse = { state: 'unknown' };

/** Where the key came from, with the keychain entry's expiry day. */
function description(found: FoundKey): string {
  if (found.source === 'env') {
    return 'CURSOR_API_KEY';
  }

  return found.expiresAtMs === undefined
    ? 'keychain'
    : `keychain, expires ${new Date(found.expiresAtMs).toISOString().slice(0, 10)}`;
}

/**
 * The one account `user` gives. `apiKeyName` is left out: it names the key
 * in Cursor's dashboard, not the person; the SDK gives no team name.
 */
export function authenticated(
  found: FoundKey,
  user: SDKUser,
): AuthStatusResponse {
  const name = [user.userFirstName, user.userLastName]
    .filter((part) => part !== undefined && part !== '')
    .join(' ');
  const account: AuthAccount = {
    label: 'Cursor',
    description: description(found),
    active: true,
    ...(name === '' ? {} : { name }),
    ...(user.userEmail === undefined || user.userEmail === ''
      ? {}
      : { email: user.userEmail }),
  };

  return { state: 'authenticated', accounts: [account] };
}
