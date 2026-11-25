// A transcript diff wraps its code to the original's room, on the
// original's fake (scenario `longresults`): DiffRows in Tool.tsx gets the
// tool's width less the five cells beside the `⎿`, and the tool's width is
// the row less the transcript's two.
@Tags(['fake_agent'])
library;

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_harness.dart';
import '../../app/window_fake_test.dart' show connected, sent;

void main() {
  testWidgets('a diff wraps in the room the original gives it, at 80', (
    t,
  ) async {
    final connection = await connected(t, const Size(80, 24));
    await sent(t, connection, 'longresults');
    final rows = [for (final row in t.screen.lines) row.trimRight()];
    final at = rows.indexWhere(
      (row) => row.contains('1 + export const greeting'),
    );
    expect(at, isNot(-1), reason: t.screen.text);
    // As the original draws them at 80x24.
    expect(rows.sublist(at, at + 4), [
      "      1 + export const greeting = 'Hello, and welcome to chord, the "
          'terminal',
      "          ' +",
      "      2 +   'client for coding agents that speak the Agent Client "
          "Protocol, '",
      "          + 'run from source';",
    ]);
    // The tint still fills the row to its last cell but one, 79 cells, as
    // the original's; only the code's room is narrower.
    for (final y in [at, at + 1, at + 2, at + 3]) {
      final tint = t.screen.styleAt(6, y).bg;
      expect(tint, isNotNull, reason: 'row $y');
      expect(t.screen.styleAt(78, y).bg, tint, reason: 'row $y');
      expect(t.screen.styleAt(79, y).bg, isNot(tint), reason: 'row $y');
    }
  }, skip: fakeAgentSkip);
}
