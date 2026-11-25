import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fixtures/selection_area.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'selection runtime fixture exposes public queries and keys $size',
      (t) async {
        await t.pumpWidget(const SelectionAreaFixture(), size: size);
        expect(t.screen.text, contains('Selection area'));
        expect(t.screen.text, contains('held: false · following: true'));
        await t.press('f2');
        expect(t.screen.text, contains('Record 12'));
        await t.press('ctrl+r');
        expect(t.screen.text, contains('Reveal last: true'));
        await t.press('ctrl+b');
        expect(t.screen.text, contains('Code snapshot:'));
        await t.press('ctrl+o');
        expect(t.screen.text, contains('Known overlay'));
        await t.press('ctrl+u');
        await t.press('ctrl+s');
        expect(t.screen.text, contains('Snapshot unresolved'));
        await t.press('ctrl+u');
        await t.press('ctrl+t');
        await t.press('ctrl+t');
        await t.press('ctrl+s');
        expect(t.screen.text, contains('none:'));
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      },
    );
  }
}
