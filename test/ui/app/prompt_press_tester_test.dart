import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal;
import 'front_routing_test.dart' show show, window;

void main() {
  group('tester CTUI-171: prompt border presses', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      for (final point in [
        'top left',
        'top right',
        'left',
        'right',
        'bottom',
        'gutter',
      ]) {
        final namedTop = point.startsWith('top');
        testWidgets(
          '$point ${namedTop ? 'keeps list keys' : 'returns prompt keys'} at $size',
          (t) async {
            final w = await window(t, size, EditorTerminal());
            final fold = w.connection.fold;
            show(w.connection, w.child);
            fold.app.value = reduceWindow(
              fold.app.value,
              const AgentsFocusedAction(true),
            );
            await t.pump();
            expect(fold.app.value.agentsFocus, isTrue);
            final top = t.screen.lines.lastIndexWhere(
              (line) => line.startsWith('╭'),
            );
            final bottom = t.screen.lines.lastIndexWhere(
              (line) => line.startsWith('╰'),
            );
            expect(top, greaterThanOrEqualTo(0));
            final position = switch (point) {
              'top left' => Offset(0, top),
              'top right' => Offset(size.width - 1, top),
              'left' => Offset(0, top + 1),
              'right' => Offset(size.width - 1, top + 1),
              'bottom' => Offset(4, bottom),
              _ => Offset(2, top + 1),
            };
            await t.mouse(
              MouseEvent(
                MouseEventKind.release,
                position: position,
                button: MouseButton.primary,
              ),
            );
            expect(fold.app.value.agentsFocus, isTrue);
            await t.mouse(
              MouseEvent(
                MouseEventKind.press,
                position: position,
                button: MouseButton.primary,
              ),
            );
            await t.mouse(
              MouseEvent(
                MouseEventKind.release,
                position: position,
                button: MouseButton.primary,
              ),
            );
            await t.pump();
            if (namedTop) {
              // The original draws NamedTop outside the box's mouse handler.
              expect(fold.app.value.agentsFocus, isTrue);
              await t.type('q');
              expect(fold.stateOf(w.child)!.draft, '');
              await t.press('enter');
            }
            expect(fold.app.value.agentsFocus, isFalse);
            expect(fold.front, w.child);
            await t.type('界🙂e\u0301');
            expect(fold.stateOf(w.child)!.draft, '界🙂e\u0301');
            expect(fold.stateOf(mainKey)!.draft, '');
            await t.resize(
              size.width == 120 ? const Size(80, 24) : const Size(120, 40),
            );
            await t.type('X');
            expect(fold.stateOf(w.child)!.draft, '界🙂e\u0301X');
          },
        );
      }
    }
  });
}
