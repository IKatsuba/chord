import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24), Size(43, 37)]) {
    testWidgets('the site draws at $size', (t) async {
      await t.pumpWidget(const Site(), size: size);
      expect(t.screen, shows('chord'));
    });
  }
}
