/**
 * Which key a call uses: one answer per session/new, never cached across
 * sessions, always passed to the SDK as `apiKey`, so a login another SDK
 * program left in its own file is never used (CHD-622, Q3).
 */
import type { SdkCredentialStore } from '@cursor/sdk';

/** Where the key comes from: the environment and the keychain. */
export interface CredentialSource {
  readonly env: Readonly<Record<string, string | undefined>>;
  readonly store: SdkCredentialStore;
  readonly now: () => number;
}

/** A key found, and where it came from, which `auth/status` names. */
export interface FoundKey {
  readonly apiKey: string;
  readonly source: 'env' | 'keychain';
  /** When the keychain's key expires, where its entry says. */
  readonly expiresAtMs?: number;
}

/**
 * `CURSOR_API_KEY` when set, else the keychain's key when unexpired, else
 * none: signed out. A keychain that fails or does not answer rejects,
 * naming the keychain. A key minted for another backend is not checked
 * here: Cursor refuses it at `Cursor.me` (owner, CHD-622).
 */
export async function findKey(
  source: CredentialSource,
): Promise<FoundKey | undefined> {
  const fromEnv = source.env.CURSOR_API_KEY;

  if (fromEnv !== undefined && fromEnv !== '') {
    return { apiKey: fromEnv, source: 'env' };
  }

  const stored = await source.store.load();

  if (
    stored === undefined ||
    (stored.apiKeyExpiresAtMs !== undefined &&
      stored.apiKeyExpiresAtMs <= source.now())
  ) {
    return undefined;
  }

  return {
    apiKey: stored.apiKey,
    source: 'keychain',
    ...(stored.apiKeyExpiresAtMs === undefined
      ? {}
      : { expiresAtMs: stored.apiKeyExpiresAtMs }),
  };
}

/** `findKey`'s key alone. */
export async function apiKey(
  source: CredentialSource,
): Promise<string | undefined> {
  return (await findKey(source))?.apiKey;
}
