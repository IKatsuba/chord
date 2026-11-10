import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:net';
import { loopback, LoopbackPortTaken } from '../../src/platform/loopback.ts';
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
