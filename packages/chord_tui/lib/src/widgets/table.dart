import '../foundation/table_widths.dart';
import '../rendering/box.dart';
import '../rendering/table.dart';
import '../terminal/style.dart';
import 'framework.dart';
import 'theme.dart';

/// One row of a [Table]: a widget per column.
class TableRow {
  /// A row of [children]; a [key] keeps the row's cells, and their state,
  /// with it when rows move.
  const TableRow({this.key, required this.children});

  /// Tells the row apart across rebuilds.
  final Key? key;

  /// The cells, one per column.
  final List<Widget> children;
}

/// The lines around and between a [Table]'s cells.
class TableBorder {
  /// A single-line grid in [style], the theme's border when null.
  const TableBorder.all({this.style});

  /// The grid's style.
  final Style? style;
}

/// Widgets in rows and columns, as Flutter's Table: each row as tall as
/// its tallest cell, cells at the top left of theirs.
///
/// Columns take their widths from [columnWidths], or else
/// [defaultColumnWidth]; [columnGap] blank cells go between columns. A
/// cell wraps or cuts its own content; the table never slices it.
class Table extends StatelessWidget {
  /// A table of [children]; every row has as many cells as the first.
  Table({
    super.key,
    this.columnWidths,
    this.defaultColumnWidth = const FlexColumnWidth(),
    this.columnGap = 0,
    this.border,
    this.children = const [],
  }) {
    if (columnGap < 0) throw ArgumentError.value(columnGap, 'columnGap');
    for (final row in children) {
      if (row.children.length != children.first.children.length) {
        throw ArgumentError('Every row of a Table needs the same cells.');
      }
    }
  }

  /// Widths by column index.
  final Map<int, TableColumnWidth>? columnWidths;

  /// The width of a column [columnWidths] does not name.
  final TableColumnWidth defaultColumnWidth;

  /// Blank cells between two columns; use 0 with a [border].
  final int columnGap;

  /// A grid, or none.
  final TableBorder? border;

  /// The rows.
  final List<TableRow> children;

  @override
  Widget build(BuildContext context) {
    final columns = children.isEmpty ? 0 : children.first.children.length;
    final b = border;
    return _Grid(
      columns: columns,
      specs: [
        for (var i = 0; i < columns; i++)
          columnWidths?[i] ?? defaultColumnWidth,
      ],
      columnGap: columnGap,
      border: b == null ? null : (b.style ?? Theme.of(context).border),
      children: [
        for (final row in children)
          for (final (i, cell) in row.children.indexed)
            row.key == null ? cell : _Cell(_CellKey(row.key!, i), cell),
      ],
    );
  }
}

class _CellKey extends Key {
  const _CellKey(this.row, this.column);

  final Key row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is _CellKey && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

class _Cell extends StatelessWidget {
  const _Cell(Key key, this.child) : super(key: key);

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Grid extends MultiChildRenderObjectWidget {
  const _Grid({
    required this.columns,
    required this.specs,
    required this.columnGap,
    required this.border,
    super.children,
  });

  final int columns;
  final List<TableColumnWidth> specs;
  final int columnGap;
  final Style? border;

  @override
  RenderBox createRenderObject(BuildContext context) => RenderTable(
    columns: columns,
    specs: specs,
    columnGap: columnGap,
    border: border,
  );

  @override
  void updateRenderObject(BuildContext context, RenderTable r) {
    r
      ..columns = columns
      ..specs = specs
      ..columnGap = columnGap
      ..border = border;
  }
}
