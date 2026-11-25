// `/help` opens the shortcuts panel and leaves an open one open, as the
// original's `help_opened` does (src/ui/shortcuts/state.ts); `?` toggles.
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show show, window;

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('/help sent while the panel is open leaves it open, at '
        '$size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final app = w.connection.app;
      show(w.connection, w.child);
      await t.pump();
      await t.press('?');
      await t.pump();
      expect(app.value.shortcuts.help, isTrue);
      await t.type('/help');
      await settle(t);
      await t.press('enter');
      await t.pump();
      expect(app.value.draft, '');
      expect(app.value.shortcuts.help, isTrue);
    });
  }
}
