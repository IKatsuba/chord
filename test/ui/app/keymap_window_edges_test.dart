import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'keymap_window_test.dart' show window, launchWith;
import 'selection_window_test.dart' show selectionConnection, select;

void main() {
  group('tester: rebound window action ownership', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'shifted punctuation acts without changing Unicode draft $size',
        (t) async {
          final c = await window(t, size, [
            {
              'context': 'Global',
              'bindings': {'#': 'app:toggleTranscript'},
            },
          ]);
          await t.paste('界👩‍💻é');
          t.host.handleKey(const KeyEvent('#', shift: true));
          await t.pump();
          expect(c.app.value.expanded, isTrue);
          expect(c.app.value.draft, '界👩‍💻é');
          await t.press('#');
          expect(c.app.value.expanded, isFalse);
          expect(c.app.value.draft, '界👩‍💻é');
        },
      );

      testWidgets('rebound help remains typed on a nonempty draft $size', (
        t,
      ) async {
        final c = await window(t, size, [
          {
            'context': 'Chat',
            'bindings': {'#': 'help:toggle', '?': null},
          },
        ]);
        await t.type('a');
        t.host.handleKey(const KeyEvent('#', shift: true));
        await t.pump();
        expect(c.app.value.draft, 'a#');
        expect(c.app.value.shortcuts.help, isFalse);
        await t.press('ctrl+c');
        await t.press('#');
        expect(c.app.value.shortcuts.help, isTrue);
        expect(c.app.value.draft, isEmpty);
      });

      testWidgets(
        'printable chord owns its strokes and drops wrong suffix $size',
        (t) async {
          final c = await window(t, size, [
            {
              'context': 'Global',
              'bindings': {'g t': 'app:toggleTranscript'},
            },
          ]);
          await t.paste('draft');
          await t.press('g');
          expect(c.app.value.draft, 'draft');
          await t.press('t');
          expect(c.app.value.expanded, isTrue);
          expect(c.app.value.draft, 'draft');
          await t.press('g z');
          expect(c.app.value.expanded, isTrue);
          expect(c.app.value.draft, 'draft');
          await t.type('x');
          expect(c.app.value.draft, 'draftx');
        },
      );

      testWidgets('rebound scrolling preserves an active selection $size', (
        t,
      ) async {
        final c = selectionConnection();
        addTearDown(c.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: launchWith([
              {
                'context': 'Scroll',
                'bindings': {'ctrl+t': 'scroll:top', 'home': null},
              },
            ]),
            connection: c,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        await select(t, 'reply words');
        final before = writes.length;
        await t.press('ctrl+t');
        await t.press('ctrl+c');
        expect(writes.length, before + 1);
        expect(writes.last, 'reply words');
        expect(t.exitRequested, isFalse);
      });
    }
  });
}
