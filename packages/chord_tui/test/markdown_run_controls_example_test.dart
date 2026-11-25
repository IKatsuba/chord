import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../example/markdown_run_controls.dart' show MarkdownRunControlsDemo;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('every demo run target has a described key $size', (t) async {
      await t.pumpWidget(const MarkdownRunControlsDemo(), size: size);
      for (final binding in t.focusManager.activeBindings) {
        expect(t.screen, shows(binding.description));
      }
      await t.press('shift+r');
      expect(t.screen, shows('Run only: run only'));
      await t.press('r');
      expect(t.screen, shows('Run: x'));
      await t.press('c');
      expect(t.screen, shows('Copy: x'));
      expect(
        t.focusManager.activeBindings.map((b) => b.description),
        contains('Record run-only action'),
      );
    });
  }
}
