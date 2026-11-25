import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  _testerReportLabelBoundaries();
  for (final size in const [Size(120, 40), Size(80, 24), Size(32, 10)]) {
    testWidgets(
      'unlabeled reports start after the existing result gutter $size',
      (t) async {
        const report = model.ReportEntry('resume', 'resume', [
          (label: '', text: 'No earlier session 界😀'),
          (label: 'Agent:', text: 'fake'),
          (label: '', text: 'Unlabeled continuation'),
        ]);
        List<String>? drawn;
        for (final selectable in [false, true]) {
          final source = entrySelectionSource(
            report,
            id: 'report',
            revision: 1,
            width: size.width,
          );
          await t.pumpWidget(
            TranscriptEntry(
              report,
              selectionSource: selectable ? source : null,
            ),
            size: size,
          );
          final rows = t.screen.lines;
          expect(rows[2].indexOf('⎿'), 2);
          expect(rows[2].indexOf('No earlier'), 5);
          expect(rows[3].indexOf('Agent:'), 5);
          expect(rows[3].indexOf('fake'), 12);
          expect(rows[4].indexOf('Unlabeled'), 5);
          if (drawn != null) expect(rows, drawn);
          drawn = List.of(rows);
        }
      },
    );
  }
}

void _testerReportLabelBoundaries() {
  group('tester: U52d exact empty-label boundary', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'empty labels omit the column while a space label retains it at $size',
        (t) async {
          const report = model.ReportEntry('report', 'report', [
            (label: 'LongLabel:', text: 'Labeled'),
            (label: '', text: 'Unlabeled'),
            (label: ' ', text: 'SpaceLabel'),
            (label: '', text: 'After'),
          ]);
          for (final bound in [false, true]) {
            final source = entrySelectionSource(
              report,
              id: 'tester-report',
              revision: 1,
              width: size.width,
            );
            await t.pumpWidget(
              TranscriptEntry(report, selectionSource: bound ? source : null),
              size: size,
            );
            expect(t.screen.lines[2].indexOf('Labeled'), 16);
            expect(t.screen.lines[3].indexOf('Unlabeled'), 5);
            expect(t.screen.lines[4].indexOf('SpaceLabel'), 16);
            expect(t.screen.lines[5].indexOf('After'), 5);
          }
        },
      );
    }
  });
}
