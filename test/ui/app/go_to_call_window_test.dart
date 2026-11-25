// CTUI-85: Enter in a task's background detail puts the call's own box on
// the transcript's top line, as the original's jump does (layout.ts rowOf):
// a task further down a group of tasks lands on its own row, not on the
// group's. On the original's fake through TestRuntimes, whose children run
// on the fake alone.
@Tags(['fake_agent'])
library;

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'monitors_window_test.dart' show monitorsWindow, until;

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    for (final (at, name) in [
      (0, 'Watch the build'),
      (1, 'Watch the deploy'),
    ]) {
      testWidgets("a task's detail goes to its own row in the group, task "
          '${at + 1} of 2, at $size', (t) async {
        await monitorsWindow(t, size);
        await t.type('tasktwo');
        await t.press('enter');
        await until(
          t,
          () => t.screen.text.contains(
            'The build and the deploy are being watched.',
          ),
        );
        // Replies under the group, so the transcript has room to scroll.
        for (var i = 0; i < 8; i++) {
          final before = t.screen.text;
          await t.type('text');
          await t.press('enter');
          await until(t, () => t.screen.text != before);
          await until(t, () => !t.screen.text.contains('esc to interrupt'));
        }
        await t.press('home');
        await t.pump();
        await t.press('down');
        await t.press('enter');
        for (var i = 0; i < at; i++) {
          await t.press('down');
        }
        await t.press('enter');
        await t.pump();
        await t.press('enter');
        await t.pump();
        await t.pump();
        final top = t.screen.lines.first;
        expect(top, contains(name), reason: t.screen.text);
        expect(top, contains(at == 0 ? '├─' : '└─'), reason: t.screen.text);
      }, skip: fakeAgentSkip);
    }
  }
}
