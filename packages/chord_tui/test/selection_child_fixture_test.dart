import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fixtures/selection_child.dart';
import 'widgets/selection_test.dart' show drag;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'source child fixture keeps rows and toggles copy/code eligibility $size',
      (t) async {
        await t.pumpWidget(const SelectionChildFixture(), size: size);
        final first = t.screen.lines.indexOf('first eligible');
        final last = t.screen.lines.indexOf('last eligible');
        expect(first, 3);
        expect(last, greaterThan(first + 3));
        await drag(t, Offset(0, first), Offset(12, last));
        await t.press('ctrl+s ctrl+b');
        expect(t.screen, shows(r'Snapshot: first eligible\nlast eligible'));
        expect(t.screen, shows('Visible eligible code: 0'));
        await t.press('f2');
        expect(t.screen, shows('middle included'));
        expect(t.screen.lines.indexOf('last eligible'), last);
        await t.press('ctrl+b');
        expect(t.screen, shows('Visible eligible code: 1'));
        await drag(t, Offset(0, first + 1), Offset(6, first + 1));
        await t.press('ctrl+s');
        expect(t.screen, shows('Snapshot: wrapped'));
        await t.press('f2 ctrl+s ctrl+b');
        expect(t.screen, shows('phase none'));
        expect(t.screen, shows('Visible eligible code: 0'));
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      },
    );
  }
}
