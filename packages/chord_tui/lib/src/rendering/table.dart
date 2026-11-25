import '../foundation/geometry.dart';
import '../foundation/table_widths.dart';
import '../terminal/buffer.dart';
import '../terminal/style.dart';
import 'box.dart';

/// Cells in rows and columns, each row as tall as its tallest cell;
/// `Table` is the widget to use.
///
/// With [border], a single-line grid: one cell of edge and separator, one
/// cell of padding each side of a cell's content, no rule between rows.
class RenderTable extends RenderBox with RenderWithChildren {
  /// A table of [columns] columns, its cells row by row in [children].
  RenderTable({
    required this.columns,
    required this.specs,
    this.columnGap = 0,
    this.border,
  });

  /// How many columns there are.
  int columns;

  /// How each column takes its width.
  List<TableColumnWidth> specs;

  /// Blank cells between two columns.
  int columnGap;

  /// The grid's style, or null for no grid.
  Style? border;

  List<int> _widths = const [];
  List<int> _rowTops = const [];
  List<int> _rowHeights = const [];

  int get _rows => columns == 0 ? 0 : children.length ~/ columns;

  // Where column [i]'s content starts.
  int _left(int i) {
    var x = border == null ? 0 : 2;
    for (var k = 0; k < i; k++) {
      x += _widths[k] + (border == null ? columnGap : 3);
    }
    return x;
  }

  @override
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    final visible = clip.intersect(Rect.fromOffsetSize(origin, size));
    visitChildren((child) => visitor(child, origin + child.offset, visible));
  }

  @override
  bool hitTestSelf(Offset position) => border != null && _rowTops.isNotEmpty;

  @override
  void performLayout() {
    final grid = border != null;
    if (columns == 0 || children.isEmpty) {
      _widths = List.filled(columns, 0);
      _rowTops = _rowHeights = const [];
      size = constraints.constrain(Size.zero);
      return;
    }
    final furniture = grid ? 3 * columns + 1 : columnGap * (columns - 1);
    final bounded = constraints.hasBoundedWidth;
    final natural = List.filled(columns, 0);
    for (final (i, c) in children.indexed) {
      final col = i % columns;
      final s = specs[col];
      if (s is IntrinsicColumnWidth || (!bounded && s is FlexColumnWidth)) {
        // A measuring layout; the final one comes at the solved width.
        c.layout(const BoxConstraints());
        if (c.size.width > natural[col]) natural[col] = c.size.width;
      }
    }
    _widths = solveColumnWidths(
      specs: specs,
      natural: natural,
      available: bounded ? constraints.maxWidth : null,
      furniture: furniture,
    );
    final tops = <int>[], heights = <int>[];
    var y = grid ? 1 : 0;
    for (var r = 0; r < _rows; r++) {
      var height = 0;
      for (var col = 0; col < columns; col++) {
        final c = children[r * columns + col];
        final w = _widths[col];
        c.layout(BoxConstraints(minWidth: w, maxWidth: w));
        c.offset = Offset(_left(col), y);
        if (c.size.height > height) height = c.size.height;
      }
      tops.add(y);
      heights.add(height);
      y += height;
    }
    _rowTops = tops;
    _rowHeights = heights;
    final width = _widths.fold(furniture, (a, b) => a + b);
    size = constraints.constrain(Size(width, y + (grid ? 1 : 0)));
  }

  @override
  PaintCoverage describePaintCoverage(Rect localClip) {
    final clip = localClip.intersect(Rect.fromOffsetSize(Offset.zero, size));
    final rectangles = <Rect>[];
    if (border != null && _rowTops.isNotEmpty) {
      final bottom = _rowTops.last + _rowHeights.last;
      final right = _widths.fold(columns + 1, (a, w) => a + w + 2);
      rectangles.addAll([
        Rect(0, 0, right, 1).intersect(clip),
        Rect(0, bottom, right, 1).intersect(clip),
        Rect(0, 1, 1, bottom - 1).intersect(clip),
        for (var i = 0; i < columns; i++)
          Rect(_left(i) + _widths[i] + 1, 1, 1, bottom - 1).intersect(clip),
      ]);
    }
    return PaintCoverage(
      declaredFor: RenderTable,
      afterChildren: rectangles.where((r) => !r.isEmpty).toList(),
    );
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    final clip = canvas.clipped(Rect.fromOffsetSize(origin, size));
    paintChildren(canvas, origin);
    final style = border;
    if (style == null || _rowTops.isEmpty) return;
    void rule(int y, String left, String middle, String right) {
      var x = origin.x;
      clip.drawText(x++, y, left, style);
      for (var i = 0; i < columns; i++) {
        if (i > 0) clip.drawText(x++, y, middle, style);
        clip.drawText(x, y, '─' * (_widths[i] + 2), style);
        x += _widths[i] + 2;
      }
      clip.drawText(x, y, right, style);
    }

    final bottom = _rowTops.last + _rowHeights.last;
    rule(origin.y, '┌', '┬', '┐');
    for (var y = 1; y < bottom; y++) {
      clip.drawText(origin.x, origin.y + y, '│', style);
      for (var i = 0; i < columns; i++) {
        clip.drawText(
          origin.x + _left(i) + _widths[i] + 1,
          origin.y + y,
          '│',
          style,
        );
      }
    }
    rule(origin.y + bottom, '└', '┴', '┘');
  }
}
