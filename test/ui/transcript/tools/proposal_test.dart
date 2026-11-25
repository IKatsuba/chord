// A team's table, its instructions and its folded body, as the original's
// tests/ui/transcript/tools/proposal_test.ts checks them; the proposal's
// own call, marks drawn and saved line come with propose_team.
import 'package:chord/session/team_command.dart' show leadRole;
import 'package:chord/teams.dart';
import 'package:chord/ui/transcript/tools/proposal.dart';
import 'package:chord_tui/chord_tui.dart' show cellWidth;
import 'package:test/test.dart';

const _tester = TeamMember(
  name: 'tester',
  role: 'Writes the failing test, then proves the fix',
  agent: 'claude',
  model: 'sonnet',
  mode: 'acceptEdits',
  instructions: 'Write it.\nRun it.',
);

const _coder = TeamMember(
  name: 'coder',
  role: 'Writes the fix, in the files the lead names',
  agent: 'codex',
  model: 'gpt-5.3-codex',
  mode: 'auto',
  instructions: 'Fix it.',
);

const _team = Team(
  description: 'Fixes a bug end to end',
  lead: TeamLead(agent: 'claude', model: 'opus', mode: 'default'),
  members: [_tester, _coder],
  body: '# How bugfix works',
);

TeamMember _member(
  TeamMember of, {
  String? name,
  String? mode,
  String? effort,
  bool noMode = false,
}) => TeamMember(
  name: name ?? of.name,
  role: of.role,
  agent: of.agent,
  model: of.model,
  effort: effort ?? of.effort,
  mode: noMode ? null : mode ?? of.mode,
  instructions: of.instructions,
);

Team _with(Team team, {TeamLead? lead, List<TeamMember>? members}) => Team(
  description: team.description,
  lead: lead ?? team.lead,
  members: members ?? team.members,
  body: team.body,
);

List<String> _texts(List<TableLine> lines) => [
  for (final line in lines) line.text,
];

String? _slice(String text, (int, int)? range) =>
    range == null ? null : text.substring(range.$1, range.$2);

List<String> _modes(List<TableLine> lines) => [
  for (final line in lines) _slice(line.text, line.mode)!,
];

/// CHD-356's team: three agents set an effort, the reviewer leaves it.
final _efforts = _with(
  _team,
  lead: const TeamLead(
    agent: 'claude',
    model: 'opus',
    effort: 'high',
    mode: 'default',
  ),
  members: [
    _member(_tester, effort: 'high'),
    _member(_coder, effort: 'xhigh'),
    const TeamMember(
      name: 'reviewer',
      role: 'Reads the diff and edits nothing',
      agent: 'claude',
      model: 'opus',
      mode: 'plan',
      instructions: 'Read it.',
    ),
  ],
);

/// The same team saved before: tester on medium and bypass, coder on none.
final _effortsBefore = _with(
  _efforts,
  members: [
    _member(_efforts.members[0], effort: 'medium', mode: 'bypassPermissions'),
    _coder,
    _member(_efforts.members[2], mode: 'read-only'),
  ],
);

void main() {
  test("the table's columns fit the width: the role and then agent · model "
      'wrap in their columns, the mode never', () {
    final rows = agentRows(_team);
    final wide = proposalTable(rows, 120);
    expect(_texts(wide), [
      'lead    claude · opus          default      $leadRole',
      'tester  claude · sonnet        acceptEdits  Writes the failing test, '
          'then proves the fix',
      'coder   codex · gpt-5.3-codex  auto         Writes the fix, in the '
          'files the lead names',
    ]);
    expect(_modes(wide), ['default', 'acceptEdits', 'auto']);
    expect(_texts(proposalTable(rows, 70)), [
      'lead    claude · opus          default      Splits the job, says who',
      '                                            edits which files, reports',
      '                                            to main',
      'tester  claude · sonnet        acceptEdits  Writes the failing test,',
      '                                            then proves the fix',
      'coder   codex · gpt-5.3-codex  auto         Writes the fix, in the',
      '                                            files the lead names',
    ]);
    // Where agent · model's longest word and the role's least do not fit
    // beside the other cells, the table is laid out as opened.
    expect(
      _texts(proposalTable(rows, 44)),
      _texts(proposalTable(rows, 44, whole: true)),
    );
  });

  test('opened, each role is whole on lines of its own under its row, to '
      'the right edge', () {
    final rows = agentRows(_team);
    final opened = proposalTable(rows, 80, whole: true);
    expect(_texts(opened), [
      'lead    claude · opus          default',
      '        $leadRole',
      'tester  claude · sonnet        acceptEdits',
      '        Writes the failing test, then proves the fix',
      'coder   codex · gpt-5.3-codex  auto',
      '        Writes the fix, in the files the lead names',
    ]);
    expect(_modes(opened), ['default', '', 'acceptEdits', '', 'auto', '']);
    expect(
      [for (final line in opened) (line.row.name, line.role)],
      [
        ('lead', false),
        ('lead', true),
        ('tester', false),
        ('tester', true),
        ('coder', false),
        ('coder', true),
      ],
    );
    // The same shape at any width, so nothing jumps as the terminal resizes.
    expect(_texts(proposalTable(rows, 200, whole: true)), _texts(opened));
    expect(_texts(proposalTable(rows, 50, whole: true)), [
      'lead    claude · opus          default',
      '        Splits the job, says who edits which',
      '        files, reports to main',
      'tester  claude · sonnet        acceptEdits',
      '        Writes the failing test, then proves the',
      '        fix',
      'coder   codex · gpt-5.3-codex  auto',
      '        Writes the fix, in the files the lead',
      '        names',
    ]);
  });

  test('opened, a change keeps every model whole, its mark and was on the '
      'first row', () {
    final after = _with(
      _team,
      members: [
        _member(_tester, mode: 'bypassPermissions'),
        _coder,
      ],
    );
    final lines = proposalTable(
      agentRows(after, _team),
      80,
      marked: true,
      whole: true,
    );
    expect(_texts(lines), [
      '   lead    claude · opus          default',
      '           $leadRole',
      '~  tester  claude · sonnet        bypassPermissions was acceptEdits',
      '           Writes the failing test, then proves the fix',
      '   coder   codex · gpt-5.3-codex  auto',
      '           Writes the fix, in the files the lead names',
    ]);
    expect(
      [for (final line in lines) _slice(line.text, line.was)],
      [null, null, ' was acceptEdits', null, null, null],
    );
  });

  test('opened, where the mode leaves no room, the role spans the agent and '
      'mode columns', () {
    final after = _with(
      _team,
      members: [
        _member(_tester, mode: 'bypassPermissions'),
        _coder,
      ],
    );
    final lines = proposalTable(
      agentRows(after, _team),
      44,
      marked: true,
      whole: true,
    );
    expect(
      _texts([
        for (final line in lines)
          if (line.role) line,
      ]),
      [
        '           Splits the job, says who edits',
        '           which files, reports to main',
        '           Writes the failing test, then',
        '           proves the fix',
        '           Writes the fix, in the files the',
        '           lead names',
      ],
    );
  });

  test('opened, a row that does not fit wraps its mode first and its model '
      'last, at spaces', () {
    const reviewer = TeamMember(
      name: 'security-review',
      role: 'Reviews the diff for security problems and edits nothing',
      agent: 'claude',
      model: 'claude-sonnet-4-5-20250929',
      mode: 'acceptEdits',
      instructions: 'Review it.',
    );
    final before = _with(_team, members: [reviewer]);
    final after = _with(
      _team,
      members: [_member(reviewer, mode: 'bypassPermissions')],
    );
    final rows = agentRows(after, before);
    final lines = proposalTable(rows, 74, marked: true, whole: true);
    expect(_texts(lines), [
      '   lead             claude · opus                        default',
      '                    Splits the job, says who edits which files, '
          'reports to',
      '                    main',
      '~  security-review  claude · claude-sonnet-4-5-20250929  '
          'bypassPermissions',
      '                                                         was '
          'acceptEdits',
      '                    Reviews the diff for security problems and edits',
      '                    nothing',
    ]);
    expect(_modes(lines), ['default', '', '', 'bypassPermissions', '', '', '']);
    expect(
      [for (final line in lines) _slice(line.text, line.was)],
      [null, null, null, null, 'was acceptEdits', null, null],
    );
    expect(
      [for (final line in lines) line.role],
      [false, true, true, false, false, true, true],
    );
    expect(
      _texts(proposalTable(rows, 72, marked: true, whole: true).sublist(3, 6)),
      [
        '~  security-review  claude ·                           '
            'bypassPermissions',
        '                    claude-sonnet-4-5-20250929         was '
            'acceptEdits',
        '                    Reviews the diff for security problems and edits',
      ],
    );
  });

  test("a change's rows are marked against the team saved before, its gone "
      'members last', () {
    final after = _with(
      _team,
      members: [
        _member(_tester, mode: 'bypassPermissions'),
        _member(_coder, name: 'fixer'),
      ],
    );
    final lines = [
      for (final line in proposalTable(
        agentRows(after, _team),
        120,
        marked: true,
      ))
        if (line.mode.$2 > line.mode.$1) line,
    ];
    expect(
      [for (final line in lines) line.text.substring(0, 11)],
      ['   lead    ', '~  tester  ', '+  fixer   ', '-  coder   '],
    );
    expect(_modes(lines), ['default', 'bypassPermissions', 'auto', 'auto']);
    expect(
      [for (final line in lines) _slice(line.text, line.was)],
      [null, ' was acceptEdits', null, null],
    );
  });

  test('a member named lead is marked as itself, never as the lead', () {
    const reviewer = TeamMember(
      name: 'lead',
      role: 'Reviews the fix',
      agent: 'claude',
      instructions: 'Review',
    );
    final before = _with(_team, members: [..._team.members, reviewer]);
    final changed = _with(
      before,
      members: [
        ..._team.members,
        const TeamMember(
          name: 'lead',
          role: 'Reviews the fix',
          agent: 'claude',
          instructions: 'Review carefully',
        ),
      ],
    );
    List<(String, RowChange?)> marks(List<ProposalRow> rows) => [
      for (final row in rows) (row.role, row.change),
    ];
    expect(marks(agentRows(changed, before)), [
      (leadRole, null),
      (_tester.role, null),
      (_coder.role, null),
      ('Reviews the fix', RowChange.changed),
    ]);
    expect(marks(agentRows(_team, before)), [
      (leadRole, null),
      (_tester.role, null),
      (_coder.role, null),
      ('Reviews the fix', RowChange.removed),
    ]);
  });

  test("a changed row says the mode it had, none where its mode is the same, "
      "and — for the runtime's own", () {
    final after = _with(
      _team,
      lead: const TeamLead(agent: 'claude', model: 'sonnet', mode: 'default'),
      members: [_member(_tester, noMode: true), _coder],
    );
    expect(
      [for (final row in agentRows(after, _team)) row.was],
      [null, 'acceptEdits', null],
    );
    expect(
      [for (final row in agentRows(_team, after)) row.was],
      [null, '—', null],
    );
  });

  test('a mode that skips the person ok is told apart', () {
    expect(
      [
        for (final mode in [
          'bypassPermissions',
          'full-access',
          'default',
          'auto',
          null,
        ])
          skipsAsking(mode),
      ],
      [true, true, false, false, false],
    );
  });

  test('the body folds to its first lines, and ctrl+o adds the '
      'instructions', () {
    const blocks = ['How bugfix works', '1. One\n2. Two', 'Reporting'];
    const instructions = ['', "tester's instructions", 'Write it.'];
    final folded = proposalBody(
      instructions: instructions,
      blocks: blocks,
      keep: 2,
      expanded: false,
    );
    expect(folded.lines, ['', 'How bugfix works', '1. One']);
    expect(folded.hidden, 7);
    final none = proposalBody(
      instructions: instructions,
      blocks: blocks,
      keep: 0,
      expanded: false,
    );
    expect(none.lines, isEmpty);
    expect(none.hidden, 10);
    expect(
      proposalBody(
        instructions: instructions,
        blocks: blocks,
        keep: 2,
        expanded: true,
      ).lines,
      [
        ...instructions,
        '',
        'How bugfix works',
        '',
        '1. One',
        '2. Two',
        '',
        'Reporting',
      ],
    );
  });

  test("each agent's instructions are wrapped to the width whole, a long "
      'line no longer cut (CHD-332)', () {
    const long =
        'Ты ведущий команды `dev`: читай задачу, `quarry task list`, решай, '
        'кто что делает, и следи за правилом.';
    final team = _with(
      _team,
      lead: const TeamLead(
        agent: 'claude',
        model: 'opus',
        mode: 'default',
        instructions: long,
      ),
      members: [_tester],
    );
    expect(instructionLines(team, 30), [
      '',
      "lead's instructions",
      'Ты ведущий команды `dev`:',
      'читай задачу, `quarry task',
      'list`, решай, кто что делает,',
      'и следи за правилом.',
      '',
      "tester's instructions",
      'Write it.',
      'Run it.',
    ]);
  });

  test('an effort is a column between agent · model and the mode, — where '
      'none is set, and none where no agent sets one', () {
    expect(_texts(proposalTable(agentRows(_efforts), 114)), [
      'lead      claude · opus          high   default      $leadRole',
      'tester    claude · sonnet        high   acceptEdits  Writes the failing '
          'test, then proves the fix',
      'coder     codex · gpt-5.3-codex  xhigh  auto         Writes the fix, in '
          'the files the lead names',
      'reviewer  claude · opus          —      plan         Reads the diff and '
          'edits nothing',
    ]);
    expect(_texts(proposalTable(agentRows(_efforts), 74)), [
      'lead      claude · opus          high   default      Splits the job, says',
      '                                                     who edits which',
      '                                                     files, reports to',
      '                                                     main',
      'tester    claude · sonnet        high   acceptEdits  Writes the failing',
      '                                                     test, then proves the',
      '                                                     fix',
      'coder     codex · gpt-5.3-codex  xhigh  auto         Writes the fix, in',
      '                                                     the files the lead',
      '                                                     names',
      'reviewer  claude · opus          —      plan         Reads the diff and',
      '                                                     edits nothing',
    ]);
    expect(agentRows(_team)[0].effort, '—');
    expect(
      proposalTable(agentRows(_team), 120)[0].text,
      'lead    claude · opus          default      $leadRole',
    );
  });

  test('a changed effort says the one it had, and folded drops that before '
      'agent · model narrows', () {
    final rows = agentRows(_efforts, _effortsBefore);
    expect(
      [for (final row in rows) (row.effort, row.effortWas)],
      [('high', null), ('high', 'medium'), ('xhigh', '—'), ('—', null)],
    );
    expect(
      [
        for (final row in agentRows(_team, _efforts))
          (row.effort, row.effortWas),
      ],
      [('—', 'high'), ('—', 'high'), ('—', 'xhigh'), ('—', null)],
    );
    final all = proposalTable(rows, 114, marked: true);
    final wide = [
      for (final line in all)
        if (line.mode.$2 > line.mode.$1) line,
    ];
    expect(_texts(all), [
      '   lead      claude · opus          high             default            '
          '                Splits the job, says who',
      '                                                                        '
          '                edits which files, reports',
      '                                                                        '
          '                to main',
      '~  tester    claude · sonnet        high was medium  acceptEdits was '
          'bypassPermissions  Writes the failing test,',
      '                                                                        '
          '                then proves the fix',
      '~  coder     codex · gpt-5.3-codex  xhigh was —      auto               '
          '                Writes the fix, in the',
      '                                                                        '
          '                files the lead names',
      '~  reviewer  claude · opus          —                plan was read-only '
          '                Reads the diff and edits',
      '                                                                        '
          '                nothing',
    ]);
    expect(_slice(wide[1].text, wide[1].effortWas), ' was medium');
    expect(wide[0].effortWas, isNull);
    // Too narrow for its columns beside the changed cells, laid out as
    // opened.
    expect(
      _texts(proposalTable(rows, 74, marked: true)),
      _texts(proposalTable(rows, 74, marked: true, whole: true)),
    );
  });

  test('opened, a changed cell that wraps breaks before was, and the effort '
      'wraps before the model', () {
    final rows = agentRows(_efforts, _effortsBefore);
    final opened = proposalTable(rows, 74, marked: true, whole: true);
    expect(_texts(opened), [
      '   lead      claude · opus          high             default',
      '             Splits the job, says who edits which files, reports to main',
      '~  tester    claude · sonnet        high was medium  acceptEdits',
      '                                                     was '
          'bypassPermissions',
      '             Writes the failing test, then proves the fix',
      '~  coder     codex · gpt-5.3-codex  xhigh was —      auto',
      '             Writes the fix, in the files the lead names',
      '~  reviewer  claude · opus          —                plan was read-only',
      '             Reads the diff and edits nothing',
    ]);
    expect(_slice(opened[3].text, opened[3].was), 'was bypassPermissions');
    final long = proposalTable(
      agentRows(
        _efforts,
        _with(
          _effortsBefore,
          members: [
            ..._effortsBefore.members,
            const TeamMember(
              name: 'security-review',
              role: 'Reviews the diff for security problems and edits nothing',
              agent: 'claude',
              model: 'claude-sonnet-4-5-20250929',
              effort: 'max',
              mode: 'bypassPermissions',
              instructions: 'Review it.',
            ),
          ],
        ),
      ),
      74,
      marked: true,
      whole: true,
    );
    expect(_texts(long.sublist(3, 6)), [
      '~  tester           claude · sonnet              high    acceptEdits',
      '                                                 was     was',
      '                                                 medium  '
          'bypassPermissions',
    ]);
    expect(_slice(long[4].text, long[4].effortWas), 'was');
    expect(_slice(long[5].text, long[5].effortWas), 'medium');
    expect(_slice(long[5].text, long[5].was), 'bypassPermissions');
    expect(_texts(long.sublist(long.length - 4, long.length - 2)), [
      '-  security-review  claude ·                     max     '
          'bypassPermissions',
      '                    claude-sonnet-4-5-20250929',
    ]);
  });

  test('narrow, every word of agent · model and of the role is kept, each '
      'wrapping in its column', () {
    final rows = agentRows(_efforts, _effortsBefore);
    for (final width in [74, 60]) {
      final read = _texts(proposalTable(rows, width, marked: true)).join(' ');
      for (final row in rows) {
        for (final word in '${row.runtime} ${row.role}'.split(' ')) {
          expect(read, contains(word), reason: '$word at $width');
        }
      }
      expect(read, isNot(contains('…')));
    }
  });

  test('no row of a narrow table is wider than its width', () {
    for (final (rows, marked) in [
      (agentRows(_efforts, _effortsBefore), true),
      (agentRows(_team), false),
    ]) {
      for (var width = 70; width >= 48; width--) {
        for (final line in proposalTable(rows, width, marked: marked)) {
          expect(
            cellWidth(line.text),
            lessThanOrEqualTo(width),
            reason: '$width: ${line.text}',
          );
        }
      }
    }
  });
}
