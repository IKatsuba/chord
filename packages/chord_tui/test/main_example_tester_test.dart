import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/main.dart';

void main() {
  group('tester: package example lifecycle', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('tiny resizes retain the fold state at $size', (t) async {
        await t.pumpWidget(const App(), size: size);
        await t.press('ctrl+o');
        for (final small in const [Size.zero, Size(1, 1)]) {
          await t.resize(small);
          await t.resize(size);
          expect(t.screen, shows(r'$ dart analyze'));
          await t.resize(small);
          await t.press('ctrl+o');
          await t.resize(size);
          expect(t.screen, isNot(shows(r'$ dart analyze')));
          await t.press('ctrl+o');
        }
      });

      testWidgets(
        'removal releases actions and remount starts closed at $size',
        (t) async {
          await t.pumpWidget(const App(), size: size);
          await t.press('ctrl+o');
          await t.pumpWidget(const SizedBox(), size: size);
          await t.press('ctrl+o');
          await t.press('ctrl+q');
          expect(t.exitRequested, isFalse);
          await t.pumpWidget(const App(), size: size);
          expect(t.screen, isNot(shows(r'$ dart analyze')));
          await t.press('ctrl+o');
          expect(t.screen, shows(r'$ dart analyze'));
          await t.press('ctrl+q');
          expect(t.exitRequested, isTrue);
        },
      );
    }
  });
}
