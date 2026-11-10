/** A process's credential chain, compared against the store on every save. */
import { z } from '@zod/zod';
import type { FxProviderCredentials } from 'libfx/node';
import {
  type Secrets,
  type SecretProvider,
  SecretStoreTimeout,
} from '../platform/secrets.ts';
import { type CredentialLock, withCredentialLock } from './credential_lock.ts';

const CREDENTIAL = z.object({
  accessToken: z.string().min(1),
  refreshToken: z.string().min(1).optional(),
  accountId: z.string().min(1),
  expiresAt: z.number().finite().optional(),
});

export type CredentialState =
  'unsaved' | 'saved' | 'signed_out' | 'account_changed';

export class CredentialSignedOut extends Error {
  constructor(readonly state: 'signed_out' | 'account_changed') {
    super('Sign in to a plan for riff.');

    this.name = 'CredentialSignedOut';
  }
}

/** Parses only libfx's public credential shape; accountId comes from libfx. */
export function credentialOf(raw: string): FxProviderCredentials & {
  accountId: string;
} {
  try {
    const value = CREDENTIAL.parse(JSON.parse(raw));

    return {
      accessToken: value.accessToken,
      ...(value.refreshToken === undefined
        ? {}
        : { refreshToken: value.refreshToken }),
      accountId: value.accountId,
      ...(value.expiresAt === undefined ? {} : { expiresAt: value.expiresAt }),
    };
  } catch {
    throw new CredentialSignedOut('signed_out');
  }
}

/** The callbacks libfx uses inside its refreshLock. Never nest this lock. */
export interface CredentialLease {
  read(): Promise<FxProviderCredentials>;
  save(next: FxProviderCredentials): Promise<void>;
  /** Invalid refreshes clear only the chain this process read. */
  invalidate(state: 'signed_out' | 'account_changed'): Promise<never>;
}

export interface CredentialCell {
  readonly account: string | undefined;
  /** Prompt admission reads once outside the refresh lock, per L2. */
  check(): Promise<FxProviderCredentials>;
  locked<T>(run: (lease: CredentialLease) => Promise<T>): Promise<T>;
  logout(): Promise<void>;
}

export function credentialCell(
  store: Secrets,
  stateDir: string,
  provider: SecretProvider,
  notify: (state: CredentialState) => void = () => {},
): CredentialCell {
  let account: string | undefined;
  let expected: string | undefined;
  let pending: FxProviderCredentials | undefined;
  let ended: CredentialSignedOut | undefined;

  const refuse = (state: 'signed_out' | 'account_changed'): never => {
    ended = new CredentialSignedOut(state);
    pending = undefined;

    notify(state);

    throw ended;
  };

  const checked = (raw: string | null) => {
    if (ended !== undefined) {
      throw ended;
    }

    if (raw === null) {
      return refuse('signed_out');
    }

    const value = credentialOf(raw);

    if (account !== undefined && value.accountId !== account) {
      return refuse('account_changed');
    }

    account ??= value.accountId;

    return value;
  };

  const save = async (held: CredentialLock, next: FxProviderCredentials) => {
    if (ended !== undefined) {
      throw ended;
    }

    const value = credentialOf(JSON.stringify(next));
    let raw: string | null;

    try {
      raw = await store.get(provider);
    } catch {
      pending = value;

      notify('unsaved');

      return;
    }

    checked(raw);

    if (value.accountId !== account) {
      refuse('account_changed');
    }

    const json = JSON.stringify(value);

    if (raw === json) {
      expected = raw;
      pending = undefined;

      notify('saved');

      return;
    }

    if (expected === undefined || raw !== expected) {
      refuse('signed_out');
    }

    pending = value;

    const saved = () => {
      expected = json;
      pending = undefined;

      notify('saved');
    };

    try {
      await store.set(provider, json);
      saved();
    } catch (error) {
      notify('unsaved');

      if (error instanceof SecretStoreTimeout) {
        const completion = error.completion.then(saved);

        held.track(completion);
      }

      // libfx must keep using the newly rotated credential even though
      // persistence failed. The next locked read retries this rotation.
    }
  };

  return {
    get account() {
      return account;
    },
    check: async () => checked(await store.get(provider)),
    locked: (run) =>
      withCredentialLock(stateDir, provider, store.name, (held) =>
        run({
          read: async () => {
            if (pending !== undefined) {
              await save(held, pending);
            }

            const raw = await store.get(provider);
            const value = checked(raw);

            expected = raw ?? undefined;

            return pending ?? value;
          },
          save: (next) => save(held, next),
          invalidate: async (state) => {
            const raw = await store.get(provider);

            checked(raw);

            if (raw === expected) {
              try {
                await store.delete(provider);
              } catch (error) {
                if (error instanceof SecretStoreTimeout) {
                  held.track(error.completion);
                }

                throw error;
              }
            }

            return refuse(state);
          },
        }),
      ),
    logout: () =>
      withCredentialLock(stateDir, provider, store.name, async (held) => {
        try {
          await store.delete(provider);
        } catch (error) {
          if (error instanceof SecretStoreTimeout) {
            held.track(error.completion);
          }

          throw error;
        }

        refuse('signed_out');
      }).catch((error: unknown) => {
        if (!(error instanceof CredentialSignedOut)) {
          throw error;
        }
      }),
  };
}
