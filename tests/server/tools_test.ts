import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { PermissionWait } from '../../src/session/transcript/types.ts';
import { parseTeam, type Team } from '../../src/teams.ts';
import {
  agentsAnswer,
  type Caller,
  monitorsAnswer,
  monitorsText,
  monitorText,
  type ProposeAnswer,
  proposeTeam,
  proposeText,
  type RuntimeOffer,
  sessionsAnswer,
  stopMonitorText,
  type TeamPlaces,
  teamsAnswer,
  type WindowView,
} from '../../src/server/tools.ts';

const OFFER: RuntimeOffer = {
  models: [{ id: 'fake-large', name: 'Fake Large' }],
  current: 'fake-large',
  modes: [
    { id: 'default', name: 'Default' },
    { id: 'plan', name: 'Plan' },
  ],
  currentMode: 'default',
};

/** A window of three runtimes: one read, one failing, one never read. */
function windowOf(probed: string[] = []): WindowView {
  return {
    sessions: () => [
      {
        key: 0,
        runtime: 'fake',
        id: 'one',
        model: 'fake-large',
        children: [],
      },
    ],
    runtimes: () => ['fake', 'broken', 'claude'],
    offer: (runtime, probe) => {
      if (probe) {
        probed.push(runtime);
      }

      return Promise.resolve(
        runtime === 'fake'
          ? OFFER
          : runtime === 'broken'
            ? { error: 'Unknown agent "broken".' }
            : probe
              ? OFFER
              : undefined,
      );
    },
    spawn: () => Promise.resolve({ error: 'no tasks here' }),
    teams: () => Promise.resolve({ found: [], runs: [] }),
    runTeam: () => Promise.resolve({ error: 'no teams here' }),
    teamPlaces: () => Promise.reject(new Error('no teams here')),
    askPerson: () => Promise.resolve(undefined),
    openMember: () => Promise.resolve({ error: 'no members here' }),
    message: () => ({ error: 'no parent here' }),
    open: () => Promise.resolve({ error: 'no agents here' }),
    tell: () => ({ error: 'no children here' }),
    close: () => ({ error: 'no children here' }),
    monitor: () => ({ error: 'no monitors here' }),
    stopMonitor: () => ({ error: 'no monitors here' }),
    monitors: () => [],
    served: () => {},
    servedLater(caller) {
      return (call) => this.served(caller, call);
    },
  };
}

test('list_agents names every runtime, with the models and modes read and how to read the rest, starting none', async () => {
  const probed: string[] = [];

  expect(await agentsAnswer(windowOf(probed))).toStrictEqual({
    agents: [
      {
        name: 'fake',
        models: [{ id: 'fake-large', name: 'Fake Large' }],
        current: 'fake-large',
        modes: [
          { id: 'default', name: 'Default' },
          {
            id: 'plan',
            name: 'Plan',
          },
        ],
        currentMode: 'default',
      },
      {
        name: 'broken',
        note: 'models and modes could not be read: Unknown agent "broken".',
      },
      {
        name: 'claude',
        note: 'models and modes not read yet; list_agents with agent "claude" reads them',
      },
    ],
  });
  expect(probed).toStrictEqual([]);
});

test('list_agents with an agent reads that one, starting it if need be', async () => {
  const probed: string[] = [];

  expect(await agentsAnswer(windowOf(probed), 'claude')).toStrictEqual({
    agents: [
      {
        name: 'claude',
        models: [{ id: 'fake-large', name: 'Fake Large' }],
        current: 'fake-large',
        modes: [
          { id: 'default', name: 'Default' },
          { id: 'plan', name: 'Plan' },
        ],
        currentMode: 'default',
      },
    ],
  });
  expect(probed).toStrictEqual(['claude']);
});

test('list_agents with a runtime chord does not know says so and starts nothing', async () => {
  const probed: string[] = [];

  expect(await agentsAnswer(windowOf(probed), 'codx')).toStrictEqual({
    agents: [
      {
        name: 'codx',
        note: 'chord knows no runtime named codx; list_agents without an agent names every one',
      },
    ],
  });
  expect(probed).toStrictEqual([]);
});

test("list_sessions gives the window's session, the caller's marked, and no tab (CHD-493)", () => {
  const window = windowOf();

  expect(sessionsAnswer({ role: 'person', key: 0, window })).toStrictEqual({
    sessions: [
      {
        id: 'one',
        runtime: 'fake',
        model: 'fake-large',
        you: true,
      },
    ],
  });
  expect(sessionsAnswer({ role: 'person', key: 5, window })).toStrictEqual({
    sessions: [{ id: 'one', runtime: 'fake', model: 'fake-large' }],
  });
});

test("list_sessions gives each session's long-lived agents with it, and a child is never `you`", () => {
  const window: WindowView = {
    ...windowOf(),
    sessions: () => [
      {
        key: 0,
        runtime: 'claude',
        id: 'one',
        model: 'opus',
        children: [
          {
            id: '7f3a9c2e',
            name: 'parser',
            runtime: 'codex',
            model: undefined,
          },
        ],
      },
    ],
  };
  const parser = [
    {
      id: '7f3a9c2e',
      name: 'parser',
      runtime: 'codex',
      model: null,
    },
  ];

  expect(sessionsAnswer({ role: 'person', key: 0, window })).toStrictEqual({
    sessions: [
      {
        id: 'one',
        runtime: 'claude',
        model: 'opus',
        you: true,
        agents: parser,
      },
    ],
  });
  expect(
    sessionsAnswer({ role: 'child', key: 0, agent: '7f3a9c2e', window }),
  ).toStrictEqual({
    sessions: [
      {
        id: 'one',
        runtime: 'claude',
        model: 'opus',
        agents: parser,
      },
    ],
  });
});

test('the monitor tools say what the model reads: the id, how events come, and what runs', () => {
  expect(
    monitorText({
      id: 'm1',
      description: 'dev server errors',
      timeout_ms: 600_000,
    }),
  ).toStrictEqual(
    'Started monitor m1 (dev server errors); it times out in 10m. Its ' +
      'output does not come in this answer: each batch of lines (up to 100, ' +
      'gathered over 200 ms) reaches you later as a message from "dev server ' +
      'errors · monitor", and so does its end. Keep working. stop_monitor ' +
      'with id "m1" stops it.',
  );
  expect(
    stopMonitorText({
      id: 'm1',
      description: 'dev server errors',
      events: 3,
      ran_ms: 252_000,
    }),
  ).toStrictEqual('Stopped m1 (dev server errors) after 4m 12s and 3 events.');

  const running = [
    {
      id: 'm1',
      description: 'dev server errors',
      command: 'tail -f dev.log',
      startedAt: 0,
      timeoutMs: 600_000,
      events: 3,
    },
    {
      id: 'm2',
      description: 'CI run 4812',
      command: 'gh run watch 4812',
      startedAt: 300_000,
      timeoutMs: 3_600_000,
      events: 0,
    },
  ];

  expect(monitorsText(running, 360_000)).toStrictEqual(
    '2 running: m1 dev server errors (6m, 3 events), m2 CI run 4812 (1m, ' +
      'no events)',
  );
  expect(monitorsText([], 0)).toStrictEqual('No monitors running');
  expect(monitorsAnswer(running).monitors[1]).toStrictEqual({
    id: 'm2',
    description: 'CI run 4812',
    command: 'gh run watch 4812',
    started_at: '1970-01-01T00:05:00.000Z',
    events: 0,
    timeout_ms: 3_600_000,
  });
});

test("list_teams gives each team's agents and its open runs, and a broken file's problem", () => {
  expect(
    teamsAnswer({
      found: [
        {
          name: 'bugfix',
          file: '/p/.chord/teams/bugfix.md',
          place: 'project',
          hides: false,
          team: {
            description: 'Fixes a bug',
            lead: {
              agent: 'claude',
              model: 'opus',
              effort: 'high',
              instructions: '  Keep lead requirements.\n',
            },
            members: [
              {
                name: 'tester',
                role: 'Writes the test',
                agent: 'claude',
                mode: 'acceptEdits',
                effort: 'medium',
                instructions: 'Test it.',
              },
            ],
            body: 'How.',
          },
        },
        {
          name: 'triage',
          file: '/u/teams/triage.md',
          place: 'user',
          hides: false,
          problem: 'members.1.agent is missing',
        },
      ],
      runs: [
        { team: 'bugfix', name: 'bugfix' },
        { team: 'bugfix', name: 'bugfix 2' },
        { team: 'review', name: 'review' },
      ],
    }),
  ).toStrictEqual({
    runs: [
      { team: 'bugfix', name: 'bugfix' },
      { team: 'bugfix', name: 'bugfix 2' },
      { team: 'review', name: 'review' },
    ],
    teams: [
      {
        name: 'bugfix',
        description: 'Fixes a bug',
        body: 'How.',
        lead: {
          agent: 'claude',
          model: 'opus',
          effort: 'high',
          instructions: '  Keep lead requirements.\n',
        },
        members: [
          {
            name: 'tester',
            role: 'Writes the test',
            agent: 'claude',
            mode: 'acceptEdits',
            effort: 'medium',
            instructions: 'Test it.',
          },
        ],
        runs: ['bugfix', 'bugfix 2'],
      },
      {
        name: 'triage',
        problem:
          'members.1.agent is missing; it cannot run until its ' +
          'file is fixed',
      },
    ],
  });
});

/** A team as `propose_team` takes it. */
const PROPOSED = {
  name: 'bugfix',
  description: 'Fixes a bug end to end',
  lead: { agent: 'fake', model: 'fake-large' },
  members: [
    {
      name: 'tester',
      role: 'Writes the failing test',
      agent: 'fake',
      mode: 'plan',
      instructions: 'Write the smallest failing test.',
    },
  ],
  body: '# How bugfix works\n\nThe lead splits the job.',
};

/**
 * `propose_team` called from a window whose teams go in `dir`, the person
 * picking `pick`: what was drawn as it waited, the box asked, and the answer.
 */
async function proposed(
  dir: string,
  pick: string | undefined,
  {
    input = PROPOSED as unknown,
    saved,
  }: {
    input?: unknown;
    saved?: TeamPlaces['saved'];
  } = {},
) {
  const asked: Omit<PermissionWait, 'id'>[] = [];
  const shown: ProposeAnswer[] = [];
  const window: WindowView = {
    ...windowOf(),
    teamPlaces: () =>
      Promise.resolve({
        agent: 'claude',
        project: {
          file: join(dir, 'project', 'bugfix.md'),
          shown: '.chord/teams/bugfix.md',
        },
        user: {
          file: join(dir, 'user', 'bugfix.md'),
          shown: '~/.config/chord/teams/bugfix.md',
        },
        ...(saved === undefined ? {} : { saved }),
      }),
    askPerson: (_caller, wait) => {
      asked.push(wait);

      return Promise.resolve(pick);
    },
  };
  const caller: Caller = { role: 'person', key: 0, window };
  const answer = await proposeTeam(
    caller,
    input,
    new AbortController().signal,
    (one) => shown.push(one),
  );

  return { asked, shown, answer };
}

test('propose_team refuses a team that fails the check with its first problem, asking nothing', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-'));

  try {
    const { asked, answer } = await proposed(dir, 'project', {
      input: { ...PROPOSED, lead: { agent: 'nobody' } },
    });

    expect(answer).toStrictEqual({
      error: 'lead.agent: chord knows no runtime named nobody',
    });
    expect(asked).toStrictEqual([]);
    expect(
      (
        await proposed(dir, 'project', {
          input: { ...PROPOSED, name: 'main' },
        })
      ).answer,
    ).toStrictEqual({ error: 'the name main is taken' });
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('propose_team draws the proposal, asks where to save it, and chord writes the file the person picked', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-'));

  try {
    const { asked, shown, answer } = await proposed(dir, 'user');

    expect(shown).toStrictEqual([
      {
        proposal: 'new',
        files: {
          project: '.chord/teams/bugfix.md',
          user: '~/.config/chord/teams/bugfix.md',
        },
      },
    ]);
    expect(asked[0]?.save).toStrictEqual({
      question: 'Save team bugfix?',
      files: {
        project: '.chord/teams/bugfix.md',
        user: '~/.config/chord/teams/bugfix.md',
      },
      escape: 'tell claude what to change',
    });
    expect(asked[0]?.options.map((option) => option.name)).toStrictEqual([
      'Yes, for this project',
      'Yes, for every project',
      'No, tell claude what to change',
    ]);
    expect(answer).toStrictEqual({
      ...shown[0]!,
      saved: '~/.config/chord/teams/bugfix.md',
    });
    expect(
      proposeText(answer as Exclude<ProposeAnswer, { error: string }>),
    ).toStrictEqual('Saved to ~/.config/chord/teams/bugfix.md.');

    const text = await readFile(join(dir, 'user', 'bugfix.md'), 'utf8');
    const read = parseTeam('bugfix', text, ['fake']);

    assert('team' in read);
    expect(read.team.members[0]?.mode).toStrictEqual('plan');
    expect(read.team.body).toStrictEqual(PROPOSED.body);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('propose_team writes nothing when the person will say what to change, or the question is withdrawn', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-'));

  try {
    const change = await proposed(dir, 'change');

    expect(change.answer).toStrictEqual({ ...change.shown[0]!, saved: false });
    expect(
      proposeText(change.answer as Exclude<ProposeAnswer, { error: string }>),
    ).toStrictEqual(
      'The person did not save it; they will say what to change.',
    );

    const withdrawn = await proposed(dir, undefined);

    expect('error' in withdrawn.answer).toBeTruthy();
    expect([...readdirSync(dir, { withFileTypes: true })]).toStrictEqual([]);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("propose_team under a saved team's name is a change, saved back where that team is", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-'));
  const before: Team = { ...PROPOSED, body: 'Old ways.' } as Team;

  try {
    const file = join(dir, 'user', 'bugfix.md');
    const { asked, shown, answer } = await proposed(dir, 'replace', {
      saved: { file, shown: '~/.config/chord/teams/bugfix.md', team: before },
    });

    expect(shown[0]).toStrictEqual({
      proposal: 'change',
      files: { user: '~/.config/chord/teams/bugfix.md' },
      before,
    });
    expect(asked[0]?.save?.question).toStrictEqual('Replace team bugfix?');
    expect(asked[0]?.options.map((option) => option.name)).toStrictEqual([
      'Yes, in ~/.config/chord/teams/bugfix.md',
      'No, tell claude what to change',
    ]);
    expect((answer as { saved?: string }).saved).toStrictEqual(
      '~/.config/chord/teams/bugfix.md',
    );
    expect(await readFile(file, 'utf8')).toContain('The lead splits');
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('propose_team says a write that failed, as a refusal', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-'));

  try {
    // A file where the directory would go.
    await writeFile(join(dir, 'project'), '');

    const { answer } = await proposed(dir, 'project');

    assert('error' in answer);
    expect(answer.error).toContain('.chord/teams/bugfix.md was not saved');
  } finally {
    await rm(dir, { recursive: true });
  }
});

describe('CHD-493 U4 tester: list_sessions during startup', () => {
  test('unknown session and model remain null without leaking internal keys or probing agents', () => {
    const probed: string[] = [];
    const window: WindowView = {
      ...windowOf(probed),
      sessions: () => [
        {
          key: 17,
          runtime: 'fake',
          id: undefined,
          model: undefined,
          children: [
            {
              id: 'worker-id',
              name: 'worker',
              runtime: 'codex',
              model: undefined,
            },
          ],
        },
      ],
    };

    for (const role of ['person', 'child'] as const) {
      expect(sessionsAnswer({ role, key: 17, window })).toStrictEqual({
        sessions: [
          {
            id: null,
            runtime: 'fake',
            model: null,
            ...(role === 'person' ? { you: true } : {}),
            agents: [
              {
                id: 'worker-id',
                name: 'worker',
                runtime: 'codex',
                model: null,
              },
            ],
          },
        ],
      });
    }

    expect(probed).toStrictEqual([]);
  });
});

test('list_teams adds only actual known run IDs and keeps existing run names', () => {
  expect(
    teamsAnswer({
      found: [],
      runs: [
        { team: 'fixture', name: 'fixture', id: 'actual-id' },
        { team: 'legacy', name: 'legacy' },
      ],
    }),
  ).toEqual({
    teams: [],
    runs: [
      { team: 'fixture', name: 'fixture', id: 'actual-id' },
      { team: 'legacy', name: 'legacy' },
    ],
  });
});
