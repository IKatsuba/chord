import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:test/test.dart';

String rowText(SelectionRow row) {
  final cells = <int, String>{};
  for (final cell in row.glyphs) {
    cells[cell.x] = cell.glyph.text;
  }
  return [
    for (
      var x = 0;
      x <
          (cells.keys.isEmpty
              ? 0
              : cells.keys.reduce((a, b) => a > b ? a : b) + 1);
      x++
    )
      cells[x] ?? ' ',
  ].join();
}

void main() {
  test(
    'closed code controls set minimum width and leave source serialization exact',
    () {
      for (final (label, minimum) in [('', 10), ('ts', 15), ('console', 20)]) {
        final source = SelectionSource.markdown(
          id: label,
          revision: 0,
          text: '```$label\nx\n```',
          copyCodeBlocks: true,
        );
        final shape = shapeSelectionSource(source, width: 80);
        expect(shape.width, minimum);
        expect(rowText(shape.rows.first), contains('─[copy]─┐'));
        expect(shape.selectedText, 'x');
        final narrow = shapeSelectionSource(source, width: minimum - 1);
        expect(narrow.rows.map(rowText).join(), isNot(contains('[copy]')));
      }
    },
  );
  test(
    'open and quoted code never acquire controls or control minimum width',
    () {
      for (final text in ['```\nx', '> ```\n> x\n> ```']) {
        final source = SelectionSource.markdown(
          id: text,
          revision: 0,
          text: text,
          copyCodeBlocks: true,
        );
        final shape = shapeSelectionSource(source, width: 80);
        expect(shape.rows.map(rowText).join(), isNot(contains('[copy]')));
        final ordinary = SelectionSource.markdown(
          id: text,
          revision: 0,
          text: text,
        );
        expect(shape.width, shapeSelectionSource(ordinary, width: 80).width);
      }
    },
  );
  test('controls never alter source code blank lines or tabs', () {
    final source = SelectionSource.markdown(
      id: 'code',
      revision: 0,
      text: '```\n\tfirst\n\nlast\n```',
      copyCodeBlocks: true,
    );
    final shape = shapeSelectionSource(source, width: 80);
    expect(shape.rows.map(rowText).join(), contains('[copy]'));
    expect(shape.selectedText, '\tfirst\n\nlast');
    expect(source.codeBlocks.single.text, '\tfirst\n\nlast');
  });
  test(
    'button rectangles follow list/group insets and disabled context omits them',
    () {
      final markdown = SelectionSource.markdown(
        id: 'nested',
        revision: 0,
        text: '- ```ts\n  x\n  ```',
        copyCodeBlocks: true,
      );
      final group = SelectionSource.group(
        id: 'group',
        revision: 0,
        children: [SelectionSourceChild(source: markdown, insetLeft: 3)],
      );
      final shape = shapeSelectionSource(group, width: 80);
      expect(shape.codeButtons.values.single, const Rect(12, 0, 6, 1));
      expect(shape.selectedText, 'x');
      final disabled = SelectionSource.group(
        id: 'disabled',
        revision: 0,
        children: [
          SelectionSourceChild(
            source: markdown,
            insetLeft: 3,
            selectable: false,
          ),
        ],
      );
      final omitted = shapeSelectionSource(disabled, width: 80);
      expect(
        omitted.rows.map(rowText).toList(),
        shape.rows.map(rowText).toList(),
      );
      expect(omitted.codeButtons, isEmpty);
      expect(omitted.codeBounds, isEmpty);
      expect(omitted.selectedText, isEmpty);
    },
  );
  test('picked quoted code changes only its own rendered frame style', () {
    final source = SelectionSource.markdown(
      id: 'quote',
      revision: 0,
      text: '> ```ts\n> x\n> ```',
      copyCodeBlocks: true,
    );
    final theme = ThemeData.dark();
    final plain = shapeSelectionSource(source, width: 80, theme: theme);
    final picked = shapeSelectionSource(
      source,
      width: 80,
      theme: theme,
      selectedCodeBlock: source.codeBlocks.single.id,
    );
    expect(
      picked.rows.first.glyphs.where((g) => g.x == 0).last.glyph.style,
      theme.dim,
    );
    expect(
      picked.rows.first.glyphs.where((g) => g.x == 2).last.glyph.style,
      theme.accent,
    );
    expect(picked.selectedText, plain.selectedText);
    expect(picked.codeButtons, isEmpty);
  });
}
