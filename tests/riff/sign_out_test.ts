import { afterEach, beforeEach, describe, expect, jest, test } from 'bun:test';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { providerOf } from '../../src/riff/provider.ts';
import { memorySecrets } from '../../src/platform/secrets.ts';
import { credentialCell } from '../../src/riff/credentials.ts';
import { planCredential } from '../../src/riff/qa_provider.ts';
import { readProvider, writeProvider } from '../../src/riff/provider_record.ts';
import { signOut, signedOutWords } from '../../src/riff/sign_out.ts';

let root: string;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'chord-sign-out-'));
});

afterEach(async () => {
  jest.useRealTimers();
  await rm(root, { recursive: true, force: true });
});

describe('riff sign-out', () => {
  test('record cleanup failure retains deletion, still revokes and is not drawn', async () => {
    const store = memorySecrets({
      grok: JSON.stringify(planCredential('grok')),
      codex: JSON.stringify(planCredential('codex')),
    });

    await mkdir(join(root, 'riff', 'provider'), { recursive: true });

    let called = false;
    const result = await signOut({
      provider: 'grok',
      store,
      stateDir: root,
      signal: new AbortController().signal,
      cancel: () => {},
      deleted: () => {},
      fetch: async () => {
        called = true;

        expect(await store.get('grok')).toBeNull();

        return new Response();
      },
    });

    expect(called).toBe(true);
    expect(result).toEqual({
      provider: 'grok',
      revoked: true,
      recordFailed: true,
    });
    expect(signedOutWords(result)).toBe(
      'Signed out of Grok, and xAI revoked the sign-in. This session has ended; /login to sign in again.',
    );
    expect(
      providerOf(
        { codex: await store.get('codex'), grok: await store.get('grok') },
        'grok',
      ),
    ).toBe('codex');
  });

  test.each(['deadline', 'leaving'] as const)(
    'revocation %s reports failure without restoring the entry',
    async (reason) => {
      const store = memorySecrets({
        grok: JSON.stringify(planCredential('grok')),
      });
      const controller = new AbortController();
      const started = Promise.withResolvers<AbortSignal>();

      jest.useFakeTimers();

      const done = signOut({
        provider: 'grok',
        store,
        stateDir: root,
        signal: controller.signal,
        cancel: () => {},
        deleted: () => {},
        fetch: (_url, init) => {
          started.resolve(init?.signal as AbortSignal);

          return new Promise<Response>(() => {});
        },
      });
      const signal = await started.promise;

      if (reason === 'deadline') {
        jest.advanceTimersByTime(10_000);
      } else {
        controller.abort();
      }

      const result = await done;

      expect(signal.aborted).toBe(true);
      expect(result).toEqual({
        provider: 'grok',
        revoked: false,
        reason: 'the revocation request failed',
      });
      expect(await store.get('grok')).toBeNull();
    },
  );

  test('ChatGPT cancels at once, deletes under the lock, clears its record and revokes nothing', async () => {
    const store = memorySecrets({
      codex: JSON.stringify(planCredential('codex')),
    });
    const order: string[] = [];

    await writeProvider(root, 'codex');

    const result = await signOut({
      provider: 'codex',
      store,
      stateDir: root,
      signal: new AbortController().signal,
      fetch: () => {
        throw new Error('ChatGPT must not revoke');
      },
      cancel: () => order.push('cancel'),
      deleted: () => order.push('deleted'),
    });

    expect(order).toEqual(['cancel', 'deleted']);
    expect(await store.get('codex')).toBeNull();
    expect(await readProvider(root)).toBeUndefined();
    expect(signedOutWords(result)).toBe(
      'Signed out of ChatGPT. This session has ended; /login to sign in again, or /new for another agent.',
    );
  });

  test.each([200, 503])(
    'Grok deletes before POST and reports HTTP %i',
    async (status) => {
      const value = planCredential('grok');
      const store = memorySecrets({
        grok: JSON.stringify(value),
        codex: JSON.stringify(planCredential('codex')),
      });
      let deleted = false;

      await writeProvider(root, 'codex');

      const result = await signOut({
        provider: 'grok',
        store,
        stateDir: root,
        signal: new AbortController().signal,
        cancel: () => {},
        deleted: () => {
          deleted = true;
        },
        fetch: async (url, init) => {
          expect(deleted).toBe(true);
          expect(await store.get('grok')).toBeNull();
          expect(url).toBe('https://auth.x.ai/oauth2/revoke');
          expect(init?.method).toBe('POST');
          expect(new Headers(init?.headers).get('content-type')).toBe(
            'application/x-www-form-urlencoded',
          );
          expect(
            Object.fromEntries(new URLSearchParams(String(init?.body))),
          ).toEqual({
            token: value.refreshToken,
            client_id: 'b1a00492-073a-47ea-816f-4c329264a828',
          });

          return new Response(null, { status });
        },
      });

      expect(result).toEqual(
        status === 200
          ? { provider: 'grok', revoked: true }
          : { provider: 'grok', revoked: false, status },
      );
      expect(signedOutWords(result)).toContain(
        status === 200 ? 'xAI revoked the sign-in.' : '(HTTP 503)',
      );
      expect(await readProvider(root)).toBe('codex');
      expect(await store.get('codex')).not.toBeNull();
    },
  );

  test.each([
    null,
    '{}',
    JSON.stringify({ accessToken: 'fixture', accountId: 'fixture' }),
  ])(
    'Grok missing or invalid refresh token makes no request (%s)',
    async (raw) => {
      const store = memorySecrets(raw === null ? {} : { grok: raw });
      const result = await signOut({
        provider: 'grok',
        store,
        stateDir: root,
        signal: new AbortController().signal,
        cancel: () => {},
        deleted: () => {},
        fetch: () => {
          throw new Error('must not request');
        },
      });

      expect(result).toEqual({
        provider: 'grok',
        revoked: false,
        reason: 'no refresh token was stored',
      });
      expect(signedOutWords(result)).toContain('(no refresh token was stored)');
      expect(await store.get('grok')).toBeNull();
    },
  );

  test('a network failure never restores the entry or leaks backend text', async () => {
    const store = memorySecrets({
      grok: JSON.stringify(planCredential('grok')),
    });
    const result = await signOut({
      provider: 'grok',
      store,
      stateDir: root,
      signal: new AbortController().signal,
      cancel: () => {},
      deleted: () => {},
      fetch: () =>
        Promise.reject(new Error('sensitive fixture backend detail')),
    });

    expect(signedOutWords(result)).toContain('(the revocation request failed)');
    expect(signedOutWords(result)).not.toContain('sensitive');
    expect(await store.get('grok')).toBeNull();
  });

  test('a failed local delete reports failure and never revokes or claims deletion', async () => {
    const store = memorySecrets({
      grok: JSON.stringify(planCredential('grok')),
    });
    let deleted = false;

    await expect(
      signOut({
        provider: 'grok',
        store: {
          ...store,
          delete: () => Promise.reject(new Error('fixture deletion failed')),
        },
        stateDir: root,
        signal: new AbortController().signal,
        cancel: () => {},
        deleted: () => {
          deleted = true;
        },
        fetch: () => {
          throw new Error('must not request');
        },
      }),
    ).rejects.toThrow('fixture deletion failed');
    expect(deleted).toBe(false);
    expect(await store.get('grok')).not.toBeNull();
  });

  test('logout follows a locked rotation and prevents the old process saving again', async () => {
    const store = memorySecrets({
      grok: JSON.stringify(planCredential('grok')),
    });
    const cell = credentialCell(store, root, 'grok');
    const read = Promise.withResolvers<void>();
    const release = Promise.withResolvers<void>();
    const rotating = cell.locked(async (lease) => {
      await lease.read();
      read.resolve();
      await release.promise;
      await lease.save(planCredential('grok', 1));
    });

    await read.promise;

    const ending = signOut({
      provider: 'grok',
      store,
      stateDir: root,
      signal: new AbortController().signal,
      cancel: () => {},
      deleted: () => {},
      fetch: (_url, init) => {
        expect(new URLSearchParams(String(init?.body)).get('token')).toBe(
          'fixture-refresh-1',
        );

        return Promise.resolve(new Response());
      },
    });

    release.resolve();
    await rotating;
    await ending;
    await expect(
      cell.locked((lease) => lease.save(planCredential('grok', 2))),
    ).rejects.toThrow();
    expect(await store.get('grok')).toBeNull();
  });
});
