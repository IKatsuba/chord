// The note a resumed session's past closes with, naming the monitors it
// left running, as ../chord's Transcript.tsx draws `monitors_left`: a dim ⏺
// beside a dim line, after a gap.
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the monitors left running are a dim ⏺ beside a dim line at '
        '$size', (t) async {
      await t.pumpWidget(
        const TranscriptEntry(
          model.MonitorsLeftEntry('history-monitors', [
            (id: 'm1', description: 'dev server errors'),
            (id: 'm2', description: 'CI run 4812'),
          ]),
        ),
        size: Size(size.width - 2, size.height),
      );
      final rows = [for (final row in t.screen.lines) row.trimRight()];
      expect(rows[0], '');
      final note = rows.skip(1).takeWhile((row) => row.isNotEmpty).toList();
      expect(note.first, startsWith('⏺ dev server errors and CI run 4812'));
      expect(note.skip(1).every((row) => row.startsWith('  ')), isTrue);
      expect(
        note.map((row) => row.substring(2).trim()).join(' '),
        'dev server errors and CI run 4812 were running when this session '
        'was left and are not restarted',
      );
      expect(t.screen.styleAt(0, 1).isDim, isTrue);
      expect(t.screen.styleAt(2, 1).isDim, isTrue);
    });
  }
}
