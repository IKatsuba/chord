import { describe, expect, test } from 'bun:test';
import type { TeamAgentShown } from '../../../src/session/transcript/types.ts';
import type { Team } from '../../../src/teams.ts';
import {
  headlineText,
  type ListedTeam,
  messageHeadline,
  newTeamPrompt,
  pickedDraft,
  ranNote,
  runningHeader,
  type RunningLine,
  runningTable,
  runningWords,
  stoppedLine,
  teamChoices,
  teamCommand,
  teamRefusal,
  teamsHint,
  teamsWhere,
} from '../../../src/ui/teams/teams.ts';

const BUGFIX: Team = {
  description: 'Fixes a bug end to end: a failing test first, then the fix.',
  lead: { agent: 'claude', model: 'opus', mode: 'default' },
  members: [
    {
      name: 'tester',
      role: 'Writes the failing test',
      agent: 'claude',
      model: 'sonnet',
      mode: 'acceptEdits',
      instructions: 'Write it.',
    },
    {
      name: 'coder',
      role: 'Writes the fix',
      agent: 'codex',
      model: 'gpt-5.3-codex',
      mode: 'auto',
      instructions: 'Fix it.',
    },
    {
      name: 'reviewer',
      role: 'Reads the diff',
      agent: 'claude',
      model: 'opus',
      mode: 'plan',
      instructions: 'Read it.',
    },
  ],
  body: '# How bugfix works\n\nOne writer per file.',
};

const TEAMS: ListedTeam[] = [
  {
    name: 'bugfix',
    file: '/w/.chord/teams/bugfix.md',
    shown: '.chord/teams/bugfix.md',
    place: 'project',
    hides: false,
    team: BUGFIX,
  },
  {
    name: 'review',
    file: '/h/.config/chord/teams/review.md',
    shown: '~/.config/chord/teams/review.md',
    place: 'user',
    hides: false,
    team: {
      ...BUGFIX,
      description: 'Reviews a branch before it goes to the owner',
      members: BUGFIX.members.slice(0, 2).map((member) => ({
        ...member,
        agent: 'claude',
      })),
    },
  },
  {
    name: 'triage',
    file: '/h/.config/chord/teams/triage.md',
    shown: '~/.config/chord/teams/triage.md',
    place: 'user',
    hides: false,
    problem: 'members.1.agent is missing',
  },
];

test('/team reads its forms: list, new, show, run, stop', () => {
  expect(teamCommand('')).toStrictEqual({ form: 'list' });
  expect(teamCommand('list')).toStrictEqual({ form: 'list' });
  expect(teamCommand('new fixes bugs, a test first')).toStrictEqual({
    form: 'new',
    words: 'fixes bugs, a test first',
  });
  expect(teamCommand('show bugfix')).toStrictEqual({
    form: 'show',
    name: 'bugfix',
  });
  expect(teamCommand('run bugfix issue 214: a quote\nis lost')).toStrictEqual({
    form: 'run',
    name: 'bugfix',
    job: 'issue 214: a quote\nis lost',
  });
  // A second run's name is two words.
  expect(teamCommand('stop bugfix  2')).toStrictEqual({
    form: 'stop',
    name: 'bugfix 2',
  });
});

test('/team refuses a form it does not know, and one missing what it takes', () => {
  expect(teamCommand('delete bugfix')).toStrictEqual({
    form: 'refused',
    problem: '/team has no delete; it takes list, new, show, run or stop',
  });
  // A team is changed by asking main in plain words.
  expect(teamCommand('edit bugfix')).toStrictEqual({
    form: 'refused',
    problem: '/team has no edit; it takes list, new, show, run or stop',
  });
  expect(teamCommand('run bugfix')).toStrictEqual({
    form: 'refused',
    problem: '/team run bugfix takes the job after the name',
  });
  expect(teamCommand('show')).toStrictEqual({
    form: 'refused',
    problem: 'Which team? /team lists them',
  });
  expect(teamCommand('new').form).toStrictEqual('refused');
  expect(teamCommand('stop').form).toStrictEqual('refused');
});

test("main gets /team new's words after one line naming propose_team", () => {
  const made = newTeamPrompt('fixes bugs');
  const [line, ...rest] = made.split('\n');

  expect(line!.includes('propose_team')).toBeTruthy();
  expect(rest.join('\n')).toStrictEqual('\nfixes bugs');
});

test("chord's note to main names the job, the lead and how to reach it", () => {
  expect(ranNote('bugfix', 'bugfix 2', 'issue 214')).toStrictEqual(
    'The person handed team bugfix this job: "issue 214". Its lead is ' +
      '@bugfix 2 and reports to you; send_message reaches it.',
  );
});

test('a team not found, or broken, is refused with its file and its problem', () => {
  expect(teamRefusal('bugfx', undefined)).toStrictEqual(
    'No team named bugfx · /team lists them',
  );
  expect(teamRefusal('triage', TEAMS[2])).toStrictEqual(
    '~/.config/chord/teams/triage.md is not a team chord can run:\n' +
      'members.1.agent is missing',
  );
  expect(teamRefusal('bugfix', TEAMS[0])).toStrictEqual(undefined);
});

test('/team stop says who it closed', () => {
  expect(stoppedLine('bugfix', ['tester', 'coder', 'reviewer'])).toStrictEqual(
    'Stopped bugfix: its lead, tester, coder, and reviewer are closed · ' +
      '/resume lists them',
  );
  expect(stoppedLine('bugfix 2', [])).toStrictEqual(
    'Stopped bugfix 2: its lead is closed · /resume lists it',
  );
});

test("a team's running state is its run's time, or how many runs", () => {
  expect(runningWords([], 0)).toStrictEqual('');
  expect(
    runningWords([{ team: 'bugfix', name: 'bugfix', since: 0 }], 361_000),
  ).toStrictEqual('✻ working 6m');
  expect(
    runningWords(
      [
        { team: 'bugfix', name: 'bugfix', since: 0 },
        { team: 'bugfix', name: 'bugfix 2', since: 0 },
      ],
      1,
    ),
  ).toStrictEqual('✻ 2 runs');
});

test('the picker lines up each team in columns, a broken file with its problem and path', () => {
  const runs = [{ team: 'bugfix', name: 'bugfix', since: 0 }];
  const wide = teamChoices(TEAMS, runs, 361_000, 116).map(({ label }) => label);

  expect(wide).toStrictEqual([
    'bugfix  4 agents · claude, codex  this project   ✻ working 6m  ' +
      'Fixes a bug end to end: a failing test first, then the fix.',
    'review  3 agents · claude         every project                ' +
      'Reviews a branch before it goes to the owner',
    'triage  ✗ not read: members.1.agent is missing                 ' +
      '~/.config/chord/teams/triage.md',
  ]);

  // With nothing running the path still starts where the description does.
  expect(
    teamChoices(TEAMS, [], 0, 116).map(({ label }) => label),
  ).toStrictEqual([
    'bugfix  4 agents · claude, codex  this project   ' +
      'Fixes a bug end to end: a failing test first, then the fix.',
    'review  3 agents · claude         every project  ' +
      'Reviews a branch before it goes to the owner',
    'triage  ✗ not read: members.1.agent is missing   ' +
      '~/.config/chord/teams/triage.md',
  ]);

  // A problem wider than the columns before the description moves the
  // description over, for the path to start where it does.
  const longer = TEAMS.map((found) =>
    'problem' in found
      ? { ...found, problem: 'members.1.agent is missing, and so is lead' }
      : found,
  );

  expect(
    teamChoices(longer.slice(1), [], 0, 116).map(({ label }) => label),
  ).toStrictEqual([
    'review  3 agents · claude  every project                        ' +
      'Reviews a branch before it goes to the owner',
    'triage  ✗ not read: members.1.agent is missing, and so is lead  ' +
      '~/.config/chord/teams/triage.md',
  ]);

  // At 80 columns the runtimes and the broken file's path go.
  const narrow = teamChoices(TEAMS, [], 0, 76).map(({ label }) => label);

  expect(narrow).toStrictEqual([
    'bugfix  4 agents  this project   Fixes a bug end to end: a failing test ' +
      'first, then the fix.',
    'review  3 agents  every project  Reviews a branch before it goes to the ' +
      'owner',
    'triage  ✗ not read: members.1.agent is missing',
  ]);
});

test("the picker says where teams are saved, and Enter's draft runs a team, and a broken one has none", () => {
  expect(
    teamsWhere({ project: '.chord/teams', user: '~/.config/chord/teams' }, 116),
  ).toStrictEqual(
    'Saved for this project in .chord/teams, and for every project in ' +
      '~/.config/chord/teams.',
  );
  expect(teamsWhere({ project: '.chord/teams' }, 76)).toStrictEqual(
    'Saved for this project in .chord/teams.',
  );
  expect(pickedDraft(TEAMS[0]!)).toStrictEqual('/team run bugfix ');
  expect(pickedDraft(TEAMS[2]!)).toStrictEqual(undefined);
});

test("the picker's hint offers Enter on a team it can run, and says how a broken one gets fixed", () => {
  expect(teamsHint(TEAMS[0]!, 116)).toStrictEqual([
    'Enter to hand it a job',
    '/team show <name>',
  ]);
  expect(teamsHint(TEAMS[0]!, 76)).toStrictEqual(['Enter to hand it a job']);
  expect(teamsHint(TEAMS[2]!, 116)).toStrictEqual([
    'Fix the file, or ask main to fix triage',
  ]);
  expect(teamsHint(TEAMS[2]!, 76)).toStrictEqual(['Ask main to fix triage']);
  expect(teamsHint(undefined, 116)).toStrictEqual([]);
});

test("/team show's running form gives each agent its file's mode, its state and latest headline, wrapped to the width (CHD-471)", () => {
  const run = {
    name: 'bugfix',
    since: 0,
    at: 361_000,
    job: 'strings at the end of a line lose their closing quote; see issue',
    agents: [
      {
        name: 'lead',
        lead: true as const,
        open: true,
        state: { glyph: '✻', words: 'working 8s', tone: 'dim' as const },
        latest: headlineText({ name: 'coder', sent: true }),
      },
      {
        name: 'tester',
        open: true,
        state: {
          glyph: '●',
          words: 'permission 12s',
          tone: 'warning' as const,
        },
        latest: headlineText({
          name: 'Bash',
          arg: 'deno task test tests/parse',
        }),
      },
      { name: 'coder', open: true },
      { name: 'reviewer', open: false },
    ],
  };

  expect(
    runningHeader('bugfix', '.chord/teams/bugfix.md', run, 70),
  ).toStrictEqual([
    'bugfix · .chord/teams/bugfix.md · working 6m on "strings at the end of',
    'a line lose their closing quote; see issue"',
  ]);

  const lines = runningTable(BUGFIX, run.agents, 200);

  expect(lines.map(({ text }) => text)).toStrictEqual([
    'lead      claude · opus          default      ✻ working 8s      → to @coder',
    'tester    claude · sonnet        acceptEdits  ● permission 12s  ' +
      'Bash(deno task test tests/parse)',
    'coder     codex · gpt-5.3-codex  auto         idle',
    'reviewer  claude · opus          plan         not opened',
  ]);
  expect(lines[1]!.text.slice(...lines[1]!.state)).toStrictEqual(
    '● permission 12s',
  );

  expect(lines.map(({ under }) => under)).toStrictEqual([[], [], [], []]);

  // At 70 the headline would keep fewer than 20 cells beside the state, so
  // it goes under the row, from the runtime's column.
  const narrow = runningTable(BUGFIX, run.agents, 70);

  expect(narrow.flatMap(({ text, under }) => [text, ...under])).toStrictEqual([
    'lead      claude · opus          default      ✻ working 8s',
    '          → to @coder',
    'tester    claude · sonnet        acceptEdits  ● permission 12s',
    '          Bash(deno task test tests/parse)',
    'coder     codex · gpt-5.3-codex  auto         idle',
    'reviewer  claude · opus          plan         not opened',
  ]);

  // With 20 cells or more beside the row it wraps there.
  const latest = 'Bash(deno task test tests/parse --filter strings)';
  const wrapped = runningTable(BUGFIX, [{ ...run.agents[1]!, latest }], 80);

  expect(wrapped[0]!.text).toStrictEqual(
    'tester  claude · sonnet  acceptEdits  ● permission 12s  Bash(deno task test',
  );
  expect(wrapped[0]!.under).toStrictEqual([
    '                                                        tests/parse --filter',
    '                                                        strings)',
  ]);
});

test("/team show's running form reads the lead's runtime from the lead, though a member is named lead", () => {
  const team = {
    ...BUGFIX,
    members: [
      { ...BUGFIX.members[0]!, name: 'lead', model: 'sonnet', mode: 'plan' },
    ],
  };
  const lines = runningTable(
    team,
    [
      { name: 'lead', lead: true, open: true },
      {
        name: 'lead',
        open: true,
        latest: messageHeadline({
          name: 'tester',
          runtime: 'claude',
          reachable: true,
        }),
      },
    ],
    200,
  );

  expect(lines.map(({ text }) => text)).toStrictEqual([
    'lead  claude · opus    default  idle',
    'lead  claude · sonnet  plan     idle  ← from @tester · claude',
  ]);
});

test("/team show's running form has the file's efforts as a column, which gives way where that keeps the headline beside the row", () => {
  const team: Team = {
    ...BUGFIX,
    lead: { ...BUGFIX.lead, effort: 'high' },
    members: [{ ...BUGFIX.members[0]!, effort: 'low' }, BUGFIX.members[1]!],
  };
  const agents = [
    {
      name: 'lead',
      lead: true as const,
      open: true,
      state: { glyph: '✓', words: 'replied 6s ago', tone: 'dim' as const },
      latest: '← from @tester · claude',
    },
    {
      name: 'tester',
      open: true,
      state: {
        glyph: '●',
        words: 'permission 5s',
        tone: 'warning' as const,
      },
      latest: 'Bash(deno task test tests/parse)',
    },
    { name: 'coder', open: false },
  ];
  const wide = runningTable(team, agents, 114);

  expect(wide.map(({ text }) => text)).toStrictEqual([
    'lead    claude · opus          high  default      ✓ replied 6s ago  ← from @tester · claude',
    'tester  claude · sonnet        low   acceptEdits  ● permission 5s   Bash(deno task test tests/parse)',
    'coder   codex · gpt-5.3-codex  —     auto         not opened',
  ]);
  expect(wide[1]!.text.slice(...wide[1]!.state)).toStrictEqual(
    '● permission 5s',
  );

  // At 86 the effort would leave the headline 18 cells; without it, 24.
  const between = runningTable(team, agents, 86);

  expect(between.flatMap(({ text, under }) => [text, ...under])).toStrictEqual([
    'lead    claude · opus          default      ✓ replied 6s ago  ← from @tester · claude',
    'tester  claude · sonnet        acceptEdits  ● permission 5s   Bash(deno task test',
    '                                                              tests/parse)',
    'coder   codex · gpt-5.3-codex  auto         not opened',
  ]);
  expect(between[1]!.text.slice(...between[1]!.state)).toStrictEqual(
    '● permission 5s',
  );

  // At 74 the headline goes under the row either way, so the effort stays.
  const narrow = runningTable(team, agents, 74);

  expect(narrow.map(({ text }) => text)).toStrictEqual([
    'lead    claude · opus          high  default      ✓ replied 6s ago',
    'tester  claude · sonnet        low   acceptEdits  ● permission 5s',
    'coder   codex · gpt-5.3-codex  —     auto         not opened',
  ]);
  expect(narrow[1]!.under).toStrictEqual([
    '        Bash(deno task test tests/parse)',
  ]);
});

test("/team show's running form says what of an agent is not yet seen beside its state, the marks in one column (CHD-471)", () => {
  const idle = { glyph: '◦', words: 'idle 3m', tone: 'dim' as const };
  const lines = runningTable(
    BUGFIX,
    [
      {
        name: 'lead',
        lead: true,
        open: true,
        state: { glyph: '✻', words: 'working 8s', tone: 'dim' },
      },
      {
        name: 'tester',
        open: true,
        state: idle,
        mark: { glyph: '✓', words: 'new reply', tone: 'success' },
      },
      { name: 'coder', open: true, state: idle },
      { name: 'reviewer', open: false },
    ],
    200,
  );

  expect(lines.map(({ text }) => text)).toStrictEqual([
    'lead      claude · opus          default      ✻ working 8s',
    'tester    claude · sonnet        acceptEdits  ◦ idle 3m     ✓ new reply',
    'coder     codex · gpt-5.3-codex  auto         ◦ idle 3m',
    'reviewer  claude · opus          plan         not opened',
  ]);
  expect(lines[1]!.text.slice(...lines[1]!.state)).toStrictEqual('◦ idle 3m');
  expect(lines[1]!.text.slice(...lines[1]!.mark!)).toStrictEqual('✓ new reply');
  expect(lines[2]!.mark).toBe(undefined);
});

describe("/team show's running form wraps its own columns where they are wider than the width, and hides nothing (CHD-471)", () => {
  const team: Team = {
    ...BUGFIX,
    lead: { agent: 'fake', model: 'fake-large', mode: 'default' },
    members: [
      {
        ...BUGFIX.members[0]!,
        agent: 'fake',
        model: 'claude-opus-5-5-20261001-preview-long',
      },
      {
        ...BUGFIX.members[1]!,
        name: 'a-member-with-a-name-far-longer-than-a-third',
        agent: 'fake',
        model: 'fake-large',
        mode: 'plan',
      },
    ],
  };
  const agents: TeamAgentShown[] = [
    {
      name: 'lead',
      lead: true,
      open: true,
      state: { glyph: '◦', words: 'idle 9s', tone: 'dim' },
      mark: { glyph: '✓', words: 'new reply', tone: 'success' },
      latest: '← from @tester · fake',
    },
    {
      name: 'tester',
      open: true,
      state: { glyph: '●', words: 'permission 8s', tone: 'warning' },
      mark: { glyph: '←', words: 'new message', tone: 'dim' },
      latest: 'Bash(deno task test tests/parse)',
    },
  ];
  const drawn = (lines: readonly RunningLine[]) =>
    lines.flatMap(({ text, under }) => [text, ...under]);
  const states = (lines: readonly RunningLine[]) =>
    lines.map((line) => {
      const on = [line.text, ...line.under][line.stateLine]!;

      return [
        on.slice(...line.state),
        line.mark === undefined ? undefined : on.slice(...line.mark),
      ];
    });

  test('at 72 the model id wraps after its runtime in a third of the width, and the state and mark go whole under the row', () => {
    const lines = runningTable(team, agents, 72);

    expect(drawn(lines)).toStrictEqual([
      'lead    fake · fake-large         default',
      '        ◦ idle 9s        ✓ new reply',
      '        ← from @tester · fake',
      'tester  fake ·                    acceptEdits',
      '        claude-opus-5-5-20261001',
      '        -preview-long',
      '        ● permission 8s  ← new message',
      '        Bash(deno task test tests/parse)',
    ]);
    expect(states(lines)).toStrictEqual([
      ['◦ idle 9s', '✓ new reply'],
      ['● permission 8s', '← new message'],
    ]);
  });

  test('at 112 the row has room for its own columns', () => {
    const lines = runningTable(team, agents, 112);

    expect(drawn(lines)).toStrictEqual([
      'lead    fake · fake-large                             default      ◦ idle 9s        ✓ new reply',
      '        ← from @tester · fake',
      'tester  fake · claude-opus-5-5-20261001-preview-long  acceptEdits  ● permission 8s  ← new message',
      '        Bash(deno task test tests/parse)',
    ]);
    expect(states(lines)).toStrictEqual([
      ['◦ idle 9s', '✓ new reply'],
      ['● permission 8s', '← new message'],
    ]);
  });

  test('a long name wraps in its column once the runtime has, and the model id stays whole where it fits the column', () => {
    const all = [
      ...agents,
      { name: 'a-member-with-a-name-far-longer-than-a-third', open: false },
    ];

    expect(drawn(runningTable(team, all, 72)).slice(-3)).toStrictEqual([
      'a-member-with-a-name-far  fake · fake-large         plan',
      '-longer-than-a-third',
      '                          not opened',
    ]);

    const wide = runningTable(team, all, 112);

    expect(drawn(wide).slice(3, 6)).toStrictEqual([
      'tester                                 fake ·                                 acceptEdits',
      '                                       claude-opus-5-5-20261001-preview-long',
      '                                       ● permission 8s  ← new message',
    ]);
    expect(states(wide).at(-1)).toStrictEqual(['not opened', undefined]);
  });
});
