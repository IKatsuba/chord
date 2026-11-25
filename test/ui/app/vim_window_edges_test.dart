import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal;
import 'images_state_test.dart' show image;
import 'selection_window_test.dart' show selectionConnection;
import 'vim_window_test.dart' show window, settle;

void main() {
  group('tester: port vim routing and ownership boundaries', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'held image deletion is atomic and send reset keeps register $size',
        (t) async {
          final c = await window(t, size, vim: true);
          c.app.value = reduceWindow(
            c.app.value,
            ImagesAddedAction([image(1)]),
          );
          await t.pump();
          await t.paste('界🙂 [Image #1] é');
          await t.press('esc');
          await t.press('0 f [ x');
          expect(c.app.value.draft, '界🙂  é');
          expect(c.app.value.vim?.register, const VimRegister('[Image #1]'));
          await t.press('u');
          expect(c.app.value.draft, '界🙂 [Image #1] é');
          await t.press('ctrl+c');
          await t.press('i');
          await t.type('/help');
          await t.press('enter');
          await settle(t);
          expect(c.app.value.draft, isEmpty);
          expect(c.app.value.vim?.mode, VimMode.insert);
          expect(c.app.value.vim?.register, const VimRegister('[Image #1]'));
        },
      );

      testWidgets(
        'invalid settings refuse persistence while vim still toggles $size',
        (t) async {
          final root = await Directory.systemTemp.createTemp(
            'vim-save-tester-',
          );
          addTearDown(() => root.delete(recursive: true));
          final file = File('${root.path}/settings.json');
          const raw = '{"editorMode":';
          await file.writeAsString(raw);
          final c = await window(t, size, settingsFile: file.path);
          await t.type('/vim');
          await t.press('enter');
          await settle(t);
          expect(c.app.value.vim?.mode, VimMode.insert);
          expect(t.screen.text, contains('could not be saved'));
          expect(await file.readAsString(), raw);
          expect(root.listSync().map((e) => e.uri.pathSegments.last), [
            'settings.json',
          ]);
        },
      );

      testWidgets(
        'editor return in normal mode stands on the last grapheme $size',
        (t) async {
          final c = selectionConnection(const []);
          c.app.value = c.app.value.withVim(true);
          addTearDown(c.close);
          final terminal = EditorTerminal(saved: '界🙂é\n');
          await t.pumpWidget(
            TranscriptWindow(
              launch: const Launch(
                name: 'fake',
                agent: null,
                agentCommand: 'unused',
                version: 'test',
                directory: '.',
                vim: true,
              ),
              connection: c,
              terminal: terminal,
            ),
            size: size,
          );
          await t.type('draft');
          await t.press('esc');
          await t.press('ctrl+g');
          await settle(t);
          expect((c.app.value.draft, c.app.value.cursor), ('界🙂é', 2));
          expect(c.app.value.vim?.mode, VimMode.normal);
          await t.press('x');
          expect(c.app.value.draft, '界🙂');
        },
      );

      testWidgets(
        'shifted punctuation submit outranks normal-mode filtering $size',
        (t) async {
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
          await t.pump();
          await settle(t);
          expect(c.app.value.shortcuts.help, isTrue);
          expect(c.app.value.draft, isEmpty);
          expect(c.app.value.vim?.mode, VimMode.insert);
        },
      );
    }
  });
}
