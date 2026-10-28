import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { serveChord } from '../../../src/server/server.ts';
import { createResources } from '../../../src/platform/resources.ts';
import type { ResourceFixtureCase } from '../../../src/platform/resource_fixture.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { ready, send, withWindow, type Window } from './render.tsx';

async function withResourcesWindow(
  body: (window: Window) => Promise<void>,
  options: { scenario?: ResourceFixtureCase; columns?: number } = {},
) {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await body(window);
      },
      {
        agent: 'codex',
        agentCommand: fakeAgentCommand('resources'),
        startupOf: () => ({ agentCommand: fakeAgentCommand('resources') }),
        runtimes: ['codex', 'claude'],
        server,
        resources: createResources({
          collectors: 'fixture',
          fixtureCase: options.scenario ?? 'normal',
          timeoutMs: 50,
        }),
        columns: options.columns ?? 120,
        rows: options.columns === 80 ? 24 : 40,
      },
    );
  } finally {
    await server.close();
  }
}

describe('limits in the window', () => {
  for (const columns of [120, 80]) {
    test(`${columns}-column Resources shows a line per provider window`, () =>
      withResourcesWindow(
        async (window) => {
          await send(window, 'resources');
          await window.shows('Resource facts are advisory');

          expect(window.mounted('Resources')).toBe(true);
          expect(window.mounted('advisory snapshot')).toBe(true);
          expect(window.mounted('claude · 5h: 12.345% used')).toBe(true);
          expect(window.mounted('codex · 7d: usage unknown')).toBe(true);
        },
        { scenario: 'partial', columns },
      ));
  }

  for (const [scenario, line] of [
    ['timeout', 'codex: unavailable · Timed out after 0.05 s.'],
    ['unavailable', 'claude: unavailable · Scripted unavailable provider.'],
  ] as const) {
    test(`${scenario} is a provider not read in a completed report`, () =>
      withResourcesWindow(
        async (window) => {
          await send(window, 'resources');
          await window.shows('Resource facts are advisory');

          expect(window.mounted(line)).toBe(true);
        },
        { scenario },
      ));
  }
});

test('a harness window without a limits reader reads none, even for provider-named fake runtimes', async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'resources');
        await window.shows('Resource facts are advisory');

        expect(window.mounted('The limits could not be read.')).toBe(true);
      },
      {
        agent: 'codex',
        agentCommand: fakeAgentCommand('resources'),
        startupOf: () => ({ agentCommand: fakeAgentCommand('resources') }),
        runtimes: ['codex', 'claude'],
        server,
      },
    );
  } finally {
    await server.close();
  }
});

describe('tester: Resources keyboard and snapshot continuity', () => {
  for (const columns of [120, 80]) {
    test(`${columns}-column ctrl+o preserves the advisory report and unsent prompt`, () =>
      withResourcesWindow(
        async (window) => {
          await send(window, 'resources');
          await window.shows('Resource facts are advisory');

          const read = window.frame().match(/Read: [0-9:]+ UTC/);

          assert(read);

          await window.type('unsent draft');
          await window.press('\x0f');

          expect(window.frame()).toContain(read[0]);
          expect(window.frame()).toContain('unsent draft');

          await window.press('\x0f');

          expect(window.frame()).toContain(read[0]);
          expect(window.frame()).toContain('unsent draft');
        },
        { columns },
      ));
  }
});
