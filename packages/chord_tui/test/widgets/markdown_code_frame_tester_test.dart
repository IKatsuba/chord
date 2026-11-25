import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart'
    show shapeSelectionSource;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester U4 framed-code boundaries', () {
    for (final size in [const Size(80, 24), const Size(120, 40)]) {
      testWidgets(
        'zero and narrow frames never paint into a sibling at $size',
        (t) async {
          for (var width = 0; width <= 8; width++) {
            await t.pumpWidget(
              Row(
                children: [
                  SizedBox(
                    width: width,
                    child: Markdown('```sh\n界👩‍💻e\u0301\n```'),
                  ),
                  Text('|'),
                ],
              ),
              size: size,
            );
            expect(t.screen.charAt(width, 0), '|', reason: 'width $width');
            for (var y = 0; y < size.height; y++) {
              for (var x = width + 1; x < size.width; x++) {
                expect(t.screen.charAt(x, y), ' ', reason: '$width: $x,$y');
              }
            }
          }
        },
      );
      testWidgets('character cuts preserve each grapheme and copy at $size', (
        t,
      ) async {
        for (final cluster in ['界', '👩‍💻', 'e\u0301']) {
          for (var edge = 0; edge <= 4; edge++) {
            final width = 4 + edge + graphemeWidth(cluster);
            final code = '${'x' * edge}${cluster}z';
            final source = SelectionSource.markdown(
              id: 'frame',
              revision: 0,
              text: '```\n$code\n```',
            );
            await t.pumpWidget(
              Row(
                children: [
                  SizedBox(
                    width: width,
                    child: Markdown.fromSelectionSource(source),
                  ),
                ],
              ),
              size: size,
            );
            expect(t.screen.charAt(2 + edge, 1), cluster);
            expect(t.screen.charAt(2, 2), 'z');
            expect(t.screen.text, isNot(contains('↪')));
            expect(
              shapeSelectionSource(source, width: width).selectedText,
              code,
            );
          }
        }
      });
    }
    testWidgets('a resized framed block recovers its complete wide layout', (
      t,
    ) async {
      final source = SelectionSource.markdown(
        id: 'frame',
        revision: 0,
        text: '```sh\n${'alpha beta ' * 12}界👩‍💻e\u0301\n```',
        copyCodeBlocks: true,
      );
      await t.pumpWidget(
        Markdown.fromSelectionSource(source, onCopyCodeBlock: (_) {}),
        size: const Size(120, 40),
      );
      final wide = t.screen.buffer.lines;
      await t.resize(const Size(80, 24));
      expect(t.screen.lines.first, startsWith('┌─ sh '));
      expect(t.screen.text, isNot(contains('↪')));
      await t.resize(const Size(0, 0));
      expect(t.screen.text, isEmpty);
      await t.resize(const Size(1, 1));
      await t.resize(const Size(120, 40));
      expect(t.screen.buffer.lines, wide);
    });
  });
}
