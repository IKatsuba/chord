// Keys on a Russian layout in the window, as the original's guide has
// them: a key that does nothing as typed is the US key in its place, text
// typed stays as typed, and on an empty prompt in a kitty terminal the key
// in `?`'s place opens the shortcuts.
import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'dart:convert';

import 'package:chord/ui/shortcuts/bindings.dart'
    show layoutKeys, readKeybindings;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart' show selectionConnection;

Future<StartConnection> _window(
  WidgetTester t,
  Size size, {
  bool vim = false,
  List<Object?>? blocks,
}) async {
  final c = selectionConnection(const []);
  if (vim) c.app.value = c.app.value.withVim(true);
  addTearDown(c.close);
  await t.pumpWidget(
    TranscriptWindow(
      launch: Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
        keymap: blocks == null
            ? null
            : readKeybindings(jsonEncode({'bindings': blocks})).keymap,
      ),
      connection: c,
    ),
    size: size,
    layoutFallback: layoutKeys,
  );
  return c;
}

/// `,` as Russian – PC types it: shift and the key US has `/` on, which a
/// kitty terminal names.
const _commaWhereQuestionIs = KeyEvent(',', shift: true, baseKey: '/');

void main() {
  group('tester: CTUI-67 port literal and modifier ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'every non-shift modifier stays non-vim when reading shifted ф $size',
        (t) async {
          final c = await _window(t, size, vim: true);
          await t.type('ар бв');
          await t.press('esc');
          for (final press in const [
            KeyEvent('ф', shift: true, ctrl: true, baseKey: 'a'),
            KeyEvent('ф', shift: true, alt: true, baseKey: 'a'),
            KeyEvent('ф', shift: true, superKey: true, baseKey: 'a'),
            KeyEvent('ф', shift: true, hyper: true, baseKey: 'a'),
            KeyEvent('ф', shift: true, meta: true, baseKey: 'a'),
          ]) {
            await t.sendKey(press);
            expect(c.app.value.vim!.mode, VimMode.normal, reason: '$press');
            expect(c.app.value.cursor, 4, reason: '$press');
            expect(c.app.value.draft, 'ар бв', reason: '$press');
          }
        },
      );

      for (final (command, cursor, draft) in [
        ('f', 2, 'абр в'),
        ('t', 1, 'абр в'),
        ('r', 0, 'рбр в'),
      ]) {
        testWidgets(
          'after $command a kitty base key cannot replace the literal Russian target $size',
          (t) async {
            final c = await _window(t, size, vim: true);
            await t.type('абр в');
            await t.press('esc');
            await t.type('0$command');
            await t.sendKey(const KeyEvent('р', baseKey: 'h'));
            expect(c.app.value.vim!.mode, VimMode.normal);
            expect(c.app.value.cursor, cursor);
            expect(c.app.value.draft, draft);
            expect(c.app.value.vim!.pending, isEmpty);
          },
        );
      }

      testWidgets(
        'search owns Russian and wide text before layout readings and restores help after Esc $size',
        (t) async {
          final c = await _window(t, size);
          await t.press('ctrl+r');
          await t.type('ф界🙂e\u0301');
          await t.sendKey(_commaWhereQuestionIs);
          expect(c.app.value.search?.query, 'ф界🙂e\u0301,');
          expect(c.app.value.shortcuts.help, isFalse);
          await t.resize(
            size.width == 120 ? const Size(80, 24) : const Size(120, 40),
          );
          await t.press('esc');
          expect(c.app.value.search, isNull);
          await t.sendKey(_commaWhereQuestionIs);
          expect(c.app.value.shortcuts.help, isTrue);
          expect(c.app.value.draft, '');
        },
      );

      testWidgets(
        'Apple ё reaches the second fallback only on an empty prompt $size',
        (t) async {
          final c = await _window(
            t,
            size,
            blocks: [
              {
                'context': 'Chat',
                'bindings': {r'\': 'help:toggle'},
              },
            ],
          );
          await t.type('ё');
          expect(c.app.value.shortcuts.help, isTrue);
          await t.press('esc');
          await t.type('даё');
          expect(c.app.value.draft, 'даё');
          expect(c.app.value.shortcuts.help, isFalse);
        },
      );
    }
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the key in ?\'s place opens the shortcuts on an empty '
        'prompt, and types its , after text, at $size', (t) async {
      final c = await _window(t, size);
      await t.sendKey(_commaWhereQuestionIs);
      expect(c.app.value.shortcuts.help, isTrue);
      expect(c.app.value.draft, '');
      await t.press('esc');
      expect(c.app.value.shortcuts.help, isFalse);
      await t.type('да');
      await t.sendKey(_commaWhereQuestionIs);
      expect(c.app.value.draft, 'да,');
      expect(c.app.value.shortcuts.help, isFalse);
    });

    testWidgets('Russian text stays as typed, and ctrl+ч begins ctrl+x as '
        'it would, at $size', (t) async {
      final c = await _window(t, size);
      await t.type('привет');
      expect(c.app.value.draft, 'привет');
      await t.press('ctrl+ч');
      expect('${t.focusManager.pendingChord}', '[ctrl+x]');
      await t.press('esc');
      expect(c.app.value.draft, 'привет');
    });

    testWidgets('vim\'s normal mode reads р as h, and after f takes р as '
        'itself, at $size', (t) async {
      final c = await _window(t, size, vim: true);
      await t.type('ар бв');
      await t.press('esc');
      expect(c.app.value.cursor, 4);
      await t.type('р');
      expect(c.app.value.cursor, 3);
      expect(c.app.value.draft, 'ар бв');
      await t.type('0');
      await t.type('fр');
      expect(c.app.value.draft, 'ар бв');
      expect(c.app.value.cursor, 1);
    });
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a key the file binds as typed is its own, ahead of what its '
        'reading is bound to, at $size', (t) async {
      final c = await _window(
        t,
        size,
        blocks: [
          {
            'context': 'Chat',
            'bindings': {'ф': 'help:toggle'},
          },
          {
            'context': 'Global',
            'bindings': {'a': 'history:search'},
          },
        ],
      );
      await t.sendKey(const KeyEvent('ф', baseKey: 'a'));
      expect(c.app.value.shortcuts.help, isTrue);
      expect(c.app.value.search, isNull);
    });

    testWidgets('the search line types the key in ?\'s place as its , at '
        '$size', (t) async {
      final c = await _window(t, size);
      await t.press('ctrl+r');
      expect(c.app.value.search, isNotNull);
      await t.sendKey(_commaWhereQuestionIs);
      expect(c.app.value.shortcuts.help, isFalse);
      expect(c.app.value.search?.query, ',');
    });
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    for (final (name, press) in [
      ('Ш from the table', const KeyEvent('Ш')),
      ('shift+ш from kitty', const KeyEvent('ш', shift: true, baseKey: 'i')),
    ]) {
      testWidgets('vim reads $name as I, inserting at the line\'s start, not '
          'as i, at $size', (t) async {
        final c = await _window(t, size, vim: true);
        await t.type('ар бв');
        await t.press('esc');
        expect(c.app.value.cursor, 4);
        await t.sendKey(press);
        expect(c.app.value.vim!.mode, VimMode.insert);
        expect(c.app.value.cursor, 0);
        expect(c.app.value.draft, 'ар бв');
      });
    }
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('in vim\'s normal mode a window action on a reading comes '
        'before vim\'s own key, at $size', (t) async {
      final c = await _window(
        t,
        size,
        vim: true,
        blocks: [
          {
            'context': 'Global',
            'bindings': {'a': 'history:search'},
          },
        ],
      );
      await t.type('ар');
      await t.press('esc');
      expect(c.app.value.vim!.mode, VimMode.normal);
      await t.type('ф');
      expect(c.app.value.search, isNotNull);
      expect(c.app.value.vim!.mode, VimMode.normal);
      expect(c.app.value.draft, 'ар');
    });
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a modified reading is no vim key: ctrl+shift+ф leaves the '
        'mode, cursor and draft alone, at $size', (t) async {
      final c = await _window(t, size, vim: true);
      await t.type('ар бв');
      await t.press('esc');
      await t.sendKey(
        const KeyEvent('ф', ctrl: true, shift: true, baseKey: 'a'),
      );
      expect(c.app.value.vim!.mode, VimMode.normal);
      expect(c.app.value.cursor, 4);
      expect(c.app.value.draft, 'ар бв');
    });
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('ctrl+x ф with none waiting says so, as ctrl+x a does, at '
        '$size', (t) async {
      final c = await _window(t, size);
      await t.press('ctrl+x');
      await t.type('ф');
      await t.pump();
      expect(c.app.value.draft, '');
      expect(t.screen.text, contains('Nothing waits on you'));
    });
  }
}
