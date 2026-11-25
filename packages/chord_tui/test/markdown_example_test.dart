import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/markdown.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final at = '${size.width}x${size.height}';

    testWidgets('the markdown example draws, streams and recolours at $at', (
      t,
    ) async {
      await t.pumpWidget(const MarkdownExample(), size: size);
      expect(t.screen.lines[0], ' Markdown  dark, 100%');
      expect(t.screen.lines[1], 'Terminal cells');
      expect(t.screen.lines[size.height - 1], contains('ctrl+s Stream again'));

      await t.press('ctrl+s');
      expect(t.screen.lines[0], ' Markdown  dark, 0%');
      await t.pump(const Duration(milliseconds: 120));
      expect(t.screen.lines[0], isNot(' Markdown  dark, 0%'));

      await t.press('ctrl+t');
      expect(t.screen.lines[0], startsWith(' Markdown  light'));
      expect(t.screen.styleAt(1, 0), ThemeData.light().accent);
    });
  }
  group('tester: Markdown example lifecycle and keys', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('all scroll keys, theme cycle and quit at $size', (t) async {
        await t.pumpWidget(const MarkdownExample(), size: size);
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
        for (var i = 0; i < 3; i++) {
          await t.press('ctrl+t');
        }
        expect(t.screen.text, first);
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      });
    }
    testWidgets('removal cancels an active streaming timer', (t) async {
      await t.pumpWidget(const MarkdownExample());
      await t.press('ctrl+s');
      await t.pumpWidget(Text('replacement'));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.screen.text, 'replacement');
    });
  });
}
