import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:net';
import { loopback, LoopbackPortTaken } from '../../src/platform/loopback.ts';
import { serve } from '../../src/platform/serve.ts';
import type { Served } from '../../src/platform/serve.ts';

const callback = () =>
  Promise.resolve({ response: new Response('Signed in.'), finish: true });

describe('sign-in loopback listener', () => {
  test('only GET at the callback path finishes; a rejected state keeps waiting', async () => {
    const seen: string[] = [];
    const server = await loopback({
      port: 0,
      path: '/callback',
      signal: new AbortController().signal,
      callback: (request) => {
        const state = new URL(request.url).searchParams.get('state') ?? '';

        seen.push(state);

        return Promise.resolve({
          response: new Response(state, {
            status: state === 'current' ? 200 : 400,
          }),
          finish: state === 'current',
        });
      },
    });
    const address = `http://127.0.0.1:${server.port}`;

    try {
      expect(server.port).not.toBe(1455);
      expect((await fetch(`${address}/other`)).status).toBe(404);
      expect(
        (await fetch(`${address}/callback`, { method: 'POST' })).status,
      ).toBe(404);
      expect((await fetch(`${address}/callback?state=old`)).status).toBe(400);
      expect(
        await (await fetch(`${address}/callback?state=current`)).text(),
      ).toBe('current');
      expect(seen).toEqual(['old', 'current']);
    } finally {
      await server.close();
    }

    await expect(fetch(address)).rejects.toThrow();
  });

  test('abort and explicit leaving close both families', async () => {
    for (const action of ['abort', 'leave']) {
      const controller = new AbortController();
      const server = await loopback({
        port: 0,
        path: '/callback',
        signal: controller.signal,
        callback,
      });

      if (action === 'abort') {
        controller.abort();
      }

      await server.close();

      const replacement = await loopback({
        port: server.port,
        path: '/callback',
        signal: new AbortController().signal,
        callback,
      });

      await replacement.close();
    }
  });

  test('an occupied v4 random port is port taken', async () => {
    const occupied = createServer();

    await new Promise<void>((resolve) =>
      occupied.listen(0, '127.0.0.1', resolve),
    );

    const address = occupied.address();

    assert(address !== null && typeof address !== 'string');

    try {
      await expect(
        loopback({
          port: address.port,
          path: '/callback',
          signal: new AbortController().signal,
          callback,
        }),
      ).rejects.toBeInstanceOf(LoopbackPortTaken);
    } finally {
      await new Promise<void>((resolve, reject) =>
        occupied.close((error) => (error ? reject(error) : resolve())),
      );
    }
  });

  test.each(['EADDRINUSE', 'EACCES', 'EAFNOSUPPORT', 'EADDRNOTAVAIL'])(
    'v6 %s closes v4 on failure and preserves it without IPv6',
    async (code) => {
      const events: string[] = [];
      const failure = Object.assign(new Error('fixture bind failure'), {
        code,
      });
      const pending = loopback(
        {
          port: 0,
          path: '/callback',
          signal: new AbortController().signal,
          callback,
        },
        (options): Served => {
          events.push(`bind ${options.hostname}`);

          if (options.hostname === '::1') {
            throw failure;
          }

          return {
            port: 23456,
            close: () => {
              events.push('close v4');

              return Promise.resolve();
            },
          };
        },
      );

      if (code === 'EADDRINUSE' || code === 'EACCES') {
        await expect(pending).rejects.toBeInstanceOf(
          code === 'EADDRINUSE' ? LoopbackPortTaken : Error,
        );
        expect(events).toEqual(['bind 127.0.0.1', 'bind ::1', 'close v4']);
      } else {
        const server = await pending;

        expect(events).toEqual(['bind 127.0.0.1', 'bind ::1']);
        await server.close();
      }
    },
  );

  test('a cancelled attempt does not bind', async () => {
    const controller = new AbortController();

    controller.abort();

    await expect(
      loopback(
        { port: 0, path: '/callback', signal: controller.signal, callback },
        () => {
          throw new Error('must not bind');
        },
      ),
    ).rejects.toThrow();
  });
});

describe('tester: sign-in listener boundaries', () => {
  test.each(['abort', 'finish'])(
    '%s automatically closes both listeners without caller cleanup',
    async (action) => {
      const controller = new AbortController();
      const closed: string[] = [];
      const completions: Promise<void>[] = [];
      const server = await loopback(
        {
          port: 0,
          path: '/callback',
          signal: controller.signal,
          callback,
        },
        (options, handler) => {
          const listener = serve(options, handler);
          const completion = Promise.withResolvers<void>();

          completions.push(completion.promise);

          return {
            port: listener.port,
            close: async () => {
              await listener.close();
              closed.push(options.hostname);
              completion.resolve();
            },
          };
        },
      );

      try {
        expect(server.port).not.toBe(1455);
        expect(completions).toHaveLength(2);

        if (action === 'abort') {
          controller.abort();
        } else {
          const response = await fetch(`http://[::1]:${server.port}/callback`);

          expect(await response.text()).toBe('Signed in.');
        }

        await Promise.all(completions);
        expect(closed.sort()).toEqual(['127.0.0.1', '::1']);

        const replacement = await loopback({
          port: server.port,
          path: '/callback',
          signal: new AbortController().signal,
          callback,
        });

        await replacement.close();
      } finally {
        await server.close();
      }
    },
    5000,
  );

  test('a port occupied on IPv6 alone releases the attempted IPv4 listener', async () => {
    const occupied = createServer();

    await new Promise<void>((resolve, reject) => {
      occupied.once('error', reject);
      occupied.listen({ host: '::1', port: 0, ipv6Only: true }, resolve);
    });

    const address = occupied.address();

    assert(address !== null && typeof address !== 'string');

    try {
      expect(address.port).not.toBe(1455);
      await expect(
        loopback({
          port: address.port,
          path: '/callback',
          signal: new AbortController().signal,
          callback,
        }),
      ).rejects.toMatchObject({
        name: 'LoopbackPortTaken',
        port: address.port,
      });

      const replacement = createServer();

      try {
        await new Promise<void>((resolve, reject) => {
          replacement.once('error', reject);
          replacement.listen(address.port, '127.0.0.1', resolve);
        });

        expect(replacement.listening).toBe(true);
        expect(occupied.listening).toBe(true);
      } finally {
        await new Promise<void>((resolve, reject) =>
          replacement.close((error) => (error ? reject(error) : resolve())),
        );
      }
    } finally {
      await new Promise<void>((resolve, reject) =>
        occupied.close((error) => (error ? reject(error) : resolve())),
      );
    }
  });

  test('cancellation during the second bind closes both listeners and rejects', async () => {
    const controller = new AbortController();
    const closed: string[] = [];

    await expect(
      loopback(
        { port: 0, path: '/callback', signal: controller.signal, callback },
        (options) => {
          if (options.hostname === '::1') {
            controller.abort();
          }

          return {
            port: 23456,
            close: () => {
              closed.push(options.hostname);

              return Promise.resolve();
            },
          };
        },
      ),
    ).rejects.toThrow();
    expect(closed).toEqual(['127.0.0.1', '::1']);
  });

  test('cancelling one attempt leaves another waiting through stale states', async () => {
    const firstController = new AbortController();
    const first = await loopback({
      port: 0,
      path: '/callback',
      signal: firstController.signal,
      callback,
    });
    const seen: string[] = [];
    const second = await loopback({
      port: 0,
      path: '/callback',
      signal: new AbortController().signal,
      callback: (request) => {
        const state = new URL(request.url).searchParams.get('state') ?? '';

        seen.push(state);

        return Promise.resolve({
          response: new Response(state, { status: 400 }),
          finish: false,
        });
      },
    });

    try {
      expect(first.port).not.toBe(second.port);
      expect(second.port).not.toBe(1455);
      firstController.abort();

      for (const host of ['127.0.0.1', '[::1]']) {
        const response = await fetch(
          `http://${host}:${second.port}/callback?state=stale`,
        );

        expect(response.status).toBe(400);
        expect(await response.text()).toBe('stale');
      }

      expect(seen).toEqual(['stale', 'stale']);
    } finally {
      await Promise.all([first.close(), second.close()]);
    }
  });
});
