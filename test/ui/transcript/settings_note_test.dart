import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'setting failure and success use original distinct result gutters at $size',
      (t) async {
        await t.pumpWidget(
          const TranscriptEntry(
            model.NotedEntry(
              'id',
              'config',
              'Could not set Effort to High: refused',
              failed: true,
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.take(3), [
          '',
          '› /config',
          '⏺ Could not set Effort to High: refused',
        ]);
        expect(t.screen.styleAt(0, 2).fg, ThemeData.dark().error.fg);
        await t.pumpWidget(
          const TranscriptEntry(
            model.NotedEntry('id', 'config', 'Effort set to High'),
          ),
          size: size,
        );
        expect(t.screen.lines.take(3), [
          '',
          '› /config',
          '  ⎿  Effort set to High',
        ]);
        expect(t.screen.styleAt(5, 2).fg, ThemeData.dark().dim.fg);
      },
    );
  }
}
