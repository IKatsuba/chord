// ctrl+c while an agent's form has the keys stops the turn, which takes the
// form with it, on the original's fake (scenario `form`), as the original's
// keyCommand answers it with `interrupt` (CTUI-86).
@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' show connected, until;

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('ctrl+c stops the turn and its form at $size', (t) async {
      final connection = await connected(t, size);
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
      // The box is gone; its record and the turn's end are in its place.
      expect(t.screen, isNot(shows('Esc to cancel')));
      expect(t.screen, shows('⎿  Cancelled'));
      expect(t.screen, shows('⎿  Interrupted by user'));
      // The turn stopped; ctrl+c did not start towards quitting.
      expect(connection.app.value.quitArmed, isFalse);
    }, skip: fakeAgentSkip);
  }
}
