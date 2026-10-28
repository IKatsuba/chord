import { describe, expect, test } from 'bun:test';
import {
  createResources,
  type ResourceCollectors,
} from '../../src/platform/resources.ts';
import { ResourceReadError } from '../../src/platform/resource_process.ts';

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
    const read = createResources({ collectors: readers(calls) });
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
    const read = createResources({ collectors: readers(calls) });
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
    const read = createResources({ collectors: readers(calls) });
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
    const read = createResources({
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
    const read = createResources({
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
    const read = createResources({
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
    const read = createResources({ collectors: 'fixture' });
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
});
