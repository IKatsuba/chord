import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import type { Caller } from '../../../src/server/tools.ts';
import { createResources } from '../../../src/platform/resources.ts';
import {
  fixtureResourceRead,
  type ResourceFixtureCase,
} from '../../../src/platform/resource_fixture.ts';
import type { ResourceAccess } from '../../../src/session/resource_access.ts';
import {
  ResourceService,
  type ResourceRead,
} from '../../../src/session/resource_service.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  isAlive,
  ready,
  send,
  until,
  withWindow,
  type Window,
} from './render.tsx';

const team = `---
description: Resource relevance fixture
lead:
  agent: codex
members:
  - name: reviewer
    role: Reviewer
    agent: claude
    instructions: Review the supplied changes.
---
Preserve these role bytes.
`;

async function withResourcesWindow(
  body: (
    window: Window,
    resources: ResourceAccess,
    caller: () => Caller,
    retained: string[],
  ) => Promise<void>,
  options: {
    scenario?: ResourceFixtureCase;
    columns?: number;
    resources?: ResourceAccess;
    heldClose?: Promise<void>;
  } = {},
) {
  const directory = await mkdtemp(join(tmpdir(), 'chord-resource-window-'));
  const resources =
    options.resources ??
    createResources({
      stateDirectory: directory,
      collectors: 'fixture',
      fixtureCase: options.scenario ?? 'normal',
    });
  const server = serveChord();
  const admit = server.admit.bind(server);
  let main: Caller | undefined;
  const retained: string[] = [];
  const retain = resources.retain;

  resources.retain = (interest, signal, valid) => {
    retained.push(interest.agent);

    return retain(interest, signal, valid);
  };

  server.admit = (caller) => {
    if (caller.role === 'person') {
      main = caller;
    }

    return admit(caller);
  };

  try {
    await resources.start();
    await withWindow(
      async (window) => {
        await ready(window);
        await body(
          window,
          resources,
          () => {
            assert(main);

            return main;
          },
          retained,
        );
      },
      {
        agent: 'codex',
        agentCommand: fakeAgentCommand('resources'),
        startupOf: () => ({ agentCommand: fakeAgentCommand('resources') }),
        runtimes: ['codex', 'claude', 'unused'],
        server,
        resources,
        teamSelection: { intent: 'balanced' },
        teams: { bugfix: team },
        columns: options.columns ?? 120,
        rows: options.columns === 80 ? 24 : 40,
        ...(options.heldClose === undefined
          ? {}
          : { heldClose: options.heldClose }),
      },
    );
  } finally {
    await resources.close();
    await server.close();
    await rm(directory, { recursive: true, force: true });
  }
}

describe('resource facts in the window', () => {
  for (const columns of [120, 80]) {
    test(`${columns}-column Resources keeps independent unknown/partial facts and advisory warnings`, () =>
      withResourcesWindow(
        async (window, resources) => {
          await send(window, 'resources');
          await window.shows('Resource facts are advisory');

          expect(window.mounted('Resources')).toBe(true);
          expect(window.mounted('Preferences: balanced')).toBe(true);
          expect(window.mounted('12.345% used')).toBe(true);
          expect(window.mounted('usage unknown')).toBe(true);
          expect(window.mounted('identity unverified')).toBe(true);
          expect(window.mounted('external work may be missing')).toBe(true);
          expect(
            resources
              .read()
              .unbound.every((source) => source.source === 'fixture'),
          ).toBe(true);
        },
        { scenario: 'partial', columns },
      ));
  }

  test('current session and resolved team roles are the only retained sources; facts never fan out', () =>
    withResourcesWindow(async (window, resources, caller, retained) => {
      await until(
        'current source observation',
        () => resources.read().unbound.length === 1,
      );

      expect([...new Set(retained)]).toEqual(['codex']);

      const main = caller();

      main.window.budgets?.(main);
      main.window.budgets?.(main);

      expect([...new Set(retained)]).toEqual(['codex']);

      await send(window, '/team run bugfix resources');
      await until(
        'only the resolved team sources',
        () => resources.read().unbound.length === 2,
      );
      await until('planned reviewer fact', () =>
        resources
          .read()
          .activeRuns.some(
            (role) =>
              role.team === 'bugfix' &&
              role.member === 'reviewer' &&
              role.state === 'planned',
          ),
      );

      expect([...new Set(retained)]).toEqual(['codex', 'claude']);
      expect(retained).not.toContain('unused');
      expect(
        resources
          .read()
          .activeRuns.some(
            (role) => role.team === null && role.member === 'main',
          ),
      ).toBe(true);
    }));

  for (const scenario of ['pending', 'unavailable', 'long'] as const) {
    test(`${scenario} remains a completed advisory report`, () =>
      withResourcesWindow(
        async (window) => {
          await send(window, 'resources');
          await window.shows('Resource facts are advisory');

          expect(
            window.mounted(
              scenario === 'pending'
                ? 'pending · capacity unknown'
                : scenario === 'unavailable'
                  ? 'Scripted unsupported provider version'
                  : 'deliberately',
            ),
          ).toBe(true);
          expect(window.mounted('Resources')).toBe(true);
        },
        { scenario },
      ));
  }

  test('closing one shared consumer keeps the read; clear revokes it before old exit without cancelling replacement', async () => {
    const wall = Date.now();
    let elapsed = 0;
    let calls = 0;
    const pending = Promise.withResolvers<ResourceRead>();
    const signals: AbortSignal[] = [];
    const service = new ResourceService({
      now: () => ({ wall: wall + elapsed, monotonic: elapsed }),
      every: () => () => {},
    });
    const resources: ResourceAccess = {
      processRef: service.processRef,
      start: () => service.start(),
      read: (preferences) => service.read(preferences),
      active: (runs) => service.active(runs),
      close: () => service.close(),
      retain: (interest, signal, valid) =>
        service.retain(
          {
            key: interest.agent,
            agent: interest.agent,
            read: (readSignal) => {
              calls++;
              signals.push(readSignal);

              return calls === 1
                ? pending.promise
                : fixtureResourceRead(
                    interest.agent,
                    { sourceRef: 'replacement', sessionRef: 'replacement' },
                    'normal',
                    readSignal,
                  );
            },
          },
          signal,
          valid,
        ),
    };
    const oldExits = Promise.withResolvers<void>();

    try {
      await withResourcesWindow(
        async (window, access, caller) => {
          try {
            await until('first held collector', () => calls === 1);

            const oldPid = window.pids[0]!;
            const main = caller();
            const child = await main.window.open(main.key, {
              agent: 'codex',
              name: 'helper',
              prompt: 'resources',
            });

            assert(!('error' in child));
            await until('shared child source', () => window.pids.length === 2);

            expect(calls).toBe(1);

            await window.shows('helper');

            main.window.close(main, child.id);

            expect(signals[0]?.aborted).toBe(false);

            await until(
              'closed child no longer drawn',
              () => !window.frame().includes('helper'),
            );

            await send(window, '/clear');
            await until(
              'old collector revoked before old process close is released',
              () => signals[0]?.aborted === true,
            );

            pending.resolve(
              await fixtureResourceRead(
                'codex',
                { sourceRef: 'old-generation', sessionRef: 'old-generation' },
                'normal',
                new AbortController().signal,
              ),
            );
            await until(
              'old source drained',
              () => access.read().unbound.length === 0,
            );

            elapsed = 120000;

            await until('replacement read', () => {
              service.tick();

              return calls === 2 && access.read().unbound.length === 1;
            });

            oldExits.resolve();
            await until(
              'old fake process exited',
              async () => !(await isAlive(oldPid)),
            );
            await until(
              'replacement generation still live',
              () => access.read().unbound[0]?.sourceRef === 'replacement',
            );

            expect(signals[1]?.aborted).toBe(false);
            expect(
              access
                .read()
                .unbound.some(
                  (source) => source.sourceRef === 'old-generation',
                ),
            ).toBe(false);
          } finally {
            oldExits.resolve();
          }
        },
        { resources, heldClose: oldExits.promise },
      );
    } finally {
      oldExits.resolve();
      pending.resolve(
        await fixtureResourceRead(
          'codex',
          { sourceRef: 'cleanup', sessionRef: 'cleanup' },
          'normal',
          new AbortController().signal,
        ),
      );
      await resources.close();
    }
  });
});

test('an omitted harness resource service stays disabled even for provider-named fake runtimes', async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'resources');
        await window.shows('Resource facts are advisory');

        expect(
          window.mounted('No usable quota observations; capacity unknown'),
        ).toBe(true);
        expect(window.mounted('Custom ACP command')).toBe(false);
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
