@Tags(['fake_agent'])
library;

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'monitors_window_test.dart' show monitorsWindow, until;

void main() {
  group('tester U3 monitor command resize', () {
    testWidgets('a live command rewraps at spaces and recovers after resize', (
      t,
    ) async {
      await monitorsWindow(t, const Size(120, 40));
      await t.type('monitors');
      await t.press('enter');
      await until(t, () => t.screen.text.contains('m1 · times out after 10m'));
      List<String> commandRows() {
        final rows = [for (final row in t.screen.lines) row.trimRight()];
        final start = rows.indexOf(' ⏺ Monitor(dev server errors)');
        final end = rows.indexOf('      m1 · times out after 10m', start);
        expect(start, greaterThanOrEqualTo(0), reason: t.screen.text);
        expect(end, greaterThan(start), reason: t.screen.text);
        return rows.sublist(start + 1, end + 1);
      }

      final wide = commandRows();
      await t.resize(const Size(80, 24));
      expect(commandRows(), [
        '   ⎿  \$ sleep 1; echo "ERROR [router] POST /login 500: Cannot read properties',
        '      of undefined (reading \'trim\')"; echo "    at validate',
        '      (src/routes/login.tsx:41:22)"; sleep 600',
        '      m1 · times out after 10m',
      ]);
      await t.resize(const Size(120, 40));
      expect(commandRows(), wide);
    }, skip: fakeAgentSkip);
  });
}
