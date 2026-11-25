// A port of wrap-ansi 10.0.2's `exec` and `wrapWord`, on glyphs that carry
// their own styles: https://github.com/chalk/wrap-ansi
//
// MIT License
//
// Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import 'layout.dart';

const _tabSize = 8;

/// One source line of glyphs, its tabs still single glyphs, wrapped to
/// [columns] as wrap-ansi's `exec` wraps a line.
List<List<Glyph>> wrapAnsiLine(
  List<Glyph> source,
  int columns, {
  bool hard = false,
  bool trim = true,
  bool wordWrap = true,
}) {
  final line = _expandTabs(source);
  bool blank(Glyph g) => g.text.runes.every(_jsWhitespace);
  if (trim && line.every(blank)) return [[]];

  final words = <List<Glyph>>[[]];
  final gaps = <Glyph>[];
  for (final g in line) {
    if (g.text == ' ') {
      gaps.add(g);
      words.add([]);
    } else {
      words.last.add(g);
    }
  }

  final rows = <List<Glyph>>[[]];
  var rowLength = 0;
  var trimmedRow = -1;
  for (final (index, word) in words.indexed) {
    final wordWidth = TextLayout.lineWidth(word);
    final rowIndex = rows.length - 1;
    if (trim && trimmedRow != rowIndex) {
      final row = rows[rowIndex];
      var start = 0;
      while (start < row.length && blank(row[start])) {
        start++;
      }
      if (start > 0) {
        rows[rowIndex] = row.sublist(start);
        rowLength = TextLayout.lineWidth(rows[rowIndex]);
      }
      if (rows[rowIndex].isNotEmpty) trimmedRow = rowIndex;
    }

    if (index > 0) {
      if (rowLength >= columns && (!wordWrap || !trim)) {
        rows.add([]);
        rowLength = 0;
      }
      if (rowLength > 0 || !trim) {
        rows.last.add(gaps[index - 1]);
        rowLength++;
      }
    }

    if (hard && wordWrap && wordWidth > columns) {
      final remaining = columns - rowLength;
      final startingThisRow = 1 + (wordWidth - remaining - 1) ~/ columns;
      final startingNextRow = (wordWidth - 1) ~/ columns;
      if (startingNextRow < startingThisRow) {
        rows.add([]);
        rowLength = 0;
      }
      rowLength = _wrapWord(rows, word, columns, rowLength);
      continue;
    }

    if (rowLength + wordWidth > columns && rowLength > 0 && wordWidth > 0) {
      if (!wordWrap && rowLength < columns) {
        rowLength = _wrapWord(rows, word, columns, rowLength);
        continue;
      }
      rows.add([]);
      rowLength = 0;
    }

    if (rowLength + wordWidth > columns && !wordWrap) {
      rowLength = _wrapWord(rows, word, columns, rowLength);
      continue;
    }

    rows.last.addAll(word);
    rowLength += wordWidth;
  }

  if (trim) {
    for (final row in rows) {
      while (row.isNotEmpty && row.last.text == ' ') {
        row.removeLast();
      }
    }
  }
  return rows;
}

/// Whether JavaScript's `trim` drops [c]: Dart's set less U+0085, which
/// JavaScript keeps.
bool _jsWhitespace(int c) => c != 0x85 && String.fromCharCode(c).trim().isEmpty;

/// [word] laid on from the last row, a cell past [columns] starting a new
/// one; the width of the row it ends on.
int _wrapWord(List<List<Glyph>> rows, List<Glyph> word, int columns, int at) {
  var visible = at;
  for (final (index, g) in word.indexed) {
    if (g.width > 0 && visible > 0 && visible + g.width > columns) {
      rows.add([]);
      visible = 0;
    }
    rows.last.add(g);
    visible += g.width;
    if (visible == columns && index < word.length - 1) {
      rows.add([]);
      visible = 0;
    }
  }
  // A last row of only zero-width glyphs joins the row before it.
  if (visible == 0 && rows.last.isNotEmpty && rows.length > 1) {
    rows[rows.length - 2].addAll(rows.removeLast());
  }
  return TextLayout.lineWidth(rows.last);
}

/// [line] with each tab as the spaces to the next stop, every one keeping
/// the tab's source offset.
List<Glyph> _expandTabs(List<Glyph> line) {
  if (!line.any((g) => g.text == '\t')) return line;
  final out = <Glyph>[];
  var visible = 0;
  for (final g in line) {
    if (g.text != '\t') {
      out.add(g);
      visible += g.width;
      continue;
    }
    final spaces = _tabSize - visible % _tabSize;
    for (var i = 0; i < spaces; i++) {
      out.add(Glyph(' ', 1, g.style, sourceOffset: g.sourceOffset));
    }
    visible += spaces;
  }
  return out;
}
