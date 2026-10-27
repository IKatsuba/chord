import { describe, expect, test } from 'bun:test';
import { getEventListeners } from 'node:events';
import { serveChord } from '../../../src/server/server.ts';
import { openSession } from '../../../src/session/session.ts';
import type { ResourceAccess } from '../../../src/session/resource_access.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { promptRow, ready, send, until, withWindow } from './render.tsx';

const team = `---
description: Explicit choose fixture
lead:
  agent: codex
members:
  - name: reviewer
    role: Review only
    agent: claude
    instructions: Preserve exact scope.
---
Keep all instructions and permissions.
`;

test('choose sends exactly one visible main turn after retaining only the resolved team providers', async () => {
  const server = serveChord();
  const retained: string[] = [];
  const prompts: string[] = [];
  const resources: ResourceAccess = {
    processRef: 'fixture',
    start: async () => {},
    retain: (interest) => {
      retained.push(interest.agent);

      return () => {};
    },
    read: () => {
      expect(retained).toContain('codex');
      expect(retained).toContain('claude');
      expect(retained).not.toContain('unused');

      return {
        schemaVersion: 1,
        observedAt: new Date().toISOString(),
        preferences: { intent: 'balanced' },
        pools: [],
        unbound: [],
        unavailable: [],
        activeRuns: [],
        warnings: [],
      };
    },
    active: () => {},
    close: () => Promise.resolve([]),
  };

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/team choose fixture selectedidle');
        await until('selection turn completed', () =>
          window.mounted('Selection attempt recorded; no automatic retry.'),
        );
        expect(
          prompts.filter((prompt) => prompt.includes('through /team choose')),
        ).toHaveLength(1);
        expect(window.mounted('/team choose fixture selectedidle')).toBe(true);
        expect(window.mounted('Selection: agent-selected')).toBe(true);
      },
      {
        server,
        resources,
        teams: { fixture: team, unrelated: team.replaceAll('codex', 'unused') },
        runtimes: ['fake', 'codex', 'claude', 'unused'],
        startupOf: () => ({ agentCommand: fakeAgentCommand('selectedteam') }),
        openWith: async (args) => {
          const session = await openSession(args);
          const prompt = session.prompt.bind(session);

          session.prompt = (text, ...rest) => {
            prompts.push(text);

            return prompt(text, ...rest);
          };

          return session;
        },
      },
    );
  } finally {
    await server.close();
  }
});

for (const command of [
  '/team choose',
  '/team choose fixture',
  '/team choose missing selectedidle',
]) {
  test(`${command} refuses locally without a model turn or direct fallback`, async () => {
    const prompts: string[] = [];
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, command);
          await until('local refusal', () =>
            window.mounted(
              command.endsWith('missing selectedidle')
                ? 'No team named missing'
                : command.endsWith('fixture')
                  ? 'takes the job after the name'
                  : 'Which team?',
            ),
          );
          expect(prompts).toEqual([]);
          expect(window.pids).toHaveLength(1);
        },
        {
          server,
          teams: { fixture: team },
          runtimes: ['fake', 'codex', 'claude'],
          startupOf: () => ({ agentCommand: fakeAgentCommand() }),
          openWith: async (args) => {
            const session = await openSession(args);
            const prompt = session.prompt.bind(session);

            session.prompt = (text, ...rest) => {
              prompts.push(text);

              return prompt(text, ...rest);
            };

            return session;
          },
        },
      );
    } finally {
      await server.close();
    }
  });
}

test('unavailable MCP refuses choose locally without a main selection turn', async () => {
  const prompts: string[] = [];

  await withWindow(
    async (window) => {
      await ready(window);
      await send(window, '/team choose fixture selectedidle');
      await until('local MCP refusal', () =>
        window.mounted('no selection turn was sent'),
      );
      expect(prompts).toEqual([]);
      expect(window.pids).toHaveLength(1);
    },
    {
      teams: { fixture: team },
      runtimes: ['fake', 'codex', 'claude'],
      startupOf: () => ({ agentCommand: fakeAgentCommand() }),
      openWith: async (args) => {
        const session = await openSession(args);
        const prompt = session.prompt.bind(session);

        session.prompt = (text, ...rest) => {
          prompts.push(text);

          return prompt(text, ...rest);
        };

        return session;
      },
    },
  );
});

for (const cancel of ['clear', 'interrupt', 'disconnect'] as const) {
  test(`queued choose obeys ordinary ${cancel} cancellation without direct fallback`, async () => {
    const server = serveChord();
    const prompts: string[] = [];
    let queued = false;
    let frontReady = false;
    const interests: AbortSignal[] = [];
    const resources: ResourceAccess = {
      processRef: 'queued-choose-fixture',
      start: () => Promise.resolve(),
      retain: (interest, signal) => {
        if (interest.agent !== 'fake') {
          interests.push(signal);
        }

        return () => {};
      },
      read: () => ({
        schemaVersion: 1,
        observedAt: new Date().toISOString(),
        preferences: {},
        pools: [],
        unbound: [],
        unavailable: [],
        activeRuns: [],
        warnings: [],
      }),
      active: () => {},
      close: () => Promise.resolve([]),
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'costwait');
          await window.shows('Working until stopped.');
          await send(window, '/team choose fixture selectedidle');
          await until('choose queued', () => queued);

          if (cancel === 'clear') {
            await send(window, '/clear');
            await until(
              'replacement session ready with restored draft',
              () => window.pids.length === 2 && frontReady,
            );
            expect(promptRow(window)).toContain(
              '/team choose fixture selectedidle',
            );
          } else if (cancel === 'disconnect') {
            await window.session()?.close();
          } else {
            await window.press('\x1b');
            await until('choose removed from queue', () => !queued);
          }

          await until(
            'old choose resource generation revoked',
            () =>
              interests.length === 2 &&
              interests.every((signal) => signal.aborted),
          );
          expect(
            prompts.some((prompt) => prompt.includes('through /team choose')),
          ).toBe(false);
          expect(window.pids).toHaveLength(cancel === 'clear' ? 2 : 1);
        },
        {
          server,
          resources,
          teams: { fixture: team },
          runtimes: ['fake', 'codex', 'claude'],
          startupOf: () => ({ agentCommand: fakeAgentCommand('selectedteam') }),
          onState: (state) => {
            queued = (state.sessions[state.front]?.queue.length ?? 0) > 0;
            frontReady =
              state.sessions[state.front]?.connection.status === 'ready';
          },
          openWith: async (args) => {
            const session = await openSession(args);
            const prompt = session.prompt.bind(session);

            session.prompt = (text, ...rest) => {
              prompts.push(text);

              return prompt(text, ...rest);
            };

            return session;
          },
        },
      );
    } finally {
      await server.close();
    }
  });
}

for (const direct of ['typed', 'picker'] as const) {
  test(`direct ${direct} saved-team path sends zero main selection turns`, async () => {
    const prompts: string[] = [];
    const server = serveChord();
    let mainId: string | undefined;

    try {
      await withWindow(
        async (window) => {
          await ready(window);

          mainId = window.session()?.id;

          if (direct === 'typed') {
            await send(window, '/team run fixture selectedidle');
          } else {
            await send(window, '/team');
            await until('team picker', () =>
              window.mounted('Enter to hand it a job'),
            );
            await window.press('\r');
            await window.type('selectedidle');
            await window.press('\r');
          }

          await until(
            'saved team first job',
            () =>
              window.pids.length === 2 &&
              prompts.some((prompt) => prompt.includes('selectedidle')),
          );
          expect(
            prompts.filter((prompt) => prompt.includes('through /team choose')),
          ).toEqual([]);
        },
        {
          server,
          teams: { fixture: team },
          runtimes: ['fake', 'codex', 'claude'],
          startupOf: () => ({ agentCommand: fakeAgentCommand() }),
          openWith: async (args) => {
            const session = await openSession(args);
            const prompt = session.prompt.bind(session);

            session.prompt = (text, ...rest) => {
              if (session.id === mainId) {
                throw new Error(
                  'direct run must not send main a selection prompt',
                );
              }

              prompts.push(text);

              return prompt(text, ...rest);
            };

            return session;
          },
        },
      );
    } finally {
      await server.close();
    }
  });
}

function chooseInterests() {
  const signals = new Set<AbortSignal>();
  const live = new Map<number, string>();
  let next = 0;
  const resources: ResourceAccess = {
    processRef: 'choose-lifetime-fixture',
    start: () => Promise.resolve(),
    retain: (interest, signal) => {
      const id = ++next;

      if (interest.agent !== 'fake') {
        signals.add(signal);
      }

      const release = () => {
        live.delete(id);
        signal.removeEventListener('abort', release);
      };

      live.set(id, interest.agent);
      signal.addEventListener('abort', release, { once: true });

      if (signal.aborted) {
        release();
      }

      return release;
    },
    read: () => ({
      schemaVersion: 1,
      observedAt: new Date().toISOString(),
      preferences: {},
      pools: [],
      unbound: [],
      unavailable: [],
      activeRuns: [],
      warnings: [],
    }),
    active: () => {},
    close: () => Promise.resolve([]),
  };

  return { live, resources, signals };
}

for (const scenario of ['text', 'error'] as const) {
  test(`choose-only interests and listeners detach after ${scenario} completion and repeated choices retain only main`, async () => {
    const server = serveChord();
    const { live, resources, signals } = chooseInterests();
    let requests = 0;

    try {
      await withWindow(
        async (window) => {
          await ready(window);

          for (let choice = 1; choice <= 3; choice++) {
            await send(window, `/team choose fixture job ${choice}`);
            await until(
              'this selection prompt reached the fake agent',
              () => requests === choice,
            );
            await until(
              'this completed selection released its interests',
              () => live.size === 1,
            );
            expect([...live.values()]).toEqual(['fake']);

            for (const signal of signals) {
              expect(getEventListeners(signal, 'abort')).toHaveLength(0);
            }
          }

          expect(window.pids).toHaveLength(1);
        },
        {
          server,
          resources,
          teams: { fixture: team },
          runtimes: ['fake', 'codex', 'claude'],
          startupOf: () => ({ agentCommand: fakeAgentCommand(scenario) }),
          openWith: async (args) => {
            const session = await openSession(args);
            const prompt = session.prompt.bind(session);

            session.prompt = (text, ...rest) => {
              if (text.includes('through /team choose')) {
                requests++;
              }

              return prompt(text, ...rest);
            };

            return session;
          },
        },
      );
    } finally {
      await server.close();
    }
  });
}

test('selection completion leaves independent run interests until run close, then only main', async () => {
  const server = serveChord();
  const { live, resources } = chooseInterests();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/team choose fixture selectedidle');
        await until('selection completed', () =>
          window.mounted('Selection attempt recorded; no automatic retry.'),
        );
        await until(
          'only main and run interests remain',
          () => live.size === 3,
        );
        expect([...live.values()].sort()).toEqual(['claude', 'codex', 'fake']);
        await send(window, '/team stop fixture');
        await until(
          'run interests close without a retained choose owner',
          () => live.size === 1,
        );
        expect([...live.values()]).toEqual(['fake']);
      },
      {
        server,
        resources,
        teams: { fixture: team },
        runtimes: ['fake', 'codex', 'claude'],
        startupOf: () => ({ agentCommand: fakeAgentCommand('selectedteam') }),
      },
    );
  } finally {
    await server.close();
  }
});

describe('CHD-533 tester: interrupted choice ownership', () => {
  test('a wedged selection is revoked by clear without entering the replacement session', async () => {
    const server = serveChord();
    const { live, resources, signals } = chooseInterests();
    const prompts: string[] = [];
    let replacementReady = false;

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/team choose fixture wedged selection');
          await until(
            'selection reached the wedged fake',
            () => prompts.length === 1,
          );
          expect([...live.values()].sort()).toEqual([
            'claude',
            'codex',
            'fake',
          ]);
          await send(window, '/clear');
          await until(
            'replacement is ready',
            () => window.pids.length === 2 && replacementReady,
          );
          await until('old choice interests released', () =>
            [...live.values()].every((agent) => agent === 'fake'),
          );
          expect(prompts).toHaveLength(1);

          for (const signal of signals) {
            expect(getEventListeners(signal, 'abort')).toHaveLength(0);
          }
        },
        {
          server,
          resources,
          columns: 80,
          rows: 24,
          teams: { fixture: team },
          runtimes: ['fake', 'codex', 'claude'],
          startupOf: () => ({
            agentCommand: fakeAgentCommand(undefined, '--hang', 'turn'),
          }),
          onState: (state) => {
            replacementReady =
              state.sessions[state.front]?.connection.status === 'ready';
          },
          openWith: async (args) => {
            const session = await openSession(args);
            const prompt = session.prompt.bind(session);

            session.prompt = (text, ...rest) => {
              prompts.push(text);

              return prompt(text, ...rest);
            };

            return session;
          },
        },
      );
    } finally {
      await server.close();
    }
  });

  test('main exiting during a choice releases its interests without a direct retry', async () => {
    const server = serveChord();
    const { live, resources, signals } = chooseInterests();
    let requests = 0;

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/team choose fixture crash');
          await until('choice reached main', () => requests === 1);
          await until('crashed choice releases team interests', () =>
            [...live.values()].every((agent) => agent === 'fake'),
          );
          expect(window.pids).toHaveLength(1);
          expect(requests).toBe(1);
          expect(signals.size).toBeGreaterThan(0);

          for (const signal of signals) {
            expect(getEventListeners(signal, 'abort')).toHaveLength(0);
          }
        },
        {
          server,
          resources,
          teams: { fixture: team },
          runtimes: ['fake', 'codex', 'claude'],
          startupOf: () => ({ agentCommand: fakeAgentCommand('crash') }),
          openWith: async (args) => {
            const session = await openSession(args);
            const prompt = session.prompt.bind(session);

            session.prompt = (text, ...rest) => {
              requests++;

              return prompt(text, ...rest);
            };

            return session;
          },
        },
      );
    } finally {
      await server.close();
    }
  });
});
