import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/text_area_span.dart';
import 'package:test/test.dart';

void main() {
  _testerSpanUnitBoundaries();
  test('full text must remain exact, including normalization and controls', () {
    for (final replacement in ['changed', 'text\n', 'tex', 'te\u0301xt']) {
      expect(
        () => TextAreaSpanStyles('text', TextSpan(replacement)),
        throwsArgumentError,
      );
    }
    final empty = TextAreaSpanStyles('', const TextSpan(''));
    final controller = TextAreaController();
    final row = controller.layout(width: 5, maxHeight: 1).rows.single;
    expect(empty.rowSpan(row).toPlainText(), '');
    controller.dispose();
  });

  test(
    'styles resolve at raw grapheme starts across UTF16 and nested runs',
    () {
      const text = 'e\u0301👩\u200d💻界Z';
      final source = TextSpan(
        '',
        style: Style.bold,
        children: [
          const TextSpan('e', style: Style(fg: Colors.red)),
          const TextSpan('\u0301👩', style: Style.inverse),
          const TextSpan('\u200d💻界', style: Style(fg: Colors.blue)),
          const TextSpan('Z'),
        ],
      );
      final projection = TextAreaSpanStyles(text, source, base: Style.dim);
      final controller = TextAreaController(text: text);
      final rows = controller.layout(width: 3, maxHeight: 10).rows;
      final runs = [
        for (final row in rows) ...projection.rowSpan(row).flatten(),
      ];
      expect(runs.map((run) => run.$1).join(), text);
      expect(runs.map((run) => run.$1), ['e\u0301', '👩\u200d💻', '界', 'Z']);
      expect(runs[0].$2.fg, Colors.red);
      expect(runs[0].$2.isInverse, isFalse);
      expect(runs[1].$2.isInverse, isTrue);
      expect(runs[1].$2.fg, isNull);
      expect(runs[2].$2.fg, Colors.blue);
      for (final run in runs) {
        expect(run.$2.isBold, isTrue);
        expect(run.$2.isDim, isTrue);
      }
      controller.dispose();
    },
  );

  test('raw LF tabs ANSI and controls retain exact actual-row text', () {
    const text = 'ab\tcd\n\x1b[31mred\x1b[0m\u0001end';
    final children = [
      const TextSpan('ab\tc', style: Style.inverse),
      const TextSpan('d\n\x1b[3', style: Style.bold),
      const TextSpan('1mred\x1b[0m\u0001end', style: Style.italic),
    ];
    final projection = TextAreaSpanStyles(
      text,
      TextSpan('', children: children),
    );
    children.clear();
    final controller = TextAreaController(text: text);
    for (final width in [0, 1, 4, 8, 80]) {
      final layout = controller.layout(width: width, maxHeight: 20);
      for (final row in layout.rows) {
        expect(projection.rowSpan(row).toPlainText(), row.text);
      }
    }
    controller.dispose();
  });

  test(
    'whole-text cross-wrap styling retains exact-width empty cursor rows',
    () {
      const text = 'abcneedleXYZ';
      final projection = TextAreaSpanStyles(
        text,
        const TextSpan(
          '',
          children: [
            TextSpan('abc'),
            TextSpan('needle', style: Style.inverse),
            TextSpan('XYZ'),
          ],
        ),
      );
      final controller = TextAreaController(text: text);
      final layout = controller.layout(width: 4, maxHeight: 10);
      expect(layout.rows.last.text, '');
      expect(layout.cursorColumn, 0);
      expect(projection.rowSpan(layout.rows.last).toPlainText(), '');
      final hits = [
        for (final row in layout.rows)
          for (final run in projection.rowSpan(row).flatten())
            if (run.$2.isInverse) run.$1,
      ];
      expect(hits.join(), 'needle');
      controller.dispose();
    },
  );
}

void _testerSpanUnitBoundaries() {
  group('tester: U27F every UTF16 split boundary', () {
    test(
      'all split positions style raw graphemes by their first code unit',
      () {
        const graphemes = ['é', '👩‍💻', '界', '🙂', 'Z'];
        final text = graphemes.join();
        final starts = <int>[];
        var offset = 0;
        for (final value in graphemes) {
          starts.add(offset);
          offset += value.length;
        }
        final controller = TextAreaController(text: text);
        for (var split = 1; split < text.length; split++) {
          final projection = TextAreaSpanStyles(
            text,
            TextSpan(
              '',
              children: [
                TextSpan(text.substring(0, split), style: Style.inverse),
                TextSpan(text.substring(split), style: Style.dim),
              ],
            ),
          );
          for (final width in [0, 1, 2, 3, 4, 8]) {
            for (final row
                in controller.layout(width: width, maxHeight: 20).rows) {
              final span = projection.rowSpan(row);
              expect(span.toPlainText(), row.text);
              final runs = span.flatten();
              expect(runs.length, row.end - row.start);
              for (var i = row.start; i < row.end; i++) {
                final run = runs[i - row.start];
                expect(run.$1, graphemes[i]);
                expect(run.$2.isInverse, starts[i] < split);
                expect(run.$2.isDim, starts[i] >= split);
              }
            }
          }
        }
        controller.dispose();
      },
    );
  });
}
