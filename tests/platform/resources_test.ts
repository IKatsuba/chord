import { describe, expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import {
  createResources,
  type ResourceCollectors,
} from '../../src/platform/resources.ts';
import { normalizeCodex } from '../../src/session/resource_normalization.ts';
import type { ResourceAccess } from '../../src/session/resource_access.ts';
import { until } from '../session/conversation_fake.ts';

async function withResources(
  collectors: ResourceCollectors | 'fixture',
  body: (resources: ResourceAccess) => void | Promise<void>,
) {
  const directory = await mkdtemp(join(tmpdir(), 'chord-resource-factory-'));
  const resources = createResources({ stateDirectory: directory, collectors });

  try {
    await resources.start();
    await body(resources);
  } finally {
    await resources.close();
    await rm(directory, { recursive: true, force: true });
  }
}

function readers(calls: string[]): ResourceCollectors {
  return {
    resolve: (provider, interest) => {
      calls.push(`resolve:${provider}:${interest.cwd}`);

      return Promise.resolve(
        interest.command === undefined
          ? { path: '/fixture/provider', version: '1' }
          : { unavailable: 'Custom command association is unverified.' },
      );
    },
    read: (provider, _path, cwd, _signal, source) => {
      calls.push(`read:${provider}:${cwd}`);

      return Promise.resolve(
        normalizeCodex(
          { account: { type: 'chatgpt' } },
          {
            rateLimits: {
              primary: {
                usedPercent: 0,
                windowDurationMins: 300,
                resetsAt: null,
              },
              secondary: null,
            },
            rateLimitsByLimitId: null,
          },
          { ...source, receivedAt: new Date().toISOString() },
        ),
      );
    },
  };
}

describe('explicit resource factory', () => {
  test('startup and cached facts never fan out or start a reader', async () => {
    const calls: string[] = [];

    await withResources(readers(calls), (resources) => {
      expect(resources.read().unbound).toEqual([]);
      expect(resources.read({ intent: 'economy' }).preferences.intent).toBe(
        'economy',
      );
      expect(calls).toEqual([]);
    });
  });

  test('same configured provider shares; another cwd remains a separate unbound source', async () => {
    const calls: string[] = [];

    await withResources(readers(calls), async (resources) => {
      const first = new AbortController();
      const second = new AbortController();
      const interest = { agent: 'codex', cwd: '/fixture/project-a' };

      resources.retain(interest, first.signal);
      resources.retain(interest, second.signal);
      resources.retain(
        { ...interest, cwd: '/fixture/project-b' },
        new AbortController().signal,
      );
      await until(() => resources.read().unbound.length === 2);

      expect(calls).toEqual([
        'resolve:codex:/fixture/project-a',
        'resolve:codex:/fixture/project-b',
        'read:codex:/fixture/project-a',
        'read:codex:/fixture/project-b',
      ]);
      expect(
        new Set(resources.read().unbound.map((value) => value.sourceRef)).size,
      ).toBe(2);
      expect(resources.read().pools).toEqual([]);
      expect(JSON.stringify(resources.read())).not.toContain('/fixture/');

      first.abort();

      expect(resources.read().unbound).toHaveLength(2);
    });
  });

  test('custom commands and unknown runtimes are advisory without provider reads', async () => {
    const calls: string[] = [];

    await withResources(readers(calls), async (resources) => {
      resources.retain(
        { agent: 'codex', cwd: '/fixture/project', command: ['custom-acp'] },
        new AbortController().signal,
      );
      resources.retain(
        { agent: 'other', cwd: '/fixture/project' },
        new AbortController().signal,
      );
      await until(
        () =>
          resources.read().unavailable.length === 2 &&
          resources
            .read()
            .unavailable.every((value) => !value.reason.includes('pending')),
      );

      expect(calls).toEqual(['resolve:codex:/fixture/project']);
      expect(resources.read().unbound).toEqual([]);
      expect(JSON.stringify(resources.read())).not.toContain('retry');
    });
  });

  test('explicit fixture mode cannot resolve installed sources even for Codex/Claude labels', async () => {
    const previous = process.env['PATH'];

    process.env['PATH'] = '';

    try {
      await withResources('fixture', async (resources) => {
        for (const agent of ['codex', 'claude']) {
          resources.retain(
            {
              agent,
              cwd: '/fixture/project',
              command: 'never-launch-this-wrapper',
            },
            new AbortController().signal,
          );
        }

        await until(() => resources.read().unbound.length === 2);

        expect(resources.read().unbound.map((value) => value.source)).toEqual([
          'fixture',
          'fixture',
        ]);
        expect(
          resources
            .read()
            .unbound.every(
              (value) =>
                value.windows[0]?.observedAt === null &&
                value.windows[0]?.state === 'unknown',
            ),
        ).toBe(true);
      });
    } finally {
      if (previous === undefined) {
        delete process.env['PATH'];
      } else {
        process.env['PATH'] = previous;
      }
    }
  });
});
