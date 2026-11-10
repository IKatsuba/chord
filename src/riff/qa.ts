/** Explicit system/fixture choice for the child; QA never opens the keychain. */
import { z } from '@zod/zod';
import type { FxFetch } from 'libfx/node';
import process from 'node:process';
import {
  memorySecrets,
  secrets,
  type Secrets,
  secretStoreName,
  systemSecrets,
} from '../platform/secrets.ts';
import { fakeProvider } from './start.ts';
import { planCredential, planFetch } from './qa_provider.ts';

export const QA_ENV = 'CHORD_RIFF_QA';
export const QA_STATE_ENV = 'CHORD_RIFF_QA_STATE';
export const QA_PROVIDER_ENV = 'CHORD_RIFF_QA_PROVIDER';
export const QA_STORE_ENV = 'CHORD_RIFF_QA_STORE';

const STATE = z.enum([
  'signed-in',
  'signed-out',
  'no-store',
  'timeout',
  'unsaved',
  'saved',
  'removed',
  'account-changed',
]);

/** Called only by the launcher; system access must be explicitly selected. */
export function riffAccess(
  env: Readonly<Record<string, string | undefined>>,
  system: () => Secrets = systemSecrets,
): {
  readonly provider: ReturnType<typeof fakeProvider>;
  readonly secrets: Secrets;
  readonly fetch: FxFetch;
} {
  const provider = fakeProvider(env);

  if (provider === undefined) {
    return { provider, secrets: system(), fetch: globalThis.fetch };
  }

  if (env[QA_ENV] !== '1' || !env[QA_STATE_ENV]) {
    return { provider, secrets: memorySecrets(), fetch: globalThis.fetch };
  }

  const state = STATE.parse(env[QA_STATE_ENV]);
  const plan = z.enum(['codex', 'grok']).parse(env[QA_PROVIDER_ENV] ?? 'codex');
  const platform =
    env[QA_STORE_ENV] === undefined
      ? process.platform
      : z.enum(['darwin', 'linux', 'win32']).parse(env[QA_STORE_ENV]);
  const name = secretStoreName(platform);
  const backing = memorySecrets(
    state === 'signed-out'
      ? {}
      : { [plan]: JSON.stringify(planCredential(plan)) },
  );
  let store: Secrets = backing;

  if (state === 'no-store' || state === 'timeout') {
    store = secrets(
      {
        get: () =>
          state === 'timeout'
            ? new Promise<string | null>(() => {})
            : Promise.reject(new Error('Fixture store unavailable.')),
        set: () => Promise.reject(new Error('Fixture store unavailable.')),
        delete: () => Promise.reject(new Error('Fixture store unavailable.')),
      },
      name,
    );
  } else if (state === 'unsaved') {
    store = {
      ...backing,
      set: () => Promise.reject(new Error('Fixture write failed.')),
    };
  }

  const fixture = planFetch({
    plan,
    unauthorized: state === 'unsaved' || state === 'saved',
  });
  const fetch: FxFetch = async (url, init) => {
    const response = await fixture.fetch(url, init);

    if (url.endsWith('/responses') && response.ok) {
      if (state === 'removed') {
        await backing.delete(plan);
      } else if (state === 'account-changed') {
        await backing.set(
          plan,
          JSON.stringify({
            ...planCredential(plan),
            accountId: 'other-fixture-account',
          }),
        );
      }
    }

    return response;
  };

  return { provider: undefined, secrets: store, fetch };
}
