import { afterEach, beforeEach, describe, expect, jest, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { FxFetch } from 'libfx/node';
import {
  LoopbackPortTaken,
  type LoopbackOptions,
} from '../../src/platform/loopback.ts';
import {
  memorySecrets,
  SecretStoreTimeout,
  SecretStoreUnavailable,
  type SecretProvider,
} from '../../src/platform/secrets.ts';
import { planCredential } from '../../src/riff/qa_provider.ts';
import { withCredentialLock } from '../../src/riff/credential_lock.ts';
import { readProvider } from '../../src/riff/provider_record.ts';
import {
  BROWSER_DEADLINE,
  runSignIn,
  type SignInRun,
} from '../../src/riff/sign_in_run.ts';
import type { SignInProgress } from '../../src/riff/sign_in.ts';
import { until } from '../session/conversation_fake.ts';

let root: string;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'chord-sign-in-'));
});

describe('tester: sign-in driver cancellation and persistence', () => {
  test.each(['codex', 'grok'] as const)(
    '%s: cancelled token exchange cannot save a late OAuth answer',
    async (provider) => {
      const run = setup(provider, 'browser');
      const entered = Promise.withResolvers<void>();
      const release = Promise.withResolvers<void>();
      const done = runSignIn({
        ...run.options,
        fetch: async (url, init) => {
          if (new URL(url).pathname.endsWith('/token')) {
            entered.resolve();
            await release.promise;
          }

          return run.fake.fetch(url, init);
        },
      });

      await run.ready;

      const bound = run.bound();
      const browser = run.steps.find((step) => step.kind === 'browser');

      assert(bound !== undefined && browser?.kind === 'browser');

      const address = new URL(browser.address);
      const redirect = address.searchParams.get('redirect_uri');
      const response = bound.callback(
        new Request(
          `${redirect}?code=fixture&state=${address.searchParams.get('state')}`,
        ),
      );

      try {
        await entered.promise;
        run.controller.abort();
        await done;
        expect(run.closed()).toBeGreaterThan(0);
        expect(await run.store.get(provider)).toBeNull();
        expect(await readProvider(root)).toBeUndefined();
      } finally {
        run.controller.abort();
        release.resolve();
        await response;
        await done;
      }

      expect(run.steps.some((step) => step.kind === 'success')).toBe(false);
      expect(await run.store.get(provider)).toBeNull();
    },
  );

  test('Esc while waiting for the credential lock never saves after acquiring it', async () => {
    const run = setup('codex', 'code');
    const entered = Promise.withResolvers<void>();
    const release = Promise.withResolvers<void>();
    const saving = Promise.withResolvers<void>();
    const holder = withCredentialLock(
      root,
      'codex',
      run.store.name,
      async () => {
        entered.resolve();
        await release.promise;
      },
    );

    await entered.promise;

    const done = runSignIn({
      ...run.options,
      emit: (id, step) => {
        run.options.emit(id, step);

        if (step.kind === 'saving') {
          saving.resolve();
        }
      },
    });

    try {
      await saving.promise;
      run.controller.abort();
    } finally {
      release.resolve();
      await holder;
      await done;
    }

    expect(await run.store.get('codex')).toBeNull();
    expect(await readProvider(root)).toBeUndefined();
    expect(run.steps.at(-1)?.kind).toBe('saving');
  });

  test('a timed-out sign-in write retains the lock until its late completion', async () => {
    const run = setup('codex', 'code');
    const release = Promise.withResolvers<void>();
    let completion: Promise<void> | undefined;

    try {
      await runSignIn({
        ...run.options,
        store: {
          ...run.store,
          set: (provider, value) => {
            completion = release.promise.then(() =>
              run.store.set(provider, value),
            );

            return Promise.reject(
              new SecretStoreTimeout(run.store.name, completion),
            );
          },
        },
      });
      expect(run.steps.at(-1)?.kind).toBe('store_slow');
      expect(await readProvider(root)).toBeUndefined();

      expect(
        (
          await stat(join(root, 'riff', 'credentials', 'codex.lock'))
        ).isDirectory(),
      ).toBe(true);

      const after = withCredentialLock(root, 'codex', run.store.name, () =>
        run.store.get('codex'),
      );

      release.resolve();
      expect(JSON.parse((await after) ?? '{}').accountId).toBe(
        'fixture-account',
      );
      expect(run.steps.some((step) => step.kind === 'success')).toBe(false);
    } finally {
      release.resolve();
      await completion;
      await withCredentialLock(root, 'codex', run.store.name, () =>
        Promise.resolve(),
      );
    }
  });

  test.each(['codex', 'grok'] as const)(
    '%s: device expiry uses libfx words and saves no credential',
    async (provider) => {
      const run = setup(provider, 'code');

      jest.useFakeTimers();

      await runSignIn({
        ...run.options,
        emit: (id, step) => {
          run.options.emit(id, step);

          if (step.kind === 'code') {
            jest.setSystemTime(step.expiresAt + 1);
          }
        },
      });

      expect(run.steps.at(-1)).toMatchObject({
        kind: 'expired',
        message: expect.stringContaining(
          'The code expired before it was entered.',
        ),
      });
      expect(await run.store.get(provider)).toBeNull();
      expect(await readProvider(root)).toBeUndefined();
      expect(run.bound()).toBeUndefined();
      expect(run.fake.urls).toHaveLength(1);
    },
  );
});

afterEach(async () => {
  jest.useRealTimers();
  await rm(root, { recursive: true, force: true });
});

function fixture(provider: SecretProvider) {
  const urls: string[] = [];
  const fetch: FxFetch = (url, init) => {
    urls.push(url);
    expect(init?.signal).toBeInstanceOf(AbortSignal);

    const path = new URL(url).pathname;

    if (path === '/api/accounts/deviceauth/usercode') {
      return Promise.resolve(
        Response.json({
          user_code: 'WXYZ-1234',
          device_auth_id: 'fixture',
          interval: 1,
        }),
      );
    }

    if (path === '/oauth2/device/code') {
      return Promise.resolve(
        Response.json({
          user_code: 'WXYZ-1234',
          device_code: 'fixture',
          verification_uri: 'https://example.invalid/device',
          expires_in: 600,
          interval: 1,
        }),
      );
    }

    if (path === '/api/accounts/deviceauth/token') {
      return Promise.resolve(
        Response.json({
          authorization_code: 'fixture',
          code_verifier: 'fixture',
        }),
      );
    }

    if (path === '/oauth/token' || path === '/oauth2/token') {
      const value = planCredential(provider);

      return Promise.resolve(
        Response.json({
          access_token: value.accessToken,
          refresh_token: value.refreshToken,
          expires_in: 3600,
        }),
      );
    }

    if (path === '/oauth2/userinfo') {
      return Promise.resolve(Response.json({ sub: 'fixture-account' }));
    }

    throw new Error('Unexpected fixture sign-in endpoint.');
  };

  return { fetch, urls };
}

function setup(provider: SecretProvider, way: 'browser' | 'code') {
  const ready = Promise.withResolvers<void>();
  const fake = fixture(provider);
  const controller = new AbortController();
  const steps: SignInProgress[] = [];
  const store = memorySecrets();
  let bound: LoopbackOptions | undefined;
  let closed = 0;
  const options: SignInRun = {
    attempt: 4,
    provider,
    way,
    store,
    stateDir: root,
    signal: controller.signal,
    fetch: fake.fetch,
    listen: (settings) => {
      bound = settings;

      settings.signal.addEventListener('abort', () => closed++);

      return Promise.resolve({
        port: 23456,
        close: () => {
          closed++;

          return Promise.resolve();
        },
      });
    },
    emit: (attempt, step) => {
      expect(attempt).toBe(4);
      steps.push(step);

      if (step.kind === 'browser') {
        ready.resolve();
      }
    },
  };

  return {
    options,
    steps,
    store,
    controller,
    fake,
    bound: () => bound,
    closed: () => closed,
    ready: ready.promise,
  };
}

describe('riff sign-in driver over libfx', () => {
  for (const provider of ['codex', 'grok'] as const) {
    test(`${provider}: browser binds before the address, ignores stale state, and saves under the lock`, async () => {
      const run = setup(provider, 'browser');
      const done = runSignIn(run.options);

      await until(() => run.steps.some((step) => step.kind === 'browser'));

      const bound = run.bound();
      const browser = run.steps.find((step) => step.kind === 'browser');

      assert(bound !== undefined && browser?.kind === 'browser');

      const url = new URL(browser.address);
      const redirect = new URL(url.searchParams.get('redirect_uri') ?? '');

      expect(bound.path).toBe(redirect.pathname);
      expect(bound.port).toBe(Number(redirect.port));

      if (provider === 'codex') {
        expect(redirect.href).toBe('http://localhost:1455/auth/callback');
      }

      const old = await bound.callback(
        new Request(`${redirect.href}?code=fixture&state=old`),
      );

      expect(old.finish).toBe(false);
      expect(old.response.status).toBe(400);
      expect(run.steps.at(-1)?.kind).toBe('browser');
      expect(run.fake.urls).toEqual([]);

      const current = `${redirect.href}?code=fixture&state=${url.searchParams.get('state')}`;
      const [first, duplicate] = await Promise.all([
        bound.callback(new Request(current)),
        bound.callback(new Request(current)),
      ]);

      expect(first.finish).toBe(true);
      expect(duplicate.response.status).toBe(409);
      await done;
      expect(
        JSON.parse((await run.store.get(provider)) ?? '{}').accountId,
      ).toBe('fixture-account');
      expect(await readProvider(root)).toBe(provider);
      expect(run.steps.at(-1)?.kind).toBe('success');
      expect(run.closed()).toBeGreaterThan(0);
    });

    test(`${provider}: device code uses libfx start and completion with fake fetch`, async () => {
      const run = setup(provider, 'code');

      await runSignIn(run.options);

      expect(run.bound()).toBeUndefined();
      expect(
        run.steps.some(
          (step) => step.kind === 'code' && step.code === 'WXYZ-1234',
        ),
      ).toBe(true);
      expect(run.steps.at(-1)?.kind).toBe('success');
      expect(await readProvider(root)).toBe(provider);
    });
  }

  test('ChatGPT port taken stays D and never shows an address', async () => {
    const run = setup('codex', 'browser');

    await runSignIn({
      ...run.options,
      listen: (settings) =>
        Promise.reject(new LoopbackPortTaken(settings.port)),
    });

    expect(run.steps.map((step) => step.kind)).toEqual(['port_taken']);
    expect(await run.store.get('codex')).toBeNull();
  });

  test.each(['codex', 'grok'] as const)(
    '%s: a stale error callback follows libfx and denies the current attempt',
    async (provider) => {
      const run = setup(provider, 'browser');
      const done = runSignIn(run.options);

      await run.ready;

      const bound = run.bound();

      assert(bound !== undefined);

      const answer = await bound.callback(
        new Request(
          `http://127.0.0.1:23456${bound.path}?error=access_denied&state=old`,
        ),
      );

      expect(answer.finish).toBe(true);
      await done;
      expect(run.steps.at(-1)).toMatchObject({
        kind: 'failure',
        code:
          provider === 'codex'
            ? 'LIBFX_CHATGPT_SIGN_IN_DENIED'
            : 'LIBFX_GROK_SIGN_IN_DENIED',
      });
      expect(await run.store.get(provider)).toBeNull();
      expect(run.fake.urls).toEqual([]);
    },
  );

  test('Grok retries startSignIn three times and names the final taken port', async () => {
    const run = setup('grok', 'browser');
    const ports: number[] = [];

    await runSignIn({
      ...run.options,
      listen: (settings) => {
        ports.push(settings.port);

        return Promise.reject(new LoopbackPortTaken(settings.port));
      },
    });

    expect(ports).toHaveLength(3);
    expect(run.steps.at(-1)).toMatchObject({
      kind: 'failure',
      message: `Loopback port ${ports[2]} is taken by another program.`,
    });
  });

  test('Esc aborts the browser wait, closes the listener and drops late callbacks', async () => {
    const run = setup('grok', 'browser');
    const done = runSignIn(run.options);

    await until(() => run.bound() !== undefined);
    run.controller.abort();
    await done;
    expect(run.closed()).toBeGreaterThan(0);
    expect(run.steps.some((step) => step.kind === 'success')).toBe(false);
    expect(await run.store.get('grok')).toBeNull();
  });

  test('the browser deadline expires after ten minutes and closes the listener', async () => {
    const run = setup('grok', 'browser');

    jest.useFakeTimers();

    const done = runSignIn(run.options);

    await run.ready;
    jest.advanceTimersByTime(BROWSER_DEADLINE);
    await done;
    expect(run.steps.at(-1)).toMatchObject({
      kind: 'expired',
      message: 'The browser did not come back in 10 minutes.',
    });
    expect(run.closed()).toBeGreaterThan(0);
  });

  test('no store stops before OAuth or any listener', async () => {
    const run = setup('codex', 'browser');

    await runSignIn({
      ...run.options,
      store: {
        ...run.store,
        get: () => Promise.reject(new SecretStoreUnavailable('Secret Service')),
      },
    });

    expect(run.bound()).toBeUndefined();
    expect(run.fake.urls).toEqual([]);
    expect(run.steps.at(-1)?.kind).toBe('no_store');
  });
});
