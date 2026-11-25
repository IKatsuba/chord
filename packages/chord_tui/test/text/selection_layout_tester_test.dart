import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:test/test.dart';

void main() {
  group('tester: semantic draft maps and exposed projection boundaries', () {
    for (final width in [1, 2, 3, 4, 7, 80, 120]) {
      test(
        'draft preserves exposed units, logical newlines and controller at width $width',
        () {
          final raw = width >= 80
              ? '\x1b[31mAe\u0301\x1b[0m\n\n\t👩‍💻界\n'
              : 'Ae\u0301\n\n\t👩‍💻界\n';
          final controller = TextAreaController(text: raw);
          final cursor = controller.cursor;
          final layout = controller.layout(width: width, maxHeight: 1);
          final shape = shapeTextAreaSelection(
            id: controller,
            text: raw,
            layout: layout,
          );
          expect(
            shape.selectedText,
            width == 1 ? 'Ae\u0301\n\n\t\n' : 'Ae\u0301\n\n\t👩‍💻界\n',
          );
          expect(shape.rows.where((r) => r.hardBreak != null), hasLength(3));
          for (final row in shape.rows) {
            for (final cell in row.glyphs) {
              if (cell.sourceId == null ||
                  cell.x + cell.glyph.width > layout.width) {
                continue;
              }
              final unit = shape.fragments.single.extract(
                cell.offset!,
                cell.offset! + 1,
              );
              if (unit == '\t') continue;
              expect(
                unit,
                cell.glyph.text,
                reason: 'width $width, offset ${cell.offset}',
              );
            }
          }
          expect(controller.text, raw);
          expect(controller.cursor, cursor);
          expect(controller.lastLayout, same(layout));
          controller.dispose();
        },
      );
    }

    // The original stripper consumes a row ending in ESC [ 3 as a related
    // escape; the next row's literal tail remains. Whole-text cleanup is red.
    for (final (width, expected) in [(2, '1mred[0m'), (7, 'red[0m')]) {
      test(
        'split ANSI draft copies actual exposed CSI tails at width $width',
        () {
          const raw = '\x1b[31mred\x1b[0m';
          final controller = TextAreaController(text: raw);
          final layout = controller.layout(width: width, maxHeight: 1);
          final shape = shapeTextAreaSelection(
            id: controller,
            text: raw,
            layout: layout,
          );
          expect(shape.selectedText, expected);
          for (final row in shape.rows) {
            for (final cell in row.glyphs) {
              expect(
                shape.fragments.single.extract(cell.offset!, cell.offset! + 1),
                cell.glyph.text,
              );
            }
          }
          expect(controller.text, raw);
          expect(controller.lastLayout, same(layout));
          controller.dispose();
        },
      );
    }

    test('nested mutable style spans cannot alter an existing source', () {
      final nested = <TextSpan>[const TextSpan('e', style: Style.bold)];
      final outer = <TextSpan>[
        TextSpan('', children: nested),
        const TextSpan('\u0301界'),
      ];
      final source = SelectionSource.text(
        id: 'text',
        revision: 0,
        text: TextSpan('', children: outer),
      );
      nested.add(const TextSpan('bad'));
      outer.clear();
      final shape = shapeSelectionSource(source, width: 80);
      expect(shape.selectedText, 'e\u0301界');
      expect(shape.rows.single.glyphs.map((g) => g.glyph.text), [
        'e\u0301',
        '界',
      ]);
      expect(shape.rows.single.glyphs.first.glyph.style.isBold, isTrue);
    });

    for (final width in [80, 120]) {
      test(
        'middle clipping exposes neither omitted bytes nor synthetic ellipsis $width',
        () {
          final source = SelectionSource.text(
            id: 'text',
            revision: 0,
            text: TextSpan('👩‍💻${'x' * width}界\nhidden'),
            softWrap: false,
            overflow: TextOverflow.middle,
            maxLines: 1,
          );
          final shape = shapeSelectionSource(source, width: width);
          final fragment = shape.fragments.single;
          expect(fragment.ranges, hasLength(2));
          expect(fragment.extract(0, fragment.length), shape.selectedText);
          expect(shape.selectedText, startsWith('👩‍💻'));
          expect(shape.selectedText, endsWith('界'));
          expect(shape.selectedText, isNot(contains('...')));
          expect(shape.selectedText, isNot(contains('hidden')));
          expect(
            shape.rows.single.glyphs.where((g) => g.sourceId == null),
            isNotEmpty,
          );
        },
      );
    }
  });
}
