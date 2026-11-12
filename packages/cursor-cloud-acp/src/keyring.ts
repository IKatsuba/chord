/**
 * The SDK's `SdkCredentialStore` over the OS keychain, through
 * `@napi-rs/keyring`: one entry whose password is the JSON of the SDK's
 * stored credentials. It reaches only `login`, `logout` and `status`.
 */
import { AsyncEntry, type EntryOptions } from '@napi-rs/keyring';
import type { SdkCredentialStore, StoredSdkCredentials } from '@cursor/sdk';
import { z } from 'zod';
import { KeychainError } from './errors.ts';

export const SERVICE = '@chorded/cursor-cloud-acp';
export const ACCOUNT = 'cursor-api-key';
// Unpinned, Linux falls silently to the kernel keyring, lost at reboot.
export const OPTIONS: EntryOptions = { linux: { store: 'secret-service' } };
/** macOS asks with a dialog when another node reads the item; never wait on it. */
export const BOUND_MS = 10_000;

/** The keychain entry's calls the store makes. */
export type Entry = Pick<
  AsyncEntry,
  'getPassword' | 'setPassword' | 'deletePassword'
>;

/**
 * The shape the SDK stores. An entry of any other shape, or not JSON, loads
 * as signed out, so the format holds across versions.
 */
const STORED = z.object({
  version: z.literal(1),
  backendUrl: z.string(),
  apiKey: z.string(),
  apiKeyExpiresAtMs: z.number().optional(),
  email: z.string().optional(),
  createdAtMs: z.number(),
});

function parsed(password: string | null): StoredSdkCredentials | undefined {
  if (password === null) {
    return undefined;
  }

  try {
    const stored = STORED.safeParse(JSON.parse(password));

    // JSON has no undefined, so an optional field is absent, as the SDK's
    // type wants, never present and undefined.
    return stored.success ? (stored.data as StoredSdkCredentials) : undefined;
  } catch {
    return undefined;
  }
}

/** `call` bounded at `BOUND_MS`, any failure a `KeychainError`. */
async function bounded<T>(
  call: (signal: AbortSignal) => Promise<T>,
  bound: number,
): Promise<T> {
  const signal = AbortSignal.timeout(bound);

  try {
    return await call(signal);
  } catch (error) {
    throw new KeychainError(
      signal.aborted
        ? `The keychain did not answer within ${bound / 1000} s.`
        : `The keychain refused: ${error instanceof Error ? error.message : String(error)}`,
      { cause: error },
    );
  }
}

/** The store over `entry`, the real keychain's but in a test. */
export function keyringStore(
  entry: Entry = new AsyncEntry(SERVICE, ACCOUNT, OPTIONS),
  bound = BOUND_MS,
): SdkCredentialStore {
  return {
    load: async () =>
      parsed(await bounded((signal) => entry.getPassword(signal), bound)),
    save: (credentials) =>
      bounded(
        (signal) => entry.setPassword(JSON.stringify(credentials), signal),
        bound,
      ),
    clear: async () => {
      await bounded((signal) => entry.deletePassword(signal), bound);
    },
  };
}
