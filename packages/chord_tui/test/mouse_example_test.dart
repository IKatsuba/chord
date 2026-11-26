import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/mouse.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('one report one event, one row and unchanged draft at $size', (
      t,
    ) async {
      await t.pumpWidget(const MouseExample(), size: size);
      final focus = t.focusManager.primaryFocus;
      expect(t.screen.lines[2], 'Sample log row 5');
      await t.type(' +typed');
      final before = t.screen.lines[2];
      await t.mouse(
        const MouseEvent(
          MouseEventKind.wheel,
          position: Offset(0, 0),
          scrollDelta: Offset(0, -1),
        ),
      );
      expect(t.screen, shows('reports: 1'));
      expect(t.screen, shows('delta (0,-1)'));
      expect(t.screen.lines[2], 'Sample log row 4');
      await t.mouse(
        MouseEvent(
          MouseEventKind.wheel,
          position: Offset(1, size.height - 6),
          scrollDelta: const Offset(0, 1),
        ),
      );
      expect(t.screen, shows('reports: 2'));
      expect(t.screen.lines[2], before);
      await t.mouse(
        const MouseEvent(
          MouseEventKind.press,
          position: Offset(0, 2),
          button: MouseButton.primary,
        ),
      );
      await t.mouse(
        MouseEvent(
          MouseEventKind.release,
          position: Offset(0, size.height - 1),
          button: MouseButton.primary,
        ),
      );
      expect(t.screen, shows('reports: 4'));
      expect(t.screen, shows('draft stays here +typed'));
      expect(t.focusManager.primaryFocus, same(focus));
      await t.press('shift+up');
      expect(t.screen.lines[2], 'Sample log row 4');
      expect(t.screen, shows('reports: 4'));
      await t.press('ctrl+l');
      expect(t.screen, shows('reports: 0'));
      expect(t.screen, shows('draft stays here +typed'));
      for (final key in ['shift+up', 'shift+down', 'ctrl+l', 'ctrl+q']) {
        expect(t.screen, shows(key));
      }
    });
    testWidgets(
      'public capture demo logs held motion outside bounds at $size',
      (t) async {
        await t.pumpWidget(const MouseExample(), size: size);
        await t.mouse(
          const MouseEvent(
            MouseEventKind.press,
            position: Offset(0, 2),
            button: MouseButton.primary,
          ),
        );
        await t.mouse(
          MouseEvent(
            MouseEventKind.move,
            position: Offset(size.width + 2, size.height + 2),
            button: MouseButton.primary,
          ),
        );
        expect(
          t.screen,
          shows('move at (${size.width + 2},${size.height + 2})'),
        );
        await t.mouse(
          MouseEvent(
            MouseEventKind.release,
            position: Offset(size.width + 2, size.height + 2),
            button: MouseButton.primary,
          ),
        );
        expect(
          t.screen,
          shows('release at (${size.width + 2},${size.height + 2})'),
        );
        expect(t.screen, shows('reports: 3'));
        expect(t.screen, shows('draft stays here'));
      },
    );
    testWidgets('a merged report scrolls by its size at $size', (t) async {
      await t.pumpWidget(const MouseExample(), size: size);
      expect(t.screen.lines[2], 'Sample log row 5');
      await t.mouse(
        const MouseEvent(
          MouseEventKind.wheel,
          position: Offset(0, 0),
          scrollDelta: Offset(0, -3),
        ),
      );
      expect(t.screen, shows('reports: 1'));
      expect(t.screen.lines[2], 'Sample log row 2');
      await t.mouse(
        const MouseEvent(
          MouseEventKind.wheel,
          position: Offset(0, 0),
          scrollDelta: Offset(0, 2),
        ),
      );
      expect(t.screen.lines[2], 'Sample log row 4');
    });
  }
}
