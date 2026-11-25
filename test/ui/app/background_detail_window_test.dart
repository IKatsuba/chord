// A task's detail in the background view, its work followed as a log, and
// Enter in a detail going to the call that started its item, on the
// original's fake and chord's own server, as the original's
// tests/ui/background/BackgroundDetail_test.tsx and BackgroundView_test.tsx
// have them; the transcript scrolls to the entry that draws the call
// (decisions: the entry's top, not a row inside it).
@Tags(['fake_agent'])
library;

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'monitors_window_test.dart' show monitorsWindow, until;

/// The frame's lines, its border taken off.
List<String> _frame(WidgetTester t) {
  final rows = [for (final row in t.screen.lines) row.trimRight()];
  for (var i = 0; i + 1 < rows.length; i++) {
    if (rows[i].startsWith('╭') && rows[i + 1].contains('Background')) {
      final bottom = rows.indexWhere((row) => row.startsWith('╰'), i);
      return [
        for (final row in rows.sublist(i + 1, bottom))
          row.substring(2, row.length - 1).trimRight(),
      ];
    }
  }
  return const [];
}

void main() {
  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("a task's detail pins its name and state, then follows its "
        'task and work; Enter goes to its Agent block at $size', (t) async {
      final connection = await monitorsWindow(t, size);
      await t.type('tasklong');
      await t.press('enter');
      await until(
        t,
        () => t.screen.text.contains('The build is being watched'),
      );
      await t.press('down');
      await t.press('enter');
      await t.press('enter');
      await until(
        t,
        () => _frame(t).any((line) => line.contains('Watching the build.')),
      );
      final detail = _frame(t);
      expect(detail.first, 'Background · 1 of 1');
      expect(detail[2], 'Watch the build');
      expect(detail[3], startsWith('working '));
      expect(detail[3], contains('tool uses · task · fake'));
      expect(detail[4], '› taskwait');
      // As tall as its lines: the hint under them after one gap.
      final at = detail.indexWhere((l) => l.contains('Watching the build.'));
      expect(detail[at + 1], '');
      expect(detail[at + 2], startsWith('Enter to go to its call'));

      await t.press('enter');
      await t.pump();
      await t.pump();
      expect(_frame(t), isEmpty);
      expect(connection.app.value.backgroundView, isNull);
      expect(connection.app.value.agentsFocus, isFalse);
      // Its Agent block in sight; all of this transcript fits, so nothing
      // scrolls.
      expect(t.screen, shows('⏺ Agent(Watch the build) · fake'));
    }, skip: skip);
  }

  testWidgets("a monitor's detail goes to its Monitor call, scrolling the "
      'transcript back to it', (t) async {
    await monitorsWindow(t, const Size(80, 24));
    await t.type('monitors');
    await t.press('enter');
    await until(
      t,
      () => t.screen.text.contains('Received the message from dev server'),
    );
    // The transcript read from its top, its header there.
    await t.press('home');
    await t.pump();
    expect(t.screen.lines.first, contains('chord v'));
    await t.press('down');
    await t.press('enter');
    await t.press('enter');
    await t.pump();
    expect(_frame(t).first, 'Background · m1, 1 of 2');
    await t.press('enter');
    await t.pump();
    await t.pump();
    expect(_frame(t), isEmpty);
    expect(t.screen.lines.first.trimRight(), ' ⏺ Monitor(dev server errors)');
    // Held there: the rule says what is below, and the last message is
    // under it, as the original lands.
    expect(t.screen, shows('── ↓ 1 line below · end to jump to the bottom'));
    expect(t.screen, isNot(shows('Received the message from dev server')));
  }, skip: skip);

  group('CTUI-36 tester: task detail over real fake permission', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a later permission hides and restores the same task detail at $size',
        (t) async {
          final connection = await monitorsWindow(t, size);
          await t.type('tasklong');
          await t.press('enter');
          await until(
            t,
            () => t.screen.text.contains('The build is being watched'),
          );
          await t.press('down');
          await t.press('enter');
          await t.press('enter');
          await until(
            t,
            () => _frame(t).any((l) => l.contains('Watching the build.')),
          );
          final detail = connection.app.value.backgroundView!.detail;
          connection.conversation.send('permission');
          await until(
            t,
            () => _frame(t).isEmpty && t.screen.text.contains('Write'),
          );
          expect(connection.app.value.backgroundView?.detail, detail);
          await t.press('enter');
          await until(
            t,
            () => _frame(t).any((l) => l.contains('Watching the build.')),
          );
          expect(connection.app.value.backgroundView?.detail, detail);
          expect(_frame(t), contains('Watch the build'));
          await t.press('escape');
          await t.press('escape');
          await t.pump();
          expect(connection.app.value.backgroundView, isNull);
        },
        skip: skip,
      );
    }
  });
}
