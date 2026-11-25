import 'package:chord/session/start_connection.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../../tool/mentions.dart';
import 'mentions_window_test.dart' show settle;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final agents in [false, true]) {
      testWidgets(
        'standalone injected ${agents ? 'populated' : 'empty'} roster fixture keeps actual prompt wiring $size',
        (t) async {
          final c = StartConnection(command: 'unused', cwd: '.');
          addTearDown(c.close);
          await t.pumpWidget(mentionsPreview(c, agents: agents), size: size);
          final focus = t.focusManager.primaryFocus;
          await t.type('@@');
          await settle(t);
          if (agents) {
            expect(t.screen, shows('parser'));
            expect(t.screen, shows('bugfix 2'));
            await t.press('down down down tab');
            expect(c.app.value.draft, '@@"bugfix 2" ');
          } else {
            expect(t.screen, shows('No agents to mention'));
            await t.press('tab');
            expect(c.app.value.draft, '@@');
          }
          expect(t.focusManager.primaryFocus, same(focus));
        },
      );
    }
    testWidgets(
      'standalone many-file fixture uses shared keyboard viewport and full pick $size',
      (t) async {
        final c = StartConnection(command: 'unused', cwd: '.');
        addTearDown(c.close);
        await t.pumpWidget(mentionsPreview(c, large: true), size: size);
        await t.type('@');
        await settle(t);
        await t.press(List.filled(15, 'down').join(' '));
        await settle(t);
        expect(t.screen, shows('source/file_015.dart'));
        await t.press('tab');
        expect(c.app.value.draft, '@source/file_015.dart ');
      },
    );
  }
}
