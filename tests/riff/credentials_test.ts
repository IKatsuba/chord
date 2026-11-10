import { afterEach, describe, expect, test } from 'bun:test';
import { execFile } from 'node:child_process';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import {
  memorySecrets,
  secrets,
  SecretStoreTimeout,
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

describe('CHD-606 tester: credential rotation boundaries', () => {
  test('failed late write keeps its pending rotation for the next lock', async () => {
    const root = await directory();
    const backing = memorySecrets({ codex: JSON.stringify(credential(0)) });
    const completion = Promise.withResolvers<void>();
    const states: CredentialState[] = [];
    let attempts = 0;
    const store: Secrets = {
      ...backing,
      set: async (provider, value) => {
        attempts++;

        if (attempts === 1) {
          throw new SecretStoreTimeout(backing.name, completion.promise);
        }

        await backing.set(provider, value);
      },
    };
    const cell = credentialCell(store, root, 'codex', (state) =>
      states.push(state),
    );

    await cell.locked(async (lease) => {
      await lease.read();
      await lease.save(credential(1));
    });

    expect(states).toEqual(['unsaved']);
    expect(await backing.get('codex')).toBe(JSON.stringify(credential(0)));

    const retry = cell.locked((lease) => lease.read());

    completion.reject(new Error('fixture late write failed'));
    expect(await retry).toEqual(credential(1));
    expect(attempts).toBe(2);
    expect(states).toEqual(['unsaved', 'saved']);
    expect(await backing.get('codex')).toBe(JSON.stringify(credential(1)));
  });

  test.each(['newer chain', 'logout', 'other account'] as const)(
    'an unsaved rotation cannot overwrite %s before retry',
    async (change) => {
      const root = await directory();
      const backing = memorySecrets({ codex: JSON.stringify(credential(0)) });
      const states: CredentialState[] = [];
      let writes = 0;
      const store: Secrets = {
        ...backing,
        set: () => {
          writes++;

          return Promise.reject(new Error('fixture write unavailable'));
        },
      };
      const cell = credentialCell(store, root, 'codex', (state) =>
        states.push(state),
      );

      await cell.locked(async (lease) => {
        await lease.read();
        await lease.save(credential(1));
      });

      if (change === 'logout') {
        await credentialCell(backing, root, 'codex').logout();
      } else {
        await backing.set(
          'codex',
          JSON.stringify(
            credential(2, change === 'other account' ? 'other' : undefined),
          ),
        );
      }

      const authoritative = await backing.get('codex');
      const state =
        change === 'other account' ? 'account_changed' : 'signed_out';

      await expect(cell.locked((lease) => lease.read())).rejects.toMatchObject({
        state,
      });
      await expect(cell.check()).rejects.toBeInstanceOf(CredentialSignedOut);
      expect(writes).toBe(1);
      expect(states).toEqual(['unsaved', state]);
      expect(await backing.get('codex')).toBe(authoritative);
    },
  );

  test('store access failing between prompt checks fails closed and never writes', async () => {
    const root = await directory();
    const backing = memorySecrets({ codex: JSON.stringify(credential(0)) });
    const failure = new Error('fixture store vanished');
    let absent = false;
    let writes = 0;
    const store: Secrets = {
      ...backing,
      get: (provider) =>
        absent ? Promise.reject(failure) : backing.get(provider),
      set: () => {
        writes++;

        return Promise.resolve();
      },
    };
    const cell = credentialCell(store, root, 'codex');

    expect(await cell.check()).toEqual(credential(0));

    absent = true;

    await expect(cell.check()).rejects.toBe(failure);
    expect(writes).toBe(0);
    expect(await backing.get('codex')).toBe(JSON.stringify(credential(0)));
  });

  test('two independent processes never spend the same rotating token', async () => {
    const root = await directory();
    const entry = join(root, 'fixture.json');

    await writeFile(entry, JSON.stringify(credential(0)));

    const script = `
      import { readFile, writeFile } from 'node:fs/promises';
      import { credentialCell } from './src/riff/credentials.ts';
      import { secrets } from './src/platform/secrets.ts';
      const [root, entry] = process.argv.slice(1);
      const cell = credentialCell(secrets({
        get: () => readFile(entry, 'utf8'),
        set: ({ value }) => writeFile(entry, value),
        delete: () => Promise.resolve(false),
      }, 'fixture store'), root, 'codex');
      await cell.check();
      for (let step = 0; step < 4; step++) {
        await cell.locked(async (lease) => {
          const value = await lease.read();
          const token = Number(value.refreshToken.slice('refresh-'.length));
          process.stdout.write(token + '\\n');
          await lease.save({
            accessToken: 'access-' + (token + 1),
            refreshToken: 'refresh-' + (token + 1),
            accountId: 'fixture-account', expiresAt: token + 1,
          });
        });
      }
    `;
    const completed = await Promise.allSettled(
      [0, 1].map(() =>
        promisify(execFile)(process.execPath, ['-e', script, root, entry], {
          cwd: new URL('../..', import.meta.url),
          timeout: 10_000,
        }),
      ),
    );
    const results = completed.map((result) => {
      if (result.status === 'rejected') {
        throw result.reason;
      }

      return result.value;
    });

    const spent = results
      .flatMap(({ stdout }) => stdout.trim().split('\n').map(Number))
      .sort((a, b) => a - b);

    expect(results.map(({ stderr }) => stderr)).toEqual(['', '']);
    expect(spent).toEqual([0, 1, 2, 3, 4, 5, 6, 7]);
    expect(JSON.parse(await readFile(entry, 'utf8'))).toEqual(credential(8));
    expect(await readdir(join(root, 'riff', 'credentials'))).toEqual([]);
  });
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
