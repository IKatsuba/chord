import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../../../tool/selection.dart';
import 'quit_window_test.dart' show settled;
import 'selection_window_test.dart';
import 'code_pick_window_test.dart' show pickHint, pressBounded;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'recording pick fixture reaches offscreen quote and ordinary full source at $size',
      (t) async {
        final connection = selectionConnection();
        addTearDown(connection.close);
        final recorder = SelectionRecorder();
        await t.pumpWidget(
          selectionPreview(connection, [
            '--pick',
            '--many',
            '--manual',
          ], recorder),
          size: size,
        );
        expect(t.screen, isNot(shows('quoted body')));
        await pressBounded(t, 'ctrl+x b');
        expect(t.screen, shows('quoted body'));
        expect(t.screen, shows(pickHint));
        await pressBounded(t, 'c');
        expect(recorder.writes, ['quoted body']);
        await pressBounded(t, 'ctrl+x b up c');
        expect(recorder.writes, ['quoted body', '\tcopy body\n\ntail']);
      },
    );
    test('real code failure expires without a range retry $size', () {
      fakeAsync((clock) {
        final t = WidgetTester();
        final connection = selectionConnection();
        final recorder = SelectionRecorder(failure: true);
        try {
          settled(
            clock,
            t.pumpWidget(
              selectionPreview(connection, ['--pick', '--manual'], recorder),
              size: size,
            ),
          );
          settled(clock, pressBounded(t, 'ctrl+x b c'));
          expect(
            t.screen,
            shows('could not copy: recording clipboard refused'),
          );
          expect(t.screen, isNot(shows('ctrl + c to try again')));
          expect(t.screen, isNot(shows(pickHint)));
          expect(recorder.writes, isEmpty);
          clock.elapse(const Duration(milliseconds: 2999));
          settled(clock, t.pump());
          expect(t.screen, shows('could not copy'));
          clock.elapse(const Duration(milliseconds: 1));
          settled(clock, t.pump());
          expect(t.screen, isNot(shows('could not copy')));
        } finally {
          t.dispose();
          settled(clock, connection.close());
        }
        expect(clock.pendingTimers, isEmpty);
      });
    });
    test(
      'recording pending code times out at bound and pending retry quits without waiting $size',
      () {
        fakeAsync((clock) {
          final t = WidgetTester();
          final connection = selectionConnection();
          final recorder = SelectionRecorder(timeout: true);
          try {
            settled(
              clock,
              t.pumpWidget(
                selectionPreview(connection, ['--pick', '--manual'], recorder),
                size: size,
              ),
            );
            settled(clock, pressBounded(t, 'ctrl+x b c'));
            clock.elapse(const Duration(milliseconds: 1199));
            settled(clock, t.pump());
            expect(t.screen, isNot(shows('could not copy')));
            clock.elapse(const Duration(milliseconds: 1));
            settled(clock, t.pump());
            expect(
              t.screen,
              shows('could not copy: the clipboard did not answer'),
            );
            expect(t.screen, isNot(shows('ctrl + c to try again')));
            settled(clock, pressBounded(t, 'ctrl+x b c ctrl+d'));
            expect(t.exitRequested, isTrue);
            expect(recorder.attempts, hasLength(2));
            expect(recorder.writes, isEmpty);
          } finally {
            t.dispose();
            settled(clock, connection.close());
          }
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );
  }
}
