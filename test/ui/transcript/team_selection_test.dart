// CTUI-94: what of a team selects in the transcript, as the original's
// source draws it. A member's expanded instructions are selectable
// (Transcript.tsx TeamPartLine: {...selectable}); the line above them is
// furniture. A proposal's description, table, instructions and saved line
// are furniture (Tool.tsx Proposal: FILL, no useSelectable); a change's
// body diff selects, its headline and code (Tool.tsx Diff and DiffRows).
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/teams.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../app/selection_window_test.dart';

const _team = Team(
  description: 'Fixes a bug end to end',
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
  ],
  body: 'Old way of working',
);

const _changed = Team(
  description: 'Fixes a bug end to end',
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
  ],
  body: 'New way of working',
);

model.ToolEntry _proposal(Team team, {Team? before}) => model.ToolEntry(
  'p',
  model.ToolCall(
    'p',
    status: 'completed',
    chord: model.ChordCall(
      tool: model.ChordTool.proposeTeam,
      input: {'name': 'bugfix', ...team.toJson()},
      answer: before == null
          ? {'proposal': 'new', 'files': <String, Object?>{}}
          : {
              'proposal': 'change',
              'files': <String, Object?>{},
              'before': before.toJson(),
            },
    ),
  ),
);

/// The window over [entries], and what a drag from [from] to the end of
/// [to] copies, ctrl+o pressed first when [expand]; with [reverse], from
/// the end of [from] back to the start of [to].
Future<List<String>> _copied(
  WidgetTester t,
  Size size,
  List<model.Entry> entries,
  String from,
  String to, {
  bool expand = false,
  bool reverse = false,
}) async {
  final connection = selectionConnection(entries);
  addTearDown(connection.close);
  final writes = <String>[];
  await t.pumpWidget(
    TranscriptWindow(
      launch: selectionLaunch,
      connection: connection,
      copyOnSelect: false,
      copy: (text, _) {
        writes.add(text);
        return const copy.CopyResult.sent();
      },
    ),
    size: size,
  );
  if (expand) {
    await t.press('ctrl+o');
    await t.pump();
  }
  final start = cellOf(t, from, end: reverse);
  final end = cellOf(t, to, end: !reverse);
  await t.mouse(primary(MouseEventKind.press, start));
  await t.mouse(primary(MouseEventKind.move, end));
  await t.mouse(primary(MouseEventKind.release, end));
  await t.press('ctrl+shift+c');
  return writes;
}

void main() {
  group('tester: team selection wrapping and expanded geometry', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      for (final reverse in [false, true]) {
        testWidgets(
          'styled Unicode instructions copy through wraps at $size, reverse $reverse',
          (t) async {
            final text =
                'Run 界🙂e\u0301 ${List.filled(16, 'the parser').join(' ')}.\nReport every failure.';
            final writes = await _copied(
              t,
              size,
              [
                model.TeamPartEntry('unicode', (
                  team: 'bugfix',
                  member: 'tester',
                  text: '\x1b[31m$text\x1b[0m',
                )),
              ],
              reverse ? 'every failure.' : 'Run 界🙂e\u0301',
              reverse ? 'Run 界🙂e\u0301' : 'every failure.',
              expand: true,
              reverse: reverse,
            );
            expect(writes.single, text);
          },
        );
      }

      testWidgets(
        'expanded proposal diff copies Unicode without its furniture at $size',
        (t) async {
          final changed = Team(
            description: _team.description,
            lead: _team.lead,
            members: _team.members,
            body: 'New 界🙂e\u0301 way of working',
          );
          final writes = await _copied(
            t,
            size,
            [_proposal(changed, before: _team)],
            'New 界🙂e\u0301 way of working',
            'Fixes a bug',
            expand: true,
            reverse: true,
          );
          expect(writes.single, contains('New 界🙂e\u0301 way of working'));
          expect(writes.single, contains('Old way of working'));
          for (final furniture in ['Fixes a bug', 'acceptEdits', 'Write it.']) {
            expect(writes.single, isNot(contains(furniture)));
          }
        },
      );
    }
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('expanded team instructions select, their line does not, at '
        '$size', (t) async {
      final writes = await _copied(
        t,
        size,
        const [
          model.TeamPartEntry('t', (
            team: 'bugfix',
            member: 'tester',
            text: 'Run the tests.\nReport each failure.',
          )),
        ],
        'each failure.',
        "bugfix's instructions",
        expand: true,
        reverse: true,
      );
      expect(writes.single, 'Run the tests.\nReport each failure.');
    });

    testWidgets("a change's body diff selects and the proposal's rows do "
        'not, at $size', (t) async {
      final writes = await _copied(
        t,
        size,
        [_proposal(_changed, before: _team)],
        'New way of working',
        'Fixes a bug',
        reverse: true,
      );
      final copied = writes.single;
      expect(copied, contains('Old way of working'));
      expect(copied, contains('New way of working'));
      for (final row in ['Fixes a bug', 'tester', 'acceptEdits', 'Write it.']) {
        expect(copied, isNot(contains(row)));
      }
    });

    testWidgets("a new proposal's rows copy nothing, at $size", (t) async {
      final writes = await _copied(
        t,
        size,
        [_proposal(_team)],
        'Fixes a bug',
        'Old way of working',
      );
      expect(writes.join(), isNot(contains('Fixes a bug')));
      expect(writes.join(), isNot(contains('tester')));
    });
  }
}
