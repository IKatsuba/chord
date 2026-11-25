import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fixtures/markdown_controls.dart';
import 'widgets/markdown_controls_test.dart' show cell, click;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'framework controls fixture records current complete blocks without clipboard $size',
      (t) async {
        await t.pumpWidget(const MarkdownControlsFixture(), size: size);
        expect(
          t.screen.lines.where((line) => line.contains('[copy]')),
          hasLength(1),
        );
        final focus = t.focusManager.primaryFocus;
        await click(t, cell(t, '[copy]'));
        expect(t.screen, shows(r'Copies 1: \tcopy body\n\ntail'));
        expect(t.focusManager.primaryFocus, same(focus));
        await t.press('f3');
        expect(t.screen, shows('covered border'));
        await t.press('f3 f2');
        expect(
          t.screen.lines.where((line) => line.contains('[copy]')),
          hasLength(2),
        );
        await t.press('ctrl+b ctrl+b ctrl+y');
        expect(t.screen, shows('Copies 2: quoted body'));
        await t.type('x');
        expect(t.screen, shows('draftx'));
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      },
    );
  }
}
