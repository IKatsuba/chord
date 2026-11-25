import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show show, window;

void main() {
  group('tester CTUI-169: repeated help remains local', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      for (final exited in [false, true]) {
        testWidgets(
          'reopen survives resize and session switch, exited $exited at $size',
          (t) async {
            final w = await window(t, size, EditorTerminal());
            show(w.connection, w.child);
            if (exited) w.session.exit('scripted exit');
            await settle(t);
            for (var i = 0; i < 3; i++) {
              await t.type('/help');
              await t.press('enter');
              await settle(t);
              expect(w.connection.app.value.shortcuts.help, isTrue);
              expect(w.connection.app.value.draft, '');
              expect(w.session.turns, isEmpty);
              await t.resize(i.isEven ? const Size(40, 12) : size);
            }
            show(w.connection, mainKey);
            await t.pump();
            expect(w.connection.app.value.shortcuts.help, isTrue);
            await t.press('?');
            expect(w.connection.app.value.shortcuts.help, isFalse);
            await t.press('?');
            expect(w.connection.app.value.shortcuts.help, isTrue);
            await t.press('esc');
            expect(w.connection.app.value.shortcuts.help, isFalse);
          },
        );
      }
    }
  });
}
