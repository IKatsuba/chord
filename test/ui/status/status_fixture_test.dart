import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/status.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('status fixture cycles modes with Ctrl+G at $size', (t) async {
      await t.pumpWidget(const StatusFixture(), size: size);
      expect(t.screen, shows('⏸ plan mode on'));
      await t.press('ctrl+g');
      expect(t.screen, shows('⏵⏵ accept edits on'));
      await t.press('ctrl+g');
      expect(t.screen, shows('⏵⏵ auto mode on'));
      await t.press('ctrl+t');
      expect(t.screen, shows('Interrupting…'));
      await t.press('ctrl+q');
      expect(t.exitRequested, isTrue);
    });
  }
}
