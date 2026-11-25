@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart' show heldBack;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as window;

void main() {
  group('tester U11b held window lifecycle', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'repeated idle Esc and resize retain the question until focused at $size',
        (t) async {
          final connection = await window.connected(t, size);
          await t.type('mainbetween');
          await t.press('enter');
          await window.until(
            () =>
                connection.app.value.transcript.turn is AwaitingPermission &&
                heldBack(connection.app.value),
          );
          final wait =
              (connection.app.value.transcript.turn as AwaitingPermission)
                  .permissions
                  .first;
          await t.pump();
          for (var i = 0; i < 3; i++) {
            await t.press('escape');
          }
          await t.resize(Size.zero);
          await t.resize(const Size(1, 1));
          await t.resize(size);
          expect(heldBack(connection.app.value), isTrue);
          expect(
            (connection.app.value.transcript.turn as AwaitingPermission)
                .permissions
                .first
                .id,
            wait.id,
          );
          await t.press('ctrl+x');
          await t.press('a');
          await t.press('escape');
          await window.until(
            () => connection.app.value.transcript.turn is! AwaitingPermission,
          );
          await t.pump();
          expect(t.screen.lines.join('\n'), contains('Rejected'));
        },
        skip: fakeAgentSkip,
      );
    }
  });
}
