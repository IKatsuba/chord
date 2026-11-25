import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/main.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('ctrl+o opens and closes the fold, keys listed, at $size', (
      t,
    ) async {
      await t.pumpWidget(const App(), size: size);
      expect(t.screen, shows('Run checks'));
      expect(t.screen, isNot(shows(r'$ dart analyze')));
      expect(t.screen, shows('Toggle tool details'));
      expect(t.screen, shows('Quit'));

      await t.press('ctrl+o');
      expect(t.screen, shows(r'$ dart analyze'));

      await t.press('ctrl+o');
      expect(t.screen, isNot(shows(r'$ dart analyze')));
    });

    testWidgets('ctrl+q asks the app to exit, at $size', (t) async {
      await t.pumpWidget(const App(), size: size);
      await t.press('ctrl+q');
      expect(t.exitRequested, isTrue);
    });
  }
}
