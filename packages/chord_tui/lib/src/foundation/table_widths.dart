/// How a table column takes its width, in cells of content.
sealed class TableColumnWidth {
  const TableColumnWidth();
}

/// A column [value] cells wide.
class FixedColumnWidth extends TableColumnWidth {
  /// A column of [value] cells.
  const FixedColumnWidth(this.value) : assert(value >= 0);

  /// Its width.
  final int value;
}

/// A column as wide as its widest cell laid out with no width limit, but
/// no wider than [maxWidth].
class IntrinsicColumnWidth extends TableColumnWidth {
  /// A column as wide as its cells, up to [maxWidth].
  const IntrinsicColumnWidth({this.maxWidth})
    : assert(maxWidth == null || maxWidth >= 0);

  /// The cap, if any.
  final int? maxWidth;
}

/// A share, weighted by [value], of the width the other columns leave.
class FlexColumnWidth extends TableColumnWidth {
  /// A share of weight [value].
  const FlexColumnWidth([this.value = 1])
    : assert(value > 0 && value < double.infinity, 'A finite weight.');

  /// Its weight.
  final double value;
}

/// The content widths of a table's columns.
///
/// [natural] is each column's widest cell at no width limit, used by
/// intrinsic columns and, when [available] is null (no limit), by flex
/// ones. [furniture] is what gaps and borders take. Fixed and intrinsic
/// widths come first; flex columns share what is left by weight, the
/// cells left over by rounding going one each in column order, and get
/// nothing when nothing is left.
List<int> solveColumnWidths({
  required List<TableColumnWidth> specs,
  required List<int> natural,
  required int? available,
  int furniture = 0,
}) {
  final widths = List.filled(specs.length, 0);
  var used = furniture;
  var heaviest = 0.0;
  for (final s in specs) {
    if (s is FlexColumnWidth && s.value > heaviest) heaviest = s.value;
  }
  // Weights over the heaviest are at most 1, so neither their sum nor a
  // share of the room can overflow, however large the weights are.
  var weights = 0.0;
  for (final (i, s) in specs.indexed) {
    switch (s) {
      case FixedColumnWidth(:final value):
        widths[i] = value;
      case IntrinsicColumnWidth(:final maxWidth):
        final n = natural[i];
        widths[i] = maxWidth != null && n > maxWidth ? maxWidth : n;
      case FlexColumnWidth(:final value):
        if (available == null) widths[i] = natural[i];
        weights += value / heaviest;
        continue;
    }
    used += widths[i];
  }
  if (available == null || weights == 0) return widths;
  final left = available - used;
  if (left <= 0) return widths;
  var given = 0;
  for (final (i, s) in specs.indexed) {
    if (s is FlexColumnWidth) {
      widths[i] = (left * (s.value / heaviest / weights)).floor();
      given += widths[i];
    }
  }
  for (final (i, s) in specs.indexed) {
    if (given >= left) break;
    if (s is FlexColumnWidth) {
      widths[i]++;
      given++;
    }
  }
  return widths;
}
