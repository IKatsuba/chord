import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show show, window;

void main() {
  group('tester CTUI-179: command history session ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      for (final ending in ['hanging', 'late after cancel', 'exited']) {
        testWidgets('kept drafts stay owned with $ending agent at $size', (
          t,
        ) async {
          final w = await window(t, size, EditorTerminal());
          final fold = w.connection.fold;
          await t.type('main draft');
          await t.press('super+down');
          show(w.connection, w.child);
          await t.pump();
          await t.type('sent prompt');
          await t.press('enter');
          await settle(t);
          expect(w.session.turns.single.text, 'sent prompt');
          if (ending == 'late after cancel') {
            await t.press('esc');
            await settle(t);
            expect(w.session.cancels, 1);
          }
          await t.type('界🙂e\u0301 child draft');
          await t.press('super+down');
          expect(fold.app.value.draft, '');
          if (ending == 'late after cancel') {
            w.session.turns.single.answer();
          } else if (ending == 'exited') {
            w.session.exit('scripted exit');
          }
          await settle(t);
          await t.resize(
            size.width == 120 ? const Size(80, 24) : const Size(120, 40),
          );
          await t.press('super+up');
          expect(fold.app.value.draft, '界🙂e\u0301 child draft');
          expect(t.screen, shows('界🙂e\u0301 child draft'));
          show(w.connection, mainKey);
          await t.pump();
          await t.press('super+up');
          expect(fold.app.value.draft, 'main draft');
          expect(fold.stateOf(w.child)!.draft, '界🙂e\u0301 child draft');
          show(w.connection, w.child);
          await t.pump();
          await t.press('super+up');
          expect(fold.app.value.draft, 'sent prompt');
        });
      }
    }
  });
}
