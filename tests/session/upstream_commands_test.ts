import { describe, expect, test } from 'bun:test';
import type {
  ListedTeam,
  TeamListing,
} from '../../src/session/team_command.ts';
import {
  notAloneRefusal,
  openedText,
  runText,
  selectedRunRefusal,
  startedText,
  teamsText,
  teamText,
} from '../../src/session/upstream_commands.ts';
import type { Team } from '../../src/teams.ts';

const TEAM = {
  description: 'Fixes a reported bug',
  lead: { agent: 'claude', model: 'opus', effort: 'high', mode: 'auto' },
  members: [
    {
      name: 'developer',
      role: 'Builds the fix',
      agent: 'claude',
      model: 'opus',
      mode: 'auto',
    },
    { name: 'tester', role: 'Tests the fix', agent: 'codex', mode: 'agent' },
  ],
  body: '',
} as unknown as Team;

const found = (over: object): ListedTeam =>
  ({
    name: 'bugfix',
    file: '/a/bugfix.md',
    place: 'project',
    shown: '.chord/teams/bugfix.md',
    team: TEAM,
    ...over,
  }) as unknown as ListedTeam;

const DIRS = {
  project: '.chord/teams',
  user: '~/.config/chord/teams',
};
const NOW = 360_000;

describe('/team list', () => {
  const listing = (over: Partial<TeamListing>): TeamListing => ({
    teams: [],
    runs: [],
    dirs: DIRS,
    ...over,
  });

  test('a team a line, its parts joined; then no run, where they go, what to type', () => {
    expect(
      teamsText(
        listing({
          teams: [
            found({}),
            found({ name: 'wide', place: 'user' }),
            found({ name: 'near', hides: true }),
            {
              name: 'broken',
              file: '/a/broken.md',
              place: 'project',
              shown: 'x',
              problem: 'description is required',
            } as unknown as ListedTeam,
          ],
        }),
        NOW,
      ),
    ).toBe(
      [
        'Teams:',
        '',
        '- bugfix · 3 agents · claude, codex · this project · Fixes a reported bug',
        '- wide · 3 agents · claude, codex · every project · Fixes a reported bug',
        "- near · 3 agents · claude, codex · this project · hides every project's · Fixes a reported bug",
        '- broken · not read: description is required',
        '',
        'No run is open.',
        '',
        'Saved for this project in .chord/teams, and for every project in ~/.config/chord/teams.',
        '',
        '/team show and a name shows a team; /team run, a name and a job starts one.',
      ].join('\n'),
    );
  });

  test('a run says how long, several say how many', () => {
    const one = { team: 'bugfix', name: 'bugfix', since: 0 };
    const two = { team: 'bugfix', name: 'bugfix 2', since: 0 };

    expect(
      teamsText(listing({ teams: [found({})], runs: [one] }), NOW),
    ).toContain(
      '- bugfix · 3 agents · claude, codex · this project · working 6m · Fixes',
    );
    expect(
      teamsText(listing({ teams: [found({})], runs: [one] }), NOW),
    ).toContain('Runs open:\n\n- bugfix · team bugfix · working 6m');
    expect(
      teamsText(listing({ teams: [found({})], runs: [one, two] }), NOW),
    ).toContain('this project · 2 runs · Fixes');
  });

  test('no team: the window line in its place, and no line about what to type', () => {
    expect(teamsText(listing({ dirs: { project: '.chord/teams' } }), NOW)).toBe(
      [
        'No teams yet. /team new and a few words about the work makes one.',
        '',
        'No run is open.',
        '',
        'Saved for this project in .chord/teams.',
      ].join('\n'),
    );
  });

  test('nothing in it a renderer could take for a tag', () => {
    expect(teamsText(listing({ teams: [found({})] }), NOW)).not.toMatch(/[<>]/);
  });
});

describe('/team show', () => {
  test('a team not running: an unset value is left out', () => {
    expect(teamText('bugfix', '.chord/teams/bugfix.md', TEAM)).toBe(
      [
        'bugfix · .chord/teams/bugfix.md',
        '',
        'Fixes a reported bug',
        '',
        'Agents:',
        '',
        '- lead · claude · opus · high · auto · Splits the job, says who edits which files, reports to main',
        '- developer · claude · opus · auto · Builds the fix',
        '- tester · codex · agent · Tests the fix',
      ].join('\n'),
    );
  });

  test('a running one: its header on one line, and which are open', () => {
    expect(
      runText({
        name: 'bugfix 2',
        file: '.chord/teams/bugfix.md',
        team: TEAM,
        job: 'the login\ntest fails',
        since: 0,
        open: ['developer'],
        now: NOW,
      }),
    ).toBe(
      [
        'bugfix 2 · .chord/teams/bugfix.md · working 6m on "the login test fails"',
        '',
        'Fixes a reported bug',
        '',
        'Agents:',
        '',
        '- lead (bugfix 2) · open · claude · opus · high · auto · Splits the job, says who edits which files, reports to main',
        '- developer · open · claude · opus · auto · Builds the fix',
        '- tester · not open · codex · agent · Tests the fix',
      ].join('\n'),
    );
  });

  test('a selected run is refused, naming its run id', () => {
    expect(selectedRunRefusal('bugfix', '7f3a9c21')).toBe(
      "bugfix is a selected run, and only chord's window shows its receipt: chord -r with this session's id, then /team show 7f3a9c21 there",
    );
  });
});

describe('a file that tries to make rows of its own', () => {
  const HOSTILE = {
    ...TEAM,
    description: 'Fixes bugs\n\n- fake · row\r\nAgents:',
    members: [
      {
        name: 'tester',
        role: 'Tests\n- another · fake row',
        agent: 'codex',
      },
    ],
  } as unknown as Team;
  const rows = (text: string) =>
    text.split('\n').filter((line) => line.startsWith('- '));

  test('stays one row each in /team show, not running and running', () => {
    expect(rows(teamText('bugfix', 'a.md', HOSTILE))).toHaveLength(2);

    const running = runText({
      name: 'bugfix',
      file: 'a.md',
      team: HOSTILE,
      job: 'a job',
      since: 0,
      open: [],
      now: NOW,
    });

    expect(rows(running)).toHaveLength(2);
    expect(running).toContain('Fixes bugs - fake · row Agents:\n\nAgents:');
    expect(running).toContain('Tests - another · fake row');
  });

  test.each(['\v', '\f', '\u0085', '\u2028', '\u2029'])(
    'any line separator goes too: %j',
    (separator) => {
      const text = teamText('bugfix', 'a.md', {
        ...TEAM,
        description: `Fixes${separator}- fake · row`,
      } as Team);

      expect(text).toContain('\n\nFixes - fake · row\n\n');
    },
  );

  test('stays one row in /team list, a broken file too', () => {
    const text = teamsText(
      {
        teams: [
          found({ team: HOSTILE }),
          {
            name: 'broken',
            file: '/a/broken.md',
            place: 'project',
            shown: 'x',
            problem: 'bad\n- fake · row',
          } as unknown as ListedTeam,
        ],
        runs: [],
        dirs: DIRS,
      },
      NOW,
    );

    expect(rows(text)).toHaveLength(2);
    expect(text).toContain('- broken · not read: bad - fake · row');
  });
});

describe('the other replies', () => {
  test('/team run names the lead by its run, bare', () => {
    expect(startedText('bugfix', 'bugfix 2')).toBe(
      'Team bugfix started. Its lead is bugfix 2; /team stop bugfix 2 ends it.',
    );
    expect(startedText('bugfix', 'bugfix', 'A note.')).toBe(
      'Team bugfix started. Its lead is bugfix; /team stop bugfix ends it.\n\nA note.',
    );
  });

  test('/new says it is idle and what starts it', () => {
    expect(openedText('codex 2', 'codex')).toBe(
      "Opened codex 2 (codex). It is idle, with no prompt yet; main's send_message starts it, so ask main to send it the work.",
    );
  });

  test('a command beside other blocks ran nothing', () => {
    expect(notAloneRefusal('team')).toBe(
      '/team takes text alone, and this prompt had other blocks beside it. Nothing ran; send the command by itself.',
    );
  });
});
