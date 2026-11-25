// propose_team's call: its headline once served, the proposal read from
// what chord served, the line the person's answer leaves, a change's body
// counted as not yet written, and the team drawn under the call at 120x40
// and 80x24: description, table, instructions, body, a change's diff whole
// and the saved line. The original's tests/ui/transcript/tools/
// proposal_test.ts proposalOf, savedLine and bodyChangeLine cases, and
// tests/ui/dialogs/Permission_test.tsx's proposal rows.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/teams.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord/ui/transcript/tools/chord.dart';
import 'package:chord/ui/transcript/tools/diff.dart';
import 'package:chord/ui/transcript/tools/proposal.dart';
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord_tui/chord_tui.dart' hide Folded;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _team = Team(
  description: 'Fixes a bug end to end',
  lead: TeamLead(agent: 'claude', model: 'opus', mode: 'default'),
  members: [
    TeamMember(
      name: 'tester',
      role: 'Writes the failing test, then proves the fix',
      agent: 'claude',
      model: 'sonnet',
      mode: 'acceptEdits',
      instructions: 'Write it.\nRun it.',
    ),
    TeamMember(
      name: 'coder',
      role: 'Writes the fix, in the files the lead names',
      agent: 'codex',
      model: 'gpt-5.3-codex',
      mode: 'bypassPermissions',
      instructions: 'Fix it.',
    ),
  ],
  body: '# How bugfix works',
);

Map<String, Object?> get _input => {'name': 'bugfix', ..._team.toJson()};

ChordCall _call({Object? answer, String? error, bool pending = false}) =>
    ChordCall(
      tool: ChordTool.proposeTeam,
      input: _input,
      answer: answer,
      error: error,
      pending: pending,
    );

List<String> _rows(WidgetTester t) => [
  for (final row in t.screen.lines) row.trimRight(),
];

void main() {
  group('CTUI-37 tester: proposal warning and old-value styles', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'warning mode and old value keep their distinct styles at $size',
        (t) async {
          final coder = _team.members.last;
          final before = Team(
            description: _team.description,
            lead: _team.lead,
            members: [
              _team.members.first,
              TeamMember(
                name: coder.name,
                role: coder.role,
                agent: coder.agent,
                model: coder.model,
                mode: 'plan',
                instructions: coder.instructions,
              ),
            ],
            body: _team.body,
          );
          final theme = themeData('dark');
          await t.pumpWidget(
            Theme(
              data: theme,
              child: Tool(
                ToolCall(
                  'tester-style',
                  status: 'completed',
                  chord: _call(
                    answer: {
                      'proposal': 'change',
                      'files': <String, Object?>{},
                      'before': before.toJson(),
                    },
                  ),
                ),
                expanded: true,
              ),
            ),
            size: size,
          );
          final lines = t.screen.lines;
          final warningRow = lines.indexWhere(
            (line) => line.contains('bypassPermissions'),
          );
          final oldRow = lines.indexWhere((line) => line.contains('was plan'));
          expect(warningRow, greaterThanOrEqualTo(0));
          expect(oldRow, greaterThanOrEqualTo(0));
          final warningAt = lines[warningRow].indexOf('bypassPermissions');
          for (
            var x = warningAt;
            x < warningAt + 'bypassPermissions'.length;
            x++
          ) {
            expect(t.screen.styleAt(x, warningRow).fg, theme.warning.fg);
          }
          expect(
            t.screen.styleAt(lines[oldRow].indexOf('was plan'), oldRow).isDim,
            isTrue,
          );
        },
      );
    }
  });

  test('a proposal is read from what chord served, and not before or after '
      'a refusal', () {
    final view = proposalOf(
      _call(
        answer: {'proposal': 'new', 'files': <String, Object?>{}},
        pending: true,
      ),
    )!;
    expect(
      (view.name, view.team, view.change, view.before, view.saved),
      ('bugfix', _team, false, null, null),
    );
    final change = proposalOf(
      _call(
        answer: {
          'proposal': 'change',
          'files': <String, Object?>{},
          'before': _team.toJson(),
          'saved': false,
        },
      ),
    )!;
    expect((change.change, change.before, change.saved), (true, _team, false));
    expect(proposalOf(_call()), isNull);
    expect(proposalOf(_call(error: 'no')), isNull);
  });

  test("the person's answer leaves its line under the call", () {
    ProposalView view([Object? saved]) =>
        ProposalView(name: 'bugfix', team: _team, change: false, saved: saved);
    expect(savedLine(view()), isNull);
    expect(savedLine(view('.chord/teams/bugfix.md')), (
      text:
          'Saved to .chord/teams/bugfix.md · /team run bugfix <job> hands it '
          'a job',
      saved: true,
    ));
    expect(savedLine(view(false)), (
      text: 'Not saved · the person will say what to change',
      saved: false,
    ));
  });

  test("a change's body counts itself as not yet written", () {
    final diff = diffView('bugfix.md', 'one\ntwo\n', 'one\nthree\nfour\n');
    expect(
      bodyChangeLine('bugfix', diff.view),
      "bugfix.md's body · 2 additions, 1 removal",
    );
  });

  test('Team(bugfix) is named a proposal or a change once served', () {
    Map<String, Object?> headline(ChordCall call) {
      final line = chordHeadline(call);
      return {'name': line.name, 'arg': ?line.arg, 'note': ?line.note};
    }

    expect(headline(_call()), {'name': 'Team', 'arg': 'bugfix'});
    expect(headline(_call(answer: {'proposal': 'new'}, pending: true)), {
      'name': 'Team',
      'arg': 'bugfix',
      'note': ' · proposal',
    });
    expect(headline(_call(answer: {'proposal': 'change'})), {
      'name': 'Team',
      'arg': 'bugfix',
      'note': ' · change',
    });
    expect(chordLines(_call(answer: {'proposal': 'new'})), isEmpty);
    expect(chordLines(_call(error: 'members is missing')), [
      'members is missing',
    ]);
  });

  testWidgets("the body wraps in the width the original gives what is under "
      "a call's ⎿: the row's less the transcript's inset and the gutter, at "
      '80 columns', (t) async {
    const body =
        '## Who edits what\n\n- A member that needs a file it does not own '
        'asks its owner directly, and tells the lead what they agreed.';
    final team = Team(
      description: _team.description,
      lead: _team.lead,
      members: _team.members,
      body: body,
    );
    await t.pumpWidget(
      Theme(
        data: themeData('dark'),
        // The transcript's padding, a column each side, as the window has.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Tool(
            ToolCall(
              'c',
              status: 'completed',
              chord: ChordCall(
                tool: ChordTool.proposeTeam,
                input: {'name': 'bugfix', ...team.toJson()},
                answer: {'proposal': 'new', 'files': <String, Object?>{}},
              ),
            ),
            expanded: false,
          ),
        ),
      ),
      // Tall enough for the body below the table and instructions.
      size: const Size(80, 60),
    );
    final rows = _rows(t);
    final at = rows.indexWhere((row) => row.contains('- A member'));
    expect(
      rows[at].trim(),
      '- A member that needs a file it does not own asks its owner directly,',
    );
    expect(rows[at + 1].trim(), 'and tells the lead what they agreed.');
  });

  group('on screen', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      Future<void> draw(
        WidgetTester t,
        ChordCall call, {
        bool expanded = false,
      }) => t.pumpWidget(
        Theme(
          data: themeData('dark'),
          child: Tool(
            ToolCall('c', status: 'completed', chord: call),
            expanded: expanded,
          ),
        ),
        size: size,
      );

      testWidgets('a proposal waiting on the person: description, table, '
          'instructions and body, a mode that skips asking in the warning '
          'colour, at $size', (t) async {
        await draw(
          t,
          _call(answer: {'proposal': 'new', 'files': <String, Object?>{}}),
        );
        final rows = _rows(t);
        expect(rows[1], '⏺ Team(bugfix) · proposal');
        expect(rows[2], '  ⎿  Fixes a bug end to end');
        expect(rows[3], '');
        expect(rows[4], startsWith('     lead '));
        final coder = rows.indexWhere((row) => row.contains('coder'));
        expect(rows[coder], contains('bypassPermissions'));
        final at = rows[coder].indexOf('bypassPermissions');
        expect(t.screen.styleAt(at, coder).fg, isNotNull);
        expect(rows, contains("     tester's instructions"));
        expect(rows, contains('     Write it.'));
        expect(rows.any((row) => row.contains('How bugfix works')), isTrue);
        // Not answered yet: no saved line.
        expect(rows.any((row) => row.contains('Saved to')), isFalse);
      });

      testWidgets('saved, the line says where and how to run it, at $size', (
        t,
      ) async {
        await draw(
          t,
          _call(
            answer: {
              'proposal': 'new',
              'files': <String, Object?>{},
              'saved': '.chord/teams/bugfix.md',
            },
          ),
        );
        final rows = _rows(t);
        final saved = rows.indexWhere((row) => row.contains('Saved to'));
        expect(
          rows[saved],
          startsWith('     Saved to .chord/teams/bugfix.md · /team run bugfix'),
        );
      });

      testWidgets("a change marks its rows and draws the body's change as a "
          'diff under a line that counts it, at $size', (t) async {
        final before = Team(
          description: _team.description,
          lead: _team.lead,
          members: [_team.members.first],
          body: '# How it works',
        );
        await draw(
          t,
          _call(
            answer: {
              'proposal': 'change',
              'files': <String, Object?>{},
              'before': before.toJson(),
            },
          ),
        );
        final rows = _rows(t);
        expect(rows[1], '⏺ Team(bugfix) · change');
        expect(rows.any((row) => row.contains('+  coder')), isTrue);
        expect(rows, contains("     bugfix.md's body · 1 addition, 1 removal"));
      });
    }
  });
}
