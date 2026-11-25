// A selected run's receipt: its lines under the `Team(…)` row, and, for a
// run no longer open, `/team show <run ID>`'s recorded receipt as chord's
// own report. The original's RecordedReceipt_test.tsx and the selection
// lines it draws.
import 'package:chord/session/team_selection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/teams.dart';
import 'package:chord/ui/teams/recorded_receipt.dart';
import 'package:chord/ui/transcript/tools/selection_lines.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _reason =
    'Preserve all instructions and exact permission requirements; capacity '
    'is unknown.';

const _team = Team(
  description: 'Fixture',
  lead: TeamLead(agent: 'fake', model: 'fake-small'),
  members: [],
  body: 'Keep instructions.',
);

SelectionReceipt _refused() {
  final receipt = selectionReceipt(
    'actual-attempt',
    (name: 'fixture', place: 'project'),
    freezeSelection(
      _team,
      {
        'reason':
            'Preserve instructions and exact permissions; resource freshness '
            'remains unknown.',
      },
      const {},
      ['fake'],
    ).frozen!,
  );
  return {
    ...receipt,
    'roles': [
      for (final role in (receipt['roles'] as List).cast<Map>())
        {
          ...role,
          'state': 'refused',
          'note': 'Cancelled before its first job; closing.',
        },
    ],
  };
}

model.ChordCall _call(SelectionReceipt receipt) => model.ChordCall(
  tool: model.ChordTool.runTeam,
  input: const {'job': 'Actual recorded job.'},
  asked: receipt['runId'] as String,
  answer: {'id': receipt['runId'], 'receipt': receipt},
  error: 'Actual recorded refusal.',
);

void main() {
  test("a receipt's lines name the selection, each role planned and as it "
      'came up, and, opened, the saved definition and its changes', () {
    final receipt = _refused();
    expect(selectionLines(receipt), [
      'Selection: agent-selected · this run',
      'Reason: Preserve instructions and exact permissions; resource '
          'freshness remains unknown.',
      'Billing: unknown · advisory',
      'Planned for this run:',
      'lead (lead): fake · model fake-small · effort agent default '
          '(unconfirmed) · mode agent default (unconfirmed)',
      'Actual: refused · session runtime unknown · model unknown · effort '
          'unknown · mode unknown',
      'lead: Cancelled before its first job; closing.',
      'ctrl+o for saved definition and changes',
    ]);
    expect(selectionLines(receipt, expanded: true).skip(7), [
      'Run: actual-attempt · saved definition: fixture (project)',
      'lead saved: fake · model fake-small · effort agent default '
          '(unconfirmed) · mode agent default (unconfirmed)',
      'Changes from saved: none',
    ]);
    expect(
      selectionLines(withSelectionCleanupWarning(receipt)),
      contains('Warning: $agentCleanupUnverified'),
    );
    expect(selectionLines({'not': 'a receipt'}), isEmpty);
  });

  test("a recorded receipt is chord's own report: no live claim, its job, "
      'its lines as recorded, and the failure it ended in', () {
    final call = _call(_refused());
    expect(recordedReceiptTitle(call), 'Recorded Team receipt (fixture)');
    final lines = recordedReceiptLines(call, 120, historical: true);
    expect(
      [for (final line in lines) line.text],
      [
        'Recorded by Chord · current state unknown · historical observation',
        'Recorded: time unknown',
        'Actual recorded job.',
        'Selection: agent-selected · this run',
        'Reason: Preserve instructions and exact permissions; resource '
            'freshness remains unknown.',
        'Billing: unknown · advisory',
        'Planned for this run:',
        'lead (lead): fake · model fake-small · effort agent default '
            '(unconfirmed) · mode agent default (unconfirmed)',
        'Actual at recording: refused · session runtime unknown · model '
            'unknown · effort unknown · mode unknown',
        'lead: Cancelled before its first job; closing.',
        'Run: actual-attempt · saved definition: fixture (project)',
        'lead saved: fake · model fake-small · effort agent default '
            '(unconfirmed) · mode agent default (unconfirmed)',
        'Changes from saved: none',
        'Recorded failure: Actual recorded refusal.',
      ],
    );
    expect([for (final line in lines) line.dim].take(2), [true, true]);
    expect(lines.last.failed, isTrue);
    // A call that is not the admitted one has no receipt to show.
    expect(
      recordedReceiptTitle(
        model.ChordCall(
          tool: model.ChordTool.runTeam,
          input: const {},
          answer: {'id': 'other', 'receipt': _refused()},
        ),
      ),
      isNull,
    );
  });

  testWidgets('a selected run\'s lines under its Team row break only at a '
      'space at 80x24, as the original\'s wrap-ansi does', (t) async {
    final planned = selectionReceipt(
      'a1b2c3d4',
      (name: 'fixture', place: 'project'),
      freezeSelection(
        const Team(
          description: 'Fixture',
          lead: TeamLead(agent: 'fake'),
          members: [
            TeamMember(
              name: 'reviewer',
              role: 'Review only',
              agent: 'fake',
              instructions: 'Review.',
            ),
          ],
          body: 'Keep instructions.',
        ),
        {
          'reason': _reason,
          'lead': {'agent': 'codex', 'model': 'fake-small', 'mode': 'plan'},
          'members': {
            'reviewer': {
              'agent': 'claude',
              'model': 'fake-small',
              'mode': 'plan',
            },
          },
        },
        const {},
        ['fake', 'codex', 'claude'],
      ).frozen!,
    );
    final call = model.ChordCall(
      tool: model.ChordTool.runTeam,
      input: const {'team': 'fixture', 'job': 'selectedidle'},
      asked: 'a1b2c3d4',
      answer: {
        'id': 'a1b2c3d4',
        'name': 'fixture',
        'team': 'fixture',
        'agent': 'codex',
        'receipt': planned,
      },
    );
    Future<List<String>> drawn({required bool open}) async {
      final scroll = ScrollController(follow: Follow.bottom),
          selection = SelectionController();
      addTearDown(scroll.dispose);
      addTearDown(selection.dispose);
      await t.pumpWidget(
        Theme(
          data: themeData('dark'),
          child: SelectionArea(
            controller: selection,
            selectionStyle: const Style(inverse: true),
            child: Transcript(
              transcript: model.Transcript.empty.withEntries([
                model.ToolEntry(
                  't1',
                  model.ToolCall('c1', status: 'completed', chord: call),
                ),
              ]),
              controller: scroll,
              selectionNamespace: 'session',
              expanded: open,
            ),
          ),
        ),
        // The window keeps a column each side, as the captures show.
        size: const Size(78, 60),
      );
      return [for (final row in t.screen.lines) row.trimRight()];
    }

    final folded = await drawn(open: false);
    // ../chord tests/fixtures/selected_team_qa.ts at 80 columns, the
    // window's margin column taken off.
    expect(
      folded,
      containsAllInOrder([
        '     lead (lead): codex · model fake-small · effort agent default',
        '     (unconfirmed) · mode plan',
        '     reviewer: claude · model fake-small · effort agent default',
        '     (unconfirmed) · mode plan',
      ]),
    );
    final opened = await drawn(open: true);
    expect(
      opened,
      containsAllInOrder([
        '     lead saved: fake · model agent default (unconfirmed) · effort agent',
        '     default (unconfirmed) · mode agent default (unconfirmed)',
      ]),
    );
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("/team show <run ID> draws the run's recorded receipt with "
        'no tool marker at $size', (t) async {
      await t.pumpWidget(
        TranscriptEntry(
          model.TeamShownEntry(
            't1',
            'team show actual-attempt',
            model.TeamReceiptShown(_call(_refused())),
          ),
        ),
        size: Size(size.width - 2, size.height),
      );
      final all = [for (final row in t.screen.lines) row.trimRight()];
      final rows = all.skipWhile((row) => row.isEmpty).toList();
      expect(rows.first, '› /team show actual-attempt');
      expect(rows[1], '');
      expect(rows[2], 'Recorded Team receipt (fixture)');
      expect(
        rows[3],
        startsWith('  ⎿  Recorded by Chord · current state unknown'),
      );
      final screen = rows.join('\n');
      expect(screen, contains('Actual at recording: refused'));
      expect(screen, contains('Recorded failure: Actual recorded refusal.'));
      expect(screen, isNot(contains('⏺')));
    });
  }
}
