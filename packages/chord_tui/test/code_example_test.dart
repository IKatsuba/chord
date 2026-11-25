import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/code.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final at = '${size.width}x${size.height}';

    testWidgets('the code example numbers, wraps and recolours at $at', (
      t,
    ) async {
      await t.pumpWidget(const CodeExample(), size: size);
      expect(t.screen.lines[0], ' Code  dark, numbers on, wrap on');
      expect(t.screen.lines[2], ' dart');
      expect(t.screen.lines[3], '1   void main() {');
      expect(t.screen.styleAt(4, 3), ThemeData.dark().code!.terminal.keyword);
      expect(t.screen.lines[size.height - 1], contains('ctrl+n Line numbers'));

      await t.press('ctrl+n');
      expect(t.screen.lines[3], '  void main() {');
      await t.press('ctrl+w');
      expect(t.screen.lines[3], 'void main() {');
      expect(t.screen.lines[0], ' Code  dark, numbers off, wrap off');
      await t.press('ctrl+t');
      expect(t.screen.styleAt(0, 3), ThemeData.light().code!.terminal.keyword);
      await t.press('ctrl+t');
      expect(t.screen.styleAt(0, 3).fg, isNull);
    });
  }
  group('tester: example keyboard navigation', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('scroll keys, toggles and quit work at $size', (t) async {
        await t.pumpWidget(const CodeExample(), size: size);
        final first = t.screen.text;
        await t.press('end');
        expect(t.screen.text, contains('spaces kept, 12 cells wide'));
        await t.press('home');
        expect(t.screen.text, first);
        for (final down in ['down', 'shift+down', 'pagedown']) {
          await t.press(down);
          expect(t.screen.text, isNot(first));
          await t.press('home');
        }
        for (final up in ['up', 'shift+up', 'pageup']) {
          await t.press('end');
          final bottom = t.screen.text;
          await t.press(up);
          expect(t.screen.text, isNot(bottom));
        }
        await t.press('home');
        for (final key in ['ctrl+n', 'ctrl+w']) {
          await t.press(key);
          await t.press(key);
        }
        for (var i = 0; i < 3; i++) {
          await t.press('ctrl+t');
        }
        expect(t.screen.text, first);
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      });
    }
  });
}
