import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fixtures/key_capture.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('capture fixture action, passthrough and empty paste $size', (
      t,
    ) async {
      await t.pumpWidget(const KeyCaptureFixture(), size: size);
      await t.type('vc');
      expect(t.screen.text, contains('actions 1'));
      expect(t.screen.text, contains('Type here'));
      await t.type('x');
      await t.press('f2');
      await t.type('vc');
      expect(t.screen.text, contains('xvc'));
      expect(t.screen.text, contains('disabled'));
      await t.paste('');
      expect(t.screen.text, contains('pastes 1'));
      await t.press('ctrl+q');
      expect(t.exitRequested, isTrue);
    });
  }
}
