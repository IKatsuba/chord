// /team's words, the teams picker's rows and hint, and /team show's running
// table, as the original's tests/ui/teams/teams_test.ts checks them.
import 'package:chord/session/team_command.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/teams.dart';
import 'package:chord/ui/teams/teams.dart';
import 'package:test/test.dart';

TeamCommand _command(String args) => teamCommand(args, teamWords);

const _bugfix = Team(
  description: 'Fixes a bug end to end: a failing test first, then the fix.',
  lead: TeamLead(agent: 'claude', model: 'opus', mode: 'default'),
  members: [
    TeamMember(
      name: 'tester',
      role: 'Writes the failing test',
      agent: 'claude',
      model: 'sonnet',
      mode: 'acceptEdits',
      instructions: 'Write it.',
    ),
    TeamMember(
      name: 'coder',
      role: 'Writes the fix',
      agent: 'codex',
      model: 'gpt-5.3-codex',
      mode: 'auto',
      instructions: 'Fix it.',
    ),
    TeamMember(
      name: 'reviewer',
      role: 'Reads the diff',
      agent: 'claude',
      model: 'opus',
      mode: 'plan',
      instructions: 'Read it.',
    ),
  ],
  body: '# How bugfix works\n\nOne writer per file.',
);

ListedTeam _listed(
  String name,
  String file,
  String shown,
  TeamPlace place, {
  Team? team,
  String? problem,
}) => (
  found: FoundTeam(
    name: name,
    file: file,
    place: place,
    hides: false,
    team: team,
    problem: problem,
  ),
  shown: shown,
);

final _teams = [
  _listed(
    'bugfix',
    '/w/.chord/teams/bugfix.md',
    '.chord/teams/bugfix.md',
    TeamPlace.project,
    team: _bugfix,
  ),
  _listed(
    'review',
    '/h/.config/chord/teams/review.md',
    '~/.config/chord/teams/review.md',
    TeamPlace.user,
    team: Team(
      description: 'Reviews a branch before it goes to the owner',
      lead: _bugfix.lead,
      members: [
        for (final member in _bugfix.members.take(2))
          TeamMember(
            name: member.name,
            role: member.role,
            agent: 'claude',
            model: member.model,
            mode: member.mode,
            instructions: member.instructions,
          ),
      ],
      body: _bugfix.body,
    ),
  ),
  _listed(
    'triage',
    '/h/.config/chord/teams/triage.md',
    '~/.config/chord/teams/triage.md',
    TeamPlace.user,
    problem: 'members.1.agent is missing',
  ),
];

List<String> _labels(
  List<ListedTeam> teams,
  List<TeamRun> runs,
  num now,
  int columns,
) => [
  for (final choice in teamChoices(teams, runs, now, columns)) choice.label,
];

const ShownState _working8 = (glyph: '✻', words: 'working 8s', tone: 'dim');
const ShownState _permission12 = (
  glyph: '●',
  words: 'permission 12s',
  tone: 'warning',
);

List<String> _drawn(List<RunningLine> lines) => [
  for (final line in lines) ...[line.text, ...line.under],
];

List<(String, String?)> _states(List<RunningLine> lines) => [
  for (final line in lines)
    () {
      final all = [line.text, ...line.under];
      String cut(String on, (int, int) range) =>
          on.substring(range.$1, range.$2);
      return (
        cut(all[line.stateLine], line.state),
        line.mark == null ? null : cut(all[line.markLine], line.mark!),
      );
    }(),
];

void main() {
  test("/team's forms read in the window's words", () {
    expect(
      (_command('stop') as TeamRefused).problem,
      'Which run? The list under the prompt names them',
    );
    expect(
      (_command('choose bugfix repair it') as TeamRefused).problem,
      '/team has no choose; it takes list, new, show, run or stop',
    );
    expect(
      (_command('edit bugfix') as TeamRefused).problem,
      '/team has no edit; it takes list, new, show, run or stop',
    );
  });

  test('/team stop says who it closed', () {
    expect(
      stoppedLine('bugfix', ['tester', 'coder', 'reviewer'], teamWords),
      'Stopped bugfix: its lead, tester, coder, and reviewer are closed · '
      '/resume lists them',
    );
    expect(
      stoppedLine('bugfix 2', [], teamWords),
      'Stopped bugfix 2: its lead is closed · /resume lists it',
    );
  });

  test("a team not found, or broken, is refused with its file and its "
      'problem', () {
    expect(
      teamRefusal('bugfx', null),
      'No team named bugfx · /team lists them',
    );
    expect(
      teamRefusal('triage', _teams[2]),
      '~/.config/chord/teams/triage.md is not a team chord can run:\n'
      'members.1.agent is missing',
    );
    expect(teamRefusal('bugfix', _teams[0]), isNull);
  });

  test("a team's running state is its run's time, or how many runs", () {
    expect(runningWords([], 0), '');
    expect(
      runningWords([
        (id: null, team: 'bugfix', name: 'bugfix', since: 0),
      ], 361000),
      '✻ working 6m',
    );
    expect(
      runningWords([
        (id: null, team: 'bugfix', name: 'bugfix', since: 0),
        (id: null, team: 'bugfix', name: 'bugfix 2', since: 0),
      ], 1),
      '✻ 2 runs',
    );
  });

  test('the picker lines up each team in columns, a broken file with its '
      'problem and path', () {
    final runs = [(id: null, team: 'bugfix', name: 'bugfix', since: 0)];
    expect(_labels(_teams, runs, 361000, 116), [
      'bugfix  4 agents · claude, codex  this project   ✻ working 6m  '
          'Fixes a bug end to end: a failing test first, then the fix.',
      'review  3 agents · claude         every project                '
          'Reviews a branch before it goes to the owner',
      'triage  ✗ not read: members.1.agent is missing                 '
          '~/.config/chord/teams/triage.md',
    ]);
    // With nothing running the path still starts where the description
    // does.
    expect(_labels(_teams, [], 0, 116), [
      'bugfix  4 agents · claude, codex  this project   '
          'Fixes a bug end to end: a failing test first, then the fix.',
      'review  3 agents · claude         every project  '
          'Reviews a branch before it goes to the owner',
      'triage  ✗ not read: members.1.agent is missing   '
          '~/.config/chord/teams/triage.md',
    ]);
    // A problem wider than the columns before the description moves the
    // description over, for the path to start where it does.
    final longer = [
      _teams[1],
      _listed(
        'triage',
        '/h/.config/chord/teams/triage.md',
        '~/.config/chord/teams/triage.md',
        TeamPlace.user,
        problem: 'members.1.agent is missing, and so is lead',
      ),
    ];
    expect(_labels(longer, [], 0, 116), [
      'review  3 agents · claude  every project                        '
          'Reviews a branch before it goes to the owner',
      'triage  ✗ not read: members.1.agent is missing, and so is lead  '
          '~/.config/chord/teams/triage.md',
    ]);
    // At 80 columns the runtimes and the broken file's path go.
    expect(_labels(_teams, [], 0, 76), [
      'bugfix  4 agents  this project   Fixes a bug end to end: a failing '
          'test first, then the fix.',
      'review  3 agents  every project  Reviews a branch before it goes to '
          'the owner',
      'triage  ✗ not read: members.1.agent is missing',
    ]);
  });

  test("the picker says where teams are saved, and Enter's draft runs a "
      'team, and a broken one has none', () {
    expect(
      teamsWhere((project: '.chord/teams', user: '~/.config/chord/teams'), 116),
      'Saved for this project in .chord/teams, and for every project in '
      '~/.config/chord/teams.',
    );
    expect(
      teamsWhere((project: '.chord/teams', user: '~/.config/chord/teams'), 76),
      'For this project in .chord/teams, for every project in '
      '~/.config/chord/teams.',
    );
    expect(
      teamsWhere((project: '.chord/teams', user: null), 76),
      'Saved for this project in .chord/teams.',
    );
    expect(pickedDraft(_teams[0].found), '/team run bugfix ');
    expect(pickedDraft(_teams[2].found), isNull);
  });

  test("the picker's hint offers Enter on a team it can run, and says how a "
      'broken one gets fixed', () {
    expect(teamsHint(_teams[0].found, 116), [
      'Enter to hand it a job',
      '/team show <name>',
    ]);
    expect(teamsHint(_teams[0].found, 76), ['Enter to hand it a job']);
    expect(teamsHint(_teams[2].found, 116), [
      'Fix the file, or ask main to fix triage',
    ]);
    expect(teamsHint(_teams[2].found, 76), ['Ask main to fix triage']);
    expect(teamsHint(null, 116), isEmpty);
  });

  test("/team show's running form gives each agent its file's mode, its "
      'state and latest headline, wrapped to the width', () {
    final run = TeamRunShown(
      name: 'bugfix',
      since: 0,
      at: 361000,
      job: 'strings at the end of a line lose their closing quote; see issue',
      agents: [
        TeamAgentShown(
          name: 'lead',
          lead: true,
          open: true,
          state: _working8,
          latest: headlineText(name: 'coder', sent: true),
        ),
        TeamAgentShown(
          name: 'tester',
          open: true,
          state: _permission12,
          latest: headlineText(name: 'Bash', arg: 'bun dev test tests/parse'),
        ),
        const TeamAgentShown(name: 'coder', open: true),
        const TeamAgentShown(name: 'reviewer', open: false),
      ],
    );
    expect(runningHeader('bugfix', '.chord/teams/bugfix.md', run, 70), [
      'bugfix · .chord/teams/bugfix.md · working 6m on "strings at the end of',
      'a line lose their closing quote; see issue"',
    ]);
    final lines = runningTable(_bugfix, run.agents, 200);
    expect(
      [for (final line in lines) line.text],
      [
        'lead      claude · opus          default      ✻ working 8s      → to '
            '@coder',
        'tester    claude · sonnet        acceptEdits  ● permission 12s  '
            'Bash(bun dev test tests/parse)',
        'coder     codex · gpt-5.3-codex  auto         idle',
        'reviewer  claude · opus          plan         not opened',
      ],
    );
    expect(
      lines[1].text.substring(lines[1].state.$1, lines[1].state.$2),
      '● permission 12s',
    );
    expect(
      [for (final line in lines) line.under],
      [isEmpty, isEmpty, isEmpty, isEmpty],
    );
    // At 70 the headline would keep fewer than 20 cells beside the state,
    // so it goes under the row, from the runtime's column.
    expect(_drawn(runningTable(_bugfix, run.agents, 70)), [
      'lead      claude · opus          default      ✻ working 8s',
      '          → to @coder',
      'tester    claude · sonnet        acceptEdits  ● permission 12s',
      '          Bash(bun dev test tests/parse)',
      'coder     codex · gpt-5.3-codex  auto         idle',
      'reviewer  claude · opus          plan         not opened',
    ]);
    // With 20 cells or more beside the row it wraps there.
    final wrapped = runningTable(_bugfix, [
      TeamAgentShown(
        name: 'tester',
        open: true,
        state: _permission12,
        latest: 'Bash(bun dev test tests/parse --filter strings)',
      ),
    ], 80);
    expect(
      wrapped[0].text,
      'tester  claude · sonnet  acceptEdits  ● permission 12s  Bash(bun dev '
      'test',
    );
    expect(wrapped[0].under, [
      '                                                        tests/parse '
          '--filter',
      '                                                        strings)',
    ]);
  });

  test("/team show's running form reads the lead's runtime from the lead, "
      'though a member is named lead', () {
    final team = Team(
      description: _bugfix.description,
      lead: _bugfix.lead,
      members: const [
        TeamMember(
          name: 'lead',
          role: 'Writes the failing test',
          agent: 'claude',
          model: 'sonnet',
          mode: 'plan',
          instructions: 'Write it.',
        ),
      ],
      body: _bugfix.body,
    );
    final lines = runningTable(team, [
      const TeamAgentShown(name: 'lead', lead: true, open: true),
      TeamAgentShown(
        name: 'lead',
        open: true,
        latest: messageHeadline(
          const MessageFrom('tester', runtime: 'claude', reachable: true),
        ),
      ),
    ], 200);
    expect(
      [for (final line in lines) line.text],
      [
        'lead  claude · opus    default  idle',
        'lead  claude · sonnet  plan     idle  ← from @tester · claude',
      ],
    );
  });

  test("/team show's running form gives an agent's effort as the last part "
      'of its runtime and model, never dropped', () {
    final team = Team(
      description: _bugfix.description,
      lead: const TeamLead(
        agent: 'claude',
        model: 'opus',
        effort: 'high',
        mode: 'default',
      ),
      members: [
        const TeamMember(
          name: 'tester',
          role: 'Writes the failing test',
          agent: 'claude',
          model: 'sonnet',
          effort: 'low',
          mode: 'acceptEdits',
          instructions: 'Write it.',
        ),
        _bugfix.members[1],
      ],
      body: _bugfix.body,
    );
    const agents = [
      TeamAgentShown(
        name: 'lead',
        lead: true,
        open: true,
        state: (glyph: '◦', words: 'idle 6s', tone: 'dim'),
        mark: (glyph: '✓', words: 'new reply', tone: 'success'),
        latest: '← from @tester · claude',
      ),
      TeamAgentShown(
        name: 'tester',
        open: true,
        state: (glyph: '●', words: 'permission 5s', tone: 'warning'),
        latest: 'Bash(bun dev test tests/parse)',
      ),
      TeamAgentShown(name: 'coder', open: false),
    ];
    expect(_drawn(runningTable(team, agents, 114)), [
      'lead    claude · opus · high   default      ◦ idle 6s        ✓ new '
          'reply  ← from @tester · claude',
      'tester  claude · sonnet · low  acceptEdits  ● permission 5s          '
          '     Bash(bun dev test tests/parse)',
      'coder   codex · gpt-5.3-codex  auto         not opened',
    ]);
    expect(_drawn(runningTable(team, agents, 74)), [
      'lead    claude · opus · high   default      ◦ idle 6s        ✓ new '
          'reply',
      '        ← from @tester · claude',
      'tester  claude · sonnet · low  acceptEdits  ● permission 5s',
      '        Bash(bun dev test tests/parse)',
      'coder   codex · gpt-5.3-codex  auto         not opened',
    ]);
  });

  test("/team show's running form says what of an agent is not yet seen "
      'beside its state, the marks in one column', () {
    const ShownState idle = (glyph: '◦', words: 'idle 3m', tone: 'dim');
    final lines = runningTable(_bugfix, const [
      TeamAgentShown(name: 'lead', lead: true, open: true, state: _working8),
      TeamAgentShown(
        name: 'tester',
        open: true,
        state: idle,
        mark: (glyph: '✓', words: 'new reply', tone: 'success'),
      ),
      TeamAgentShown(name: 'coder', open: true, state: idle),
      TeamAgentShown(name: 'reviewer', open: false),
    ], 200);
    expect(
      [for (final line in lines) line.text],
      [
        'lead      claude · opus          default      ✻ working 8s',
        'tester    claude · sonnet        acceptEdits  ◦ idle 3m     ✓ new reply',
        'coder     codex · gpt-5.3-codex  auto         ◦ idle 3m',
        'reviewer  claude · opus          plan         not opened',
      ],
    );
    expect(_states(lines)[1], ('◦ idle 3m', '✓ new reply'));
    expect(lines[2].mark, isNull);
  });

  group("/team show's running form wraps its own columns where they are "
      'wider than the width, and hides nothing', () {
    final team = Team(
      description: _bugfix.description,
      lead: const TeamLead(agent: 'fake', model: 'fake-large', mode: 'default'),
      members: const [
        TeamMember(
          name: 'tester',
          role: 'Writes the failing test',
          agent: 'fake',
          model: 'claude-opus-5-5-20261001-preview-long',
          mode: 'acceptEdits',
          instructions: 'Write it.',
        ),
        TeamMember(
          name: 'a-member-with-a-name-far-longer-than-a-third',
          role: 'Writes the fix',
          agent: 'fake',
          model: 'fake-large',
          mode: 'plan',
          instructions: 'Fix it.',
        ),
      ],
      body: _bugfix.body,
    );
    const agents = [
      TeamAgentShown(
        name: 'lead',
        lead: true,
        open: true,
        state: (glyph: '◦', words: 'idle 9s', tone: 'dim'),
        mark: (glyph: '✓', words: 'new reply', tone: 'success'),
        latest: '← from @tester · fake',
      ),
      TeamAgentShown(
        name: 'tester',
        open: true,
        state: (glyph: '●', words: 'permission 8s', tone: 'warning'),
        mark: (glyph: '←', words: 'new message', tone: 'dim'),
        latest: 'Bash(bun dev test tests/parse)',
      ),
    ];

    test('at 72 the model id wraps after its runtime in a third of the '
        'width, and the state and mark go whole under the row', () {
      final lines = runningTable(team, agents, 72);
      expect(_drawn(lines), [
        'lead    fake · fake-large         default',
        '        ◦ idle 9s        ✓ new reply',
        '        ← from @tester · fake',
        'tester  fake ·                    acceptEdits',
        '        claude-opus-5-5-20261001',
        '        -preview-long',
        '        ● permission 8s  ← new message',
        '        Bash(bun dev test tests/parse)',
      ]);
      expect(_states(lines), [
        ('◦ idle 9s', '✓ new reply'),
        ('● permission 8s', '← new message'),
      ]);
    });

    test('at 112 the row has room for its own columns', () {
      final lines = runningTable(team, agents, 112);
      expect(_drawn(lines), [
        'lead    fake · fake-large                             default      '
            '◦ idle 9s        ✓ new reply',
        '        ← from @tester · fake',
        'tester  fake · claude-opus-5-5-20261001-preview-long  acceptEdits  '
            '● permission 8s  ← new message',
        '        Bash(bun dev test tests/parse)',
      ]);
      expect(_states(lines), [
        ('◦ idle 9s', '✓ new reply'),
        ('● permission 8s', '← new message'),
      ]);
    });

    test('a model id of wide characters leaves the state and mark their own '
        'spans, beside the row and under it', () {
      final wide = Team(
        description: team.description,
        lead: team.lead,
        members: const [
          TeamMember(
            name: 'tester',
            role: 'Writes the failing test',
            agent: 'fake',
            model: 'モデル-ラージ-🚀',
            mode: 'acceptEdits',
            instructions: 'Write it.',
          ),
        ],
        body: team.body,
      );
      for (final width in [112, 72, 40]) {
        expect(_states(runningTable(wide, agents, width)), [
          ('◦ idle 9s', '✓ new reply'),
          ('● permission 8s', '← new message'),
        ], reason: '$width');
      }
    });

    test('a long name wraps in its column once the runtime has, and the '
        'model id stays whole where it fits the column', () {
      const all = [
        ...agents,
        TeamAgentShown(
          name: 'a-member-with-a-name-far-longer-than-a-third',
          open: false,
        ),
      ];
      final narrow = _drawn(runningTable(team, all, 72));
      expect(narrow.sublist(narrow.length - 3), [
        'a-member-with-a-name-far  fake · fake-large         plan',
        '-longer-than-a-third',
        '                          not opened',
      ]);
      final wide = runningTable(team, all, 112);
      expect(_drawn(wide).sublist(3, 6), [
        'tester                                 fake ·                       '
            '          acceptEdits',
        '                                       '
            'claude-opus-5-5-20261001-preview-long',
        '                                       ● permission 8s  ← new '
            'message',
      ]);
      expect(_states(wide).last, ('not opened', null));
    });
  });

  test("/team show's running form on a screen too narrow for the name, "
      "runtime and mode puts the mode on the state's line, which wraps "
      'between its parts', () {
    final team = Team(
      description: _bugfix.description,
      lead: const TeamLead(
        agent: 'fake',
        model: 'fake-large',
        mode: 'acceptEdits',
      ),
      members: const [
        TeamMember(
          name: 'tester',
          role: 'Writes the failing test',
          agent: 'fake',
          model: 'fake-small',
          mode: 'acceptEdits',
          instructions: 'Write it.',
        ),
      ],
      body: _bugfix.body,
    );
    final lines = runningTable(team, const [
      TeamAgentShown(
        name: 'lead',
        lead: true,
        open: true,
        state: (glyph: '◦', words: 'idle 9s', tone: 'dim'),
      ),
      TeamAgentShown(
        name: 'tester',
        open: true,
        state: (glyph: '●', words: 'permission 8s', tone: 'warning'),
        mark: (glyph: '←', words: 'new message', tone: 'dim'),
        latest: 'Bash(bun dev test)',
      ),
    ], 30);
    expect(_drawn(lines), [
      'lead    fake ·',
      '        fake-large',
      '        acceptEdits  ◦ idle 9s',
      'tester  fake ·',
      '        fake-small',
      '        acceptEdits',
      '        ● permission 8s',
      '        ← new message',
      '        Bash(bun dev test)',
    ]);
    expect(_states(lines), [
      ('◦ idle 9s', null),
      ('● permission 8s', '← new message'),
    ]);
  });
}
