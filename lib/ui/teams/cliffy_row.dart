/// One row as @cliffy/table 1.3.1 prints it with fixed column widths and no
/// border, as the original lays out a proposal's table and `/team show`'s
/// running table: a cell wraps at single spaces, a word wider than its
/// column is cut and carried on, and columns are joined by their padding.
/// Widths are the framework's `cellWidth` and graphemes stay whole, where
/// cliffy counts and cuts code points (the owner's choice, recorded in
/// `docs/decisions.md`): a ZWJ sequence is never cut after its joiner.
library;

import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart' show cellWidth;

/// A cell's text and how many columns it spans.
final class CliffyCell {
  /// A cell of [text] spanning [span] columns.
  const CliffyCell(this.text, {this.span = 1});

  final String text;
  final int span;
}

/// [cells] laid out in columns of [widths], [padding] spaces after each
/// cell that does not start in the last column: as many lines as its
/// longest cell takes, untrimmed.
List<String> cliffyRow(
  List<CliffyCell> cells,
  List<int> widths, {
  int padding = 2,
}) {
  // Each cell's start column and its width, its span's columns and the
  // paddings between them.
  final placed = <({int start, int width})>[];
  var column = 0;
  for (final cell in cells) {
    var width = widths[column];
    for (var o = 1; o < cell.span; o++) {
      width += widths[column + o] + padding;
    }
    placed.add((start: column, width: width));
    column += cell.span;
  }
  final rest = [for (final cell in cells) cell.text];
  final lines = <String>[];
  while (true) {
    final line = StringBuffer();
    var more = false;
    for (final (index, cell) in placed.indexed) {
      final (:current, :next) = _cellValue(rest[index], cell.width);
      rest[index] = next;
      line.write(current);
      if (cell.start < widths.length - 1) line.write(' ' * padding);
      if (next.isNotEmpty) more = true;
    }
    lines.add(line.toString());
    if (!more) return lines;
  }
}

// renderCellValue: one line of [text] in [maxLength] cells, and what is
// left of it.
({String current, String next}) _cellValue(String text, int maxLength) {
  if (maxLength <= 0) return (current: '', next: '');
  final length = math.min(maxLength, cellWidth(text));
  var words = _consumeWords(length, text);
  // A word wider than the column is cut, and nothing of it is dropped.
  final breakWord = cellWidth(words) > length;
  if (breakWord) words = _consumeGraphemes(length, words);
  final from = words.length + (breakWord ? 0 : 1);
  final next = from >= text.length ? '' : text.substring(from);
  // A grapheme wider than its column pads by nothing, where cliffy throws.
  final fill = math.max(0, maxLength - cellWidth(words));
  return (current: '$words${' ' * fill}', next: next);
}

// consumeWords: the first line's words while they fit in [length], at
// least one.
String _consumeWords(int length, String content) {
  final words = content.split('\n').first.split(' ');
  final consumed = StringBuffer();
  var consumedWidth = 0;
  for (final (index, word) in words.indexed) {
    final width = cellWidth(word);
    if (index > 0 && consumedWidth + width >= length) break;
    if (index > 0) consumed.write(' ');
    consumed.write(word);
    consumedWidth = cellWidth(consumed.toString());
  }
  return consumed.toString();
}

// consumeChars, by graphemes: the first line's graphemes while they fit in
// [length], at least one.
String _consumeGraphemes(int length, String content) {
  final consumed = StringBuffer();
  var width = 0;
  for (final grapheme in content.split('\n').first.characters) {
    final next = cellWidth(grapheme);
    if (consumed.isNotEmpty && width + next > length) break;
    consumed.write(grapheme);
    width += next;
  }
  return consumed.toString();
}
