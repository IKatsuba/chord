import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/diff.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final at = '${size.width}x${size.height}';

    testWidgets('the diff example draws and recolours at $at', (t) async {
      await t.pumpWidget(const DiffExample(), size: size);
      expect(t.screen.lines[0], ' Diff  dark');
      expect(t.screen.lines[2], ' edit');
      expect(t.screen.lines[3], 'src/greeting.ts');
      expect(t.screen.lines[4], '1 + /** Greets someone by name. */');
      expect(t.screen.styleAt(0, 4).bg, ThemeData.dark().diff.tint!.added.bg);
      expect(t.screen.lines[size.height - 1], contains('ctrl+t Theme'));

      await t.press('ctrl+t');
      expect(t.screen.styleAt(0, 4).bg, ThemeData.light().diff.tint!.added.bg);
      await t.press('ctrl+t');
      expect(t.screen.lines[0], ' Diff  untinted');
      expect(t.screen.styleAt(10, 4), ThemeData.dark().diff.added);
      await t.press('ctrl+t');
      expect(t.screen.styleAt(10, 4).fg, isNull);
    });
  }
  group('tester: Diff example keys', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('scroll, full theme cycle and quit at $size', (t) async {
        await t.pumpWidget(const DiffExample(), size: size);
        final first = t.screen.text;
        for (final down in ['down', 'shift+down', 'pagedown', 'end']) {
          await t.press('home');
          await t.press(down);
          expect(t.screen.text, isNot(first));
        }
        for (final up in ['up', 'shift+up', 'pageup']) {
          await t.press('end');
          final bottom = t.screen.text;
          await t.press(up);
          expect(t.screen.text, isNot(bottom));
        }
        await t.press('home');
        for (var i = 0; i < 4; i++) {
          await t.press('ctrl+t');
        }
        expect(t.screen.text, first);
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      });
    }
  });
}
