import { describe, expect, test } from 'bun:test';
import type { SdkCredentialStore, SdkLoginOptions } from '@cursor/sdk';
import { CursorError, KeychainError } from '../src/errors.ts';
import { type LoginContext, login, logout, status } from '../src/login.ts';

const EXPIRES = Date.UTC(2027, 1, 10, 12);

/** A context over fakes, recording what reached stdout and stderr. */
function context(
  port: Partial<LoginContext['port']> = {},
  store: Partial<SdkCredentialStore> = {},
  env: Record<string, string> = {},
) {
  const out: string[] = [];
  const err: string[] = [];
  const logins: SdkLoginOptions[] = [];
  const fakeStore: SdkCredentialStore = {
    load: () => Promise.resolve(undefined),
    save: () => Promise.resolve(),
    clear: () => Promise.resolve(),
    ...store,
  };

  return {
    out,
    err,
    logins,
    context: {
      port: {
        login: (options = {}) => {
          logins.push(options);

          return Promise.resolve({
            apiKey: 'key_1',
            email: 'a@example.com',
            apiKeyExpiresAtMs: EXPIRES,
          });
        },
        logout: () => Promise.resolve(),
        status: () => Promise.resolve({ status: 'logged-out' as const }),
        ...port,
      },
      store: fakeStore,
      env,
      print: (line: string) => out.push(line),
      fail: (line: string) => err.push(line),
    } satisfies LoginContext,
  };
}

describe('login', () => {
  test("signs in into the keychain's store and says as whom and until when", async () => {
    const at = context();

    expect(await login(at.context)).toBe(0);
    expect(at.logins).toEqual([{ store: at.context.store }]);
    expect(at.out).toEqual([
      'Signed in to Cursor as a@example.com; the key expires 2027-02-10.',
    ]);
    expect(at.err).toEqual([]);
  });

  test('leaves out what the SDK did not give', async () => {
    const at = context({
      login: () => Promise.resolve({ apiKey: 'k', apiKeyExpiresAtMs: EXPIRES }),
    });

    await login(at.context);
    expect(at.out).toEqual([
      'Signed in to Cursor; the key expires 2027-02-10.',
    ]);
  });

  test('no keychain: refuses before the browser, pointing to CURSOR_API_KEY', async () => {
    const at = context(
      {},
      {
        load: () =>
          Promise.reject(
            new KeychainError(
              'The keychain refused: no Secret Service is running.',
            ),
          ),
      },
    );

    expect(await login(at.context)).toBe(1);
    expect(at.logins).toEqual([]);
    expect(at.err).toEqual([
      'No keychain to keep the key in: The keychain refused: no Secret Service is running. Set CURSOR_API_KEY instead.',
    ]);
    expect(at.out).toEqual([]);
  });

  test("a keychain failing at the save, inside the SDK's error, refuses the same way", async () => {
    const at = context({
      login: () =>
        Promise.reject(
          new CursorError('other', 'Login failed', {
            cause: new KeychainError(
              'The keychain did not answer within 10 s.',
            ),
          }),
        ),
    });

    expect(await login(at.context)).toBe(1);
    expect(at.err).toEqual([
      'No keychain to keep the key in: The keychain did not answer within 10 s. Set CURSOR_API_KEY instead.',
    ]);
  });

  test("any other failure is the SDK's message", async () => {
    const at = context({
      login: () =>
        Promise.reject(new CursorError('auth', 'Login was cancelled')),
    });

    expect(await login(at.context)).toBe(1);
    expect(at.err).toEqual(['Login was cancelled']);
  });
});

describe('logout', () => {
  test("removes the key from the keychain's store and says only that", async () => {
    const stores: unknown[] = [];
    const at = context({
      logout: (options) => {
        stores.push(options?.store);

        return Promise.resolve();
      },
    });

    expect(await logout(at.context)).toBe(0);
    expect(stores).toEqual([at.context.store]);
    expect(at.out).toEqual([
      "Signed out of Cursor: the key is removed from this machine's keychain.",
    ]);
  });

  test("a keychain's failure says so", async () => {
    const at = context({
      logout: () =>
        Promise.reject(new KeychainError('The keychain refused: locked.')),
    });

    expect(await logout(at.context)).toBe(1);
    expect(at.err).toEqual([
      'No keychain to keep the key in: The keychain refused: locked. Set CURSOR_API_KEY instead.',
    ]);
  });
});

describe('status', () => {
  test('signed in, from the keychain', async () => {
    const at = context({
      status: () =>
        Promise.resolve({
          status: 'logged-in' as const,
          backendUrl: 'https://api2.cursor.sh',
          email: 'a@example.com',
          apiKeyExpiresAtMs: EXPIRES,
        }),
    });

    expect(await status(at.context)).toBe(0);
    expect(at.out).toEqual([
      'Signed in to Cursor as a@example.com; the key expires 2027-02-10.',
    ]);
  });

  test('signed in, nothing more given', async () => {
    const at = context({
      status: () =>
        Promise.resolve({
          status: 'logged-in' as const,
          backendUrl: 'https://api2.cursor.sh',
        }),
    });

    await status(at.context);
    expect(at.out).toEqual(['Signed in to Cursor.']);
  });

  test('signed out, and CURSOR_API_KEY named when set', async () => {
    const at = context({}, {}, { CURSOR_API_KEY: 'key_env' });

    expect(await status(at.context)).toBe(0);
    expect(at.out).toEqual([
      'Not signed in to Cursor.',
      'CURSOR_API_KEY is set; it is used instead.',
    ]);
  });
});
