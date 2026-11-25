import 'dart:math' as math;
import 'package:chord_tui/chord_tui.dart';

import '../header/mark_rows.dart';
import '../pickers/mcp.dart';

/// Art steps selected solely by the available window.
enum StartStep { full, compact, line, none }

/// The original README's line beneath the full splash.
const tagline = 'One terminal for every coding agent.';

/// The agent column, or the pure layout's reserved resume frame.
int startColumn(int columns, {bool framed = false}) =>
    math.max(1, math.min(columns - 2, framed ? 84 : 62));

/// Wrapped hint rows, including the empty hint's row.
int hintRows(String hint, int width) =>
    TextLayout.wrapAnsi(TextSpan(hint), math.max(width, 1), hard: true).height;

/// The two font roles follow the gradient's middle and last stops.
(String, String)? wordmarkColours(MarkColour colour) => switch (colour) {
  MarkPlain() => null,
  MarkTone(:final tone) => (tone, tone),
  MarkGradient(:final stops) => (markPaint(stops)(middle), markPaint(stops)(1)),
};

/// The names the person's list gives that chord lacks, as one row of
/// [width]: whole names in order and a count of the rest, at least one name
/// shown. The row never grows with a typo, as the settings problems hold
/// every name.
String unknownNote(List<String> names, int width) {
  String note(int shown) =>
      'Unknown in offeredAgents: ${[...names.take(shown), if (shown < names.length) '+${names.length - shown} more'].join(', ')}';

  for (var shown = names.length; shown > 1; shown--) {
    if (cellWidth(note(shown)) <= width) return note(shown);
  }
  return note(1);
}

/// The art, list room, top margin and column for one window.
({StartStep step, int listRows, int top, int column}) startLayout({
  required int columns,
  required int rows,
  required int lines,
  bool framed = false,
  required int hintRows,
}) {
  final page = noteLayout(
    columns: columns,
    rows: rows,
    lines: lines,
    framed: framed,
    hintRows: hintRows,
  );
  return (
    step: page.step,
    listRows: page.listRows,
    top: page.top,
    column: page.column,
  );
}

/// [startLayout], and whether a note of [noteRows] under the hint is drawn:
/// never at the cost of a row of the list.
({StartStep step, int listRows, int top, int column, bool note}) noteLayout({
  required int columns,
  required int rows,
  required int lines,
  bool framed = false,
  required int hintRows,
  int noteRows = 0,
}) {
  const art = {
    StartStep.full: 11,
    StartStep.compact: 5,
    StartStep.line: 1,
    StartStep.none: 0,
  };
  final around = (framed ? 6 : 3) + hintRows;
  int room(int height) => rows - height - 1 - around - 1;
  final step = rows >= 32 && columns >= 60
      ? StartStep.full
      : rows >= 18 && columns >= 40
      ? StartStep.compact
      : room(1) >= 3
      ? StartStep.line
      : StartStep.none;
  final cap = step == StartStep.full ? 14 : unbounded;
  final fits = step == StartStep.none
      ? rows - (framed ? 1 : 0) - around
      : room(art[step]!);
  final whole = lines <= math.min(fits, cap);
  final listRows = whole
      ? math.max(lines, 1)
      : math.max(1, math.min(cap, fits - 1));
  final note =
      noteRows > 0 &&
      step != StartStep.none &&
      lines <= math.min(fits - noteRows, cap);
  final pageRows =
      art[step]! +
      (step == StartStep.none && !framed ? 0 : 1) +
      around +
      listRows +
      (whole ? 0 : 1) +
      (note ? noteRows : 0);
  return (
    step: step,
    listRows: listRows,
    top: math.max(0, (rows - pageRows) ~/ 2),
    column: startColumn(columns, framed: framed),
    note: note,
  );
}

/// Version and directory; only the directory is cut first, at a slash.
String versionLine({
  required String version,
  String? agent,
  required String directory,
  required int width,
}) {
  final rest = 'v$version · ${agent == null ? '' : '$agent · '}';
  return '$rest${cutPath(directory, math.max(1, width - cellWidth(rest)))}';
}
