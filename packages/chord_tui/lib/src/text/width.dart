import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

// Ranges of code points that take two cells: East Asian Wide and Fullwidth,
// and emoji with emoji presentation by default. Sorted, inclusive.
const List<int> _wide = [
  0x1100, 0x115F, 0x231A, 0x231B, 0x2329, 0x232A, 0x23E9, 0x23EC, //
  0x23F0, 0x23F0, 0x23F3, 0x23F3, 0x25FD, 0x25FE, 0x2614, 0x2615,
  0x2648, 0x2653, 0x267F, 0x267F, 0x2693, 0x2693, 0x26A1, 0x26A1,
  0x26AA, 0x26AB, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26CE, 0x26CE,
  0x26D4, 0x26D4, 0x26EA, 0x26EA, 0x26F2, 0x26F3, 0x26F5, 0x26F5,
  0x26FA, 0x26FA, 0x26FD, 0x26FD, 0x2705, 0x2705, 0x270A, 0x270B,
  0x2728, 0x2728, 0x274C, 0x274C, 0x274E, 0x274E, 0x2753, 0x2755,
  0x2757, 0x2757, 0x2795, 0x2797, 0x27B0, 0x27B0, 0x27BF, 0x27BF,
  0x2B1B, 0x2B1C, 0x2B50, 0x2B50, 0x2B55, 0x2B55, 0x2E80, 0x303E,
  0x3041, 0x33FF, 0x3400, 0x4DBF, 0x4E00, 0x9FFF, 0xA000, 0xA4CF,
  0xA960, 0xA97F, 0xAC00, 0xD7A3, 0xF900, 0xFAFF, 0xFE10, 0xFE19,
  0xFE30, 0xFE6F, 0xFF00, 0xFF60, 0xFFE0, 0xFFE6, 0x16FE0, 0x16FE4,
  0x17000, 0x18CFF, 0x1B000, 0x1B2FF, 0x1F004, 0x1F004, 0x1F0CF, 0x1F0CF,
  0x1F18E, 0x1F18E, 0x1F191, 0x1F19A, 0x1F1E6, 0x1F1FF, 0x1F200, 0x1F202,
  0x1F210, 0x1F23B, 0x1F240, 0x1F248, 0x1F250, 0x1F251, 0x1F300, 0x1F320,
  0x1F32D, 0x1F335, 0x1F337, 0x1F37C, 0x1F37E, 0x1F393, 0x1F3A0, 0x1F3CA,
  0x1F3CF, 0x1F3D3, 0x1F3E0, 0x1F3F0, 0x1F3F4, 0x1F3F4, 0x1F3F8, 0x1F43E,
  0x1F440, 0x1F440, 0x1F442, 0x1F4FC, 0x1F4FF, 0x1F53D, 0x1F54B, 0x1F54E,
  0x1F550, 0x1F567, 0x1F57A, 0x1F57A, 0x1F595, 0x1F596, 0x1F5A4, 0x1F5A4,
  0x1F5FB, 0x1F64F, 0x1F680, 0x1F6C5, 0x1F6CC, 0x1F6CC, 0x1F6D0, 0x1F6D2,
  0x1F6D5, 0x1F6D7, 0x1F6DC, 0x1F6DF, 0x1F6EB, 0x1F6EC, 0x1F6F4, 0x1F6FC,
  0x1F7E0, 0x1F7EB, 0x1F7F0, 0x1F7F0, 0x1F90C, 0x1F93A, 0x1F93C, 0x1F945,
  0x1F947, 0x1F9FF, 0x1FA70, 0x1FAFF, 0x20000, 0x2FFFD, 0x30000, 0x3FFFD,
];

// Code points that take no cell when they appear on their own.
const List<int> _zero = [
  0x0300, 0x036F, 0x0483, 0x0489, 0x0591, 0x05BD, 0x200B, 0x200F, //
  0x2028, 0x202E, 0x2060, 0x2064, 0x20D0, 0x20FF, 0xFE00, 0xFE0F,
  0xFE20, 0xFE2F, 0xFEFF, 0xFEFF, 0xE0100, 0xE01EF,
];

bool _inRanges(List<int> ranges, int cp) {
  var lo = 0;
  var hi = ranges.length ~/ 2 - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cp < ranges[mid * 2]) {
      hi = mid - 1;
    } else if (cp > ranges[mid * 2 + 1]) {
      lo = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// The number of cells one grapheme cluster takes: 0, 1 or 2.
int graphemeWidth(String g) {
  if (g.isEmpty) return 0;
  final first = g.codeUnitAt(0);
  if (g.length == 1) {
    if (first < 0x20 || (first >= 0x7f && first < 0xa0)) return 0;
    if (first < 0x7f) return 1;
  }
  final runes = g.runes;
  final cp = runes.first;
  if (cp < 0x20 || (cp >= 0x7f && cp < 0xa0)) return 0;
  if (_inRanges(_wide, cp)) return 2;
  if (runes.length > 1) {
    for (final r in runes) {
      // Emoji presentation selector or a joined sequence: drawn as emoji.
      if (r == 0xFE0F || r == 0x200D) return 2;
    }
  }
  if (_inRanges(_zero, cp)) return 0;
  return 1;
}

// The pattern and fast path follow ansi-regex 6.4.0 and strip-ansi 7.2.0.
// https://github.com/chalk/ansi-regex/tree/v6.4.0
// https://github.com/chalk/strip-ansi/tree/v7.2.0
//
// MIT License
// Copyright (c) Sindre Sorhus <sindresorhus@gmail.com>
// (https://sindresorhus.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
const _ansiTerminator = r'(?:\u0007|\u001B\u005C|\u009C)';
final _ansi = RegExp(
  r'(?:(?:\u001B\]|\u009D)[^\u0007\u001B\u009C\u009D]*'
  '$_ansiTerminator)'
  r'|[\u001B\u009B][[\]()#;?]*(?:\d{1,4}(?:[;:]\d{0,4})*)?'
  r'[\dA-PR-TZcf-nq-uy=><~]',
);

/// Existing terminal escape ranges, for mapping style runs without splitting them.
@internal
Iterable<(int, int)> ansiEscapeRanges(String text) =>
    !text.contains('\x1b') && !text.contains('\u009b')
    ? const []
    : _ansi.allMatches(text).map((match) => (match.start, match.end));

/// [s] without its ANSI escape sequences.
String stripAnsi(String s) {
  if (!s.contains('\x1b') && !s.contains('\u009b')) return s;
  return s.replaceAll(_ansi, '');
}

/// The number of cells [s] takes on one line, ignoring ANSI sequences.
int cellWidth(String s) {
  final plain = stripAnsi(s);
  var w = 0;
  var ascii = true;
  for (var i = 0; i < plain.length; i++) {
    final c = plain.codeUnitAt(i);
    if (c < 0x20 || c >= 0x7f) {
      ascii = false;
      break;
    }
  }
  if (ascii) return plain.length;
  for (final g in plain.characters) {
    w += graphemeWidth(g);
  }
  return w;
}

/// [s] cut to at most [width] cells, ending with [ellipsis] when cut.
/// With [preferTruncationOnSpace], a space at the cut or up to three cells
/// before it ends the prefix instead. Graphemes stay whole; only ASCII
/// spaces are candidates. Fitting text and the default cutoff are unchanged.
String truncate(
  String s,
  int width, {
  String ellipsis = '…',
  bool preferTruncationOnSpace = false,
}) {
  if (cellWidth(s) <= width) return s;
  final ew = cellWidth(ellipsis);
  if (width <= ew) {
    return width <= 0 ? '' : ellipsis.characters.take(width).string;
  }
  final plain = stripAnsi(s);
  var budget = width - ew;
  if (preferTruncationOnSpace) {
    var column = 0;
    int? space;
    for (final g in plain.characters) {
      if (column > budget) break;
      if (g == ' ' && budget - column <= 3) space = column;
      column += graphemeWidth(g);
    }
    if (space != null) budget = space;
  }
  final out = StringBuffer();
  var w = 0;
  for (final g in plain.characters) {
    final gw = graphemeWidth(g);
    if (w + gw > budget) break;
    out.write(g);
    w += gw;
  }
  out.write(ellipsis);
  return out.toString();
}

/// Cuts [text] from the start to [width] cells, retaining a whole-grapheme
/// suffix after [ellipsis]. Fitting text is unchanged; cut text loses ANSI.
/// If the marker fills the room, only its fitting whole-grapheme prefix stays.
String truncateStart(String text, int width, {String ellipsis = '…'}) {
  if (width <= 0) return '';
  if (cellWidth(text) <= width) return text;
  final plainMarker = stripAnsi(ellipsis);
  final markerWidth = cellWidth(plainMarker);
  if (markerWidth >= width) {
    final marker = StringBuffer();
    var used = 0;
    for (final grapheme in plainMarker.characters) {
      final cells = graphemeWidth(grapheme);
      if (used + cells > width) break;
      marker.write(grapheme);
      used += cells;
    }
    return marker.toString();
  }
  final suffix = <String>[];
  var used = markerWidth;
  for (final grapheme in stripAnsi(text).characters.toList().reversed) {
    final cells = graphemeWidth(grapheme);
    if (used + cells > width) break;
    suffix.add(grapheme);
    used += cells;
  }
  return plainMarker + suffix.reversed.join();
}
