import { afterEach, describe, expect, test } from 'bun:test';
import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  memorySecrets,
  secrets,
  type Secrets,
} from '../../src/platform/secrets.ts';
import {
  credentialCell,
  CredentialSignedOut,
  type CredentialState,
} from '../../src/riff/credentials.ts';

const directories: string[] = [];
const directory = async () => {
  const path = await mkdtemp(join(tmpdir(), 'chord-credential-test-'));

  directories.push(path);

  return path;
};

const credential = (token: number, account = 'fixture-account') => ({
  accessToken: `access-${token}`,
  refreshToken: `refresh-${token}`,
  accountId: account,
  expiresAt: token,
});

afterEach(async () => {
  for (const path of directories.splice(0)) {
    await rm(path, { recursive: true, force: true });
  }
});

describe('riff credential compare-and-set', () => {
  test('T8: independent cells read each rotation under one provider lock', async () => {
    const root = await directory();
    const store = memorySecrets({ codex: JSON.stringify(credential(0)) });
    const cells = [
      credentialCell(store, root, 'codex'),
      credentialCell(store, root, 'codex'),
    ];
    let current = 0;
    const spent = new Set<string>();

    await Promise.all(cells.map((cell) => cell.check()));
    await Promise.all(
      cells.flatMap((cell) =>
        Array.from({ length: 4 }, () =>
          cell.locked(async (lease) => {
            const value = await lease.read();

            expect(value.refreshToken).toBe(`refresh-${current}`);
            expect(spent.has(value.refreshToken ?? '')).toBe(false);
            spent.add(value.refreshToken ?? '');
            await lease.save(credential(++current));
          }),
        ),
      ),
    );
    expect(current).toBe(8);
    expect(await store.get('codex')).toBe(JSON.stringify(credential(8)));
    expect(await readdir(join(root, 'riff', 'credentials'))).toEqual([]);
  });

  test('already saved is a no-op; a different chain is refused', async () => {
    const root = await directory();
    const backing = memorySecrets({ codex: JSON.stringify(credential(0)) });
    let writes = 0;
    const store: Secrets = {
      ...backing,
      set: async (provider, value) => {
        writes++;
        await backing.set(provider, value);
      },
    };
    const cell = credentialCell(store, root, 'codex');

    await cell.locked(async (lease) => {
      await lease.read();
      await lease.save(credential(0));
    });

    expect(writes).toBe(0);
    await backing.set('codex', JSON.stringify(credential(2)));
    await expect(
      cell.locked((lease) => lease.save(credential(1))),
    ).rejects.toBeInstanceOf(CredentialSignedOut);
    expect(writes).toBe(0);
    expect(await backing.get('codex')).toBe(JSON.stringify(credential(2)));
  });

  test('logout queued behind refresh deletes its rotation and refuses a stale save', async () => {
    const root = await directory();
    const store = memorySecrets({ codex: JSON.stringify(credential(0)) });
    const refreshing = credentialCell(store, root, 'codex');
    const loggingOut = credentialCell(store, root, 'codex');
    const entered = Promise.withResolvers<void>();
    const continueRefresh = Promise.withResolvers<void>();
    const refresh = refreshing.locked(async (lease) => {
      await lease.read();
      entered.resolve();
      await continueRefresh.promise;
      await lease.save(credential(1));
    });

    await entered.promise;

    const logout = loggingOut.logout();

    continueRefresh.resolve();
    await Promise.all([refresh, logout]);
    expect(await store.get('codex')).toBeNull();
    await expect(
      refreshing.locked((lease) => lease.save(credential(2))),
    ).rejects.toBeInstanceOf(CredentialSignedOut);
    expect(await store.get('codex')).toBeNull();
  });

  test('another account signs this process out without changing the store', async () => {
    const root = await directory();
    const store = memorySecrets({ codex: JSON.stringify(credential(0)) });
    const states: CredentialState[] = [];
    const cell = credentialCell(store, root, 'codex', (state) =>
      states.push(state),
    );

    await cell.check();
    await store.set('codex', JSON.stringify(credential(1, 'other-account')));
    await expect(cell.check()).rejects.toMatchObject({
      state: 'account_changed',
    });
    expect(states).toEqual(['account_changed']);
    expect(await store.get('codex')).toBe(
      JSON.stringify(credential(1, 'other-account')),
    );
  });

  test('failed persistence retains rotation and retries before next locked read', async () => {
    const root = await directory();
    let raw = JSON.stringify(credential(0));
    let fail = true;
    const states: CredentialState[] = [];
    const store = secrets(
      {
        get: () => Promise.resolve(raw),
        set: ({ value }) => {
          if (fail) {
            return Promise.reject(new Error('fixture write failed'));
          }

          raw = value;

          return Promise.resolve();
        },
        delete: () => Promise.resolve(true),
      },
      'Secret Service',
    );
    const cell = credentialCell(store, root, 'codex', (state) =>
      states.push(state),
    );

    await cell.locked(async (lease) => {
      await lease.read();
      await lease.save(credential(1));
    });

    expect(states).toEqual(['unsaved']);
    expect(raw).toBe(JSON.stringify(credential(0)));

    fail = false;

    const next = await cell.locked((lease) => lease.read());

    expect(next).toEqual(credential(1));
    expect(states).toEqual(['unsaved', 'saved']);
    expect(raw).toBe(JSON.stringify(credential(1)));
  });

  test('a failed comparison read retains the new rotation for retry', async () => {
    const root = await directory();
    const backing = memorySecrets({ codex: JSON.stringify(credential(0)) });
    let fail = false;
    const states: CredentialState[] = [];
    const store: Secrets = {
      ...backing,
      get: (provider) =>
        fail
          ? Promise.reject(new Error('fixture read failed'))
          : backing.get(provider),
    };
    const cell = credentialCell(store, root, 'codex', (state) =>
      states.push(state),
    );

    await cell.locked(async (lease) => {
      await lease.read();

      fail = true;

      await lease.save(credential(1));
    });

    expect(states).toEqual(['unsaved']);

    fail = false;

    expect(await cell.locked((lease) => lease.read())).toEqual(credential(1));
    expect(states).toEqual(['unsaved', 'saved']);
  });
});
