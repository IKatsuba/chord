import { describe, expect, test } from 'bun:test';
import type { SdkCredentialStore, StoredSdkCredentials } from '@cursor/sdk';
import { apiKey } from '../src/credentials.ts';
import { KeychainError } from '../src/errors.ts';

const NOW = 1_850_000_000_000;
const STORED: StoredSdkCredentials = {
  version: 1,
  backendUrl: 'https://api2.cursor.sh',
  apiKey: 'key_keychain',
  apiKeyExpiresAtMs: NOW + 1,
  createdAtMs: NOW - 1000,
};

/** A store answering `stored`, counting its loads. */
function store(stored: StoredSdkCredentials | undefined | Error) {
  const fake = {
    loads: 0,
    load: () => {
      fake.loads += 1;

      return stored instanceof Error
        ? Promise.reject(stored)
        : Promise.resolve(stored);
    },
    save: () => Promise.reject(new Error('never saved')),
    clear: () => Promise.reject(new Error('never cleared')),
  };

  return fake satisfies SdkCredentialStore;
}

const source = (
  stored: StoredSdkCredentials | undefined | Error,
  env: Record<string, string | undefined> = {},
) => ({ env, store: store(stored), now: () => NOW });

describe('apiKey', () => {
  test('CURSOR_API_KEY over the keychain, which it does not read', async () => {
    const from = source(STORED, { CURSOR_API_KEY: 'key_env' });

    expect(await apiKey(from)).toBe('key_env');
    expect(from.store.loads).toBe(0);
  });

  test('an empty CURSOR_API_KEY is not set', async () => {
    expect(await apiKey(source(STORED, { CURSOR_API_KEY: '' }))).toBe(
      'key_keychain',
    );
  });

  test("the keychain's key when unexpired", async () => {
    expect(await apiKey(source(STORED))).toBe('key_keychain');

    const { apiKeyExpiresAtMs: _, ...never } = STORED;

    expect(await apiKey(source(never))).toBe('key_keychain');
  });

  test('none when expired', async () => {
    expect(
      await apiKey(source({ ...STORED, apiKeyExpiresAtMs: NOW })),
    ).toBeUndefined();
  });

  test('a key minted for another backend is still used: Cursor refuses it', async () => {
    expect(
      await apiKey(source({ ...STORED, backendUrl: 'https://api3.cursor.sh' })),
    ).toBe('key_keychain');
    expect(
      await apiKey(
        source(STORED, { CURSOR_BACKEND_URL: 'https://staging.example' }),
      ),
    ).toBe('key_keychain');
  });

  test('none when the keychain holds nothing, or nothing of its shape', async () => {
    expect(await apiKey(source(undefined))).toBeUndefined();
  });

  test('a keychain that fails or times out rejects with its error', async () => {
    const error = new KeychainError('The keychain did not answer within 10 s.');

    await expect(apiKey(source(error))).rejects.toBe(error);
  });

  test('reads the keychain on every call: nothing is cached', async () => {
    const from = source(STORED);

    await apiKey(from);
    await apiKey(from);
    expect(from.store.loads).toBe(2);
  });
});

describe('CHD-622 tester: independent credential resolutions', () => {
  test('concurrent sessions can finish in reverse order with their own keys', async () => {
    const first = Promise.withResolvers<StoredSdkCredentials | undefined>();
    const second = Promise.withResolvers<StoredSdkCredentials | undefined>();
    const pending = [first.promise, second.promise];
    const from = source(STORED);
    let next = 0;

    from.store.load = () => pending[next++]!;

    const a = apiKey(from);
    const b = apiKey(from);

    second.resolve({ ...STORED, apiKey: 'key_second' });
    expect(await b).toBe('key_second');
    first.resolve({ ...STORED, apiKey: 'key_first' });
    expect(await a).toBe('key_first');
    expect(next).toBe(2);
  });

  test('an environment key bypasses a failed store and a later empty value reads it again', async () => {
    const failure = new KeychainError('The keychain refused: locked.');
    const from = source(failure, { CURSOR_API_KEY: 'key_env' });

    expect(await apiKey(from)).toBe('key_env');
    expect(from.store.loads).toBe(0);

    from.env.CURSOR_API_KEY = '';

    await expect(apiKey(from)).rejects.toBe(failure);
    expect(from.store.loads).toBe(1);
  });
});
