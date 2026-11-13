import { describe, expect, test } from 'bun:test';
import type { StoredSdkCredentials } from '@cursor/sdk';
import { KeychainError } from '../src/errors.ts';
import {
  ACCOUNT,
  type Entry,
  keyringStore,
  OPTIONS,
  SERVICE,
} from '../src/keyring.ts';

const STORED: StoredSdkCredentials = {
  version: 1,
  backendUrl: 'https://api2.cursor.sh',
  apiKey: 'key_1',
  apiKeyExpiresAtMs: 1_900_000_000_000,
  email: 'a@example.com',
  createdAtMs: 1_800_000_000_000,
};

/** A keychain entry in memory; `hang` makes every call wait for its signal. */
function fakeEntry(password: string | null = null, hang = false) {
  const entry = {
    password,
    signals: [] as (AbortSignal | null | undefined)[],
    wait(signal?: AbortSignal | null) {
      entry.signals.push(signal);

      return hang
        ? new Promise<never>((_, reject) =>
            signal?.addEventListener('abort', () => reject(signal.reason)),
          )
        : Promise.resolve();
    },
    async getPassword(signal?: AbortSignal | null) {
      await entry.wait(signal);

      return entry.password;
    },
    async setPassword(value: string, signal?: AbortSignal | null) {
      await entry.wait(signal);

      entry.password = value;
    },
    async deletePassword(signal?: AbortSignal | null) {
      await entry.wait(signal);

      entry.password = null;

      return true;
    },
  };

  return entry satisfies Entry;
}

test("one entry, the package's service and account, pinned on Linux to the Secret Service", () => {
  expect(SERVICE).toBe('@chorded/cursor-cloud-acp');
  expect(ACCOUNT).toBe('cursor-api-key');
  expect(OPTIONS).toEqual({ linux: { store: 'secret-service' } });
});

describe('the store', () => {
  test("saves the SDK's credentials as JSON and loads them back", async () => {
    const entry = fakeEntry();
    const store = keyringStore(() => entry);

    await store.save(STORED);
    expect(JSON.parse(entry.password!)).toEqual(STORED);
    expect(await store.load()).toEqual(STORED);
    await store.clear();
    expect(entry.password).toBeNull();
    expect(await store.load()).toBeUndefined();
  });

  test('passes every call a signal', async () => {
    const entry = fakeEntry(JSON.stringify(STORED));
    const store = keyringStore(() => entry);

    await store.load();
    await store.save(STORED);
    await store.clear();
    expect(
      entry.signals.map((signal) => signal instanceof AbortSignal),
    ).toEqual([true, true, true]);
  });

  test.each([
    ['not JSON', 'key_1'],
    ['another version', JSON.stringify({ ...STORED, version: 2 })],
    ['no key', JSON.stringify({ ...STORED, apiKey: undefined })],
    ['an array', '[]'],
  ])('an entry of another shape (%s) loads as signed out', async (_, value) => {
    expect(await keyringStore(() => fakeEntry(value)).load()).toBeUndefined();
  });

  test('an entry without the optional fields loads', async () => {
    const { version, backendUrl, apiKey, createdAtMs } = STORED;
    const bare = { version, backendUrl, apiKey, createdAtMs };

    expect(
      await keyringStore(() => fakeEntry(JSON.stringify(bare))).load(),
    ).toEqual(bare);
  });

  test('a keychain that does not answer within the bound fails naming the keychain', async () => {
    const store = keyringStore(() => fakeEntry(null, true), 20);

    for (const call of [
      () => store.load(),
      () => store.save(STORED),
      () => store.clear(),
    ]) {
      const error = await call().catch((caught: unknown) => caught);

      expect(error).toBeInstanceOf(KeychainError);
      expect((error as Error).message).toBe(
        'The keychain did not answer within 0.02 s.',
      );
    }
  });

  test("a keychain's refusal is a KeychainError with its words", async () => {
    const entry = {
      ...fakeEntry(),
      getPassword: () =>
        Promise.reject(new Error('Platform secure storage failure')),
    };

    await expect(keyringStore(() => entry).load()).rejects.toThrow(
      new KeychainError(
        'The keychain refused: Platform secure storage failure',
      ),
    );
  });

  test('an entry that cannot be made, as without a Secret Service, fails each call as the keychain', async () => {
    const store = keyringStore(() => {
      throw new Error('Platform secure storage failure: no Secret Service');
    });

    for (const call of [
      () => store.load(),
      () => store.save(STORED),
      () => store.clear(),
    ]) {
      await expect(call()).rejects.toThrow(
        new KeychainError(
          'The keychain refused: Platform secure storage failure: no Secret Service',
        ),
      );
    }
  });
});

describe('CHD-622 tester: stored credential shape', () => {
  test.each([
    ['null', null],
    ['missing backend', { ...STORED, backendUrl: undefined }],
    ['missing creation time', { ...STORED, createdAtMs: undefined }],
    ['non-string backend', { ...STORED, backendUrl: 1 }],
    ['non-string key', { ...STORED, apiKey: null }],
    ['non-number expiry', { ...STORED, apiKeyExpiresAtMs: 'tomorrow' }],
    ['null expiry', { ...STORED, apiKeyExpiresAtMs: null }],
    ['non-string email', { ...STORED, email: 1 }],
  ])('%s is signed out without changing the entry', async (_, value) => {
    const password = JSON.stringify(value);
    const entry = fakeEntry(password);

    expect(await keyringStore(() => entry).load()).toBeUndefined();
    expect(entry.password).toBe(password);
  });
});
