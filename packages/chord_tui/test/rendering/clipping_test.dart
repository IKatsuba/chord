import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

/// A canvas that counts the cells asked of it, clipped copies included.
class CountingCanvas extends Canvas {
  CountingCanvas(super.buffer, [super.clip, List<int>? count])
    : count = count ?? [0];

  final List<int> count;

  @override
  Canvas clipped(Rect r) => CountingCanvas(buffer, clip.intersect(r), count);

  @override
  void put(int x, int y, String g, int w, Style style) {
    count[0]++;
    super.put(x, y, g, w, style);
  }
}

/// A box of [rows] that counts its paints.
class CountingBox extends RenderBox {
  CountingBox(this.rows);

  final int rows;
  var paints = 0;

  @override
  void performLayout() => size = Size(constraints.maxWidth, rows);

  @override
  void paint(Canvas canvas, Offset origin) {
    paints++;
    canvas.drawText(origin.x, origin.y, 'box $rows');
  }
}

/// [lines] numbered lines, laid out at [width].
RenderParagraph paragraph(int lines, {int width = 20}) {
  final p = RenderParagraph(
    TextSpan([for (var i = 0; i < lines; i++) 'line $i'].join('\n')),
  );
  p.layout(BoxConstraints(maxWidth: width));
  return p;
}

void main() {
  test('a paragraph cut by the clip paints only the lines inside it', () {
    final p = paragraph(5000);
    final buffer = Buffer(20, 40);
    final canvas = CountingCanvas(buffer, const Rect(0, 0, 20, 3));
    // The paragraph starts 100 rows above the clip.
    p.paint(canvas, const Offset(0, -100));
    expect(buffer.lines.take(4).map((l) => l.trimRight()), [
      'line 100',
      'line 101',
      'line 102',
      '',
    ]);
    expect(canvas.count[0], 24);
  });

  test('clipped paint shows what unclipped paint shows inside the clip', () {
    final p = paragraph(30);
    final whole = Buffer(20, 40);
    p.paint(Canvas(whole), const Offset(0, -5));
    final cut = Buffer(20, 40);
    p.paint(Canvas(cut, const Rect(0, 2, 20, 7)), const Offset(0, -5));
    for (var y = 0; y < 40; y++) {
      expect(cut.line(y), y >= 2 && y < 9 ? whole.line(y) : ' ' * 20);
    }
  });

  test('a line wider than the clip stops at its right edge', () {
    final p = RenderParagraph(TextSpan('x' * 500));
    p.layout(const BoxConstraints(maxWidth: 500));
    final buffer = Buffer(10, 1);
    final canvas = CountingCanvas(buffer);
    p.paint(canvas, Offset.zero);
    expect(buffer.line(0), 'x' * 10);
    expect(canvas.count[0], 10);
  });

  test('a column skips children outside the clip, and paints the rest', () {
    final boxes = [for (var i = 0; i < 10; i++) CountingBox(3)];
    final column = RenderFlex(direction: Axis.vertical)..children = boxes;
    column.layout(const BoxConstraints(maxWidth: 20, maxHeight: 30));
    final buffer = Buffer(20, 30);
    column.paint(Canvas(buffer, const Rect(0, 10, 20, 5)), Offset.zero);
    expect([for (final b in boxes) b.paints], [0, 0, 0, 1, 1, 0, 0, 0, 0, 0]);
    expect(buffer.line(12).trimRight(), 'box 3');

    final whole = Buffer(20, 30);
    column.paint(Canvas(whole), Offset.zero);
    expect(whole.line(12), buffer.line(12));
    expect([for (final b in boxes) b.paints], [1, 1, 1, 2, 2, 1, 1, 1, 1, 1]);
  });
  group('tester: grapheme clip edges', () {
    for (final size in [const Size(80, 24), const Size(120, 40)]) {
      test('wide graphemes and combining marks at every edge of $size', () {
        for (final glyph in ['界', '🙂', '👩‍💻', 'é']) {
          final width = cellWidth(glyph);
          final p = RenderParagraph(TextSpan(glyph));
          p.layout(BoxConstraints(maxWidth: size.width));
          for (final origin in [
            const Offset(-1, 0),
            Offset(size.width - 1, 0),
            const Offset(0, -1),
            Offset(0, size.height - 1),
          ]) {
            final b = Buffer(size.width, size.height);
            p.paint(Canvas(b), origin);
            final fits =
                origin.x >= 0 &&
                origin.y >= 0 &&
                origin.x + width <= size.width;
            expect(
              b.toString().contains(glyph),
              fits,
              reason: '$glyph at $origin',
            );
            if (fits && width == 2) {
              expect(b.charAt(origin.x + 1, origin.y), '');
            }
          }
        }
      });

      test(
        'ANSI spans clipped on both row edges retain text and style at $size',
        () {
          final p = RenderParagraph(
            parseAnsi('\x1b[31mhidden\n界é🙂\nvisible\nhidden\x1b[0m'),
          );
          p.layout(BoxConstraints(maxWidth: size.width));
          final b = Buffer(size.width, size.height);
          p.paint(Canvas(b, Rect(0, 0, size.width, 2)), const Offset(0, -1));
          expect(b.line(0).trimRight(), '界é🙂');
          expect(b.line(1).trimRight(), 'visible');
          expect(b.line(2).trimRight(), '');
          expect(b.toString().contains('hidden'), isFalse);
          expect(b.toString().contains('\x1b'), isFalse);
          expect(b.styleAt(0, 0).fg, isNotNull);
        },
      );
    }

    test('zero area and one-cell clips never paint half a wide grapheme', () {
      final p = RenderParagraph(const TextSpan('界'));
      p.layout(const BoxConstraints(maxWidth: 2));
      for (final clip in [
        const Rect(0, 0, 0, 1),
        const Rect(0, 0, 2, 0),
        const Rect(0, 0, 1, 1),
        const Rect(1, 0, 1, 1),
      ]) {
        final b = Buffer(2, 1);
        p.paint(Canvas(b, clip), Offset.zero);
        expect(b.line(0), '  ');
      }
    });
  });
}
