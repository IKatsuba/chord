// CTUI-85: where a part of a selection source starts among the rows its
// whole draws, so a scroll can put that part, not its whole, on top.
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart'
    show shapeSelectionSource;
import 'package:test/test.dart';

SelectionSource _text(Object id, String text) =>
    SelectionSource.text(id: id, revision: 0, text: TextSpan(text));

void main() {
  group('tester: target rows match shaped mixed content', () {
    final mixed = SelectionSource.group(
      id: 'mixed',
      revision: 0,
      children: [
        SelectionSourceChild(
          source: SelectionSource.text(
            id: 'prefix',
            revision: 0,
            text: parseAnsi('\x1b[31m界🙂e\u0301 wrapped words\x1b[0m'),
          ),
          insetLeft: 2,
          insetRight: 1,
        ),
        SelectionSourceChild(
          source: SelectionSource.code(
            id: 'code',
            revision: 0,
            text: 'one\ntwo\nthree',
            lineNumbers: true,
          ),
          insetLeft: 1,
          selectable: false,
        ),
        SelectionSourceChild(
          source: SelectionSource.group(
            id: 'nested',
            revision: 0,
            children: [
              SelectionSourceChild(
                source: _text('blank', ''),
                selectable: false,
              ),
              SelectionSourceChild(source: _text('target', '§')),
            ],
          ),
        ),
      ],
    );
    for (final width in [1, 4, 80, 120, unbounded]) {
      test(
        'finds the rendered marker after inset text and code at width $width',
        () {
          final shape = shapeSelectionSource(mixed, width: width);
          final row = shape.rows.indexWhere(
            (row) => row.glyphs.any((g) => g.glyph.text == '§'),
          );
          expect(row, greaterThanOrEqualTo(0));
          expect(
            selectionSourceRowOf(
              mixed,
              width: width,
              where: (id) => id == 'target',
            ),
            row,
          );
          expect(
            selectionSourceRowOf(
              mixed,
              width: width,
              where: (id) => id == 'missing',
            ),
            isNull,
          );
        },
      );
    }
    test('zero room still finds the root and excludes absent identities', () {
      expect(
        selectionSourceRowOf(mixed, width: 0, where: (id) => id == 'mixed'),
        0,
      );
      expect(
        selectionSourceRowOf(mixed, width: 0, where: (id) => id == 'missing'),
        isNull,
      );
    });
  });

  final inner = SelectionSource.group(
    id: 'inner',
    revision: 0,
    children: [
      SelectionSourceChild(source: _text('inner-gap', ''), selectable: false),
      SelectionSourceChild(source: _text('inner-head', 'inner head')),
    ],
  );
  final root = SelectionSource.group(
    id: 'root',
    revision: 0,
    children: [
      SelectionSourceChild(source: _text('gap', ''), selectable: false),
      SelectionSourceChild(
        source: _text('head', 'a long headline that wraps'),
        insetLeft: 2,
      ),
      SelectionSourceChild(source: _text('pad', '·'), selectable: false),
      SelectionSourceChild(source: inner, insetLeft: 5),
    ],
  );

  int? rowOf(Object id, int width) =>
      selectionSourceRowOf(root, width: width, where: (each) => each == id);

  test('a part starts under the rows its earlier siblings draw', () {
    expect(rowOf('root', 20), 0);
    expect(rowOf('gap', 20), 0);
    expect(rowOf('head', 20), 1);
    // The headline wraps to two rows at 18 cells beside its inset.
    expect(rowOf('pad', 20), 3);
    expect(rowOf('inner', 20), 4);
    expect(rowOf('inner-head', 20), 5);
  });

  test("a part's row follows the width its siblings wrap at", () {
    expect(rowOf('pad', 80), 2);
    expect(rowOf('inner-head', 80), 4);
  });

  test('a part the source does not hold has no row', () {
    expect(rowOf('nowhere', 20), isNull);
  });
}
