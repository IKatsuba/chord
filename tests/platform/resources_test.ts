import { describe, expect, jest, test } from 'bun:test';
import { existsSync, readFileSync } from 'node:fs';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { setImmediate } from 'node:timers/promises';
import type { ProviderLimits } from '../../src/session/budgets.ts';
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

describe('tester: per-call limits concurrency and cancellation', () => {
  test('both provider waits start before either answers and completion order does not reorder providers', async () => {
    const gates = {
      claude: Promise.withResolvers<ProviderLimits>(),
      codex: Promise.withResolvers<ProviderLimits>(),
    };
    const calls: string[] = [];
    const resources = createResources({
      collectors: readers(calls, (provider) => gates[provider].promise),
    });
    let completed = false;
    const pending = resources
      .read(undefined, place, new AbortController().signal)
      .then((answer) => {
        completed = true;

        return answer;
      });

    try {
      await until(
        () => calls.filter((call) => call.startsWith('read:')).length === 2,
      );
      gates.codex.resolve({ agent: 'codex', windows: [] });
      await setImmediate();
      expect(completed).toBe(false);
      gates.claude.resolve({
        agent: 'claude',
        unavailable: 'Fixture unavailable.',
      });
      expect((await pending).providers).toEqual([
        { agent: 'claude', unavailable: 'Fixture unavailable.' },
        { agent: 'codex', windows: [] },
      ]);
    } finally {
      gates.claude.resolve({ agent: 'claude', windows: [] });
      gates.codex.resolve({ agent: 'codex', windows: [] });
      await pending;
      await resources.close();
    }
  });

  test('a repeated call resolves and reads again with a new timestamp and independent windows', async () => {
    jest.useFakeTimers({ now: Date.parse('2026-10-28T12:00:00Z') });

    const calls: string[] = [];
    let reads = 0;
    const resources = createResources({
      collectors: readers(calls, (agent) =>
        Promise.resolve({
          agent,
          windows: [
            {
              name: 'primary',
              usedPercent: ++reads,
              windowSeconds: null,
              resetsAt: null,
              models: null,
            },
          ],
        }),
      ),
    });

    try {
      const first = await resources.read(
        ['codex'],
        place,
        new AbortController().signal,
      );

      jest.advanceTimersByTime(1000);

      const second = await resources.read(
        ['codex'],
        place,
        new AbortController().signal,
      );

      expect(first.readAt).toBe('2026-10-28T12:00:00.000Z');
      expect(second.readAt).toBe('2026-10-28T12:00:01.000Z');
      expect(first.providers).toMatchObject([
        { windows: [{ usedPercent: 1 }] },
      ]);
      expect(second.providers).toMatchObject([
        { windows: [{ usedPercent: 2 }] },
      ]);
      expect(calls.filter((call) => call.startsWith('resolve:'))).toHaveLength(
        2,
      );
      expect(calls.filter((call) => call.startsWith('read:'))).toHaveLength(2);
    } finally {
      await resources.close();
      jest.useRealTimers();
    }
  });

  test('default provider deadlines run together for ten seconds and late answers cannot replace timeouts', async () => {
    jest.useFakeTimers({ now: 0 });

    const gates = {
      claude: Promise.withResolvers<ProviderLimits>(),
      codex: Promise.withResolvers<ProviderLimits>(),
    };
    const signals: AbortSignal[] = [];
    const resources = createResources({
      collectors: readers([], (provider, _path, _cwd, signal) => {
        signals.push(signal);

        return gates[provider].promise;
      }),
    });
    let completed = false;
    const pending = resources
      .read(undefined, place, new AbortController().signal)
      .then((answer) => {
        completed = true;

        return answer;
      });

    try {
      await setImmediate();
      expect(signals).toHaveLength(2);
      jest.advanceTimersByTime(9999);
      await setImmediate();
      expect(completed).toBe(false);
      expect(signals.every((signal) => !signal.aborted)).toBe(true);
      jest.advanceTimersByTime(1);

      const answer = await pending;

      expect(answer.providers).toEqual([
        { agent: 'claude', unavailable: 'Timed out after 10 s.' },
        { agent: 'codex', unavailable: 'Timed out after 10 s.' },
      ]);
      expect(signals.every((signal) => signal.aborted)).toBe(true);

      let closed = false;
      const closing = resources.close().then(() => {
        closed = true;
      });

      await setImmediate();
      expect(closed).toBe(false);
      gates.claude.resolve({ agent: 'claude', windows: [] });
      gates.codex.resolve({ agent: 'codex', windows: [] });
      await closing;
      expect(
        answer.providers.every((provider) => 'unavailable' in provider),
      ).toBe(true);
    } finally {
      gates.claude.resolve({ agent: 'claude', windows: [] });
      gates.codex.resolve({ agent: 'codex', windows: [] });
      await pending;
      await resources.close();
      jest.useRealTimers();
    }
  });

  test('cancelling one same-provider caller leaves the other caller independent and retains late cleanup failure', async () => {
    const first = Promise.withResolvers<ProviderLimits>();
    const second = Promise.withResolvers<ProviderLimits>();
    const signals: AbortSignal[] = [];
    const resources = createResources({
      collectors: readers([], (_provider, _path, cwd, signal) => {
        signals.push(signal);

        return cwd === '/fixture/first' ? first.promise : second.promise;
      }),
    });
    const abort = new AbortController();
    const pending = resources.read(
      ['codex'],
      { ...place, cwd: '/fixture/first' },
      abort.signal,
    );
    const rejected = pending.catch((error: unknown) => error);
    const independent = resources.read(
      ['codex'],
      { ...place, cwd: '/fixture/second' },
      new AbortController().signal,
    );

    try {
      await until(() => signals.length === 2);
      abort.abort(new Error('Fixture caller cancelled.'));
      expect(await rejected).toMatchObject({
        message: 'Fixture caller cancelled.',
      });
      expect(signals[0]!.aborted).toBe(true);
      expect(signals[1]!.aborted).toBe(false);
      second.resolve({ agent: 'codex', windows: [] });
      expect((await independent).providers).toEqual([
        { agent: 'codex', windows: [] },
      ]);

      let closed = false;
      const closing = resources.close().then((failures) => {
        closed = true;

        return failures;
      });

      await setImmediate();
      expect(closed).toBe(false);
      first.reject(
        new ResourceReadError('cleanup', 'Fixture group exit unverified.'),
      );
      expect(await closing).toEqual(['Fixture group exit unverified.']);
      expect(await resources.close()).toEqual([
        'Fixture group exit unverified.',
      ]);
    } finally {
      first.resolve({ agent: 'codex', windows: [] });
      second.resolve({ agent: 'codex', windows: [] });
      await Promise.allSettled([pending, independent]);
      await resources.close();
    }
  });
});
