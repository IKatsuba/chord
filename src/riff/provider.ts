/** Plan selection and libfx's credential callbacks (CHD-606, parts 3 and 4). */
import type {
  FxCodexProvider,
  FxGrokProvider,
  FxProviderCredentials,
} from 'libfx/node';
import type { SecretProvider } from '../platform/secrets.ts';
import {
  type CredentialCell,
  type CredentialLease,
  CredentialSignedOut,
} from './credentials.ts';

/** Prefer the last sign-in when still stored; resume uses its sidecar. */
export function providerOf(
  entries: {
    readonly codex: string | null;
    readonly grok: string | null;
  },
  record: SecretProvider | undefined = undefined,
): SecretProvider | undefined {
  if (record !== undefined && entries[record] !== null) {
    return record;
  }

  return entries.codex !== null
    ? 'codex'
    : entries.grok !== null
      ? 'grok'
      : undefined;
}

export function planProvider(cell: CredentialCell, provider: SecretProvider) {
  let held: CredentialLease | undefined;
  let failed: CredentialSignedOut | undefined;

  const authorized = async <T>(run: () => Promise<T>) => {
    try {
      return await run();
    } catch (error) {
      if (error instanceof CredentialSignedOut) {
        failed = error;
      }

      throw error;
    }
  };

  const options: FxCodexProvider | FxGrokProvider = {
    provider,
    credentials: () =>
      authorized(() =>
        held === undefined ? cell.locked((lease) => lease.read()) : held.read(),
      ),
    onCredentials: (next: FxProviderCredentials) =>
      authorized(() =>
        held === undefined
          ? cell.locked((lease) => lease.save(next))
          : held.save(next),
      ),
    refreshLock: (
      _: { provider: SecretProvider; sessionId?: string },
      refresh: () => Promise<void>,
    ) =>
      authorized(() =>
        cell.locked(async (lease) => {
          held = lease;

          try {
            await refresh();
          } catch (error) {
            const code =
              error instanceof Error && 'code' in error
                ? error.code
                : undefined;

            if (code === 'LIBFX_GROK_ACCOUNT_CHANGED') {
              await lease.invalidate('account_changed');
            }

            if (
              code === 'LIBFX_CHATGPT_REFRESH_FAILED' ||
              code === 'LIBFX_GROK_REFRESH_FAILED'
            ) {
              // The public code covers transient failures too. The owner's
              // rule preserves this entry; only an account change clears it.
              throw new CredentialSignedOut('signed_out');
            }

            throw error;
          } finally {
            held = undefined;
          }
        }),
      ),
  };

  return {
    options,
    failed: () => failed,
    reset: () => {
      failed = undefined;
    },
  };
}
