import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'wheel_window_test.dart' show seed;
import 'window_layout_test.dart' show launch;

void main() {
  group('tester: repeated prompt geometry transitions', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'same-batch grow clear and type cycles retain every event $size',
        (t) async {
          final connection = seed();
          addTearDown(connection.close);
          await t.pumpWidget(
            TranscriptWindow(launch: launch, connection: connection),
            size: size,
          );
          final focus = t.focusManager.primaryFocus;
          for (var cycle = 0; cycle < 25; cycle++) {
            final before = t.inputLayoutPasses;
            expect(t.host.handlePaste('界👩‍💻e\u0301\nsecond\nthird'), isTrue);
            expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
            expect(connection.app.value.draft, '界👩‍💻e\u0301\nsecond\nthird');
            final clear = t.inputLayoutPasses;
            expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isTrue);
            expect(t.inputLayoutPasses - clear, lessThanOrEqualTo(2));
            expect(connection.app.value.draft, isEmpty);
            expect(t.exitRequested, isFalse);
            expect(t.host.handleKey(const KeyEvent('x')), isTrue);
            expect(connection.app.value.draft, 'x');
            expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isTrue);
            expect(connection.app.value.draft, isEmpty);
            expect(t.focusManager.primaryFocus, same(focus));
            expect(t.exitRequested, isFalse);
          }
          await t.pump();
          expect(t.screen.buffer.cursor?.x, 4);
          expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isTrue);
          expect(connection.app.value.quitArmed, isTrue);
          expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isTrue);
          expect(t.exitRequested, isTrue);
        },
      );
    }
  });
}
