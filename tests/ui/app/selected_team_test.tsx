import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { foldBudgetCache } from '../../../src/platform/budget_cache.ts';
import type { ResourceAccess } from '../../../src/session/resource_access.ts';
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord, type ChordServer } from '../../../src/server/server.ts';
import type { Caller, RunTeamAnswer } from '../../../src/server/tools.ts';
import { openSession } from '../../../src/session/session.ts';
import type { TeamSelection } from '../../../src/session/budgets.ts';
import type { TeamSelectionPolicy } from '../../../src/settings.ts';
import { readPast } from '../../../src/session/record.ts';
import { recordedSelection } from '../../../src/session/team_selection.ts';
import { readRecords } from '../../../src/session/sessions.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { ready, send, until, withWindow, type Window } from './render.tsx';

const team = `---
description: Frozen selection fixture
lead:
  agent: fake
members:
  - name: reviewer
    role: Review only
    agent: fake
    instructions: Preserve this exact review instruction.
---
Preserve the exact team body and permissions.
`;
const selection = {
  reason: 'Keep every instruction and permission; capacity is unknown.',
};

async function selectedWindow(
  body: (
    window: Window,
    main: Caller,
    callers: Caller[],
    prompts: string[],
    server: ChordServer,
  ) => Promise<void>,
  options: {
    policy?: () => Promise<TeamSelectionPolicy>;
    resources?: ResourceAccess;
    definition?: string;
    open?: typeof openSession;
  } = {},
) {
  const server = serveChord();
  const admit = server.admit.bind(server);
  const callers: Caller[] = [];
  const prompts: string[] = [];

  server.admit = (caller) => {
    callers.push(caller);

    return admit(caller);
  };

  try {
    await withWindow(
      async (window) => {
        await ready(window);

        const main = callers.find((caller) => caller.role === 'person');

        assert(main !== undefined);
        await body(window, main, callers, prompts, server);
      },
      {
        server,
        ...(options.resources === undefined
          ? {}
          : { resources: options.resources }),
        teams: { fixture: options.definition ?? team },
        runtimes: ['fake', 'codex', 'claude'],
        startupOf: () => ({ agentCommand: fakeAgentCommand() }),
        ...(options.policy === undefined
          ? {}
          : { selectionPolicy: options.policy }),
        openWith: async (args) => {
          const session = await (options.open ?? openSession)(args);
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
}

function success(answer: RunTeamAnswer) {
  assert(!('error' in answer), 'selected run must succeed');
  assert(answer.receipt !== undefined);

  return answer;
}

describe('selected frozen team startup', () => {
  test('scripted ordinary MCP selection links one real Team row with no owned fallback duplicate', () =>
    selectedWindow(async (window, main) => {
      await send(window, 'selectedteam');
      await until('scripted selected turn finished', () =>
        window.mounted('Selection attempt recorded; no automatic retry.'),
      );
      expect(window.mounted('Selection: agent-selected · this run')).toBe(true);
      expect(window.mounted('Recorded Team receipt (fixture)')).toBe(false);
      expect((await main.window.teams(main)).runs).toHaveLength(1);
    }));

  test('confirms actual lead configuration, retains unopened roles and preserves the saved file', () =>
    selectedWindow(async (window, main, _callers, prompts) => {
      const original = await readFile(
        join(window.dir, '.chord/teams/fixture.md'),
        'utf8',
      );
      const answer = success(
        await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Do this exact job.',
          selection: {
            ...selection,
            lead: { model: 'fake-small', mode: 'plan' },
          },
        }),
      );

      expect(answer.receipt!.roles[0]).toMatchObject({
        state: 'confirmed',
        planned: { agent: 'fake', model: 'fake-small', mode: 'plan' },
        actual: { model: 'fake-small', mode: 'plan' },
      });
      expect(answer.receipt!.roles[1]).toMatchObject({
        state: 'planned',
        actual: null,
      });
      expect(answer.receipt!.decisionRead).toBeNull();
      expect((await main.window.teams(main)).runs).toContainEqual({
        team: 'fixture',
        name: 'fixture',
        id: answer.id,
      });
      await until('selected lead first job', () =>
        prompts.some((prompt) => prompt.includes('Do this exact job.')),
      );
      expect(prompts[0]).toContain('Do this exact job.');
      expect(prompts[0]).toContain(
        'Preserve the exact team body and permissions.',
      );
      expect(
        await readFile(join(window.dir, '.chord/teams/fixture.md'), 'utf8'),
      ).toBe(original);
    }));

  test('selected full-role policy refuses before allocation while omitted selection retains direct composition', () =>
    selectedWindow(
      async (window, main, _callers, prompts) => {
        const selected = await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Refuse.',
          selection,
        });

        expect(selected).toHaveProperty('error');
        expect(window.pids).toHaveLength(1);
        expect(prompts).toEqual([]);

        const direct = await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Saved direct job.',
        });

        assert(!('error' in direct));
        expect(direct).not.toHaveProperty('receipt');
        await until('direct saved job', () =>
          prompts.some((prompt) => prompt.includes('Saved direct job.')),
        );
      },
      {
        policy: () =>
          Promise.resolve({ policy: { constraints: { agents: [] } } }),
      },
    ));

  test('receipt uses the actually served decision read rather than newer launch-time cache facts', () => {
    const oldTime = Date.parse('2026-10-27T13:00:00Z');
    let facts = foldBudgetCache([], {}, { wall: oldTime, monotonic: 0 });
    const resources: ResourceAccess = {
      processRef: 'fixture-process',
      start: () => Promise.resolve(),
      retain: () => () => {},
      read: () => facts,
      active: () => {},
      close: () => Promise.resolve([]),
    };

    return selectedWindow(
      async (_window, main, _callers, _prompts, server) => {
        const client = new Client({
          name: 'fixture-decision-reader',
          version: '0.0.0',
        });
        const admitted = server.admit(main);
        const transport = new StreamableHTTPClientTransport(
          new URL(server.url),
          {
            requestInit: {
              headers: { Authorization: `Bearer ${admitted.token}` },
            },
          },
        );

        await client.connect(transport as Parameters<Client['connect']>[0]);

        try {
          await client.callTool({ name: 'get_budgets', arguments: {} });
        } finally {
          await client.close();
        }

        facts = foldBudgetCache(
          [],
          {},
          { wall: oldTime + 10_000, monotonic: 10_000 },
        );

        const answer = success(
          await main.window.runTeam(main, {
            team: 'fixture',
            job: 'Use served facts.',
            selection,
          }),
        );

        expect(answer.receipt!.decisionRead).toEqual({
          readAt: new Date(oldTime).toISOString(),
          observationRefs: [],
        });
      },
      { resources },
    );
  });

  test('fresh policy loader failure is sanitized and selected-only', () =>
    selectedWindow(
      async (_window, main) => {
        const selected = await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Refuse selected.',
          selection,
        });

        expect(selected).toEqual({
          error:
            'Team selection settings could not be validated. Correct the settings before selecting a team.',
        });

        const direct = await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Use saved composition.',
        });

        expect(direct).not.toHaveProperty('error');
      },
      {
        policy: () =>
          Promise.reject(new Error('private loader detail must not escape')),
      },
    ));

  test('an overridden unrepresentable saved field allocates nobody', () =>
    selectedWindow(
      async (window, main) => {
        const answer = await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Never.',
          selection: { ...selection, lead: { model: 'fake-small' } },
        });

        expect(answer).toHaveProperty('error');
        expect(window.pids).toHaveLength(1);
        expect((await main.window.teams(main)).runs).toEqual([]);
      },
      {
        definition: team.replace(
          'lead:\n  agent: fake',
          `lead:\n  agent: fake\n  model: ${'m'.repeat(129)}`,
        ),
      },
    ));

  test('runtime substitution requires explicit destination model and mode and never inherits old mode', () =>
    selectedWindow(async (_window, main) => {
      expect(
        await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Refuse.',
          selection: {
            ...selection,
            lead: { agent: 'codex', model: 'fake-small' },
          },
        }),
      ).toHaveProperty('error');

      const answer = success(
        await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Use destination.',
          selection: {
            ...selection,
            lead: { agent: 'codex', model: 'fake-small', mode: 'plan' },
          },
        }),
      );

      expect(answer.agent).toBe('codex');
      expect(answer.receipt!.roles[0]).toMatchObject({
        actual: { mode: 'plan' },
        state: 'confirmed',
      });
    }));

  for (const actualAgent of [undefined, 'unexpected-runtime']) {
    test(`actual session runtime ${actualAgent ?? 'missing'} is refused before its first job`, () => {
      let opens = 0;

      return selectedWindow(
        async (_window, main, _callers, prompts) => {
          const answer = await main.window.runTeam(main, {
            team: 'fixture',
            job: 'Never deliver unconfirmed runtime.',
            selection,
          });

          assert('error' in answer && answer.receipt !== undefined);
          expect(answer.receipt.roles[0]).toMatchObject({
            state: 'refused',
            actual: { agent: actualAgent ?? null },
          });
          expect(prompts).toEqual([]);
        },
        {
          open: async (args) => {
            const session = await openSession(args);

            return ++opens === 1
              ? session
              : ({ ...session, agent: actualAgent } as typeof session);
          },
        },
      );
    });
  }

  test('a model not actually confirmed closes its allocated attempt with a parent receipt and no first job', () => {
    let opens = 0;

    return selectedWindow(
      async (window, main, _callers, prompts) => {
        const answer = await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Never deliver.',
          selection: { ...selection, lead: { model: 'fake-small' } },
        });

        assert(
          'error' in answer &&
            answer.id !== undefined &&
            answer.receipt !== undefined,
        );
        expect(answer.receipt.roles[0]?.state).toBe('refused');
        expect(answer.error).toContain('before its first job');
        expect(prompts).toEqual([]);
        expect((await main.window.teams(main)).runs).toEqual([]);

        const records = await readRecords(join(window.dir, 'state'));
        const parent = records.find(
          (record) => record.sessionId === window.session()?.id,
        );

        assert(parent !== undefined);
        await until('refusal kept in parent record', async () =>
          (await readPast(parent.path)).some(
            (entry) =>
              entry.type === 'served' && entry.call.asked === answer.id,
          ),
        );
      },
      {
        open: async (args) => {
          const session = await openSession(args);

          if (++opens > 1) {
            const models = session.models.bind(session);

            session.models = () => {
              const offered = models();

              return offered === undefined
                ? undefined
                : { ...offered, current: 'fake-large' };
            };
          }

          return session;
        },
      },
    );
  });

  test('failed initialization records only a real caller and returns the allocated attempt', () => {
    let opens = 0;

    return selectedWindow(
      async (window, main, _callers, prompts) => {
        const answer = await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Never.',
          selection,
        });

        assert(
          'error' in answer &&
            answer.receipt !== undefined &&
            answer.id !== undefined,
        );
        expect(answer.receipt.roles[0]?.state).toBe('refused');
        expect(prompts).toEqual([]);

        await until('actual caller receipt persisted', async () => {
          const records = await readRecords(join(window.dir, 'state'));
          const caller = records.find(
            (record) => record.sessionId === window.session()?.id,
          );

          if (caller === undefined) {
            return false;
          }

          return (await readPast(caller.path)).some(
            (entry) =>
              entry.type === 'served' &&
              recordedSelection(entry.call)?.runId === answer.id,
          );
        });

        const records = await readRecords(join(window.dir, 'state'));

        expect(records).toHaveLength(1);
        expect(records[0]?.sessionId).toBe(window.session()?.id);
      },
      {
        open: (args) =>
          ++opens === 1
            ? openSession(args)
            : Promise.reject(new Error('fixture initialization failure')),
      },
    );
  });

  test('clear during selected startup returns the original closing attempt and delivers no job', async () => {
    const gate = Promise.withResolvers<void>();
    let opens = 0;
    let held = false;

    try {
      await selectedWindow(
        async (window, main, _callers, prompts) => {
          const original = window.session()?.id;
          const pending = main.window.runTeam(main, {
            team: 'fixture',
            job: 'Never deliver cancelled job.',
            selection,
          });

          await until('selected attempted lead held', () => held);
          await send(window, '/clear');
          await until(
            'replacement session',
            () => window.session()?.id !== original,
          );
          gate.resolve();

          const answer = await pending;

          assert(
            'error' in answer &&
              answer.id !== undefined &&
              answer.receipt !== undefined,
          );
          expect(answer.receipt.roles[0]?.state).toBe('refused');
          expect(answer.error).toContain('before its first job');
          expect(
            prompts.some((prompt) =>
              prompt.includes('Never deliver cancelled job.'),
            ),
          ).toBe(false);
          await until('old caller attempt remains inspectable', async () =>
            (await readRecords(join(window.dir, 'state'))).some(
              (record) => record.sessionId === original,
            ),
          );
        },
        {
          open: async (args) => {
            const number = ++opens;
            const session = await openSession(args);

            if (number === 2) {
              held = true;

              await gate.promise;
            }

            return session;
          },
        },
      );
    } finally {
      gate.resolve();
    }
  });

  test('effort refusal stays soft and the receipt reports the actual effort with a sanitized note', () => {
    let opens = 0;

    return selectedWindow(
      async (_window, main) => {
        const answer = success(
          await main.window.runTeam(main, {
            team: 'fixture',
            job: 'Keep exact model and mode.',
            selection: { ...selection, lead: { effort: 'high' } },
          }),
        );

        expect(answer.receipt!.roles[0]).toMatchObject({
          state: 'confirmed',
          planned: { effort: 'high' },
          actual: { effort: 'medium' },
          note: 'The requested effort was not confirmed; the runtime effort remains advisory.',
        });
      },
      {
        open: (args) =>
          openSession(
            ++opens === 1
              ? args
              : {
                  ...args,
                  agentCommand: fakeAgentCommand(undefined, '--refuse-config'),
                },
          ),
      },
    );
  });

  test('two selected runs keep independent frozen member configurations', () =>
    selectedWindow(async (_window, main, callers) => {
      const first = success(
        await main.window.runTeam(main, {
          team: 'fixture',
          job: 'First run.',
          selection: {
            ...selection,
            members: { reviewer: { model: 'fake-small', mode: 'plan' } },
          },
        }),
      );
      const second = success(
        await main.window.runTeam(main, {
          team: 'fixture',
          job: 'Second run.',
          selection: {
            ...selection,
            members: { reviewer: { model: 'fake-large', mode: 'default' } },
          },
        }),
      );
      const lead1 = callers.find((caller) => caller.agent === first.id);
      const lead2 = callers.find((caller) => caller.agent === second.id);

      assert(lead1 !== undefined && lead2 !== undefined);

      const member1 = await main.window.openMember(lead1, {
        member: 'reviewer',
        prompt: 'First review.',
      });
      const member2 = await main.window.openMember(lead2, {
        member: 'reviewer',
        prompt: 'Second review.',
      });

      expect(member1).toMatchObject({ model: 'fake-small', mode: 'plan' });
      expect(member2).toMatchObject({ model: 'fake-large', mode: 'default' });
    }));

  test('members retain the frozen role after file edit and current policy may refuse only the unopened member', () => {
    let policy: TeamSelection = {};

    return selectedWindow(
      async (window, main, callers, prompts) => {
        const answer = success(
          await main.window.runTeam(main, {
            team: 'fixture',
            job: 'Lead continues.',
            selection: {
              ...selection,
              members: { reviewer: { model: 'fake-small', mode: 'plan' } },
            },
          }),
        );
        const lead = callers.find((caller) => caller.agent === answer.id);

        assert(lead !== undefined);
        await writeFile(
          join(window.dir, '.chord/teams/fixture.md'),
          team
            .replace('Review only', 'Changed role')
            .replace(
              'Preserve this exact review instruction.',
              'Rewritten instruction.',
            ),
        );

        policy = { constraints: { agents: [] } };

        const refused = await main.window.openMember(lead, {
          member: 'reviewer',
          prompt: 'Refuse only this member.',
        });

        expect(refused).toHaveProperty('error');
        expect((await main.window.teams(main)).runs).toHaveLength(1);
        expect(
          prompts.some((prompt) => prompt.includes('Refuse only this member.')),
        ).toBe(false);

        policy = {};

        const member = await main.window.openMember(lead, {
          member: 'reviewer',
          prompt: 'Use the frozen review role.',
        });

        assert(!('error' in member));
        expect(member.model).toBe('fake-small');
        await until('frozen member first job', () =>
          prompts.some((prompt) =>
            prompt.includes('Use the frozen review role.'),
          ),
        );

        const delivered = prompts.find((prompt) =>
          prompt.includes('Use the frozen review role.'),
        );

        expect(delivered).toContain('Preserve this exact review instruction.');
        expect(delivered).not.toContain('Rewritten instruction.');
      },
      { policy: () => Promise.resolve({ policy }) },
    );
  });
});
