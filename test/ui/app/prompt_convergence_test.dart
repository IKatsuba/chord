import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'wheel_window_test.dart' show seed;
import 'window_layout_test.dart' show launch;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final grow in [false, true]) {
      testWidgets(
        'prompt ${grow ? '1 to N' : '2 to 1'} rows preserve same-batch clear and quit $size',
        (t) async {
          final connection = seed();
          addTearDown(connection.close);
          await t.pumpWidget(
            TranscriptWindow(launch: launch, connection: connection),
            size: size,
          );
          await t.type('one');
          if (!grow) {
            await t.press('shift+enter');
            await t.type('two');
            expect(t.screen, shows('│   two'));
          }
          final focus = t.focusManager.primaryFocus;
          expect(focus, isNotNull);
          if (grow) {
            t.host.handlePaste('\ntwo\nthree');
            expect(connection.app.value.draft, 'one\ntwo\nthree');
          }
          for (var press = 0; press < 3; press++) {
            final before = t.inputLayoutPasses;
            expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isTrue);
            expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
            expect(connection.app.value.draft, isEmpty);
            expect(t.exitRequested, press == 2);
            expect(t.focusManager.primaryFocus, same(focus));
            if (press < 2) expect(connection.app.value.quitArmed, press == 1);
          }
          await t.pump();
          final prompt = t.screen.lines.indexWhere(
            (line) => line.startsWith('╭'),
          );
          expect(t.screen.lines[prompt + 1], '│ › ${' ' * (size.width - 5)}│');
          expect(t.screen.lines[prompt + 2], '╰${'─' * (size.width - 2)}╯');
          expect(t.screen.buffer.cursor, Offset(4, prompt + 1));
          expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
        },
      );
    }
  }
}
