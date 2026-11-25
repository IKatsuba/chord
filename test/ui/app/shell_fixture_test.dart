import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../../tool/shell.dart' show shellFixture;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'shell fixture fitting states never show a false below rule $size',
      (t) async {
        await t.pumpWidget(shellFixture(), size: size);
        for (final key in ['1', '2', '3', '4', '5', '6', '7', '8']) {
          await t.press(key);
          expect(t.screen.text, isNot(contains('line below')));
          expect(t.screen.text, isNot(contains('lines below')));
          await t.press('end');
          expect(t.screen.text, isNot(contains('line below')));
          expect(t.screen.text, isNot(contains('lines below')));
        }
        await t.press('2');
        expect(t.screen, shows('Running… (esc to stop)'));
        await t.press('esc');
        expect(t.screen, shows('Stopped by the user'));
        expect(t.screen.text, isNot(contains('line below')));
      },
    );
    testWidgets(
      'overflowing fixture scroll bindings expose real rows and return to bottom $size',
      (t) async {
        await t.pumpWidget(shellFixture(scenario: 'long'), size: size);
        expect(t.screen, shows('row 100'));
        expect(t.screen.text, isNot(contains('lines below')));
        await t.press('home');
        expect(t.screen, shows('bounded long output'));
        expect(t.screen, shows('lines below'));
        final top = t.screen.text;
        await t.press('shift+down');
        expect(t.screen.text, isNot(top));
        final step = t.screen.text;
        await t.press('pagedown');
        expect(t.screen.text, isNot(step));
        await t.press('end');
        expect(t.screen, shows('row 100'));
        expect(t.screen.text, isNot(contains('lines below')));
        await t.press('3');
        expect(t.screen, shows('(No output)'));
        expect(t.screen.text, isNot(contains('line below')));
      },
    );
  }
}
