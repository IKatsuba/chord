/** riff's credential JSON, kept only in the system store (CHD-485, C1). */
import pLimit from 'p-limit';
import { resourceSourceMode } from './resource_fixture.ts';

export type SecretProvider = 'codex' | 'grok';

export const SECRET_SERVICE = 'chord.riff';
export const SECRET_TIMEOUT = 20_000;

/** The injected boundary; tests never use Bun's real credential store. */
export interface SecretBackend {
  get(options: { service: string; name: string }): Promise<string | null>;
  set(options: { service: string; name: string; value: string }): Promise<void>;
  delete(options: { service: string; name: string }): Promise<boolean>;
}

/** One opaque libfx credential JSON entry per provider. */
export interface Secrets {
  readonly name: string;
  get(provider: SecretProvider): Promise<string | null>;
  set(provider: SecretProvider, value: string): Promise<void>;
  delete(provider: SecretProvider): Promise<void>;
}

export function secretStoreName(platform = process.platform): string {
  switch (platform) {
    case 'darwin':
      return 'macOS Keychain';
    case 'win32':
      return 'Windows Credential Manager';
    default:
      return 'Secret Service';
  }
}

export class SecretStoreUnavailable extends Error {
  constructor(readonly store: string) {
    const missing =
      store === 'Secret Service'
        ? 'no Secret Service (gnome-keyring or KeePassXC). Start one and try again.'
        : store === 'macOS Keychain'
          ? 'no macOS Keychain. Unlock the login keychain in Keychain Access and try again.'
          : 'no Windows Credential Manager. Enable the Credential Manager service and try again.';

    super(
      `chord keeps your sign-in in the system's credential store, and none answered: ${missing}`,
    );

    this.name = 'SecretStoreUnavailable';
  }
}

export class SecretStoreTimeout extends Error {
  constructor(
    readonly store: string,
    /** Mutations still complete in order; hold their lock until this settles. */
    readonly completion: Promise<void>,
  ) {
    super(`The ${store} did not answer in 20 s.`);

    this.name = 'SecretStoreTimeout';
  }
}

// The ACP refusal already transports unavailable-store errors to the caller.
class FixtureStoreDisabled extends SecretStoreUnavailable {
  constructor(store: string) {
    super(store);

    this.message = 'System credential access is disabled in fixture runs.';
  }
}

// Shared by every wrapper, not one queue per session or provider. A timeout
// must never let a second Bun.secrets call overtake the one still running.
const serial = pLimit(1);

/** No default backend: the caller must explicitly choose real or fixture. */
export function secrets(backend: SecretBackend, name: string): Secrets {
  let answered = false;

  const call = <T>(read: boolean, operation: () => Promise<T>): Promise<T> => {
    let expired = false;
    const result = serial(async () => {
      if (read && expired) {
        throw new SecretStoreTimeout(name, Promise.resolve());
      }

      try {
        const value = await operation();

        answered = true;

        return value;
      } catch {
        // Store errors may quote the supplied secret. Only our own words
        // leave this boundary, including a mutation that completes late.
        throw answered
          ? new Error(`The ${name} could not complete the sign-in operation.`)
          : new SecretStoreUnavailable(name);
      }
    });

    const completion = result.then(() => {});

    // A timed-out caller may ignore late completion. Keep its rejection
    // handled while allowing a lock owner to await it explicitly.
    void completion.catch(() => {});

    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        expired = true;

        reject(new SecretStoreTimeout(name, completion));
      }, SECRET_TIMEOUT);

      void result.then(
        (value) => {
          clearTimeout(timer);

          if (!expired) {
            resolve(value);
          }
        },
        (error: unknown) => {
          clearTimeout(timer);
          reject(error);
        },
      );
    });
  };

  return {
    name,
    get: (provider) =>
      call(true, () =>
        backend.get({ service: SECRET_SERVICE, name: provider }),
      ),
    set: (provider, value) =>
      call(false, () =>
        backend.set({ service: SECRET_SERVICE, name: provider, value }),
      ),
    delete: (provider) =>
      call(false, async () => {
        await backend.delete({ service: SECRET_SERVICE, name: provider });
      }),
  };
}

/** Only production's explicit store selection reaches Bun.secrets. */
export function systemSecrets(
  backend: () => SecretBackend = () => Bun.secrets,
): Secrets {
  const name = secretStoreName();
  let selected: Secrets | undefined;

  const current = () => {
    if (
      resourceSourceMode(process.env['CHORD_RESOURCE_FIXTURE']) === 'fixture'
    ) {
      throw new FixtureStoreDisabled(name);
    }

    return (selected ??= secrets(backend(), name));
  };

  // A non-riff window can offer /login without selecting any system backend.
  return {
    name,
    get: async (provider) => await current().get(provider),
    set: async (provider, value) => await current().set(provider, value),
    delete: async (provider) => await current().delete(provider),
  };
}

/** Tests and QA share the same serialization and deadline as production. */
export function memorySecrets(
  entries: Partial<Record<SecretProvider, string>> = {},
): Secrets {
  const values = new Map(Object.entries(entries));

  return secrets(
    {
      get: ({ name }) => Promise.resolve(values.get(name) ?? null),
      set: ({ name, value }) => {
        values.set(name, value);

        return Promise.resolve();
      },
      delete: ({ name }) => Promise.resolve(values.delete(name)),
    },
    secretStoreName(),
  );
}
