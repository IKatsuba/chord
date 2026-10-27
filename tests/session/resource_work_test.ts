import { describe, expect, test } from 'bun:test';
import { activeResourceRuns } from '../../src/session/resource_work.ts';
import { noAgents } from '../../src/session/window_agents.ts';
import { idle } from '../../src/session/waits.ts';
import { ActiveRun } from '../../src/session/budgets.ts';
import { BudgetCacheFile } from '../../src/platform/budget_cache.ts';
import type { Team } from '../../src/teams.ts';

type Work = Parameters<typeof activeResourceRuns>[0];
type Driven = NonNullable<Work['main']>['conversation'];

const processRef = '00000000-0000-4000-8000-000000000001';
const now = Date.parse('2026-10-27T13:00:00Z');
const conversation: Driven = {
  session: {
    id: 'opaque-session',
    gone: () => undefined,
    models: () => ({ current: 'current-model' }),
  },
};
const team: Team = {
  description: 'Fixture team.',
  lead: { agent: 'codex' },
  members: [
    {
      name: 'reviewer',
      role: 'Review',
      instructions: 'Review the changes.',
      agent: 'claude',
    },
    {
      name: 'tester',
      role: 'Test',
      instructions: 'Test the changes.',
      agent: 'codex',
    },
  ],
  body: 'Role text stays as saved.',
};

describe('active resource roles', () => {
  test('main and standalone/tasks use null team and survive strict cache roundtrip', () => {
    const agents: Work = {
      ...noAgents<Driven>(),
      main: { key: 1, agent: 'codex', conversation, wait: idle },
      children: [
        {
          id: 'standalone',
          key: 2,
          name: 'helper',
          runtime: 'claude',
          conversation,
          wait: { ...idle, working: now },
          openedAt: now,
          colour: 0,
        },
      ],
    };
    const active = activeResourceRuns(
      agents,
      new Map(),
      [
        {
          id: 'task',
          name: 'task-helper',
          agent: 'codex',
          model: null,
          team: null,
          runRef: 'main-1',
          conversation,
        },
      ],
      processRef,
      now,
    );

    expect(active.map((role) => role.team)).toEqual([null, null, null]);
    expect(active.map((role) => role.state)).toEqual([
      'idle',
      'working',
      'working',
    ]);
    expect(active.every((role) => ActiveRun.safeParse(role).success)).toBe(
      true,
    );

    const file = {
      schemaVersion: 1,
      processRef,
      writtenAt: new Date(now).toISOString(),
      pools: [],
      unbound: [],
      unavailable: [],
      activeRuns: active,
    };

    expect(
      BudgetCacheFile.parse(JSON.parse(JSON.stringify(file))).activeRuns,
    ).toEqual(active);
  });

  test('resolved team members remain planned until opened; closed roles stay ended', () => {
    const agents: Work = {
      ...noAgents<Driven>(),
      children: [
        {
          id: 'lead',
          key: 2,
          name: 'bugfix',
          runtime: 'codex',
          conversation,
          wait: idle,
          openedAt: now,
          colour: 0,
          team: 'bugfix',
        },
      ],
    };
    const runs = new Map([['lead', { name: 'bugfix', team }]]);

    expect(
      activeResourceRuns(agents, runs, [], processRef, now).map((role) => [
        role.member,
        role.state,
      ]),
    ).toEqual([
      ['lead', 'idle'],
      ['reviewer', 'planned'],
      ['tester', 'planned'],
    ]);

    const changed: Work = {
      ...agents,
      children: [
        ...agents.children,
        {
          id: 'reviewer',
          key: 3,
          name: 'reviewer',
          runtime: 'claude',
          conversation: { session: undefined },
          wait: { ...idle, ended: { failure: 'start' } },
          openedAt: now,
          colour: 1,
          team: 'bugfix',
          lead: 'lead',
        },
      ],
      closed: [
        {
          id: 'tester',
          name: 'tester',
          runtime: 'codex',
          openedAt: now,
          colour: 2,
          team: 'bugfix',
          lead: 'lead',
        },
      ],
    };

    expect(
      activeResourceRuns(changed, runs, [], processRef, now).map((role) => [
        role.member,
        role.state,
      ]),
    ).toEqual([
      ['lead', 'idle'],
      ['tester', 'ended'],
      ['reviewer', 'refused'],
    ]);
  });
});

describe('tester: active work state precedence and run isolation', () => {
  test('ended sessions override a working wait and starting tasks retain only planned model facts', () => {
    const agents: Work = {
      ...noAgents<Driven>(),
      main: {
        key: 1,
        agent: 'codex',
        conversation: {
          session: { ...conversation.session!, gone: () => 'Fixture exited.' },
        },
        wait: { ...idle, working: now },
      },
    };
    const roles = activeResourceRuns(
      agents,
      new Map(),
      [
        {
          id: 'starting-task',
          name: 'helper',
          agent: 'claude',
          model: 'planned-model',
          team: null,
          runRef: 'main-1',
          conversation: { session: undefined },
        },
      ],
      processRef,
      now,
    );

    expect(roles.map((role) => [role.state, role.model, role.team])).toEqual([
      ['ended', 'current-model', null],
      ['starting', 'planned-model', null],
    ]);
    expect(roles.every((role) => role.resourceRefs.length === 0)).toBe(true);
  });

  test('an opened member in one run cannot consume the same planned role in another', () => {
    const lead = {
      id: 'first-lead',
      key: 2,
      name: 'first',
      runtime: 'codex',
      conversation,
      wait: idle,
      openedAt: now,
      colour: 0,
      team: 'first',
    };
    const agents: Work = {
      ...noAgents<Driven>(),
      children: [
        lead,
        { ...lead, id: 'second-lead', key: 3, name: 'second', team: 'second' },
        {
          ...lead,
          id: 'opened-reviewer',
          key: 4,
          name: 'reviewer',
          runtime: 'claude',
          lead: 'first-lead',
        },
      ],
    };
    const runs = new Map([
      ['first-lead', { name: 'first', team }],
      ['second-lead', { name: 'second', team }],
    ]);
    const roles = activeResourceRuns(agents, runs, [], processRef, now);

    expect(
      roles
        .filter((role) => role.member === 'reviewer')
        .map((role) => [role.runRef, role.state]),
    ).toEqual([
      ['second-lead', 'planned'],
      ['first-lead', 'idle'],
    ]);
  });
});
