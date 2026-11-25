// The background's summary line under the agents list, on the original's
// fake and chord's own server, as the original's
// tests/ui/agents/Monitors_test.tsx and tests/ui/background/Background_test.tsx
// have it: counted by state, the list's last stop, its own hint.
@Tags(['fake_agent'])
library;

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'monitors_window_test.dart' show monitorsWindow, until;

List<String> _rows(WidgetTester t) => [
  for (final row in t.screen.lines) row.trimRight(),
];

void main() {
  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the running monitors are counted under the prompt; ↓ from an '
        'empty draft puts the ❯ on the line, its hint said, x stopping '
        'nothing, ↑ and esc going back at $size', (t) async {
      final connection = await monitorsWindow(t, size);
      await t.type('monitors');
      await t.press('enter');
      await until(
        t,
        () => _rows(t).contains('    background  2 monitors running'),
      );
      // The last line of the window, dim, with no agent rows.
      expect(_rows(t).last, '    background  2 monitors running');
      expect(t.screen.text, isNot(contains('    main ')));
      final last = size.height - 1;
      expect(t.screen.styleAt(4, last).isDim, isTrue);

      await t.press('down');
      await t.pump();
      expect(_rows(t).last, '  ❯ background  2 monitors running');
      expect(t.screen.styleAt(4, last).isBold, isTrue);
      expect(
        _rows(t)[size.height - 2],
        startsWith(
          size.width == 120
              ? '  ↑ ↓ to move · enter to open · esc to go back'
              : '  ↑ ↓ move · enter open · esc back',
        ),
      );
      // The summary line is no item: x stops nothing, the list keeps the keys.
      await t.press('x');
      await t.pump();
      expect(_rows(t).last, '  ❯ background  2 monitors running');
      expect(connection.app.value.agentsFocus, isTrue);
      // With no agents drawn it is the one stop: ↓ stays, ↑ goes back.
      await t.press('down');
      await t.pump();
      expect(_rows(t).last, '  ❯ background  2 monitors running');
      await t.press('up');
      await t.pump();
      expect(_rows(t).last, '    background  2 monitors running');
      expect(connection.app.value.agentsFocus, isFalse);
      await t.press('down');
      await t.press('escape');
      await t.pump();
      expect(connection.app.value.agentsFocus, isFalse);
    }, skip: skip);
  }

  group('CTUI-36 tester: disappearing summary', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'the last stopped monitor returns keys to the prompt at $size',
        (t) async {
          final connection = await monitorsWindow(t, size);
          await t.type('monitors');
          await t.press('enter');
          await until(t, () => connection.app.value.monitors.length == 2);
          await t.press('down');
          await t.pump();
          expect(connection.app.value.agentsFocus, isTrue);
          connection.conversation.stopMonitor('m1');
          connection.conversation.stopMonitor('m2');
          await until(t, () => !connection.app.value.agentsFocus);
          expect(t.screen.text, isNot(contains('background')));
          await t.type('draft restored');
          await t.pump();
          expect(connection.app.value.draft, 'draft restored');
        },
        skip: skip,
      );
    }
  });
}
