// The receipts main's transcript holds whose run has no Team(...) row of
// its own, drawn after its entries as the original's App draws its
// RecordedReceipt list: the original's recorded_receipts_test.ts, and a
// resumed record whose receipt was served after /clear, at 120x40 and
// 80x24.
import 'package:chord/session/replay.dart' show recordActions;
import 'package:chord/session/team_selection.dart';
import 'package:chord/session/transcript/entries.dart' show replayTranscript;
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/teams.dart';
import 'package:chord/ui/teams/recorded_receipt.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

SelectionReceipt _receipt(String runId, {String state = 'planned'}) {
  final made = selectionReceipt(
    runId,
    (name: 'fixture', place: 'project'),
    freezeSelection(
      const Team(
        description: 'Fixture',
        lead: TeamLead(agent: 'fake', model: 'fake-small'),
        members: [],
        body: 'Keep instructions.',
      ),
      {'reason': 'Keep every role; capacity is unknown.'},
      const {},
      ['fake'],
    ).frozen!,
  );
  return {
    ...made,
    'roles': [
      for (final role in (made['roles'] as List).cast<Map>())
        {...role, 'state': state},
    ],
  };
}

model.ChordCall _call(String runId, {String state = 'planned'}) =>
    model.ChordCall(
      tool: model.ChordTool.runTeam,
      input: const {
        'team': 'fixture',
        'job': 'Actual recorded job.',
        'selection': {'reason': 'Keep every role; capacity is unknown.'},
      },
      asked: runId,
      answer: {
        'id': runId,
        'name': 'fixture',
        'team': 'fixture',
        'agent': 'fake',
        'receipt': _receipt(runId, state: state),
      },
    );

Map<String, Object?> _line(Map<String, Object?> json) => json;

void main() {
  group('CTUI-37 tester: receipt viewport lifecycle', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('lazy receipts scroll and coalesce updates at $size', (
        t,
      ) async {
        final scroll = ScrollController(follow: Follow.bottom);
        final selection = SelectionController();
        final source = ValueNotifier(
          model.Transcript(
            served: [for (var i = 0; i < 12; i++) _call('viewport-$i')],
          ),
        );
        addTearDown(scroll.dispose);
        addTearDown(selection.dispose);
        addTearDown(source.dispose);
        await t.pumpWidget(
          Theme(
            data: themeData('dark'),
            child: SelectionArea(
              controller: selection,
              selectionStyle: const Style(inverse: true),
              child: ListenableBuilder(
                listenable: source,
                builder: (_) => Transcript(
                  transcript: source.value,
                  controller: scroll,
                  resumed: true,
                  selectionNamespace: 'receipt-viewport',
                ),
              ),
            ),
          ),
          size: size,
        );
        expect(scroll.contentRows, greaterThan(size.height));
        scroll.toTop();
        await t.pump();
        expect(t.screen.text, contains('Recorded Team receipt (fixture)'));
        // These client reports never become agent-selectable output.
        await t.mouse(
          const MouseEvent(
            MouseEventKind.press,
            position: Offset(2, 1),
            button: MouseButton.primary,
          ),
        );
        await t.mouse(
          const MouseEvent(
            MouseEventKind.move,
            position: Offset(20, 3),
            button: MouseButton.primary,
          ),
        );
        await t.mouse(
          const MouseEvent(
            MouseEventKind.release,
            position: Offset(20, 3),
            button: MouseButton.primary,
          ),
        );
        expect(selection.snapshot()?.text ?? '', isEmpty);
        for (var i = 0; i < 1000; i++) {
          source.value = model.Transcript(
            served: [
              ...source.value.served,
              _call('viewport-11', state: i == 999 ? 'refused' : 'confirmed'),
            ],
          );
        }
        await t.pump();
        expect(recordedReceipts(source.value), hasLength(12));
        final seen = <String>[];
        scroll.toTop();
        for (var page = 0; page < 100; page++) {
          await t.pump();
          seen.add(t.screen.text);
          if (scroll.rowsBelow == 0) break;
          scroll.pageDown();
        }
        final all = seen.join('\n');
        for (var i = 0; i < 12; i++) {
          expect(all, contains('Run: viewport-$i ·'));
        }
        expect(all, contains('Actual at recording: refused'));
        for (final tiny in const [Size(0, 0), Size(1, 1), Size(8, 4)]) {
          await t.resize(tiny);
        }
        await t.resize(size);
        scroll.toBottom();
        await t.pump();
        expect(t.screen.text, contains('Run: viewport-11 ·'));
        expect(selection.snapshot()?.text ?? '', isEmpty);
        await t.pumpWidget(Text('receipts removed'), size: size);
        source.value = model.Transcript(served: [_call('after-removal')]);
        await t.pump();
        expect(t.screen.text, contains('receipts removed'));
        expect(selection.snapshot(), isNull);
      });
    }
  });

  test('only the latest receipt of each run whose call has no row of its '
      'own is listed, in the order the runs came', () {
    final linked = _call('linked');
    final transcript = model.Transcript(
      entries: [
        model.ToolEntry(
          't1',
          model.ToolCall('c1', status: 'completed', chord: linked),
        ),
      ],
      served: [
        _call('first'),
        _call('linked', state: 'confirmed'),
        _call('second'),
        _call('first', state: 'refused'),
        // Not the admitted call: no receipt.
        model.ChordCall(
          tool: model.ChordTool.runTeam,
          input: const {},
          asked: 'other',
          answer: {'id': 'wrong', 'receipt': _receipt('other')},
        ),
      ],
    );
    final listed = recordedReceipts(transcript);
    expect([for (final call in listed) call.asked], ['first', 'second']);
    expect(
      ((recordedSelection(listed.first)!['roles'] as List).first
          as Map)['state'],
      'refused',
    );
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("a resumed record's receipt served after /clear, with no "
        'row of its own, draws after the entries at $size', (t) async {
      // The record as main's /clear left it: the run's first line in the
      // session before, its later update appended to the same record.
      final history = recordActions([
        _line({
          'type': 'session',
          'version': 1,
          'sessionId': 'main-1',
          'agent': 'fake',
          'cwd': 'p',
          'at': 0,
        }),
        _line({
          'type': 'prompt',
          'turnId': 't1',
          'prompt': 'hello',
          'images': 0,
          'links': <Object?>[],
          'at': 1,
        }),
        _line({
          'type': 'result',
          'turnId': 't1',
          'result': {'status': 'completed', 'stopReason': 'end_turn'},
        }),
        _line({
          'type': 'served',
          'turnId': 't2',
          'call': _call('a1b2c3d4', state: 'refused').toJson(),
        }),
      ]);
      final transcript = replayTranscript(history.actions);
      expect(recordedReceipts(transcript), hasLength(1));
      final scroll = ScrollController(follow: Follow.bottom);
      addTearDown(scroll.dispose);
      await t.pumpWidget(
        Theme(
          data: themeData('dark'),
          child: Transcript(
            transcript: transcript,
            controller: scroll,
            resumed: true,
          ),
        ),
        // The window keeps a column each side, as the captures show.
        size: Size(size.width - 2, size.height + 20),
      );
      final rows = [for (final row in t.screen.lines) row.trimRight()];
      final title = rows.indexOf('Recorded Team receipt (fixture)');
      expect(
        title,
        greaterThan(rows.indexWhere((row) => row.contains('hello'))),
      );
      expect(rows[title - 1], '');
      expect(
        rows[title + 1],
        '  ⎿  Recorded by Chord · current state unknown · historical '
        'observation',
      );
      expect(rows.join('\n'), contains('Actual at recording: refused'));
      expect(rows.join('\n'), isNot(contains('⏺ Team(')));
    });
  }
}
