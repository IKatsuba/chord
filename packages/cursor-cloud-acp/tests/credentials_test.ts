import { describe, expect, test } from 'bun:test';
import type { SdkCredentialStore, StoredSdkCredentials } from '@cursor/sdk';
import { apiKey, backendUrl } from '../src/credentials.ts';
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

  test("the keychain's key when unexpired and minted for the backend in use", async () => {
    expect(await apiKey(source(STORED))).toBe('key_keychain');

    const { apiKeyExpiresAtMs: _, ...never } = STORED;

    expect(await apiKey(source(never))).toBe('key_keychain');
  });

  test('none when expired', async () => {
    expect(
      await apiKey(source({ ...STORED, apiKeyExpiresAtMs: NOW })),
    ).toBeUndefined();
  });

  test('none when minted for another backend', async () => {
    expect(
      await apiKey(source({ ...STORED, backendUrl: 'https://api3.cursor.sh' })),
    ).toBeUndefined();
    expect(
      await apiKey(
        source(STORED, { CURSOR_BACKEND_URL: 'https://staging.example' }),
      ),
    ).toBeUndefined();
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

test("backendUrl is the SDK's: CURSOR_BACKEND_URL or production, trailing slashes off", () => {
  expect(backendUrl({})).toBe('https://api2.cursor.sh');
  expect(backendUrl({ CURSOR_BACKEND_URL: 'https://b.example//' })).toBe(
    'https://b.example',
  );
});
