import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/text_area_spans.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets(
      'public span fixture toggles paint and theme with stable viewport $size',
      (t) async {
        await t.pumpWidget(const TextAreaSpansExample(), size: size);
        final screen = List.of(t.screen.lines), cursor = t.screen.buffer.cursor;
        expect(t.screen, shows('ctrl+g Toggle decoration'));
        expect(t.screen, shows('ctrl+t Toggle theme'));
        expect(t.screen, shows('ctrl+q Quit'));
        var inverse = 0;
        for (var y = 0; y < 6; y++) {
          for (var x = 2; x < size.width; x++) {
            if (t.screen.styleAt(x, y).isInverse) inverse++;
          }
        }
        expect(inverse, 14);
        await t.press('ctrl+g');
        expect(t.screen.lines, screen);
        expect(t.screen.buffer.cursor, cursor);
        expect(t.screen.styleAt(70, 0).isInverse, isFalse);
        await t.press('ctrl+t');
        expect(t.screen.lines, screen);
        expect(t.screen.buffer.cursor, cursor);
        await t.press('ctrl+g');
        expect(t.screen.lines, screen);
        expect(t.screen.buffer.cursor, cursor);
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      },
    );
  }
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('public span fixture zero room reports zero rows $size', (
      t,
    ) async {
      await t.pumpWidget(const TextAreaSpansExample(zero: true), size: size);
      expect(
        t.screen,
        shows(size.width == 120 ? 'rows 0 of 2' : 'rows 0 of 3'),
      );
      expect(t.screen, isNot(shows('Context')));
      expect(t.screen.buffer.cursor, isNull);
      await t.press('ctrl+g ctrl+t ctrl+q');
      expect(t.exitRequested, isTrue);
    });
  }
}
