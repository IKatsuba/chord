/** libfx owns OAuth; chord owns the callback's lifetime and locked storage. */
import * as chatgpt from 'libfx/chatgpt';
import * as grok from 'libfx/grok';
import type { FxFetch, FxProviderCredentials } from 'libfx/node';
import pLimit from 'p-limit';
import { loopback, LoopbackPortTaken } from '../platform/loopback.ts';
import {
  type Secrets,
  type SecretProvider,
  SecretStoreTimeout,
  SecretStoreUnavailable,
} from '../platform/secrets.ts';
import { withCredentialLock } from './credential_lock.ts';
import { credentialOf } from './credentials.ts';
import { writeProvider } from './provider_record.ts';
import type { SignInProgress, SignInWay } from './sign_in.ts';

export const BROWSER_DEADLINE = 10 * 60_000;

/** The credential stays in this closure; the window can only save or drop it. */
export interface SignInSave {
  retry(attempt: number, signal: AbortSignal): Promise<boolean>;
  discard(): void;
}

export function credentialSave(
  options: SignInRun,
  credential: FxProviderCredentials,
): SignInSave {
  let json: string | undefined = JSON.stringify(
    credentialOf(JSON.stringify(credential)),
  );
  const { provider, way, store, stateDir } = options;
  const discard = () => {
    json = undefined;

    options.signal.removeEventListener('abort', discard);
  };

  options.signal.addEventListener('abort', discard, { once: true });

  const save: SignInSave = {
    discard,
    retry: async (attempt, signal) => {
      const emit = (step: SignInProgress) => {
        if (!signal.aborted && json !== undefined) {
          options.emit(attempt, step);
        }
      };

      signal.addEventListener('abort', discard, { once: true });

      try {
        signal.throwIfAborted();

        if (json === undefined) {
          return false;
        }

        emit({ kind: 'saving', provider, way });
        await withCredentialLock(
          stateDir,
          provider,
          store.name,
          async (held) => {
            signal.throwIfAborted();

            if (json === undefined) {
              throw new Error('The sign-in was cancelled.');
            }

            try {
              // A new sign-in intentionally replaces any earlier account.
              // Retrying never selects the old credential by reading it.
              await store.set(provider, json);
            } catch (error) {
              if (error instanceof SecretStoreTimeout) {
                held.track(error.completion);
              }

              throw error;
            }

            signal.throwIfAborted();
            await writeProvider(stateDir, provider);
          },
        );

        emit({ kind: 'success', provider, way, store: store.name });
        discard();

        return true;
      } catch (error) {
        if (!signal.aborted) {
          emit({
            kind:
              error instanceof SecretStoreTimeout ? 'store_slow' : 'no_store',
            provider,
            store: store.name,
            message:
              error instanceof Error
                ? error.message
                : 'The sign-in could not be saved.',
          });
        }

        return false;
      } finally {
        if (signal !== options.signal) {
          signal.removeEventListener('abort', discard);
        }
      }
    },
  };

  // Publish before a failed write makes G selectable; listener cleanup may
  // still hold the driver's returned promise after that point.
  options.retainSave?.(save);

  return save;
}

async function startBrowser(provider: SecretProvider) {
  if (provider === 'codex') {
    const started = await chatgpt.startSignIn();

    return {
      url: started.url,
      redirectUri: 'http://localhost:1455/auth/callback',
      finish: (address: string, options: chatgpt.ChatgptRequestOptions) =>
        chatgpt.finishSignIn(started, address, options),
    };
  }

  const started = await grok.startSignIn();

  return {
    url: started.url,
    redirectUri: started.redirectUri,
    finish: (address: string, options: grok.GrokRequestOptions) =>
      grok.finishSignIn(started, address, options),
  };
}

export interface SignInRun {
  readonly attempt: number;
  readonly provider: SecretProvider;
  readonly way: SignInWay;
  readonly signal: AbortSignal;
  readonly fetch: FxFetch;
  readonly store: Secrets;
  readonly stateDir: string;
  readonly emit: (attempt: number, step: SignInProgress) => void;
  readonly retainSave?: (save: SignInSave) => void;
  /** Tests use random ports or an in-memory listener, never ChatGPT's 1455. */
  readonly listen?: typeof loopback;
}

const errorCode = (error: unknown): string =>
  error !== null &&
  typeof error === 'object' &&
  'code' in error &&
  typeof error.code === 'string'
    ? error.code
    : '';

export async function runSignIn(
  options: SignInRun,
): Promise<SignInSave | void> {
  const { provider, way, store } = options;
  const deadline = new AbortController();
  const signal = AbortSignal.any([options.signal, deadline.signal]);
  const expired = new Error('The browser did not come back in 10 minutes.');
  let timer: ReturnType<typeof setTimeout> | undefined;
  let listener: Awaited<ReturnType<typeof loopback>> | undefined;
  const emit = (step: SignInProgress) => {
    if (!signal.aborted) {
      options.emit(options.attempt, step);
    }
  };

  const base = { provider, way };

  try {
    signal.throwIfAborted();
    // C1: discover a missing store before sending the person to a provider.
    await store.get(provider);
    signal.throwIfAborted();

    let credential: FxProviderCredentials;

    if (way === 'code') {
      const request = { fetch: options.fetch, signal };

      if (provider === 'codex') {
        const device = await chatgpt.startDeviceSignIn(request);

        signal.throwIfAborted();
        emit({
          ...base,
          kind: 'code',
          address: device.verificationUrl,
          code: device.userCode,
          expiresAt: device.expiresAt,
        });

        credential = await chatgpt.completeDeviceSignIn(device, request);
      } else {
        const device = await grok.startDeviceSignIn(request);

        signal.throwIfAborted();
        emit({
          ...base,
          kind: 'code',
          address: device.verificationUrl,
          code: device.userCode,
          expiresAt: device.expiresAt,
        });

        credential = await grok.completeDeviceSignIn(device, request);
      }
    } else {
      const complete = Promise.withResolvers<FxProviderCredentials>();
      const aborted = () => complete.reject(signal.reason);

      signal.addEventListener('abort', aborted, { once: true });
      // A bind may fail before anything awaits the callback result.
      void complete.promise.catch(() => {});

      try {
        timer = setTimeout(() => deadline.abort(expired), BROWSER_DEADLINE);

        for (let tries = 0; tries < 3; tries++) {
          const started = await startBrowser(provider);

          signal.throwIfAborted();

          const redirect = new URL(started.redirectUri);
          const serial = pLimit(1);
          let finished = false;

          try {
            listener = await (options.listen ?? loopback)({
              port: Number(redirect.port),
              path: redirect.pathname,
              signal,
              callback: (request) =>
                serial(async () => {
                  if (finished || signal.aborted) {
                    return {
                      response: new Response('This sign-in has ended.', {
                        status: 409,
                      }),
                      finish: false,
                    };
                  }

                  const fetch: FxFetch = (url, init) => {
                    emit({ ...base, kind: 'finishing' });

                    return options.fetch(url, init);
                  };

                  try {
                    const value = await started.finish(request.url, {
                      fetch,
                      signal,
                    });

                    signal.throwIfAborted();

                    finished = true;

                    complete.resolve(value);

                    return {
                      response: new Response('Signed in. Return to chord.'),
                      finish: true,
                    };
                  } catch (error) {
                    const code = errorCode(error);
                    const mismatch =
                      code === 'LIBFX_CHATGPT_SIGN_IN_STATE_MISMATCH' ||
                      code === 'LIBFX_GROK_SIGN_IN_STATE_MISMATCH';

                    if (!mismatch) {
                      finished = true;

                      complete.reject(error);
                    }

                    return {
                      response: new Response(
                        error instanceof Error
                          ? error.message
                          : 'Sign-in failed.',
                        { status: 400 },
                      ),
                      finish: !mismatch,
                    };
                  }
                }),
            });

            signal.throwIfAborted();
            emit({ ...base, kind: 'browser', address: started.url });

            break;
          } catch (error) {
            await listener?.close();

            listener = undefined;

            if (
              !(error instanceof LoopbackPortTaken) ||
              provider === 'codex' ||
              tries === 2
            ) {
              throw error;
            }
          }
        }

        credential = await complete.promise;
      } finally {
        signal.removeEventListener('abort', aborted);
      }
    }

    clearTimeout(timer);
    signal.throwIfAborted();

    const save = credentialSave(options, credential);

    if (
      !(await save.retry(options.attempt, options.signal)) &&
      !options.signal.aborted
    ) {
      return save;
    }
  } catch (error) {
    if (options.signal.aborted) {
      return;
    }

    if (signal.reason === expired) {
      options.emit(options.attempt, {
        ...base,
        kind: 'expired',
        message: expired.message,
      });
    } else if (
      error instanceof SecretStoreUnavailable ||
      error instanceof SecretStoreTimeout
    ) {
      emit({
        kind: error instanceof SecretStoreTimeout ? 'store_slow' : 'no_store',
        provider,
        store: store.name,
        message: error.message,
      });
    } else if (error instanceof LoopbackPortTaken && provider === 'codex') {
      emit({ kind: 'port_taken', provider, way: 'browser' });
    } else {
      const code = errorCode(error);
      const message =
        error instanceof Error ? error.message : 'Sign-in failed.';

      emit(
        code === 'LIBFX_CHATGPT_DEVICE_CODE_EXPIRED' ||
          code === 'LIBFX_GROK_DEVICE_CODE_EXPIRED'
          ? { ...base, kind: 'expired', message }
          : { ...base, kind: 'failure', code, message },
      );
    }
  } finally {
    clearTimeout(timer);
    await listener?.close();
  }
}
