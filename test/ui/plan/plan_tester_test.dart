import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/ui/plan/plan.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester U4 finished plan', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'every step status stays ordered with independent styles at $size',
        (t) async {
          await t.pumpWidget(
            PlanRecord([
              for (final (status, text) in [
                ('completed', '\x1b[31m${'A' * 160} end👩‍💻e\u0301'),
                ('in_progress', 'working'),
                ('pending', 'waiting'),
                ('future_status', 'unknown'),
              ])
                acp.PlanEntry.fromJson({
                  'content': text,
                  'status': status,
                  'priority': 'medium',
                }),
            ]),
            size: size,
          );
          expect(t.screen.lines.take(2), ['', '⏺ Plan']);
          expect(t.screen.lines[2], startsWith('  ⎿  ☒ A'));
          expect(t.screen.lines[2], endsWith('end👩‍💻e\u0301'));
          expect(t.screen.lines[3], '     ◐ working');
          expect(t.screen.lines[4], '     ☐ waiting');
          expect(t.screen.lines[5], '     ☐ unknown');
          final at = t.screen.lines[2].indexOf('...');
          expect(at, greaterThan(7));
          for (var x = at; x < at + 3; x++) {
            expect(t.screen.styleAt(x, 2), ThemeData.dark().dim);
          }
          expect(t.screen.styleAt(7, 2).isStrikethrough, isTrue);
          expect(t.screen.styleAt(7, 3).isStrikethrough, isFalse);
          expect(t.screen.styleAt(7, 2).fg, const IndexedColor(1));
        },
      );
    }
  });
}
