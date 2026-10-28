import { describe, expect, test } from 'bun:test';
import { existsSync, readFileSync } from 'node:fs';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { setImmediate } from 'node:timers/promises';
import { collectCodexResources } from '../../src/session/codex_resources.ts';
import {
  createResources,
  type ResourceCollectors,
} from '../../src/platform/resources.ts';
import {
  COLLECTOR_BOUNDS,
  ResourceReadError,
} from '../../src/platform/resource_process.ts';
import { until } from '../session/conversation_fake.ts';

const place = { cwd: '/fixture/project', commandOf: () => undefined };

function readers(
  calls: string[],
  read: ResourceCollectors['read'] = (provider) =>
    Promise.resolve({
      agent: provider,
      windows: [
        {
          name: 'primary',
          usedPercent: 0,
          windowSeconds: 18000,
          resetsAt: null,
          models: null,
        },
      ],
    }),
): ResourceCollectors {
  return {
    resolve: (provider, cwd, customCommand) => {
      calls.push(`resolve:${provider}:${cwd}`);

      return Promise.resolve(
        customCommand
          ? { unavailable: 'Custom command association is unverified.' }
          : { path: '/fixture/provider', version: '1' },
      );
    },
    read: (provider, path, cwd, signal) => {
      calls.push(`read:${provider}:${cwd}`);

      return read(provider, path, cwd, signal);
    },
  };
}

describe('limits read', () => {
  test('omitted agents read claude and codex in parallel, each in the place', async () => {
    const calls: string[] = [];
    const { read } = createResources({ collectors: readers(calls) });
    const answer = await read(undefined, place, new AbortController().signal);

    expect(Date.parse(answer.readAt)).not.toBeNaN();
    expect(answer.providers.map((provider) => provider.agent)).toEqual([
      'claude',
      'codex',
    ]);
    expect(answer.providers[1]).toEqual({
      agent: 'codex',
      windows: [
        {
          name: 'primary',
          usedPercent: 0,
          windowSeconds: 18000,
          resetsAt: null,
          models: null,
        },
      ],
    });
    expect(calls.sort()).toEqual([
      'read:claude:/fixture/project',
      'read:codex:/fixture/project',
      'resolve:claude:/fixture/project',
      'resolve:codex:/fixture/project',
    ]);
  });

  test('a filter reads only its agents once each; [] reads none; others have no reader', async () => {
    const calls: string[] = [];
    const { read } = createResources({ collectors: readers(calls) });
    const signal = new AbortController().signal;

    expect((await read([], place, signal)).providers).toEqual([]);
    expect(
      (await read(['other', 'codex', 'codex'], place, signal)).providers.map(
        (provider) =>
          'unavailable' in provider
            ? [provider.agent, provider.unavailable]
            : [provider.agent],
      ),
    ).toEqual([['other', 'No limits reader for this runtime.'], ['codex']]);
    expect(calls).toEqual([
      'resolve:codex:/fixture/project',
      'read:codex:/fixture/project',
    ]);
  });

  test('a custom ACP command is unavailable without a provider read', async () => {
    const calls: string[] = [];
    const { read } = createResources({ collectors: readers(calls) });
    const answer = await read(
      ['codex'],
      { cwd: '/fixture/project', commandOf: () => ['custom-acp'] },
      new AbortController().signal,
    );

    expect(answer.providers).toEqual([
      {
        agent: 'codex',
        unavailable: 'Custom command association is unverified.',
      },
    ]);
    expect(calls).toEqual(['resolve:codex:/fixture/project']);
  });

  test('a provider past the timeout is reported and the others still answer', async () => {
    const { read } = createResources({
      collectors: readers([], (provider, _path, _cwd, signal) =>
        provider === 'claude'
          ? new Promise((_, reject) =>
              signal.addEventListener('abort', () => reject(signal.reason)),
            )
          : Promise.resolve({ agent: 'codex', windows: [] }),
      ),
      timeoutMs: 50,
    });
    const answer = await read(undefined, place, new AbortController().signal);

    expect(answer.providers).toEqual([
      { agent: 'claude', unavailable: 'Timed out after 0.05 s.' },
      { agent: 'codex', windows: [] },
    ]);
  });

  test('a reader failure says its fixed reason; anything else a plain one', async () => {
    const { read } = createResources({
      collectors: readers([], (provider) =>
        Promise.reject(
          provider === 'claude'
            ? new ResourceReadError('protocol', 'The worker failed.')
            : new Error('private detail'),
        ),
      ),
    });
    const answer = await read(undefined, place, new AbortController().signal);

    expect(answer.providers).toEqual([
      { agent: 'claude', unavailable: 'The worker failed.' },
      { agent: 'codex', unavailable: 'The limits could not be read.' },
    ]);
  });

  test("the caller's cancellation rejects the read", async () => {
    const controller = new AbortController();
    const { read } = createResources({
      collectors: readers([], (_provider, _path, _cwd, signal) => {
        controller.abort(new Error('Caller cancelled.'));

        return new Promise((_, reject) =>
          signal.addEventListener('abort', () => reject(signal.reason)),
        );
      }),
    });

    await expect(read(['codex'], place, controller.signal)).rejects.toThrow(
      'Caller cancelled.',
    );
  });

  test('fixture mode never resolves installed providers, even for claude and codex', async () => {
    const { read } = createResources({ collectors: 'fixture' });
    const answer = await read(
      undefined,
      { cwd: '/fixture/project', commandOf: () => 'never-launch-this-wrapper' },
      new AbortController().signal,
    );

    expect(
      answer.providers.map(
        (provider) => 'windows' in provider && provider.windows[0]?.usedPercent,
      ),
    ).toEqual([12.345, 12.345]);
  });

  test('close waits for a reader still cleaning up past its timeout, and reports its cleanup failure', async () => {
    const cleaned = Promise.withResolvers<void>();
    let closed = false;
    const resources = createResources({
      collectors: readers(
        [],
        (_provider, _path, _cwd, signal) =>
          new Promise((_, reject) =>
            signal.addEventListener('abort', () => {
              void cleaned.promise.then(() =>
                reject(
                  new ResourceReadError(
                    'cleanup',
                    'Owned group exit unverified.',
                  ),
                ),
              );
            }),
          ),
      ),
      timeoutMs: 50,
    });

    expect(
      (await resources.read(['codex'], place, new AbortController().signal))
        .providers,
    ).toEqual([{ agent: 'codex', unavailable: 'Timed out after 0.05 s.' }]);

    const closing = resources.close().then((failures) => {
      closed = true;

      return failures;
    });

    // Every microtask has run: a close that did not wait has resolved.
    await setImmediate();

    expect(closed).toBe(false);

    cleaned.resolve();

    expect(await closing).toEqual(['Owned group exit unverified.']);
  });

  test("close outlives a cancelled provider's real process group until it is gone", async () => {
    const directory = await mkdtemp(join(tmpdir(), 'chord-resource-close-'));
    const file = join(directory, 'events.jsonl');
    const fixture = new URL('../fixtures/resource_provider.ts', import.meta.url)
      .pathname;
    const resources = createResources({
      collectors: readers([], (_provider, _path, cwd, signal) =>
        collectCodexResources([process.execPath, fixture, 'stubborn', file], {
          cwd,
          signal,
          bounds: {
            ...COLLECTOR_BOUNDS,
            closeMs: 100,
            termMs: 300,
            killMs: 1500,
          },
        }),
      ),
    });
    const controller = new AbortController();

    try {
      const answer = resources.read(
        ['codex'],
        { cwd: directory, commandOf: () => undefined },
        controller.signal,
      );

      answer.catch(() => {});

      await until(
        () =>
          existsSync(file) && readFileSync(file, 'utf8').includes('descendant'),
      );
      controller.abort(new Error('Call cancelled.'));
      await expect(answer).rejects.toThrow('Call cancelled.');
      await resources.close();

      for (const line of (await readFile(file, 'utf8')).trim().split('\n')) {
        const entry = JSON.parse(line) as { pid?: number; descendant?: number };
        const pid = entry.pid ?? entry.descendant;

        if (pid !== undefined) {
          expect(() => process.kill(pid, 0)).toThrow();
        }
      }
    } finally {
      await resources.close();
      await rm(directory, { recursive: true, force: true });
    }
  });
});
