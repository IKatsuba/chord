import { expect, test } from 'bun:test';
import { teamsAnswer } from '../src/server/tools.ts';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  checkProposal,
  checkTeam,
  findTeams,
  parseTeam,
  proposalShape,
  saveTeam,
  type Team,
  teamChanges,
  teamDirs,
  teamFile,
  teamPart,
  teamText,
} from '../src/teams.ts';

const RUNTIMES = ['claude', 'codex'];

/** Part 1's example, `bugfix`, as the design gives it. */
const EXAMPLE = await readFile(
  fileURLToPath(new URL('./fixtures/teams/bugfix.md', import.meta.url)),
  'utf8',
);

/**
 * A config home and a project, both temporary; nothing reads the home
 * directory of whoever runs the tests.
 */
async function place(
  run: (
    where: { configHome: string; cwd: string },
    dirs: { project: string; user: string },
  ) => Promise<void>,
) {
  const root = await mkdtemp(join(tmpdir(), 'chord-teams-'));
  const where = { configHome: join(root, 'config'), cwd: join(root, 'work') };
  const { project, user } = teamDirs(where);

  try {
    assert(user !== undefined);
    await run(where, { project, user });
  } finally {
    await rm(root, { recursive: true });
  }
}

async function write(dir: string, name: string, text: string) {
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, name), text);
}

function teamOf(text: string, name = 'bugfix'): Team {
  const read = parseTeam(name, text, RUNTIMES);

  assert('team' in read, 'problem' in read ? read.problem : '');

  return read.team;
}

function problemOf(text: string, name = 'bugfix'): string | undefined {
  const read = parseTeam(name, text, RUNTIMES);

  return 'problem' in read ? read.problem : undefined;
}

test("teams are in the project's .chord/teams and in teams/ beside the user's settings", () => {
  expect(teamDirs({ configHome: '/c', cwd: '/w' })).toStrictEqual({
    project: join('/w', '.chord', 'teams'),
    user: join('/c', 'chord', 'teams'),
  });
  expect(teamDirs({ configHome: undefined, cwd: '/w' }).user).toStrictEqual(
    undefined,
  );
});

test('the example team reads as its frontmatter and body', () => {
  const team = teamOf(EXAMPLE);

  expect(team.description.startsWith('Fixes a bug end to end')).toStrictEqual(
    true,
  );
  expect(team.lead).toStrictEqual({
    agent: 'claude',
    model: 'opus',
    mode: 'default',
    instructions: team.lead.instructions,
  });
  expect(team.members.map((member) => member.name)).toStrictEqual([
    'tester',
    'coder',
    'reviewer',
  ]);
  expect(team.members[1]?.mode).toStrictEqual('auto');
  expect(team.members[2]?.instructions).toStrictEqual(
    'Read `git diff` and the test. Say what is wrong, or that nothing is.\n' +
      'Never edit a file.\n',
  );
  expect(
    team.body.startsWith('# How bugfix works\n\n1. The lead'),
  ).toStrictEqual(true);
  expect(team.body.endsWith('does not need every step.')).toStrictEqual(true);
});

test('the example team is read back equal after a write', async () => {
  await place(async (_where, { project }) => {
    const team = teamOf(EXAMPLE);
    const file = teamFile(project, 'bugfix');

    await saveTeam(file, team);

    const text = await readFile(file, 'utf8');

    expect(text.startsWith('---\ndescription:')).toStrictEqual(true);
    expect(teamOf(text)).toStrictEqual(team);
    expect(teamText(teamOf(text))).toStrictEqual(text);
    expect(
      [...readdirSync(project, { withFileTypes: true })].map(
        ({ name }) => name,
      ),
    ).toStrictEqual(['bugfix.md']);
  });
});

test('a write that fails leaves the old file whole and nothing beside it', async () => {
  await place(async (_where, { project }) => {
    const file = teamFile(project, 'bugfix');

    await write(project, 'bugfix.md', EXAMPLE);
    await mkdir(join(project, 'review.md'));

    await expect(
      saveTeam(join(project, 'review.md'), teamOf(EXAMPLE)),
    ).rejects.toThrow();
    expect(await readFile(file, 'utf8')).toStrictEqual(EXAMPLE);
    expect(
      [...readdirSync(project, { withFileTypes: true })]
        .map(({ name }) => name)
        .sort(),
    ).toStrictEqual(['bugfix.md', 'review.md']);
  });
});

test("the project's team wins a name clash, and says it hides the user's", async () => {
  await place(async (where, { project, user }) => {
    const other = EXAMPLE.replace(
      /^description: .*$/m,
      'description: The user one',
    );

    await write(project, 'bugfix.md', EXAMPLE);
    await write(user, 'bugfix.md', other);
    await write(user, 'review.md', other);
    await write(user, 'notes.txt', 'not a team');

    const found = await findTeams(where, RUNTIMES);

    expect(
      found.map(({ name, file, place, hides }) => ({
        name,
        file,
        place,
        hides,
      })),
    ).toStrictEqual([
      {
        name: 'bugfix',
        file: join(project, 'bugfix.md'),
        place: 'project',
        hides: true,
      },
      {
        name: 'review',
        file: join(user, 'review.md'),
        place: 'user',
        hides: false,
      },
    ]);
    expect(
      found.map((team) => ('team' in team ? team.team.description : undefined)),
    ).toStrictEqual([teamOf(EXAMPLE).description, 'The user one']);
  });
});

test('a team file that starts with a BOM reads as the same team', async () => {
  expect(teamOf(`\uFEFF${EXAMPLE}`)).toStrictEqual(teamOf(EXAMPLE));

  await place(async (where, { project }) => {
    await write(project, 'bugfix.md', `\uFEFF${EXAMPLE}`);

    const [found] = await findTeams(where, RUNTIMES);

    assert(
      found && 'team' in found,
      found && 'problem' in found ? found.problem : '',
    );
    expect(found.team).toStrictEqual(teamOf(EXAMPLE));
  });
});

test('an empty frontmatter block is not a file without one', () => {
  expect(problemOf('# no frontmatter')).toStrictEqual(
    'no frontmatter between --- lines',
  );
  expect(problemOf(`\uFEFF# no frontmatter`)).toStrictEqual(
    'no frontmatter between --- lines',
  );

  const empty = problemOf('---\n---\n# How it works');

  expect(
    empty !== undefined && empty !== 'no frontmatter between --- lines',
    empty,
  ).toBeTruthy();
});

test('no team directory at all finds no teams', async () => {
  await place(async (where) => {
    expect(await findTeams(where, RUNTIMES)).toStrictEqual([]);
  });
});

test('a broken file is listed with its first problem in zod path words', async () => {
  await place(async (where, { user }) => {
    await write(user, 'triage.md', EXAMPLE.replace('    agent: codex\n', ''));

    expect(await findTeams(where, RUNTIMES)).toStrictEqual([
      {
        name: 'triage',
        file: join(user, 'triage.md'),
        place: 'user',
        hides: false,
        problem: 'members.1.agent is missing',
      },
    ]);
  });
});

test('the check refuses what part 1 refuses, naming the first problem', () => {
  const cases: [string, string][] = [
    ['# no frontmatter', 'no frontmatter between --- lines'],
    ['---\nlead: [1\n---\nx', 'the frontmatter is not valid YAML'],
    ['---\n- 1\n---\nx', 'the frontmatter is not a YAML mapping'],
    [EXAMPLE.replace(/^description: .*$/m, ''), 'description is missing'],
    [
      EXAMPLE.replace(/^description: .*$/m, 'description: ""'),
      'description: too small',
    ],
    [
      EXAMPLE.replace(/^description: .*$/m, 'description: "two\\nlines"'),
      'description: must be one line',
    ],
    [
      EXAMPLE.replace('  agent: claude\n  model: opus\n', '  model: opus\n'),
      'lead.agent is missing',
    ],
    [
      EXAMPLE.replace('agent: codex', 'agent: codx'),
      'members.1.agent: chord knows no runtime named codx',
    ],
    [
      EXAMPLE.replace('  mode: default\n', '  mode: default\n  colour: red\n'),
      'lead.colour is not a key a team has',
    ],
    [
      EXAMPLE.replace('name: coder', 'name: tester'),
      'members.1.name: tester is named twice',
    ],
    [
      EXAMPLE.replace('name: coder', 'name: main'),
      'members.1.name: main is taken',
    ],
    [
      EXAMPLE.replace('name: coder', 'name: bugfix'),
      'members.1.name: bugfix is taken',
    ],
    [
      EXAMPLE.replace('name: coder', 'name: Coder'),
      'members.1.name: must be a lowercase letter',
    ],
    [
      EXAMPLE.replace(/^ {6}Make the failing[\s\S]*?why\.\n/m, '').replace(
        '    instructions: |\n  - name: reviewer',
        '  - name: reviewer',
      ),
      'members.1.instructions is missing',
    ],
    [
      EXAMPLE.replace(
        /^ {4}role: Writes the fix.*$/m,
        `    role: ${'x'.repeat(81)}`,
      ),
      'members.1.role: too big',
    ],
    [
      EXAMPLE.replace(/members:[\s\S]*?^---$/m, 'members: []\n---'),
      'members: too small',
    ],
    [EXAMPLE.replace(/^# How bugfix works[\s\S]*/m, '\n'), 'the body is empty'],
  ];

  for (const [text, problem] of cases) {
    const found = problemOf(text);

    expect(
      found?.startsWith(problem),
      `${JSON.stringify(found)} should start with ${JSON.stringify(problem)}`,
    ).toBeTruthy();
  }
});

test('a team holds at most eight members', () => {
  const team = teamOf(EXAMPLE);
  const { body, ...frontmatter } = team;
  const members = Array.from({ length: 9 }, (_, index) => ({
    ...team.members[0],
    name: `m${index}`,
  }));

  expect(
    checkTeam('bugfix', { ...frontmatter, members }, body, RUNTIMES),
  ).toStrictEqual({
    problem: 'members: too big: expected array to have <=8 items',
  });
  expect(
    'team' in
      checkTeam(
        'bugfix',
        { ...frontmatter, members: members.slice(0, 8) },
        body,
        RUNTIMES,
      ),
  ).toStrictEqual(true);
});

test("a team's name is the file's, and some names are not a team's", () => {
  expect(problemOf(EXAMPLE, 'main')).toStrictEqual('the name main is taken');
  expect(problemOf(EXAMPLE, 'chord')).toStrictEqual('the name chord is taken');
  expect(problemOf(EXAMPLE, 'Bug_fix')).toStrictEqual(
    'the name Bug_fix must be a lowercase letter, then up to 23 of a-z, 0-9 and -',
  );
  expect(
    problemOf(EXAMPLE, 'a'.repeat(25))?.startsWith('the name'),
  ).toStrictEqual(true);
  expect(problemOf(EXAMPLE, 'fix-2')).toStrictEqual(undefined);
});

test("a lead's team part names its tools, the other runs, its instructions, the members and the body", () => {
  const read = parseTeam('bugfix', EXAMPLE, RUNTIMES);

  assert('team' in read);

  const part = teamPart(
    'bugfix',
    read.team,
    { lead: 'bugfix 2', others: ['bugfix', 'review'] },
    '/src/app',
  );

  expect(part.team).toStrictEqual('bugfix');
  expect(part.member).toStrictEqual(undefined);
  expect(
    part.text.startsWith(
      'You are the lead of team bugfix, running as bugfix 2: a long-lived ' +
        'agent chord opened for main',
    ),
  ).toBeTruthy();
  expect(part.text.includes('You work in /src/app')).toBeTruthy();
  expect(part.text.includes('open_agent {member, prompt}')).toBeTruthy();
  expect(part.text.includes('by these names: bugfix and review.')).toBeTruthy();
  expect(part.text.includes('Your instructions:\nRead the job')).toBeTruthy();
  expect(
    part.text.includes(
      '- coder: Writes the fix, in the files the lead names (codex · ' +
        'gpt-5.3-codex · auto)',
    ),
  ).toBeTruthy();
  expect(
    part.text.endsWith(`How the team works:\n${read.team.body}`),
  ).toBeTruthy();
  expect(
    teamPart(
      'bugfix',
      read.team,
      { lead: 'bugfix', others: [] },
      '/a',
    ).text.includes('No other run of a team is open in this session.'),
  ).toBeTruthy();
});

test("a member's team part names its lead, the other members it reaches, its role and its instructions", () => {
  const read = parseTeam('bugfix', EXAMPLE, RUNTIMES);

  assert('team' in read);

  const tester = read.team.members[0]!;
  const part = teamPart(
    'bugfix',
    read.team,
    { member: tester, lead: 'bugfix 2' },
    '/src/app',
  );

  expect(part.member).toStrictEqual('tester');
  expect(
    part.text.startsWith(
      'You are tester, a member of team bugfix, opened by its lead, bugfix 2.',
    ),
  ).toBeTruthy();
  expect(
    part.text.includes(
      'reaches your lead, bugfix 2, and coder and reviewer, the team',
    ),
  ).toBeTruthy();
  expect(part.text.includes('You open no long-lived agents.')).toBeTruthy();
  expect(
    part.text.includes(
      'Your role: Writes the failing test, then proves the fix',
    ),
  ).toBeTruthy();
  expect(
    part.text.includes('Your instructions:\nWrite the smallest test'),
  ).toBeTruthy();
});

/** A proposal as `propose_team` takes it. */
const PROPOSAL = {
  name: 'bugfix',
  description: 'Fixes a bug end to end',
  lead: { agent: 'claude', model: 'opus' },
  members: [
    {
      name: 'tester',
      role: 'Writes the failing test',
      agent: 'claude',
      mode: 'acceptEdits',
      instructions: 'Write it.',
    },
  ],
  body: '\n# How bugfix works\n',
};

test('a proposal is checked as its file would be, its name with it', () => {
  expect(checkProposal(PROPOSAL, RUNTIMES)).toStrictEqual({
    name: 'bugfix',
    team: {
      description: PROPOSAL.description,
      lead: PROPOSAL.lead,
      members: PROPOSAL.members,
      body: '# How bugfix works',
    },
  });
  expect(
    checkProposal({ ...PROPOSAL, name: undefined }, RUNTIMES),
  ).toStrictEqual({
    problem: 'name is missing',
  });
  expect(checkProposal({ ...PROPOSAL, body: ' ' }, RUNTIMES)).toStrictEqual({
    problem: 'the body is empty',
  });
  expect(checkProposal({ ...PROPOSAL, members: [] }, RUNTIMES)).toStrictEqual({
    problem: 'members: too small: expected array to have >=1 items',
  });
  expect(
    checkProposal(
      {
        ...PROPOSAL,
        members: [{ ...PROPOSAL.members[0], name: 'bugfix' }],
      },
      RUNTIMES,
    ),
  ).toStrictEqual({ problem: 'members.0.name: bugfix is taken' });
});

test("a team's changes are the lead's, and each member's by its name", () => {
  const checked = checkProposal(PROPOSAL, RUNTIMES);

  assert('team' in checked);

  const before = checked.team;
  const after: Team = {
    ...before,
    lead: { ...before.lead, model: 'sonnet' },
    members: [
      {
        name: 'coder',
        role: 'Writes the fix',
        agent: 'codex',
        instructions: 'Fix it.',
      },
    ],
  };

  const changes = teamChanges(before, after);

  expect(changes.lead).toStrictEqual('changed');
  expect([...changes.members]).toStrictEqual([
    ['coder', 'added'],
    ['tester', 'removed'],
  ]);
  expect(teamChanges(before, before)).toStrictEqual({ members: new Map() });
});

test("a team's lead and members take an effort, which the team part lists and a change counts", () => {
  const text = EXAMPLE.replace(
    '  model: opus\n  mode: default\n',
    '  model: opus\n  effort: high\n  mode: default\n',
  ).replace(
    'model: gpt-5.3-codex\n',
    'model: gpt-5.3-codex\n    effort: xhigh\n',
  );
  const team = teamOf(text);

  expect(team.lead.effort).toStrictEqual('high');
  expect(team.members[1]!.effort).toStrictEqual('xhigh');
  expect(team.members[0]!.effort).toStrictEqual(undefined);
  expect(teamOf(teamText(team))).toStrictEqual(team);
  expect(
    teamPart('bugfix', team, { lead: 'bugfix', others: [] }, '/a').text,
  ).toContain(
    '- coder: Writes the fix, in the files the lead names (codex · ' +
      'gpt-5.3-codex · xhigh · auto)',
  );
  expect(problemOf(text.replace('effort: high', 'effort: ""'))).toStartWith(
    'lead.effort: too small',
  );
  expect(
    teamChanges(team, {
      ...team,
      lead: { ...team.lead, effort: 'medium' },
    }),
  ).toStrictEqual({ lead: 'changed', members: new Map() });
});

test("propose_team's input takes an effort for the lead and each member", () => {
  const shape = proposalShape();
  const lead = shape.lead.parse({ agent: 'claude', effort: 'high' });
  const [member] = shape.members.parse([
    {
      name: 'coder',
      role: 'Writes the fix',
      agent: 'codex',
      effort: 'xhigh',
      instructions: 'Fix it.',
    },
  ]);

  expect(lead.effort).toStrictEqual('high');
  expect(member?.effort).toStrictEqual('xhigh');
  expect(
    checkProposal(
      { ...PROPOSAL, lead: { ...PROPOSAL.lead, effort: 'high' } },
      RUNTIMES,
    ),
  ).toMatchObject({ team: { lead: { effort: 'high' } } });
});

test('quoted team and member names are refused, including saved list_teams problems (CHD-519)', async () => {
  const bad = EXAMPLE.replace('name: tester', `name: 'a "b @notes.md suffix'`);
  const problem = 'members.0.name: must not contain the character "';

  expect(problemOf(bad)).toBe(problem);
  expect(problemOf(EXAMPLE, 'a"b')).toBe('must not contain the character "');

  const team = teamOf(EXAMPLE);

  expect(
    checkProposal(
      {
        ...team,
        name: 'bugfix',
        members: [{ ...team.members[0]!, name: 'a"b' }],
      },
      RUNTIMES,
    ),
  ).toStrictEqual({ problem });
  await place(async (where, { project }) => {
    await write(project, 'bugfix.md', bad);
    expect(
      teamsAnswer({ found: await findTeams(where, RUNTIMES), runs: [] }),
    ).toStrictEqual({
      runs: [],
      teams: [
        {
          name: 'bugfix',
          problem: `${problem}; it cannot run until its file is fixed`,
        },
      ],
    });
  });
});

test('control characters in team and member names report list_teams problems (CHD-519)', async () => {
  for (const [name, code] of [
    ['a\n@notes.md suffix', '000A'],
    ['a\rline', '000D'],
    ['a\ttab', '0009'],
    ['a\0nul', '0000'],
    ['a\u007Fdel', '007F'],
  ] as const) {
    const member = EXAMPLE.replace(
      'name: tester',
      `name: ${JSON.stringify(name)}`,
    );
    const problem = `must not contain the control character U+${code}`;

    expect(problemOf(EXAMPLE, name)).toBe(problem);
    expect(problemOf(member)).toBe(`members.0.name: ${problem}`);
    await place(async (where, { project }) => {
      await write(project, 'bugfix.md', member);
      expect(
        teamsAnswer({ found: await findTeams(where, RUNTIMES), runs: [] }),
      ).toStrictEqual({
        runs: [],
        teams: [
          {
            name: 'bugfix',
            problem: `members.0.name: ${problem}; it cannot run until its file is fixed`,
          },
        ],
      });
    });
  }
});
