import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart' show selectionConnection, select;

void main() {
  group('tester: window agent identity and selection', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'header copy follows a changed launch name through resize $size',
        (t) async {
          final connection = selectionConnection();
          addTearDown(connection.close);
          final name = ValueNotifier('codex');
          addTearDown(name.dispose);
          final writes = <String>[];
          await t.pumpWidget(
            ListenableBuilder(
              listenable: name,
              builder: (_) => TranscriptWindow(
                launch: Launch(
                  name: name.value,
                  agent: findAgent('codex'),
                  version: 'test',
                  directory: 'project',
                ),
                connection: connection,
                copyOnSelect: false,
                copy: (text, _) {
                  writes.add(text);
                  return const copy.CopyResult.sent();
                },
              ),
            ),
            size: size,
          );
          final focus = t.focusManager.primaryFocus;
          await select(t, 'codex');
          await t.press('ctrl+shift+c');
          expect(writes, ['codex']);
          expect(t.screen.lines.take(4).join(), isNot(contains('Codex')));

          name.value = 'renamed-runtime';
          await t.pump();
          await t.resize(Size.zero);
          await t.resize(const Size(1, 1));
          await t.resize(size);
          await select(t, 'renamed-runtime');
          await t.press('ctrl+shift+c');
          expect(writes, ['codex', 'renamed-runtime']);
          expect(t.focusManager.primaryFocus, same(focus));
          final header = t.screen.lines.take(4).join();
          expect(header, contains('renamed-runtime'));
          expect(header, isNot(contains('codex')));
          expect(header, isNot(contains('Codex')));
        },
      );
    }
  });
}
