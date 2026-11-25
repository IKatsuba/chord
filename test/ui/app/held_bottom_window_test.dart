// A press held at the transcript's bottom draws no "below" rule, held or
// released, until output arrives under it: the original's CHD-397
// (tests/ui/app/Selection_test.tsx, Held_test.tsx).
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart';

String _lines(int count) =>
    [for (var i = 1; i <= count; i++) '$i. Line $i of the reply'].join('\n\n');

List<model.Entry> _reply(String text) => [
  const model.UserEntry('u', 'request text'),
  model.AssistantEntry('a', TextRun.empty.plus(text)),
];

// The transcript's last row: the one above the prompt's top border.
Offset _lastRow(WidgetTester t) {
  final border = t.screen.lines.lastIndexWhere((l) => l.startsWith('╭'));
  expect(border, greaterThan(0), reason: t.screen.text);
  return Offset(4, border - 1);
}

Future<void> _pump(WidgetTester t, Size size, List<model.Entry> entries) async {
  final connection = selectionConnection(entries);
  addTearDown(connection.close);
  await t.pumpWidget(
    TranscriptWindow(
      launch: selectionLaunch,
      connection: connection,
      copy: (_, _) => const copy.CopyResult.sent(),
    ),
    size: size,
  );
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final (name, entries, target) in [
      ('a reply that fits', _reply('reply words'), 'reply words'),
      ('a tall reply', _reply(_lines(60)), 'Line 60 of'),
    ]) {
      for (final where in ['on its last line', 'on the last row']) {
        testWidgets('a press $where of $name draws no rule, held or '
            'released $size', (t) async {
          await _pump(t, size, entries);
          expect(t.screen, isNot(shows('below')));
          final at = where == 'on the last row'
              ? _lastRow(t)
              : cellOf(t, target);
          final before = t.screen.lines;
          await t.mouse(primary(MouseEventKind.press, at));
          await t.pump();
          expect(t.screen, isNot(shows('below')), reason: t.screen.text);
          // Nothing moves under the pointer either.
          expect(t.screen.lines, before);
          await t.mouse(primary(MouseEventKind.release, at));
          await t.pump();
          expect(t.screen, isNot(shows('below')), reason: t.screen.text);
        });
      }
    }

    testWidgets('output arriving under a held press is counted, and the '
        'release follows it again $size', (t) async {
      final connection = selectionConnection(_reply(_lines(60)));
      addTearDown(connection.close);
      await t.pumpWidget(
        TranscriptWindow(
          launch: selectionLaunch,
          connection: connection,
          copy: (_, _) => const copy.CopyResult.sent(),
        ),
        size: size,
      );
      final at = cellOf(t, 'Line 60 of');
      await t.mouse(primary(MouseEventKind.press, at));
      await t.pump();
      expect(t.screen, isNot(shows('below')));
      connection.app.value = AppState(
        start: const StartState(
          phase: StartPhase.connected,
          sessionId: 'selection',
        ),
        transcript: model.Transcript(
          entries: appended([], [
            ..._reply(_lines(60)),
            model.AssistantEntry('b', TextRun.empty.plus('more under it')),
          ]),
        ),
      );
      await t.pump();
      expect(t.screen, shows('lines below'), reason: t.screen.text);
      await t.mouse(primary(MouseEventKind.release, at));
      await t.pump();
      expect(t.screen, isNot(shows('below')), reason: t.screen.text);
      expect(t.screen, shows('more under it'));
    });
  }
}
