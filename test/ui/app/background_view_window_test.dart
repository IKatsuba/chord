// The background view over the window, on the original's fake and chord's
// own server, as the original's tests/ui/background/BackgroundView_test.tsx
// and BackgroundMonitor_test.tsx have it: opened from the summary line,
// its rows with the ❯, a monitor's detail, x stopping the focused one, ←
// and esc going back.
@Tags(['fake_agent'])
library;

import 'package:chord/ui/agents/agents_view.dart' show AgentsClock;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'monitors_window_test.dart' show monitorsWindow, until;

/// The frame's lines, its border taken off.
List<String> _frame(WidgetTester t) {
  final rows = [for (final row in t.screen.lines) row.trimRight()];
  final top = rows.indexWhere(
    (row) =>
        row.startsWith('╭') &&
        rows[rows.indexOf(row) + 1].contains('Background'),
  );
  if (top < 0) return const [];
  final bottom = rows.indexWhere((row) => row.startsWith('╰'), top);
  return [
    for (final row in rows.sublist(top + 1, bottom))
      row.substring(2, row.length - 1).trimRight(),
  ];
}

void main() {
  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('opened from the summary line, ↑ ↓ move the ❯, enter opens a '
        "monitor's detail, ← goes back, x stops the focused one, esc closes "
        'at $size', (t) async {
      final connection = await monitorsWindow(t, size);
      await t.type('monitors');
      await t.press('enter');
      await until(
        t,
        () => t.screen.text.contains('Received the message from dev server'),
      );
      await t.press('down');
      await t.press('enter');
      await t.pump();
      final rows = _frame(t);
      expect(rows.first, 'Background · 2 in this session');
      expect(rows[2], startsWith('❯ dev server errors  monitor · m1  running'));
      expect(rows[3], startsWith('  CI run 4812        monitor · m2  running'));
      expect(rows.last, 'Enter for details · x to stop · Esc to close');
      // The prompt is drawn but takes no keys while the view has them.
      await t.press('down');
      await t.pump();
      expect(_frame(t)[3], startsWith('❯ CI run 4812'));
      await t.press('k');
      await t.press('enter');
      await t.pump();
      final detail = _frame(t);
      expect(detail.first, 'Background · m1, 1 of 2');
      expect(detail[2], 'dev server errors');
      expect(detail[3], startsWith('running '));
      expect(detail.last, startsWith('Enter to go to its call · ↑ ↓ for the'));
      bool event(List<String> lines) =>
          lines.any((line) => line.startsWith('← ERROR [router] POST /login'));
      if (size.height == 40) {
        expect(event(detail), isTrue);
      } else {
        // Taller than its room, it pages, a rule saying what is below.
        expect(event(detail), isFalse);
        expect(detail.any((line) => line.startsWith('── ↓ ')), isTrue);
        await t.press('pagedown');
        await t.pump();
        expect(event(_frame(t)), isTrue);
        expect(_frame(t).any((line) => line.startsWith('── ↑ ')), isTrue);
      }
      // ↓ in a detail goes to the next item's.
      await t.press('down');
      await t.pump();
      expect(_frame(t).first, 'Background · m2, 2 of 2');
      expect(_frame(t), contains('← no events yet'));
      await t.press('left');
      await t.pump();
      expect(_frame(t).first, 'Background · 2 in this session');
      expect(_frame(t)[3], startsWith('❯ CI run 4812'));
      // x stops it at once: its row leaves, the ❯ to the row above, and its
      // agent is told.
      await t.press('x');
      await until(
        t,
        () => _frame(t).length < 6 || !_frame(t).join().contains('CI run'),
      );
      expect(_frame(t)[2], startsWith('❯ dev server errors'));
      expect(connection.app.value.backgroundView, isNotNull);
      await until(
        t,
        () => t.screen.text.contains('from CI run 4812 · monitor · stopped'),
      );
      await t.press('escape');
      await t.pump();
      expect(_frame(t), isEmpty);
      expect(connection.app.value.backgroundView, isNull);
      // The list keeps the keys, on the summary line.
      expect(connection.app.value.agentsFocus, isTrue);
    }, skip: skip);
  }

  testWidgets("a quiet monitor's time counts on in the open view with nothing "
      'else drawing, and stands still once it is closed', (t) async {
    await monitorsWindow(t, const Size(120, 40));
    await t.type('monitors');
    await t.press('enter');
    await until(
      t,
      () => t.screen.text.contains('Received the message from dev server'),
    );
    await t.press('down');
    await t.press('enter');
    await t.pump();
    String ci() => _frame(t).firstWhere((row) => row.contains('CI run 4812'));
    final before = ci();
    // No key, no event: only the clock moves it.
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    await t.pump();
    expect(ci(), isNot(before));
    expect(AgentsClock.subscribers, greaterThan(0));
    await t.press('escape');
    await t.pump();
    expect(AgentsClock.subscribers, 0);
  }, skip: skip);

  group('CTUI-36 tester: view ownership and clock release', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a later permission borrows keys and the view returns unchanged at $size',
        (t) async {
          final connection = await monitorsWindow(t, size);
          await t.type('monitors');
          await t.press('enter');
          await until(
            t,
            () =>
                t.screen.text.contains('Received the message from dev server'),
          );
          await t.press('down');
          await t.press('enter');
          await t.press('down');
          await t.press('enter');
          await t.pump();
          final detail = connection.app.value.backgroundView!.detail;
          expect(detail?.id, 'm2');
          connection.conversation.send('permission');
          await until(
            t,
            () => _frame(t).isEmpty && t.screen.text.contains('Write'),
          );
          expect(connection.app.value.backgroundView?.detail, detail);
          expect(AgentsClock.subscribers, 0);
          await t.press('enter');
          await until(t, () => _frame(t).isNotEmpty);
          expect(connection.app.value.backgroundView?.detail, detail);
          expect(_frame(t).first, 'Background · m2, 2 of 2');
          expect(AgentsClock.subscribers, greaterThan(0));
          await t.pumpWidget(Text('removed'), size: size);
          await t.pump();
          expect(AgentsClock.subscribers, 0);
        },
        skip: skip,
      );

      testWidgets(
        'stopped open detail keeps its end until left, then the row leaves at $size',
        (t) async {
          final connection = await monitorsWindow(t, size);
          await t.type('monitors');
          await t.press('enter');
          await until(
            t,
            () =>
                t.screen.text.contains('Received the message from dev server'),
          );
          await t.press('down');
          await t.press('enter');
          await t.press('down');
          await t.press('enter');
          await t.press('x');
          await until(
            t,
            () => _frame(t).isNotEmpty && _frame(t).first.contains('ended'),
          );
          expect(_frame(t).first, 'Background · m2, 2 of 2 · ended');
          expect(connection.app.value.monitors, hasLength(1));
          expect(AgentsClock.subscribers, greaterThan(0));
          await t.press('left');
          await t.pump();
          expect(_frame(t).first, 'Background · 1 in this session');
          expect(_frame(t).join(), isNot(contains('CI run 4812')));
          await t.press('escape');
          await t.pump();
          expect(AgentsClock.subscribers, 0);
        },
        skip: skip,
      );
    }
  });
}
