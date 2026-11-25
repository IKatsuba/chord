// /vim in the window, from the original's guide: the mode under the box,
// Esc to normal mode and through it, Enter from either mode, and the choice
// kept in the user's file.
import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/shortcuts/bindings.dart';

import 'selection_window_test.dart' show selectionConnection;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<StartConnection> window(
  WidgetTester t,
  Size size, {
  bool vim = false,
  String? settingsFile,
  List<Object?> blocks = const [],
}) async {
  // Connected, so chord's own commands run, with nothing in the transcript.
  final c = selectionConnection(const []);
  c.app.value = c.app.value.withVim(vim);
  addTearDown(c.close);
  await t.pumpWidget(
    TranscriptWindow(
      launch: Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
        vim: vim,
        keymap: readKeybindings(jsonEncode({'bindings': blocks})).keymap,
        settingsFile: settingsFile,
        shownSettingsFile: settingsFile,
      ),
      connection: c,
    ),
    size: size,
  );
  return c;
}

String status(WidgetTester t) =>
    t.screen.lines.lastWhere((l) => l.trim().isNotEmpty);

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('/vim turns vim mode on, says so, and marks the mode under '
        'the box, at $size', (t) async {
      final c = await window(t, size);
      expect(status(t), isNot(contains('-- INSERT --')));
      await t.type('/vim');
      await t.press('enter');
      await settle(t);
      expect(c.app.value.vim?.mode, VimMode.insert);
      expect(status(t), contains('-- INSERT --'));
      expect(
        t.screen.text,
        contains('Vim mode on: Esc for normal mode, i to insert'),
      );
      await t.press('esc');
      expect(status(t), contains('-- NORMAL --'));
      await t.press('i');
      await t.type('/vim');
      await t.press('enter');
      await settle(t);
      expect(c.app.value.vim, isNull);
      expect(t.screen.text, contains('Vim mode off'));
      expect(status(t), isNot(contains('--')));
    });

    testWidgets("normal mode's keys move and edit, type nothing else, and u "
        'undoes, at $size', (t) async {
      final c = await window(t, size, vim: true);
      await t.type('hello world');
      await t.press('esc');
      expect(c.app.value.vim?.mode, VimMode.normal);
      await t.press('b');
      await t.press('d');
      await t.press('w');
      expect(c.app.value.draft, 'hello ');
      // Not normal mode's: dropped, never typed.
      await t.type('zq');
      expect(c.app.value.draft, 'hello ');
      await t.press('u');
      expect(c.app.value.draft, 'hello world');
      // What insert mode typed is one undo.
      await t.press('u');
      expect(c.app.value.draft, '');
    });

    testWidgets('Esc closes an open list first; in normal mode it does what '
        'it does without vim, and Enter works from either mode, at $size', (
      t,
    ) async {
      final c = await window(t, size, vim: true);
      await t.type('/');
      expect(t.screen.text, contains('/config'));
      await t.press('esc');
      expect(t.screen.text, isNot(contains('/config')));
      expect(c.app.value.vim?.mode, VimMode.insert);
      await t.press('backspace');
      await t.type('/help');
      // The list /help opens closes first, then insert mode goes.
      await t.press('esc');
      expect(c.app.value.vim?.mode, VimMode.insert);
      await t.press('esc');
      expect(c.app.value.vim?.mode, VimMode.normal);
      // Esc again is the window's own: it changes no mode.
      await t.press('esc');
      expect(c.app.value.vim?.mode, VimMode.normal);
      await t.press('enter');
      await settle(t);
      expect(c.app.value.shortcuts.help, isTrue);
      // The box emptied, vim mode starts again in insert mode.
      expect(c.app.value.vim?.mode, VimMode.insert);
      expect(c.app.value.draft, '');
    });

    testWidgets('a half-typed command waits and Esc drops it, at $size', (
      t,
    ) async {
      final c = await window(t, size, vim: true);
      await t.type('abc');
      await t.press('esc');
      await t.press('d');
      expect(c.app.value.vim?.pending, ['d']);
      await t.press('esc');
      expect(c.app.value.vim?.pending, isEmpty);
      expect(c.app.value.draft, 'abc');
    });

    testWidgets(
      "/vim is kept in the user's file for the next start, at $size",
      (t) async {
        final dir = await Directory.systemTemp.createTemp('chord-vim-');
        addTearDown(() => dir.delete(recursive: true));
        final file = p.join(dir.path, 'chord', 'settings.json');
        await window(t, size, settingsFile: file);
        await t.type('/vim');
        await t.press('enter');
        for (var i = 0; i < 20 && !File(file).existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await t.pump();
        }
        expect(
          await File(file).readAsString(),
          contains('"editorMode": "vim"'),
        );
      },
    );

    testWidgets('a recalled draft stands normal mode on its last character, '
        'and x takes it, at $size', (t) async {
      final c = await window(t, size, vim: true);
      await t.type('/help');
      await t.press('enter');
      await settle(t);
      await t.press('?');
      await settle(t);
      expect(c.app.value.shortcuts.help, isFalse);
      await t.press('esc');
      expect(c.app.value.vim?.mode, VimMode.normal);
      // k on the only line walks back to /help, the cursor on its p.
      await t.press('k');
      expect(c.app.value.draft, '/help');
      expect(c.app.value.cursor, 4);
      await t.press('x');
      expect(c.app.value.draft, '/hel');
    });

    testWidgets("a chord the file sends on is the prompt's in normal mode, "
        'at $size', (t) async {
      final c = await window(
        t,
        size,
        vim: true,
        blocks: [
          {
            'context': 'Chat',
            'bindings': {'ctrl+s x': 'chat:submit', 'enter': null},
          },
        ],
      );
      await t.type('/help');
      // The list /help opens closes first, then insert mode goes.
      await t.press('esc');
      await t.press('esc');
      expect(c.app.value.vim?.mode, VimMode.normal);
      await t.press('ctrl+s');
      await t.press('x');
      await settle(t);
      expect(c.app.value.shortcuts.help, isTrue);
      expect(c.app.value.draft, '');
    });

    testWidgets('a shifted mark the file sends on sends from normal mode, at '
        '$size', (t) async {
      final c = await window(
        t,
        size,
        vim: true,
        blocks: [
          {
            'context': 'Chat',
            'bindings': {'#': 'chat:submit', 'enter': null},
          },
        ],
      );
      await t.type('/help');
      await t.press('esc');
      await t.press('esc');
      expect(c.app.value.vim?.mode, VimMode.normal);
      t.host.handleKey(const KeyEvent('#', shift: true));
      await settle(t);
      expect(c.app.value.shortcuts.help, isTrue);
      expect(c.app.value.vim?.mode, VimMode.insert);
    });
  }
}
