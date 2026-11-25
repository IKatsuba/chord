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

List<model.Entry> _reply(String text) => [
  const model.UserEntry('u', 'request'),
  model.AssistantEntry('a', TextRun.empty.plus(text)),
];
final _tall = [
  for (var i = 0; i < 60; i++) 'row $i 界👩‍💻e\u0301',
].join('\n\n');

void main() {
  group('tester: CTUI-177 held bottom lifecycle', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('scroll keys retain real counts during a held press $size', (
        t,
      ) async {
        final connection = selectionConnection(_reply(_tall));
        addTearDown(connection.close);
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (_, _) => const copy.CopyResult.sent(),
          ),
          size: size,
        );
        final at = cellOf(t, 'row 59');
        await t.mouse(primary(MouseEventKind.press, at));
        for (final (up, down) in [
          ('shift+up', 'shift+down'),
          ('pageup', 'end'),
          ('shift+pageup', 'shift+end'),
          ('home', 'end'),
          ('shift+home', 'shift+end'),
        ]) {
          await t.press(up);
          await t.pump();
          expect(t.screen, shows('below'), reason: '$up ${t.screen.text}');
          await t.press(down);
          await t.pump();
          expect(
            t.screen,
            isNot(shows('below')),
            reason: '$down ${t.screen.text}',
          );
        }
        await t.mouse(primary(MouseEventKind.release, at));
        await t.pump();
        // Scrolling marked the drag moved: release preserves the back view.
        expect(t.screen, shows('1 line below'));
        await t.press('end');
        await t.pump();
        expect(t.screen, isNot(shows('below')));
      });

      testWidgets(
        'a fitting Unicode reply stays rule-free through held resizes $size',
        (t) async {
          final connection = selectionConnection(
            _reply('edge 界👩‍💻e\u0301 \u001b[31m'),
          );
          addTearDown(connection.close);
          final window = TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (_, _) => const copy.CopyResult.sent(),
          );
          await t.pumpWidget(window, size: size);
          await t.mouse(primary(MouseEventKind.press, cellOf(t, 'edge')));
          for (final resized in [
            const Size(80, 24),
            const Size(120, 40),
            size,
          ]) {
            await t.pumpWidget(window, size: resized);
            expect(t.screen, isNot(shows('below')), reason: t.screen.text);
            expect(t.screen, shows('edge'));
          }
          await t.mouse(primary(MouseEventKind.release, cellOf(t, 'edge')));
          await t.pump();
          expect(t.screen, isNot(shows('below')));
        },
      );

      testWidgets(
        'a thousand updates before one frame retain genuine below output $size',
        (t) async {
          final connection = selectionConnection(_reply(_tall));
          addTearDown(connection.close);
          await t.pumpWidget(
            TranscriptWindow(
              launch: selectionLaunch,
              connection: connection,
              copy: (_, _) => const copy.CopyResult.sent(),
            ),
            size: size,
          );
          final at = cellOf(t, 'row 59');
          await t.mouse(primary(MouseEventKind.press, at));
          expect(t.screen, isNot(shows('below')));
          for (var i = 0; i < 1000; i++) {
            connection.app.value = AppState(
              start: const StartState(
                phase: StartPhase.connected,
                sessionId: 'selection',
              ),
              transcript: model.Transcript(
                entries: appended([], [
                  ..._reply(_tall),
                  model.AssistantEntry(
                    'b',
                    TextRun.empty.plus('new output $i'),
                  ),
                ]),
              ),
            );
          }
          await t.pump();
          expect(t.screen, shows('below'), reason: t.screen.text);
          await t.mouse(primary(MouseEventKind.release, at));
          await t.pump();
          expect(t.screen, isNot(shows('below')));
          expect(t.screen, shows('new output 999'));
        },
      );
    }
  });
}
