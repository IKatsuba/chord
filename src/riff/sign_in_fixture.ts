/** Offline sign-in states for --fake/--qa; no endpoint or system store. */
import { setTimeout as delay } from 'node:timers/promises';
import type { FxFetch } from 'libfx/node';
import { type Secrets, type SecretProvider } from '../platform/secrets.ts';
import { planCredential } from './qa_provider.ts';
import { credentialSave, type runSignIn } from './sign_in_run.ts';
import type { SignInProgress } from './sign_in.ts';

export const QA_SIGN_IN_ENV = 'CHORD_RIFF_QA_SIGN_IN';

export function fixtureSignIn(outcome: string): typeof runSignIn {
  return async (options) => {
    const { provider, way, signal } = options;
    const emit = (step: SignInProgress) => {
      if (!signal.aborted) {
        options.emit(options.attempt, step);
      }
    };

    if (outcome === 'port-taken' && provider === 'codex' && way === 'browser') {
      emit({ kind: 'port_taken', provider, way });

      return;
    }

    try {
      signal.throwIfAborted();
      await options.store.get(provider);

      const address = `https://example.invalid/${provider}/${way}`;

      emit(
        way === 'browser'
          ? {
              kind: 'browser',
              provider,
              way,
              address: `${address}?state=fixture&code_challenge=${'fixture'.repeat(28)}`,
            }
          : {
              kind: 'code',
              provider,
              way,
              address,
              code: 'WXYZ-1234',
              expiresAt: Date.now() + 15 * 60_000,
            },
      );

      if (outcome === 'waiting') {
        await delay(2 ** 30, undefined, { signal });

        return;
      }

      await delay(1500, undefined, { signal });

      if (outcome === 'failure' || outcome === 'denied') {
        emit({
          kind: 'failure',
          provider,
          way,
          code: `LIBFX_${provider === 'codex' ? 'CHATGPT' : 'GROK'}_${outcome === 'denied' ? 'SIGN_IN_DENIED' : way === 'code' ? 'DEVICE_CODE_UNAVAILABLE' : 'SIGN_IN_FAILED'}`,
          message: 'The fixture sign-in was refused.',
        });

        return;
      }

      if (outcome === 'expired') {
        emit({
          kind: 'expired',
          provider,
          way,
          message:
            way === 'browser'
              ? 'The browser did not come back in 10 minutes.'
              : 'The code expired before it was entered. Start again.',
        });

        return;
      }

      const save = credentialSave(options, planCredential(provider));

      if (!(await save.retry(options.attempt, signal)) && !signal.aborted) {
        return save;
      }
    } catch (error) {
      if (!signal.aborted) {
        emit({
          kind: 'failure',
          provider,
          way,
          code: '',
          message:
            error instanceof Error ? error.message : 'Fixture sign-in failed.',
        });
      }
    }
  };
}

export function fixtureSignOut(store: Secrets): FxFetch {
  return async (url) => {
    if (
      url !== 'https://auth.x.ai/oauth2/revoke' ||
      (await store.get('grok')) !== null
    ) {
      throw new Error('Unexpected fixture revocation.');
    }

    return new Response();
  };
}

/** Explicitly transfers only fixture state to the next fake child process. */
export function fixtureSignedIn(
  env: Record<string, string | undefined>,
  provider: SecretProvider | undefined,
): void {
  env['CHORD_RIFF_QA'] = '1';
  env['CHORD_RIFF_QA_STATE'] =
    provider === undefined ? 'signed-out' : 'signed-in';

  if (provider !== undefined) {
    env['CHORD_RIFF_QA_PROVIDER'] = provider;
  }
}
