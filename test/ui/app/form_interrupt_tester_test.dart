@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' show connected, until;

void main() {
  group('tester U9a form interruption recovery', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'resizing and interrupting leaves the next form usable at $size',
        (t) async {
          final connection = await connected(t, size);
          await t.type('form');
          await t.press('enter');
          await until(() => connection.app.value.transcript.asking.isNotEmpty);
          await t.pump();
          await t.type('draft');
          await t.resize(
            size.width == 120 ? const Size(80, 24) : const Size(120, 40),
          );
          await t.press('ctrl+c');
          await until(
            () =>
                connection.app.value.transcript.asking.isEmpty &&
                connection.app.value.transcript.turn is model.Idle,
          );
          await t.pump();
          expect(connection.app.value.quitArmed, isFalse);
          expect(t.screen, shows('⎿  Interrupted by user'));
          await t.type('form');
          await t.press('enter');
          await until(() => connection.app.value.transcript.asking.isNotEmpty);
          await t.pump();
          expect(t.screen, shows('Set up the deploy target'));
          await t.press('ctrl+c');
          await until(
            () =>
                connection.app.value.transcript.asking.isEmpty &&
                connection.app.value.transcript.turn is model.Idle,
          );
          await t.pump();
          expect(connection.app.value.quitArmed, isFalse);
          expect(t.screen, isNot(shows('Esc to cancel')));
        },
        skip: fakeAgentSkip,
      );
    }
  });
}
