/// Moving a selection through cards laid out in rows: plain arithmetic for
/// the gallery's grid and the install cards.
library;

/// The arrow keys a grid moves by.
enum GridStep {
  /// One card back on its row.
  left,

  /// One card on along its row.
  right,

  /// The card above.
  up,

  /// The card below.
  down,
}

/// The card [step] moves to from [index], among [count] cards [columns] to a
/// row; a step off an edge stays put, and down onto a short last row stops
/// at its last card.
int gridMove(
  int index, {
  required int count,
  required int columns,
  required GridStep step,
}) {
  if (count <= 0) return 0;
  final column = index % columns;
  final to = switch (step) {
    GridStep.left => column > 0 ? index - 1 : index,
    GridStep.right => column < columns - 1 ? index + 1 : index,
    GridStep.up => index - columns,
    GridStep.down => index + columns,
  };
  if (to < 0) return index;
  if (to >= count) {
    // Down onto a short last row lands on its last card; right stays.
    final lastRow = (count - 1) ~/ columns;
    return step == GridStep.down && index ~/ columns < lastRow
        ? count - 1
        : index;
  }
  return to;
}
