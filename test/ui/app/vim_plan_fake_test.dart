// Vim mode leaves the keys to a plan's answer, as the original's
// listHasKeys does, on the original's fake agent's plan scenarios.
@Tags(['fake_agent'])
library;

import 'package:chord/ui/app/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../dialogs/plan_box_fake_test.dart' show asked;
import 'window_fake_test.dart' as fixture;

void main() {
  group('vim mode under a plan', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('normal mode keys and Esc are the plan\'s, the draft and '
          'the mode left alone, at $size', (t) async {
        final c = await fixture.connected(t, size);
        await t.type('/vim');
        await t.press('enter');
        await t.pump();
        await asked(t, c, 'cursorplan');
        c.app.value = reduceWindow(
          c.app.value,
          const VimChangedAction(VimState(mode: VimMode.normal)),
        );
        await t.pump();
        await t.press('j');
        await t.press('j');
        await t.type('xh');
        expect(t.screen.text, contains('xh'));
        expect(c.app.value.draft, '');
        expect(c.app.value.vim?.mode, VimMode.normal);
        expect(c.app.value.vim?.pending, isEmpty);
      });

      testWidgets('insert mode Esc keeps planning rather than leave insert '
          'mode, at $size', (t) async {
        final c = await fixture.connected(t, size);
        await t.type('/vim');
        await t.press('enter');
        await t.pump();
        await asked(t, c, 'grokplan');
        await t.press('esc');
        await fixture.until(
          () => c.app.value.transcript.planAsks.every((a) => a.answer != null),
        );
        await t.pump();
        expect(c.app.value.vim?.mode, VimMode.insert);
        expect(t.screen.text, contains('Kept planning'));
      });
    }
  });
}
