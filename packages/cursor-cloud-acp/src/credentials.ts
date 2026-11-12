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

/**
 * The backend the SDK talks to, as it resolves it: a key works only
 * against the backend it was minted for. The SDK does not export its own.
 */
export function backendUrl(
  env: Readonly<Record<string, string | undefined>>,
): string {
  return (env.CURSOR_BACKEND_URL ?? 'https://api2.cursor.sh').replace(
    /\/+$/,
    '',
  );
}

/**
 * `CURSOR_API_KEY` when set, else the keychain's key when unexpired and
 * minted for the backend in use, else none: signed out. A keychain that
 * fails or does not answer rejects, naming the keychain.
 */
export async function apiKey(
  source: CredentialSource,
): Promise<string | undefined> {
  const fromEnv = source.env.CURSOR_API_KEY;

  if (fromEnv !== undefined && fromEnv !== '') {
    return fromEnv;
  }

  const stored = await source.store.load();

  if (
    stored === undefined ||
    stored.backendUrl !== backendUrl(source.env) ||
    (stored.apiKeyExpiresAtMs !== undefined &&
      stored.apiKeyExpiresAtMs <= source.now())
  ) {
    return undefined;
  }

  return stored.apiKey;
}
