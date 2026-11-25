// The plan Note's scroller in the window, on the fake agent, from the
// original's tests/ui/dialogs/PlanBox_test.tsx (CHD-437): a Note taller
// than its room pages from the Note, the choices page the transcript, and
// typing brings the view back to the cursor.
@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../app/window_fake_test.dart' as fixture;
import 'plan_box_fake_test.dart' show answered, asked;

/// The box, from its title to the prompt under it.
String box(WidgetTester t) {
  final text = t.screen.lines.join('\n');
  return text.substring(text.indexOf('Approve Plan'));
}

/// The transcript above the box.
String above(WidgetTester t) {
  final text = t.screen.lines.join('\n');
  return text.substring(0, text.indexOf('Approve Plan'));
}

void main() {
  group('the plan Note pages', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('from the Note alone; the choices page the transcript; '
          'typing follows the cursor at $size', (t) async {
        final c = await fixture.connected(t, size);
        await t.type('steps');
        await t.press('enter');
        await fixture.until(() => c.app.value.transcript.turn is Idle);
        await t.pump();
        await asked(t, c, 'cursorplan');
        final before = box(t);
        // On a choice, the page keys are the transcript's.
        await t.press('pageup');
        await t.pump();
        expect(above(t), contains('lines below'));
        expect(box(t), before);
        await t.press('pagedown');
        await t.pump();
        expect(above(t), isNot(contains('lines below')));
        await t.press('down');
        await t.press('down');
        final note = List.generate(
          160,
          (i) => 'row$i stays unchanged',
        ).join(' ');
        await t.paste(note);
        await t.pump();
        expect(box(t), contains('row159'));
        expect(box(t), contains('lines above · pageup to scroll'));
        final transcript = above(t);
        for (var page = 0; page < 60 && !box(t).contains('row0 '); page++) {
          await t.press('pageup');
          await t.pump();
        }
        expect(box(t), contains('Note  row0 stays unchanged'));
        expect(box(t), contains('lines below · pagedown to scroll'));
        expect(box(t), isNot(contains('lines above')));
        // The transcript stayed where it was.
        expect(above(t), transcript);
        // Back down a page, and typing brings the view to the cursor.
        await t.press('pagedown');
        await t.pump();
        expect(box(t), isNot(contains('Note  row0 ')));
        expect(box(t), contains('lines above · pageup to scroll'));
        await t.type('!');
        await t.pump();
        expect(box(t), contains('unchanged!'));
        expect(box(t), isNot(contains('lines below')));
        // Off the Note, the rules name no key and the page keys leave the
        // Note where it is.
        await t.press('up');
        await t.pump();
        expect(box(t), contains('❯ 2. No, keep planning'));
        expect(box(t), isNot(contains('to scroll')));
        final held = box(t);
        await t.press('pageup');
        await t.pump();
        expect(box(t), held);
        await t.press('2');
        final heard = await answered(t, c);
        expect(heard, contains('row0 stays unchanged row1'));
        expect(heard, contains('row159 stays unchanged!'));
      });
    }

    testWidgets('a one-row Note reaches both ends by the page keys and '
        'editing restores the tail', (t) async {
      final c = await fixture.connected(t, const Size(80, 24));
      await asked(t, c, 'grokplan');
      for (var row = 0; row < 3; row++) {
        await t.press('down');
      }
      await t.paste(List.generate(30, (i) => 'word$i 日本語').join(' '));
      await t.resize(const Size(80, 16));
      await t.pump();
      await t.pump();
      String noteRow() => t.screen.lines.firstWhere((r) => r.contains('Note'));
      expect(noteRow(), contains('above'));
      expect(noteRow(), contains('word29'));
      for (var page = 0; page < 60 && !noteRow().contains('word0 '); page++) {
        await t.press('pageup');
        await t.pump();
      }
      expect(noteRow(), contains('Note  word0 '));
      expect(noteRow(), contains('below'));
      expect(box(t), contains('3. No, and leave plan mode'));
      await t.type('!');
      await t.pump();
      expect(noteRow(), contains('word29 日本語!'));
      await t.resize(const Size(80, 24));
      await t.pump();
      await t.press('enter');
      final heard = await answered(t, c);
      expect(heard, contains('word29 日本語!'));
    });
  });
}
