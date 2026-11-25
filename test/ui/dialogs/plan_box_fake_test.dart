// The plan box in the window, on the original's fake agent
// (tests/fixtures/fake_agent/scenarios/plans.ts), from the original's
// tests/ui/dialogs/PlanBox_test.tsx and plan_test.ts.
@Tags(['fake_agent'])
library;

import 'dart:convert';

import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/permission.dart' show countRoom;
import 'package:chord/ui/dialogs/plan.dart' show noteLines;
import 'package:chord/ui/dialogs/plan_box.dart' show PlanBox;
import 'package:chord/ui/dialogs/plan_scroll.dart' show PlanNoteScroll;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../app/window_fake_test.dart' as fixture;

Future<void> asked(WidgetTester t, StartConnection c, String scenario) async {
  await t.type(scenario);
  await t.press('enter');
  await fixture.until(
    () => c.app.value.transcript.planAsks.any((ask) => ask.answer == null),
  );
  await t.pump();
}

Future<String> answered(WidgetTester t, StartConnection c) async {
  await fixture.until(
    () => c.app.value.transcript.entries.whereType<AssistantEntry>().any(
      (entry) => entry.text.text.startsWith('Plan answer: '),
    ),
  );
  await fixture.until(() => c.app.value.transcript.turn is Idle);
  await t.pump();
  return c.app.value.transcript.entries
      .whereType<AssistantEntry>()
      .lastWhere((entry) => entry.text.text.startsWith('Plan answer: '))
      .text
      .text;
}

/// The scroll the window hands the plan box on screen.
PlanNoteScroll _noteScroll(WidgetTester t) {
  PlanNoteScroll? found;
  void visit(Element e) {
    final widget = e.widget;
    if (widget is PlanBox && widget.scroll != null) found = widget.scroll;
    e.visitChildren(visit);
  }

  visit(t.host.rootElement);
  return found ?? (throw StateError('No plan box with a scroll.'));
}

void main() {
  group('the plan box', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets("cursor's plan: the box, its plan under the call, and 1 "
          'accepts it, at $size', (t) async {
        final c = await fixture.connected(t, size);
        await asked(t, c, 'cursorplan');
        final text = t.screen.text;
        expect(text, contains('Approve Plan'));
        // The call reads as a plan, by cursor's name for it.
        if (size.height >= 40) {
          expect(text, contains('Plan(Route updates by session)'));
        }
        expect(text, contains('Waiting for your answer to the plan…'));
        expect(text, isNot(contains('esc to interrupt')));
        expect(
          text,
          contains('  Note  Tell fake what to change, sent with 2 (optional)'),
        );
        // No blank row between the status line and the box.
        final rows = t.screen.lines;
        final top = rows.indexWhere((row) => row.contains('Approve Plan'));
        expect(rows[top - 2], contains('Waiting for your answer'));
        expect(text, contains('fake has a plan. Do you want to proceed?'));
        expect(text, contains('❯ 1. Yes, accept the plan'));
        expect(text, contains('2. No, keep planning'));
        expect(text, isNot(contains('leave plan mode')));
        expect(text, contains('Note'));
        expect(
          text,
          contains('Enter to pick · 1–2 · ↑↓ to move · Esc to keep planning'),
        );
        // The plan under its call, its todos last; the call's line above it
        // scrolls out of a short window.
        expect(text, contains('☐ Run the tests'));
        if (size.height >= 40) expect(text, contains('Waiting…'));
        // The prompt gives the keys up to the box.
        await t.press('1');
        expect(await answered(t, c), 'Plan answer: {"outcome":"accepted"}');
        expect(t.screen.text, isNot(contains('Approve Plan')));
        expect(t.screen.text, contains('Accepted'));
        expect(c.app.value.draft, isEmpty);
      });

      testWidgets("grok's: ↓ ↓ and enter leave plan mode; esc keeps planning, "
          'at $size', (t) async {
        final c = await fixture.connected(t, size);
        await asked(t, c, 'grokplan');
        expect(t.screen.text, contains('3. No, and leave plan mode'));
        await t.press('down');
        await t.press('down');
        expect(t.screen.text, contains('❯ 3. No, and leave plan mode'));
        await t.press('enter');
        expect(await answered(t, c), 'Plan answer: {"outcome":"abandoned"}');
        expect(t.screen.text, contains('Left plan mode'));
        await asked(t, c, 'grokplan');
        await t.press('esc');
        expect(await answered(t, c), 'Plan answer: {"outcome":"revise"}');
        expect(t.screen.text, contains('Kept planning'));
      });

      testWidgets('the Note row: typed, digits and all, and sent with keep '
          'planning, at $size', (t) async {
        final c = await fixture.connected(t, size);
        await asked(t, c, 'cursorplan');
        await t.press('j');
        await t.press('j');
        expect(
          t.screen.text,
          contains('Enter to keep planning with this note · ↑ to the options'),
        );
        expect(
          t.screen.text,
          contains('❯ Note    Tell fake what to change, sent with 2'),
        );
        await t.type('Keep it 2 small');
        expect(t.screen.text, contains('Keep it 2 small'));
        await t.press('enter');
        expect(
          await answered(t, c),
          'Plan answer: {"outcome":"rejected","reason":"Keep it 2 small"}',
        );
        expect(t.screen.text, contains('Kept planning: Keep it 2 small'));
        await asked(t, c, 'cursorplan');
        await t.press('j');
        await t.press('j');
        await t.type('word ' * 40);
        await t.press('enter');
        await answered(t, c);
        // The status under its call is one row, cut at the edge; a short
        // window has scrolled it out under the plan.
        if (size.height < 40) return;
        final status = t.screen.lines.lastWhere(
          (row) => row.contains('Kept planning: word'),
        );
        final below = t.screen.lines[t.screen.lines.indexOf(status) + 1];
        expect(below, isNot(contains('word')));
      });

      testWidgets('a long note stays in the box, its hidden rows counted, '
          'at $size', (t) async {
        final c = await fixture.connected(t, size);
        await asked(t, c, 'cursorplan');
        await t.press('j');
        await t.press('j');
        final note = List.generate(700, (i) => 'w$i').join(' ');
        await t.type(note);
        await t.pump();
        bool shows(String text) => t.screen.lines.any((r) => r.contains(text));
        // The whole box is on screen, the prompt under it.
        expect(shows('Approve Plan'), isTrue);
        expect(shows('1. Yes, accept the plan'), isTrue);
        expect(shows('Enter to keep planning with this note'), isTrue);
        expect(shows('for shortcuts'), isTrue);
        // The note follows the cursor: its end is shown, what is above it
        // counted.
        expect(shows('w699'), isTrue);
        expect(shows('lines above'), isTrue);
        // A short window: what is hidden is counted beside the one row.
        await t.resize(Size(size.width, 16));
        await t.pump();
        await t.pump();
        expect(shows('Approve Plan'), isTrue);
        expect(shows('Enter to keep planning with this note'), isTrue);
        // The one row is the note's last, wrapped to the cells the count
        // leaves; the cursor has a row of its own after a full one.
        final width = size.width - 12;
        final whole = noteLines(note, width);
        final last = noteLines(note, width - countRoom(whole.length) - 1).last;
        final row = t.screen.lines.firstWhere((r) => r.contains('❯ Note'));
        expect(row, contains(last));
        expect(row, contains('lines above'));
        await t.press('enter');
        final heard = await answered(t, c);
        expect(heard, contains('w0 w1'));
        expect(heard, contains('w699'));
      });

      testWidgets("the Note's scroll is let go of when its plan is answered "
          'and when the window goes away, at $size', (t) async {
        final c = await fixture.connected(t, size);
        await asked(t, c, 'cursorplan');
        final first = _noteScroll(t);
        await t.press('enter');
        await answered(t, c);
        await t.pump();
        expect(first.isDisposed, isTrue);
        await asked(t, c, 'cursorplan');
        final second = _noteScroll(t);
        expect(identical(second, first), isFalse);
        await t.pumpWidget(const SizedBox(), size: size);
        expect(second.isDisposed, isTrue);
        expect(second.hasListeners, isFalse);
      });
    }
  });

  group('tester: plan note keyboard boundaries', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a one-row Note stays at its end and sends the full Unicode note at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await asked(t, c, 'grokplan');
          await t.press('down');
          await t.press('down');
          await t.press('down');
          final note = List.generate(60, (i) => 'row$i 日本語界👩‍💻é').join(' ');
          await t.paste(note);
          await t.resize(Size(size.width, 20));
          await t.pump();
          expect(t.screen.text, contains('lines above'));
          expect(t.screen.text, contains('row59'));
          await t.press('ctrl+a');
          expect(t.screen.text, contains('row59'));
          await t.type('!');
          await t.press('ctrl+e');
          await t.type('?');
          expect(t.screen.text, contains('row59'));
          await t.resize(size);
          await t.press('enter');
          expect(
            await answered(t, c),
            'Plan answer: ${jsonEncode({'outcome': 'revise', 'feedback': '$note!?'})}',
          );
          expect(c.app.value.draft, isEmpty);
        },
      );

      testWidgets(
        'Esc drops the note and a fresh empty plan gets no stale text at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await asked(t, c, 'cursorplan');
          await t.press('j');
          await t.press('j');
          await t.type('123jk keep this separate');
          await t.press('esc');
          expect(await answered(t, c), 'Plan answer: {"outcome":"rejected"}');
          expect(c.app.value.draft, isEmpty);
          await asked(t, c, 'grokplanempty');
          expect(
            t.screen.text,
            contains('fake has written no plan. Do you want to proceed?'),
          );
          expect(t.screen.text, isNot(contains('123jk keep this separate')));
          await t.press('1');
          expect(await answered(t, c), 'Plan answer: {"outcome":"approved"}');
        },
      );
    }
  });
}
