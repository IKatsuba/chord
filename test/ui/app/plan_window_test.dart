@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  group('live plan window', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('a running plan becomes a summary after interrupt at $size', (
        t,
      ) async {
        final connection = await fixture.connected(t, size);
        await t.type('plan');
        await t.press('enter');
        await fixture.until(
          () => connection.app.value.transcript.plan.isNotEmpty,
        );
        await t.pump();
        expect(t.screen, shows('  ⎿  ☒ Read the code'));
        expect(t.screen, isNot(shows('Plan ·')));
        await t.press('esc');
        await fixture.until(
          () => connection.app.value.transcript.turn is model.Idle,
        );
        await t.pump();
        expect(t.screen, shows('Plan · 1 of 3 done'));
        expect(t.screen, shows('☐ Run the tests'));
      });
    }
  });
  group('tester U9 independent live plans', skip: fakeAgentSkip, () {
    testWidgets('interrupt retains only its own plan and narrow draft', (
      t,
    ) async {
      final first = await fixture.connected(t, const Size(80, 24));
      final other = WidgetTester();
      addTearDown(other.dispose);
      final second = await fixture.connected(other, const Size(40, 12));
      await t.type('plan');
      await t.press('enter');
      await fixture.until(() => first.app.value.transcript.plan.isNotEmpty);
      await fixture.sent(other, second, 'text');
      await other.type('other draft');
      await t.press('esc');
      await fixture.until(() => first.app.value.transcript.turn is model.Idle);
      await t.pump();
      expect(t.screen, shows('Plan · 1 of 3 done'));
      expect(first.app.value.transcript.plan, hasLength(3));
      expect(second.app.value.transcript.plan, isEmpty);
      expect(other.screen, shows('│ › other draft'));
      await t.resize(const Size(40, 12));
      expect(t.screen, shows('☐ Run the tests'));
      await t.type('new draft');
      expect(t.screen, shows('│ › new draft'));
    });
  });
}
