import 'dart:async';
import 'dart:io';

import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/prompt/prompt.dart' show endOf;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart'
    show EditorTerminal, connection, plainLaunch, settle, window;

class _ControlledEditor extends EditorTerminal {
  _ControlledEditor({
    required super.release,
    super.saved,
    this.throwAfter = false,
  });
  final bool throwAfter;
  final paths = <String>[];

  @override
  Future<int> runEditor(
    String path, {
    String? command,
    String? workingDirectory,
  }) async {
    paths.add(path);
    final code = await super.runEditor(
      path,
      command: command,
      workingDirectory: workingDirectory,
    );
    if (throwAfter) throw StateError('late editor transport failure');
    return code;
  }
}

void main() {
  group('tester: editor ownership and cleanup boundaries', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'duplicate open runs once and Unicode returns at grapheme end $size',
        (t) async {
          final release = Completer<void>();
          final terminal = _ControlledEditor(
            release: release.future,
            saved: '界👩‍💻é\n',
          );
          final c = await window(t, size, terminal);
          await t.type('draft');
          await t.press('ctrl+g');
          await settle(t);
          await t.press('ctrl+g');
          await settle(t);
          expect(terminal.drafts, ['draft\n']);
          release.complete();
          await settle(t);
          expect(c.app.value.draft, '界👩‍💻é');
          expect(c.app.value.cursor, endOf('界👩‍💻é'));
          expect(terminal.paths, hasLength(1));
          expect(await File(terminal.paths.single).parent.exists(), isFalse);
        },
      );

      for (final replace in ['terminal', 'connection']) {
        testWidgets(
          'late thrown failure after $replace replacement publishes nothing $size',
          (t) async {
            final release = Completer<void>();
            final firstTerminal = _ControlledEditor(
              release: release.future,
              throwAfter: true,
            );
            final first = connection(), second = connection();
            final current = ValueNotifier((
              connection: first,
              terminal: firstTerminal as Terminal,
            ));
            addTearDown(current.dispose);
            await t.pumpWidget(
              ListenableBuilder(
                listenable: current,
                builder: (_) => TranscriptWindow(
                  launch: plainLaunch,
                  connection: current.value.connection,
                  terminal: current.value.terminal,
                ),
              ),
              size: size,
            );
            await t.type('kept');
            await t.press('ctrl+g');
            await settle(t);
            expect(firstTerminal.paths, hasLength(1));
            if (replace == 'terminal') {
              current.value = (connection: first, terminal: EditorTerminal());
            } else {
              current.value = (connection: second, terminal: firstTerminal);
            }
            await settle(t);
            release.complete();
            await settle(t);
            expect(first.app.value.editorFailed, isNull);
            expect(second.app.value.editorFailed, isNull);
            expect(
              t.screen.text,
              isNot(contains('late editor transport failure')),
            );
            expect(
              await File(firstTerminal.paths.single).parent.exists(),
              isFalse,
            );
          },
        );
      }
    }
  });
}
