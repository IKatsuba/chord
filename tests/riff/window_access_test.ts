import { describe, expect, spyOn, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { riffWindowAccess } from '../../src/riff/window_access.ts';
import { memorySecrets } from '../../src/platform/secrets.ts';

describe('riff window access boundary', () => {
  test.each(['', '1'])(
    'fake and QA (%s) never select the system store',
    async (qa) => {
      const access = riffWindowAccess(
        {
          CHORD_RIFF_FAKE_PROVIDER: 'http://127.0.0.1:23456',
          CHORD_RIFF_QA: qa,
          CHORD_RIFF_QA_STATE: 'signed-out',
        },
        () => {
          throw new Error('must not reach system store');
        },
      );

      expect(access.fixture).toBe(true);
      expect(access.run).toBeDefined();
      expect(await access.store.get('codex')).toBeNull();
      expect(
        await access.fetch('https://auth.x.ai/oauth2/revoke', {}),
      ).toBeInstanceOf(Response);
      await expect(
        access.fetch('https://example.invalid/unlisted', {}),
      ).rejects.toThrow('Unexpected fixture');
    },
  );

  test('production selects only the explicitly injected system backend', () => {
    const store = memorySecrets();
    const access = riffWindowAccess({}, () => store);

    expect(access.store).toBe(store);
    expect(access.fixture).toBeUndefined();
    expect(access.run).toBeUndefined();
  });
});

describe('tester: offline window sign-in effects', () => {
  test.each(['', '1'])(
    'fake/QA %s aborts both ways without network or system-store selection',
    async (qa) => {
      const root = await mkdtemp(join(tmpdir(), 'chord-offline-sign-in-'));
      const network = spyOn(globalThis, 'fetch').mockImplementation(
        Object.assign(
          () => {
            throw new Error('fixture must never reach the network');
          },
          {
            preconnect: () => {
              throw new Error('fixture must never preconnect');
            },
          },
        ),
      );
      let systemCalls = 0;

      try {
        for (const way of ['browser', 'code'] as const) {
          const access = riffWindowAccess(
            {
              CHORD_RIFF_FAKE_PROVIDER: 'http://127.0.0.1:23456',
              CHORD_RIFF_QA: qa,
              CHORD_RIFF_QA_STATE: 'signed-out',
              CHORD_RIFF_QA_SIGN_IN: 'waiting',
            },
            () => {
              systemCalls++;

              throw new Error('fixture must never select Bun.secrets');
            },
          );
          const controller = new AbortController();
          const steps: string[] = [];

          assert(access.run !== undefined);
          await access.run({
            attempt: 1,
            provider: 'grok',
            way,
            stateDir: root,
            store: access.store,
            fetch: access.fetch,
            signal: controller.signal,
            emit: (_id, step) => {
              steps.push(step.kind);
              controller.abort();
            },
          });
          expect(steps).toEqual([way]);
          expect(await access.store.get('grok')).toBeNull();
        }

        expect(systemCalls).toBe(0);
        expect(network).not.toHaveBeenCalled();
        expect(await readdir(root)).toEqual([]);
      } finally {
        network.mockRestore();
        await rm(root, { recursive: true, force: true });
      }
    },
  );
});
