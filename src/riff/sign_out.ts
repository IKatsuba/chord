/** Local sign-out precedes Grok revocation (CHD-485, owner's G2 and L2). */
import type { FxFetch } from 'libfx/node';
import {
  type Secrets,
  type SecretProvider,
  SecretStoreTimeout,
} from '../platform/secrets.ts';
import { withCredentialLock } from './credential_lock.ts';
import { credentialOf } from './credentials.ts';
import { clearProvider } from './provider_record.ts';

const GROK_CLIENT = 'b1a00492-073a-47ea-816f-4c329264a828';
const GROK_REVOKE = 'https://auth.x.ai/oauth2/revoke';

export type SignOutResult = (
  | { readonly provider: 'codex' }
  | { readonly provider: 'grok'; readonly revoked: true }
  | {
      readonly provider: 'grok';
      readonly revoked: false;
      readonly reason:
        'no refresh token was stored' | 'the revocation request failed';
    }
  | {
      readonly provider: 'grok';
      readonly revoked: false;
      readonly status: number;
    }
) & { readonly recordFailed?: true };

export interface SignOutOptions {
  readonly provider: SecretProvider;
  readonly store: Secrets;
  readonly stateDir: string;
  readonly fetch: FxFetch;
  readonly signal: AbortSignal;
  /** Request cancellation of this window's riff turns and children at once. */
  readonly cancel: () => void;
  /** Local deletion has succeeded, even while revocation is still pending. */
  readonly deleted: () => void;
}

export async function signOut(options: SignOutOptions): Promise<SignOutResult> {
  const { provider, store, stateDir } = options;

  options.cancel();

  let recordFailed = false;
  const result = (value: SignOutResult): SignOutResult => ({
    ...value,
    ...(recordFailed ? { recordFailed: true } : {}),
  });

  const refresh = await withCredentialLock(
    stateDir,
    provider,
    store.name,
    async (held) => {
      const raw = await store.get(provider);
      let token: string | undefined;

      if (raw !== null) {
        try {
          token = credentialOf(raw).refreshToken;
        } catch {
          // Corrupt local credentials must still be removable.
        }
      }

      try {
        await store.delete(provider);
      } catch (error) {
        if (error instanceof SecretStoreTimeout) {
          held.track(error.completion);
        }

        throw error;
      }

      options.deleted();

      try {
        await clearProvider(stateDir, provider);
      } catch {
        // Selection ignores a record with no stored sign-in. Its cleanup
        // cannot prevent revoking the credential already deleted.
        recordFailed = true;
      }

      return token;
    },
  );

  if (provider === 'codex') {
    return result({ provider });
  }

  if (refresh === undefined) {
    return result({
      provider,
      revoked: false,
      reason: 'no refresh token was stored',
    });
  }

  const bound = new AbortController();
  const signal = AbortSignal.any([options.signal, bound.signal]);
  const cut = Promise.withResolvers<never>();
  const aborted = () => cut.reject(signal.reason);
  const timer = setTimeout(
    () => bound.abort(new Error('Revocation timed out.')),
    10_000,
  );

  signal.addEventListener('abort', aborted, { once: true });

  try {
    signal.throwIfAborted();

    // The owner's permitted port of fx's grok_oauth.zig revokeToken:
    // form fields token and client_id, with no token_type_hint.
    const response = await Promise.race([
      options.fetch(GROK_REVOKE, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          token: refresh,
          client_id: GROK_CLIENT,
        }).toString(),
        signal,
      }),
      cut.promise,
    ]);

    await Promise.race([response.body?.cancel(), cut.promise]);

    return result(
      response.ok
        ? { provider, revoked: true }
        : { provider, revoked: false, status: response.status },
    );
  } catch {
    return result({
      provider,
      revoked: false,
      reason: 'the revocation request failed',
    });
  } finally {
    clearTimeout(timer);
    signal.removeEventListener('abort', aborted);
  }
}

export function signedOutWords(result: SignOutResult): string {
  if (result.provider === 'codex') {
    return 'Signed out of ChatGPT. This session has ended; /login to sign in again, or /new for another agent.';
  }

  if (result.revoked) {
    return 'Signed out of Grok, and xAI revoked the sign-in. This session has ended; /login to sign in again.';
  }

  const reason = 'status' in result ? `HTTP ${result.status}` : result.reason;

  return `Signed out of Grok here, but xAI did not revoke the sign-in (${reason}). This session has ended; /login to sign in again.`;
}
