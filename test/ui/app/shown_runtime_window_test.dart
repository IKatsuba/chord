// CTUI-116: what reports, pickers and refusals in the window name is the
// shown agent's runtime, a picked child's rather than main's, as the
// original's `shownAgent` (src/ui/app/App.tsx); main's own when main is
// shown. The child is scripted: its runtime is a name, nothing starts.
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show show, window;

void main() {
  _testerShownRuntimeSwitches();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('the shown runtime at $size', () {
      Future<void> command(WidgetTester t, String typed) async {
        await t.type(typed);
        await t.press('enter');
        await settle(t);
      }

      testWidgets('/status names a picked child\'s runtime, then main\'s', (
        t,
      ) async {
        final w = await window(
          t,
          size,
          EditorTerminal(),
          childRuntime: 'codex',
        );
        show(w.connection, w.child);
        await t.pump();
        await command(t, '/status');
        expect(t.screen, shows('Agent:     codex'));
        expect(t.screen.text, isNot(contains('Agent:     fake')));
      });

      testWidgets('/status on main names main\'s runtime', (t) async {
        await window(t, size, EditorTerminal(), childRuntime: 'codex');
        await command(t, '/status');
        expect(t.screen, shows('Agent:     fake'));
      });

      testWidgets('/effort with none offered names the child\'s runtime', (
        t,
      ) async {
        final w = await window(
          t,
          size,
          EditorTerminal(),
          childRuntime: 'codex',
        );
        show(w.connection, w.child);
        await t.pump();
        await command(t, '/effort');
        expect(t.screen, shows('codex offers no effort'));
        expect(t.screen.text, isNot(contains('fake offers no effort')));
      });
    });
  }
}

void _testerShownRuntimeSwitches() {
  group('tester CTUI-116: runtime survives focus and resize', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('child reports stay with the picked session at $size', (
        t,
      ) async {
        final w = await window(
          t,
          size,
          EditorTerminal(),
          childRuntime: 'codex',
        );
        Future<void> command(String text) async {
          await t.type(text);
          await t.press('enter');
          await settle(t);
        }

        show(w.connection, w.child);
        await t.pump();
        await command('/status');
        expect(t.screen, shows('Agent:     codex'));
        await t.resize(
          size == const Size(120, 40)
              ? const Size(80, 24)
              : const Size(120, 40),
        );
        expect(t.screen, shows('Agent:     codex'));
        show(w.connection, mainKey);
        await t.pump();
        await command('/status');
        expect(t.screen, shows('Agent:     fake'));
        expect(t.screen, isNot(shows('Agent:     codex')));
        show(w.connection, w.child);
        await t.pump();
        expect(t.screen, shows('Agent:     codex'));
        expect(t.screen, isNot(shows('Agent:     fake')));
        await command('/effort');
        expect(t.screen, shows('codex offers no effort'));
      });
    }
  });
}
