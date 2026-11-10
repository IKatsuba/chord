/** Cross-process refresh/sign-in/logout exclusion (CHD-485, Credentials). */
import { mkdir, realpath } from 'node:fs/promises';
import { join } from 'node:path';
import pLimit from 'p-limit';
import { lock } from 'proper-lockfile';
import { SECRET_TIMEOUT, type SecretProvider } from '../platform/secrets.ts';

const mutexes = new Map<string, ReturnType<typeof pLimit>>();

export class CredentialStoreBusy extends Error {
  constructor(readonly store: string) {
    super(`The ${store} is busy. It did not become available in 20 s.`);

    this.name = 'CredentialStoreBusy';
  }
}

/** Keeps a timed-out mutation's lock alive until its actual completion. */
export interface CredentialLock {
  track(completion: Promise<void>): void;
}

export async function withCredentialLock<T>(
  stateDir: string,
  provider: SecretProvider | 'selection',
  store: string,
  operation: (held: CredentialLock) => Promise<T>,
): Promise<T> {
  const root = join(stateDir, 'riff', 'credentials');

  await mkdir(root, { recursive: true });

  const file = join(await realpath(root), provider);
  let mutex = mutexes.get(file);

  if (mutex === undefined) {
    mutex = pLimit(1);

    mutexes.set(file, mutex);
  }

  let expired = false;
  const result = Promise.withResolvers<T>();
  const timer = setTimeout(() => {
    expired = true;

    result.reject(new CredentialStoreBusy(store));
  }, SECRET_TIMEOUT);

  void mutex(async () => {
    if (expired) {
      return;
    }

    // proper-lockfile owns retries, heartbeat and dead-holder recovery.
    // realpath:false permits a lock target that holds no credential file.
    const release = await lock(file, {
      realpath: false,
      retries: {
        forever: true,
        maxRetryTime: SECRET_TIMEOUT,
        minTimeout: 100,
        maxTimeout: 250,
        factor: 1,
      },
    });

    clearTimeout(timer);

    if (expired) {
      await release();

      return;
    }

    const pending: Promise<void>[] = [];
    let released = false;

    try {
      let value: T;

      try {
        value = await operation({ track: (done) => pending.push(done) });
      } catch (error) {
        result.reject(error);

        return;
      }

      if (pending.length === 0) {
        await release();

        released = true;
      }

      result.resolve(value);
    } finally {
      // The caller's bound cannot release another process into a store
      // write still running. Keep both locks, with the library's heartbeat.
      await Promise.allSettled(pending);

      if (!released) {
        await release();
      }
    }
  }).catch((error: unknown) => {
    clearTimeout(timer);
    result.reject(error);
  });

  return result.promise;
}
