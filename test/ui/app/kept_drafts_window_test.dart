// Drafts set aside with ↓ in the window (CHD-493 U10, CTUI-35 I3): the
// field empties and nothing says so, ↑ brings the draft back where its
// cursor was, an open list keeps ↓, sending it or ctrl+c takes it, vim's
// j and k do as ↓ and ↑, and another agent's ↑ never brings it.
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show show, window;

/// The prompt's row: the screen line holding [text].
bool _shows(WidgetTester t, String text) =>
    t.screen.lines.any((line) => line.contains(text));

void main() {
  _testerKeptSwitches();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('↓ sets the draft aside with nothing on screen, and ↑ '
        'brings it back where its cursor was, at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      final empty = t.screen.text;
      await t.type('one Xtwo');
      for (var i = 0; i < 3; i++) {
        await t.press('left');
      }
      await t.press('down');
      await t.pump();
      expect(fold.app.value.draft, '');
      expect(fold.app.value.kept.single.text, 'one Xtwo');
      expect(t.screen.text, empty);
      await t.press('up');
      await t.pump();
      expect(t.screen, shows('one Xtwo'));
      await t.type('Y');
      await t.pump();
      expect(fold.app.value.draft, 'one XYtwo');
      expect(t.screen, shows('one XYtwo'));
    });

    // CTUI-179: the original's box reads cmd+↓ and cmd+↑ as ↓ and ↑.
    testWidgets('cmd+↓ sets the draft aside and cmd+↑ brings it back, '
        'at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      final empty = t.screen.text;
      await t.type('one two');
      await t.press('super+down');
      await t.pump();
      expect(fold.app.value.draft, '');
      expect(fold.app.value.kept.single.text, 'one two');
      expect(t.screen.text, empty);
      await t.press('super+up');
      await t.pump();
      expect(fold.app.value.draft, 'one two');
      expect(t.screen, shows('one two'));
    });

    testWidgets("a multi-line draft's ↓ moves the cursor until the last "
        'line, at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('first');
      await t.press('shift+enter');
      await t.type('second');
      await t.press('up');
      await t.pump();
      expect(fold.app.value.cursor, lessThan('first'.length + 1));
      await t.press('down');
      await t.pump();
      expect(fold.app.value.draft, 'first\nsecond');
      expect(fold.app.value.kept, isEmpty);
      await t.press('down');
      await t.pump();
      expect(fold.app.value.draft, '');
      expect(fold.app.value.kept.single.text, 'first\nsecond');
    });

    testWidgets('an open / list keeps ↓, at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('/');
      await settle(t);
      expect(t.screen, shows('/clear'));
      await t.press('down');
      await t.pump();
      expect(fold.app.value.draft, '/');
      expect(fold.app.value.kept, isEmpty);
    });

    testWidgets('an open @ list keeps ↓, at $size', (t) async {
      // A fixed walk: the list must not wait on however many files the
      // working directory holds.
      final w = await window(
        t,
        size,
        EditorTerminal(),
        walkFiles: (cwd, {cancellationToken}) async => ['README.md'],
      );
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('@');
      await settle(t);
      await t.press('down');
      await t.pump();
      expect(fold.app.value.draft, '@');
      expect(fold.app.value.kept, isEmpty);
    });

    // CTUI-179: in the running original, cmd+↓ and cmd+↑ do nothing while a
    // list holds the keys: the draft, the list and its highlight stay.
    for (final list in const ['/', '@']) {
      testWidgets('an open $list list ignores cmd+↓ and cmd+↑, at $size', (
        t,
      ) async {
        final w = await window(
          t,
          size,
          EditorTerminal(),
          walkFiles: (cwd, {cancellationToken}) async => ['README.md'],
        );
        final fold = w.connection.fold;
        show(w.connection, w.child);
        await t.pump();
        await t.type(list);
        await settle(t);
        final open = t.screen.text;
        for (final key in const ['super+down', 'super+up']) {
          await t.press(key);
          await settle(t);
          expect(fold.app.value.draft, list);
          expect(fold.app.value.kept, isEmpty);
          expect(t.screen.text, open);
        }
      });
    }

    testWidgets('sending a shown kept draft takes it off the stack, at $size', (
      t,
    ) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('later');
      await t.press('down');
      await t.type('now');
      await t.press('enter');
      await settle(t);
      // Sending another prompt leaves the stack.
      expect(fold.app.value.kept.single.text, 'later');
      await t.press('up');
      await t.pump();
      expect(fold.app.value.draft, 'later');
      await t.press('enter');
      await settle(t);
      // The first turn still runs: the kept draft waits behind it.
      expect([for (final turn in w.session.turns) turn.text], ['now']);
      expect(
        [for (final queued in fold.app.value.queue) queued.text],
        ['later'],
      );
      expect(fold.app.value.kept, isEmpty);
      // ↑ now walks the prompts sent, with no kept draft before them.
      await t.press('up');
      await t.pump();
      expect(fold.app.value.draft, 'later');
      await t.press('up');
      await t.pump();
      expect(fold.app.value.draft, 'now');
    });

    testWidgets('ctrl+c on a shown kept draft takes it off the stack, at '
        '$size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('drop me');
      await t.press('down');
      await t.press('up');
      await t.pump();
      expect(fold.app.value.draft, 'drop me');
      await t.press('ctrl+c');
      await t.pump();
      expect(fold.app.value.draft, '');
      expect(fold.app.value.kept, isEmpty);
      await t.press('up');
      await t.pump();
      expect(fold.app.value.draft, '');
    });

    testWidgets("another agent's ↑ does not bring the kept draft, at $size", (
      t,
    ) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('sent once');
      await t.press('enter');
      await settle(t);
      await t.type('child secret');
      await t.press('down');
      await t.pump();
      show(w.connection, mainKey);
      await t.pump();
      await t.press('up');
      await t.pump();
      // The prompts sent are the window's; the kept draft is the child's.
      expect(fold.app.value.draft, 'sent once');
      expect(_shows(t, 'child secret'), isFalse);
      await t.press('up');
      await t.pump();
      expect(fold.app.value.draft, 'sent once');
      // The child's own walk begins at its kept draft, main's walk apart.
      show(w.connection, w.child);
      await t.pump();
      await t.press('up');
      await t.pump();
      expect(fold.app.value.draft, 'child secret');
      expect(t.screen, shows('child secret'));
      expect(fold.stateOf(mainKey)!.draft, 'sent once');
    });

    testWidgets('vim normal j on the last line sets the draft aside and k '
        'brings it back, at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      fold.app.value = fold.app.value.withVim(true);
      await t.pump();
      await t.type('vim draft');
      await t.press('escape');
      await t.pump();
      expect(fold.app.value.vim?.mode, VimMode.normal);
      await t.press('j');
      await t.pump();
      expect(fold.app.value.draft, '');
      expect(fold.app.value.kept.single.text, 'vim draft');
      await t.press('k');
      await t.pump();
      expect(fold.app.value.draft, 'vim draft');
      expect(fold.app.value.kept.single.text, 'vim draft');
      expect(t.screen, shows('vim draft'));
    });
  }
}

void _testerKeptSwitches() {
  group('CTUI-35 tester: kept walks across resize and shared sends', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'shared sent history grows while main stands on its own kept draft at $size',
        (t) async {
          final w = await window(t, size, EditorTerminal());
          final fold = w.connection.fold;
          await t.type('main kept');
          await t.press('down');
          await t.press('up');
          expect(fold.app.value.draft, 'main kept');
          show(w.connection, w.child);
          await t.pump();
          await t.type('child sent');
          await t.press('enter');
          await settle(t);
          await t.type('child kept');
          await t.press('down');
          show(w.connection, mainKey);
          await t.pump();
          expect(fold.app.value.draft, 'main kept');
          await t.press('up');
          expect(fold.app.value.draft, 'child sent');
          await t.press('down');
          expect(fold.app.value.draft, 'main kept');
          await t.type(' edited');
          await t.press('down');
          expect(fold.app.value.kept.single.text, 'main kept edited');
          show(w.connection, w.child);
          await t.pump();
          await t.press('up');
          expect(fold.app.value.draft, 'child kept');
          expect(fold.stateOf(mainKey)!.kept.single.text, 'main kept edited');
        },
      );

      testWidgets('Unicode cursor survives aside, resize and recall at $size', (
        t,
      ) async {
        final w = await window(t, size, EditorTerminal());
        show(w.connection, w.child);
        await t.pump();
        await t.type('界e\u0301🙂tail');
        for (var i = 0; i < 4; i++) {
          await t.press('left');
        }
        final cursor = w.connection.app.value.cursor;
        await t.press('down');
        await t.resize(
          size.width == 120 ? const Size(80, 24) : const Size(120, 40),
        );
        await t.press('up');
        await t.pump();
        expect(w.connection.app.value.cursor, cursor);
        await t.type('X');
        expect(w.connection.app.value.draft, '界e\u0301🙂Xtail');
        await t.press('ctrl+c');
        expect(w.connection.app.value.kept, isEmpty);
        expect(w.connection.app.value.draft, '');
      });
    }
  });
}
