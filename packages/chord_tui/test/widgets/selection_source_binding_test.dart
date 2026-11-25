import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/foundation/selection_source.dart';
import 'package:chord_tui/src/rendering/selection_content.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'bound constructors reject wrong kinds and conflicting frozen geometry',
    () {
      final text = SelectionSource.text(
        id: 'text',
        revision: 0,
        text: const TextSpan('text'),
        maxLines: 2,
      );
      final code = SelectionSource.code(
        id: 'code',
        revision: 0,
        text: 'code',
        lineNumbers: true,
        softWrap: false,
      );
      final markdown = SelectionSource.markdown(
        id: 'md',
        revision: 0,
        text: 'text',
      );
      final diff = SelectionSource.diff(
        id: 'diff',
        revision: 0,
        view: diffTexts('a', 'b').view(),
        title: 'file.ts',
        showTitle: false,
      );
      expect(() => Text.fromSelectionSource(code), throwsArgumentError);
      expect(() => Code.fromSelectionSource(text), throwsArgumentError);
      expect(() => Markdown.fromSelectionSource(diff), throwsArgumentError);
      expect(() => Diff.fromSelectionSource(markdown), throwsArgumentError);
      expect(
        () => Text.fromSelectionSource(text, maxLines: 1),
        throwsArgumentError,
      );
      expect(
        () => Text.fromSelectionSource(text, align: TextAlign.right),
        throwsArgumentError,
      );
      expect(
        () => Text.fromSelectionSource(text, softWrap: false),
        throwsArgumentError,
      );
      expect(
        () => Code.fromSelectionSource(code, lineNumbers: false),
        throwsArgumentError,
      );
      expect(
        () => Code.fromSelectionSource(code, softWrap: true),
        throwsArgumentError,
      );
      expect(
        () => Diff.fromSelectionSource(diff, title: 'other.ts'),
        throwsArgumentError,
      );
      expect(
        () => Diff.fromSelectionSource(diff, showTitle: true),
        throwsArgumentError,
      );
      expect(
        () => Markdown.fromSelectionSource(markdown, onCopyCodeBlock: (_) {}),
        throwsArgumentError,
      );
      final actions = SelectionSource.markdown(
        id: 'actions',
        revision: 0,
        text: '```\na\n```',
        copyCodeBlocks: true,
      );
      expect(() => Markdown.fromSelectionSource(actions), throwsArgumentError);
    },
  );
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'bound text uses frozen geometry while ordinary text inherits at $size',
      (t) async {
        final source = SelectionSource.text(
          id: 'text',
          revision: 0,
          text: const TextSpan('first\nsecond'),
        );
        await t.pumpWidget(
          DefaultTextStyle(
            style: Style.bold,
            maxLines: 1,
            softWrap: false,
            child: Column(
              children: [
                Text.fromSelectionSource(source),
                Text('third\nfourth'),
              ],
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.take(3), ['first', 'second', 'third']);
        expect(t.screen.styleAt(0, 0).isBold, isTrue);
      },
    );
    testWidgets('bound rich widgets draw the exact offscreen shape at $size', (
      t,
    ) async {
      for (final source in [
        SelectionSource.code(
          id: 'code',
          revision: 0,
          text: '\techo 👩‍💻\n\nend',
          lineNumbers: true,
        ),
        SelectionSource.markdown(
          id: 'md',
          revision: 0,
          text: 'Text **bold**\n\n> - nested\n\n```ts\nconst a = 1;\n```',
        ),
        SelectionSource.diff(
          id: 'diff',
          revision: 0,
          view: diffTexts('old\nend', 'new\nend').view(),
          title: 'file.ts',
        ),
      ]) {
        final widget = switch (selectionSourceKind(source)) {
          SelectionSourceKind.code => Code.fromSelectionSource(source),
          SelectionSourceKind.markdown => Markdown.fromSelectionSource(source),
          _ => Diff.fromSelectionSource(source),
        };
        await t.pumpWidget(
          Theme(data: ThemeData.plain(), child: widget),
          size: size,
        );
        final shape = shapeSelectionSource(source, width: size.width);
        for (var y = 0; y < shape.height && y < size.height; y++) {
          final exposed = <int, String>{};
          for (final cell in shape.rows[y].glyphs) {
            if (cell.x >= 0 && cell.x + cell.glyph.width <= size.width) {
              exposed[cell.x] = cell.glyph.text;
            }
          }
          for (final entry in exposed.entries) {
            expect(t.screen.charAt(entry.key, y), entry.value);
          }
        }
        final render = RenderObjectElement.firstRenderObject(
          t.host.rootElement,
        );
        expect(render, isA<RenderSelectionContent>());
        final firstShape = (render as RenderSelectionContent).projection;
        await t.pump();
        expect(render.projection, same(firstShape));
      }
    });
  }
}
