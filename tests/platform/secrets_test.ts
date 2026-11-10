import { afterEach, describe, expect, jest, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  memorySecrets,
  SECRET_SERVICE,
  SECRET_TIMEOUT,
  secrets,
  systemSecrets,
  secretStoreName,
  SecretStoreTimeout,
  SecretStoreUnavailable,
  type SecretBackend,
} from '../../src/platform/secrets.ts';

const flush = async () => {
  for (let step = 0; step < 20; step++) {
    await Promise.resolve();
  }
};

const backend = (get: SecretBackend['get']): SecretBackend => ({
  get,
  set: () => Promise.resolve(),
  delete: () => Promise.resolve(true),
});

test('fixture mode refuses every system operation before selecting its backend', async () => {
  let calls = 0;

  expect(process.env['CHORD_RESOURCE_FIXTURE']).toBe('true');

  const store = systemSecrets(() => {
    calls++;

    throw new Error('The system backend must never be selected.');
  });

  expect(calls).toBe(0);

  for (const operation of [
    () => store.get('codex'),
    () => store.set('codex', 'fixture'),
    () => store.delete('codex'),
  ]) {
    await expect(operation()).rejects.toThrow(
      'System credential access is disabled in fixture runs.',
    );
  }

  expect(calls).toBe(0);
});

describe('CHD-606 tester: late credential-store failures', () => {
  test.each(['set', 'delete'] as const)(
    'a late rejected %s stays serial, sanitizes its error and allows the next call',
    async (operation) => {
      jest.useFakeTimers();

      const gate = Promise.withResolvers<never>();
      const calls: string[] = [];
      const store = secrets(
        {
          get: () => {
            calls.push('get');

            return Promise.resolve(null);
          },
          set: () => {
            calls.push('set');

            return gate.promise;
          },
          delete: () => {
            calls.push('delete');

            return gate.promise;
          },
        },
        'macOS Keychain',
      );

      await store.get('codex');

      const mutation =
        operation === 'set'
          ? store.set('codex', 'fixture credential')
          : store.delete('codex');
      const result = mutation.catch((error: unknown) => error);

      await flush();
      jest.advanceTimersByTime(SECRET_TIMEOUT);

      const timeout: unknown = await result;

      assert(timeout instanceof SecretStoreTimeout);

      const completion = timeout.completion.catch((error: unknown) => error);
      const following = store.get('grok');

      await flush();
      expect(calls).toEqual(['get', operation]);
      gate.reject(new Error('fixture credential backend detail'));

      const failure: unknown = await completion;

      assert(failure instanceof Error);
      expect(failure).not.toBeInstanceOf(SecretStoreUnavailable);
      expect(failure.message).toBe(
        'The macOS Keychain could not complete the sign-in operation.',
      );
      expect(failure.message).not.toContain('fixture credential');
      expect(await following).toBeNull();
      expect(calls).toEqual(['get', operation, 'get']);
      expect(await result).toBe(timeout);
    },
  );

  test('a first-call delete rejected after its bound reports unavailable and releases the queue', async () => {
    jest.useFakeTimers();

    const gate = Promise.withResolvers<boolean>();
    const store = secrets(
      {
        get: () => Promise.resolve(null),
        set: () => Promise.resolve(),
        delete: () => gate.promise,
      },
      'Secret Service',
    );
    const result = store.delete('grok').catch((error: unknown) => error);

    await flush();
    jest.advanceTimersByTime(SECRET_TIMEOUT);

    const timeout: unknown = await result;

    assert(timeout instanceof SecretStoreTimeout);

    const completion = timeout.completion.catch((error: unknown) => error);

    gate.reject(new Error('fixture backend credential'));

    const failure: unknown = await completion;

    assert(failure instanceof SecretStoreUnavailable);
    expect(failure.message).toContain('no Secret Service');
    expect(failure.message).not.toContain('fixture backend');
    expect(await store.get('grok')).toBeNull();
  });
});

afterEach(() => jest.useRealTimers());

describe('riff secrets queue', () => {
  test('one entry per provider, one service, with opaque libfx JSON', async () => {
    const store = memorySecrets();
    const value = JSON.stringify({
      accessToken: 'fixture',
      refreshToken: 'next',
    });

    await store.set('codex', value);
    expect(await store.get('codex')).toBe(value);
    expect(await store.get('grok')).toBeNull();
    await store.delete('codex');
    expect(await store.get('codex')).toBeNull();

    const requests: unknown[] = [];
    const recording = secrets(
      backend((options) => {
        requests.push(options);

        return Promise.resolve(null);
      }),
      'Secret Service',
    );

    await recording.get('grok');
    expect(requests).toEqual([{ service: SECRET_SERVICE, name: 'grok' }]);
  });

  test('names the system store on each platform', () => {
    expect(secretStoreName('darwin')).toBe('macOS Keychain');
    expect(secretStoreName('linux')).toBe('Secret Service');
    expect(secretStoreName('win32')).toBe('Windows Credential Manager');
  });

  test('bounds a read at 20 seconds and drops its late answer', async () => {
    jest.useFakeTimers();

    const gate = Promise.withResolvers<string | null>();
    const store = secrets(
      backend(() => gate.promise),
      'macOS Keychain',
    );
    const result = store.get('codex').catch((error: unknown) => error);

    await flush();
    jest.advanceTimersByTime(SECRET_TIMEOUT - 1);

    let finished = false;

    void result.then(() => {
      finished = true;
    });

    await flush();
    expect(finished).toBe(false);
    jest.advanceTimersByTime(1);

    const error: unknown = await result;

    assert(error instanceof SecretStoreTimeout);
    expect(error.message).toBe('The macOS Keychain did not answer in 20 s.');
    gate.resolve('late fixture');
    await error.completion;
    expect(await result).toBe(error);
  });

  test('shares serialization across wrappers and skips expired queued reads', async () => {
    jest.useFakeTimers();

    const gate = Promise.withResolvers<string | null>();
    const calls: string[] = [];
    const first = secrets(
      backend(() => {
        calls.push('first');

        return gate.promise;
      }),
      'Secret Service',
    );
    const second = secrets(
      backend(() => {
        calls.push('second');

        return Promise.resolve(null);
      }),
      'Secret Service',
    );
    const results = [first.get('codex'), second.get('grok')].map((result) =>
      result.catch((error: unknown) => error),
    );

    await flush();
    expect(calls).toEqual(['first']);
    jest.advanceTimersByTime(SECRET_TIMEOUT);
    expect(
      (await Promise.all(results)).every(
        (x) => x instanceof SecretStoreTimeout,
      ),
    ).toBe(true);
    gate.resolve(null);
    await flush();
    expect(calls).toEqual(['first']);
    await second.get('grok');
    expect(calls).toEqual(['first', 'second']);
  });

  test('a timed-out write stays queued before delete and reports late completion', async () => {
    jest.useFakeTimers();

    const gate = Promise.withResolvers<string | null>();
    const calls: string[] = [];
    const store = secrets(
      {
        get: () => gate.promise,
        set: () => {
          calls.push('set');

          return Promise.resolve();
        },
        delete: () => {
          calls.push('delete');

          return Promise.resolve(true);
        },
      },
      'Secret Service',
    );
    const read = store.get('codex').catch((error: unknown) => error);
    const write = store
      .set('codex', 'fixture')
      .catch((error: unknown) => error);
    const removed = store.delete('codex').catch((error: unknown) => error);

    await flush();
    jest.advanceTimersByTime(SECRET_TIMEOUT);

    const errors: unknown[] = await Promise.all([read, write, removed]);

    expect(calls).toEqual([]);
    gate.resolve(null);

    for (const error of errors) {
      assert(error instanceof SecretStoreTimeout);
      await error.completion;
    }

    expect(calls).toEqual(['set', 'delete']);
  });

  test('first-call failure names the missing store and remedy without backend text', async () => {
    const store = secrets(
      backend(() => Promise.reject(new Error('private fixture value'))),
      'Secret Service',
    );
    const error: unknown = await store
      .get('codex')
      .catch((caught: unknown) => caught);

    assert(error instanceof SecretStoreUnavailable);
    expect(error.store).toBe('Secret Service');
    expect(error.message).toContain(
      'no Secret Service (gnome-keyring or KeePassXC)',
    );
    expect(error.message).toContain('Start one and try again.');
    expect(error.message).not.toContain('private fixture');
  });
});
