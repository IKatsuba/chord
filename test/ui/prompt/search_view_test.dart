import 'package:chord/ui/prompt/search_view.dart';
import 'package:chord/ui/prompt/search.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'whole-text hit crosses actual soft wrap without changing geometry $size',
      (t) async {
        // The editor's four furniture cells and border leave this exact raw row.
        final text = '${'x' * (size.width - 8)}ABCD 界😀';
        final reports = <TextAreaLayout>[];
        final query = ValueNotifier('ABCD');
        addTearDown(query.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: query,
            builder: (context) {
              return Column(
                children: [
                  SearchPrompt(
                    text: text,
                    cursor: text.length,
                    query: query.value,
                    windowRows: size.height,
                    bash: false,
                    onLayoutChanged: reports.add,
                  ),
                ],
              );
            },
          ),
          size: size,
        );
        expect(reports, isNotEmpty);
        final layout = reports.last;
        expect(layout.rows, hasLength(2));
        expect(layout.rows.first.text, endsWith('AB'));
        expect(layout.rows[1].text, startsWith('CD'));
        expect(t.screen.styleAt(size.width - 4, 2).isInverse, isTrue);
        expect(t.screen.styleAt(4, 3).isInverse, isTrue);
        expect(t.screen.buffer.cursor, isNull);
        final lines = List.of(t.screen.lines), notifications = reports.length;
        query.value = '界';
        await t.pump();
        expect(t.screen.lines, lines);
        expect(reports.length, notifications);
        expect(t.screen.styleAt(4, 3).isInverse, isFalse);
        await t.pump();
        expect(reports.length, notifications);
      },
    );
  }

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'middle CUT retains Unicode suffix and inverse cursor provenance $size',
      (t) async {
        await t.pumpWidget(
          SearchLine(search: Search(query: 'HEAD ${'needle ' * 40}TAIL界😀')),
          size: size,
        );
        final line = t.screen.lines[1];
        expect(line, startsWith('  search prompts: HEAD'));
        expect(line, contains('...'));
        expect(line, endsWith('TAIL界😀'));
        expect(t.screen.styleAt(2, 1).isDim, isTrue);
        final dot = line.indexOf('...');
        for (var x = dot; x < dot + 3; x++) {
          expect(t.screen.styleAt(x, 1).isInverse, isFalse);
        }
        expect(t.screen.styleAt(size.width - 3, 1).isInverse, isTrue);
        expect(t.screen.buffer.cursor, isNull);
      },
    );
    testWidgets('short query keeps original text and cursor cells $size', (
      t,
    ) async {
      await t.pumpWidget(
        const SearchLine(search: Search(query: 'alpha界😀')),
        size: size,
      );
      expect(t.screen.lines[1], '  search prompts: alpha界😀');
      final cursor = 2 + cellWidth('search prompts: alpha界😀');
      expect(t.screen.styleAt(cursor, 1).isInverse, isTrue);
      expect(t.screen.styleAt(2, 1).isDim, isTrue);
      expect(t.screen.buffer.cursor, isNull);
    });
  }
}
