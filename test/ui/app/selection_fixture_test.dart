import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../../../tool/selection.dart';
import 'quit_window_test.dart' show settled;
import 'selection_window_test.dart' show selectionConnection, select;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    test(
      'recording fixture sends exact visible text and expires only success note $size',
      () {
        fakeAsync((async) {
          final t = WidgetTester();
          final connection = selectionConnection();
          final recorder = SelectionRecorder();
          try {
            settled(
              async,
              t.pumpWidget(
                selectionPreview(connection, [], recorder),
                size: size,
              ),
            );
            settled(async, select(t, 'Next eligible request'));
            expect(recorder.attempts, ['Next eligible request']);
            expect(recorder.writes, recorder.attempts);
            expect(
              t.screen,
              shows("sent 21 chars to the terminal's clipboard"),
            );
            async.elapse(const Duration(milliseconds: 3000));
            settled(async, t.pump());
            expect(t.screen, isNot(shows('sent 21 chars')));
            expect(t.screen, shows('ctrl + c to copy'));
            settled(async, t.press('ctrl+c'));
            expect(recorder.writes, [
              'Next eligible request',
              'Next eligible request',
            ]);
            expect(t.exitRequested, isFalse);
          } finally {
            t.dispose();
            settled(async, connection.close());
          }
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
    test(
      'recording timeout is bounded, persistent, retryable and never writes $size',
      () {
        fakeAsync((async) {
          final t = WidgetTester();
          final connection = selectionConnection();
          final recorder = SelectionRecorder(timeout: true);
          try {
            settled(
              async,
              t.pumpWidget(
                selectionPreview(connection, [], recorder),
                size: size,
              ),
            );
            settled(async, select(t, 'Next eligible request'));
            async.elapse(const Duration(milliseconds: 1199));
            settled(async, t.pump());
            expect(t.screen, isNot(shows('could not copy')));
            async.elapse(const Duration(milliseconds: 1));
            settled(async, t.pump());
            expect(
              t.screen,
              shows('could not copy: the clipboard did not answer'),
            );
            async.elapse(const Duration(seconds: 4));
            settled(async, t.pump());
            expect(t.screen, shows('ctrl + c to try again'));
            settled(async, t.press('ctrl+c'));
            expect(recorder.attempts, hasLength(2));
            expect(recorder.writes, isEmpty);
            settled(async, t.press('ctrl+d'));
            expect(t.exitRequested, isTrue);
            expect(recorder.writes, isEmpty);
          } finally {
            t.dispose();
            settled(async, connection.close());
          }
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
    testWidgets(
      'manual recording fixture waits for explicit key and failure never writes $size',
      (t) async {
        final connection = selectionConnection();
        addTearDown(connection.close);
        final recorder = SelectionRecorder(failure: true);
        await t.pumpWidget(
          selectionPreview(connection, ['--manual'], recorder),
          size: size,
        );
        await select(t, 'Next eligible request');
        expect(recorder.attempts, isEmpty);
        await t.press('ctrl+shift+c');
        expect(recorder.attempts, ['Next eligible request']);
        expect(recorder.writes, isEmpty);
        expect(t.screen, shows('could not copy: recording clipboard refused'));
        await t.paste('');
        expect(t.screen, isNot(shows('could not copy')));
      },
    );
  }
}
