import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../example/picker_preview.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('highlight preview precedes acceptance at $size', (t) async {
      await t.pumpWidget(const PickerPreviewExample(), size: size);
      expect(t.screen, shows('Highlighted: Choice 1'));
      await t.press('down');
      expect(t.screen, shows('Highlighted: Choice 2'));
      expect(t.screen, shows('Accepted: Nothing yet'));
      await t.press('enter');
      expect(t.screen, shows('Accepted: Choice 2'));
    });
  }
}
