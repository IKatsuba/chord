import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../example/overlay_visibility.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'public visibility gate retains focus and never defers hidden Tab at $size',
      (t) async {
        await t.pumpWidget(const OverlayVisibilityExample(), size: size);
        final focus = t.focusManager.primaryFocus;
        for (final label in [
          'tab Complete visible word',
          'ctrl+r Reset draft',
          'ctrl+q Quit',
        ]) {
          expect(t.screen, shows(label));
        }
        await t.press('tab');
        expect(t.screen, shows('Last Tab: completed'));
        expect(t.screen, shows('Draft: status'));
        await t.press('ctrl+r');
        await t.resize(const Size(80, 5));
        await t.press('tab');
        expect(t.screen, shows('Last Tab: ignored'));
        expect(t.screen, shows('Draft: sta'));
        expect(t.focusManager.primaryFocus, same(focus));
        await t.resize(size);
        expect(t.screen, shows('Draft: sta'));
        await t.type('y');
        expect(t.screen, shows('Draft: stay'));
      },
    );
  }
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'passive geometry fixture retains underlying row and current Tab $size',
      (t) async {
        await t.pumpWidget(
          const OverlayVisibilityExample(passive: true),
          size: size,
        );
        final focus = t.focusManager.primaryFocus;
        expect(t.screen.lines[size.height - 6], startsWith('Transcript row'));
        await t.press('tab');
        expect(t.screen, shows('Last Tab: completed'));
        expect(t.focusManager.primaryFocus, same(focus));
        await t.resize(Size(size.width, 5));
        await t.press('ctrl+r tab');
        expect(t.screen, shows('Last Tab: ignored'));
        await t.resize(size);
        expect(t.screen, shows('Draft: sta'));
      },
    );
  }
}
