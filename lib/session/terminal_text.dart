/// What a command an agent ran wrote, as plain text: the output a terminal
/// would leave on screen, folded one delta at a time. The cursor controls a
/// progress line uses are applied where they land, and every other escape
/// is dropped as it arrives, so the state a tool call's terminal keeps holds
/// no escape for a later cut to split. An escape a delta ends inside is
/// carried to the next as the parser state it left, never as its bytes, so
/// however long it runs, what is held stays within a constant.
///
/// The escapes are read as DEC's VT500 parser reads them (Paul Williams's
/// state machine, which xterm and every other emulator follow): a C1 byte,
/// a CAN, a SUB or an `ESC` ends whatever was open, a string (OSC, DCS, SOS,
/// PM, APC) runs to its BEL or ST, and C0 controls inside an escape still
/// act. A port of the original's `terminal_text.ts`; no package on pub.dev
/// fits (see docs/decisions.md).
library;

import 'dart:math';

import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart' show cellWidth, graphemeWidth;

/// Where tab stops fall, as a terminal sets them unless told otherwise.
const _tabStop = 8;

/// The most of a CSI's parameters kept while it is open. The controls
/// applied take a number or two; a longer run is no control chord applies,
/// so the sequence is dropped whole and its parameters stop growing.
const paramsLimit = 16;

/// The furthest right a cursor control or a tab takes the cursor. A
/// terminal stops it at its right margin; this state has no width, so the
/// margin is one wider than any screen, and a move of a billion columns pads
/// no line with a billion blanks. Text itself still runs past it.
const columnLimit = 1000;

/// Where the next character lands, when that is not the output's end.
final class TerminalCursor {
  const TerminalCursor(this.row, this.column);

  /// The line it is on, counted up from the last, so a cut leaves it be.
  final int row;

  /// The column, in cells: a wide character takes two.
  final int column;
}

/// The escape a delta ended inside, as far as the parser read it: its kind
/// and what the controls applied need, never a string's body.
sealed class OpenEscape {
  const OpenEscape();
}

/// After an `ESC`, perhaps with intermediates.
final class EscapeOpen extends OpenEscape {
  const EscapeOpen({this.intermediates = false});

  /// An intermediate byte came after the `ESC`.
  final bool intermediates;
}

/// Inside a CSI, its parameters so far.
final class CsiOpen extends OpenEscape {
  const CsiOpen(this.params, {this.ignored = false});

  /// The digits and `;` read so far, at most [paramsLimit].
  final String params;

  /// It is no control chord applies: a private marker, an intermediate, or
  /// parameters past the bound.
  final bool ignored;
}

/// Inside a string: an OSC, DCS, SOS, PM or APC.
final class StringOpen extends OpenEscape {
  const StringOpen();
}

/// A terminal's output as text, and what the next delta goes on from.
final class TerminalText {
  const TerminalText(
    this.output, {
    this.cursor,
    this.escape,
    this.truncated = false,
  });

  /// A terminal that has written nothing.
  static const empty = TerminalText('');

  /// Plain text, lines split by `\n`; no other control character.
  final String output;

  /// Null while the cursor sits at the output's end.
  final TerminalCursor? cursor;

  /// The escape the output so far ends inside.
  final OpenEscape? escape;

  /// Output ran past the bound and its start was dropped.
  final bool truncated;
}

/// [text] with [data] written after it, then cut to the last [limit]
/// characters: from a line's start where one falls inside them, so no line
/// is kept in pieces; within the last line only when it alone outruns the
/// bound.
TerminalText writeText(TerminalText text, String data, num limit) {
  final screen = _Screen(text)..write(data);
  return screen.result(limit, text.truncated);
}

/// [data] as a terminal would leave it, with nothing before or after.
String plainText(String data) =>
    writeText(TerminalText.empty, data, double.infinity).output;

/// The lines being written, and the parser's state between characters.
final class _Screen {
  _Screen(TerminalText text)
    : _lines = text.output.split('\n'),
      _at = text.cursor?.column,
      _escape = text.escape {
    _row = _lines.length - 1 - (text.cursor?.row ?? 0);
  }

  final List<String> _lines;

  /// Lines rewritten as cells, by index, joined back at the end.
  final _cells = <int, List<String>>{};
  late int _row;

  /// The cursor's column; null while it is at its line's end, so text that
  /// only appends never measures the line it lands on.
  int? _at;
  OpenEscape? _escape;

  int get _column => _at ??= _width(_lines[_row]);

  set _column(int column) => _at = column;

  void write(String data) {
    final printable = StringBuffer();

    void flush() {
      if (printable.isNotEmpty) {
        _print(printable.toString());
        printable.clear();
      }
    }

    for (final code in data.runes) {
      if (_escape == null && _isPrintable(code)) {
        printable.writeCharCode(code);
        continue;
      }

      flush();
      _read(String.fromCharCode(code), code);
    }

    flush();
  }

  /// One character that is a control, or comes inside an escape.
  void _read(String char, int code) {
    // What ends whatever is open, wherever it comes.
    if (code == 0x18 || code == 0x1a) {
      _escape = null;
      return;
    }

    if (code == 0x1b) {
      _escape = const EscapeOpen();
      return;
    }

    if (code >= 0x80 && code <= 0x9f) {
      _escape = code == 0x9b
          ? const CsiOpen('')
          : const [0x90, 0x98, 0x9d, 0x9e, 0x9f].contains(code)
          ? const StringOpen()
          : null;
      return;
    }

    final escape = _escape;

    if (escape is StringOpen) {
      if (code == 0x07) _escape = null;
      return;
    }

    if (code < 0x20) {
      _control(code);
      return;
    }

    if (code == 0x7f || escape == null) {
      return;
    }

    if (code > 0x7f) {
      // Not part of any escape: the sequence was broken off, and this is
      // text.
      _escape = null;
      _print(char);
      return;
    }

    if (escape is EscapeOpen) {
      _escape = _afterEscape(escape, char, code);
      return;
    }

    final csi = escape as CsiOpen;

    _escape = null;

    if (code >= 0x40) {
      if (!csi.ignored) _csi(csi.params, char);
      return;
    }

    // A private marker or an intermediate makes it a control chord does not
    // apply, and so does a run of parameters past the bound.
    final kept =
        RegExp(r'[\d;]').hasMatch(char) && csi.params.length < paramsLimit;

    _escape = CsiOpen(
      kept ? csi.params + char : csi.params,
      ignored: csi.ignored || !kept,
    );
  }

  /// A C0 control: the few that move the cursor act, the rest go.
  void _control(int code) {
    switch (code) {
      case 0x0a:
        // A new line's end is its start; an existing one's start is not.
        final last = _row == _lines.length - 1;
        _at = last ? null : 0;
        if (last) _lines.add('');
        _row += 1;
      case 0x0d:
        _column = 0;
      case 0x08:
        _column = max(0, _column - 1);
      case 0x09:
        _column = _rightTo(_column, (_column ~/ _tabStop + 1) * _tabStop);
    }
  }

  /// A CSI sequence ended by [last]: the cursor and erase controls act.
  void _csi(String params, String last) {
    final first = params.split(';').first;
    final value = first.isEmpty ? 0 : int.parse(first);
    final count = max(1, value);
    const top = 0;
    final bottom = _lines.length - 1;

    // The column holds across a move to another line, whatever its end.
    _at = _column;

    switch (last) {
      case 'A':
        _row = max(top, _row - count);
      case 'B':
        _row = min(bottom, _row + count);
      case 'C':
        _column = _rightTo(_column, _column + count);
      case 'D':
        _column = max(0, _column - count);
      case 'E':
        _row = min(bottom, _row + count);
        _column = 0;
      case 'F':
        _row = max(top, _row - count);
        _column = 0;
      case 'G':
        _column = min(count - 1, columnLimit);
      case 'K':
        _erase(value);
    }
  }

  /// Erase in line: after the cursor, up to it, or the whole line.
  void _erase(int mode) {
    final cells = _line();

    if (mode == 0) {
      _cleave(cells, _column);
      cells.length = min(cells.length, _column);
    } else if (mode == 1) {
      _cleave(cells, _column + 1);
      for (var at = 0; at <= _column && at < cells.length; at++) {
        cells[at] = ' ';
      }
    } else if (mode == 2) {
      cells.length = 0;
    }
  }

  /// Text, written over what the line holds from the cursor on.
  void _print(String text) {
    final line = _lines[_row];

    if (_at == null && !_cells.containsKey(_row)) {
      _lines[_row] = line + text;
      return;
    }

    if (!_cells.containsKey(_row) && _isAscii(text) && _isAscii(line)) {
      // The usual case, a cell a character, without splitting graphemes.
      final column = _column;
      final after = column + text.length;
      _lines[_row] =
          line.padRight(column).substring(0, column) +
          text +
          (after < line.length ? line.substring(after) : '');
      _column = after;
      return;
    }

    final cells = _line();
    final before = _column - 1 >= 0 && _column - 1 < cells.length
        ? (cells[_column - 1] == '' ? _column - 2 : _column - 1)
        : _column - 1;
    var segments = _graphemes(text);

    if (before >= 0 && before < cells.length) {
      // What a delta begins with may still belong to the character before
      // the cursor (a mark, a joiner, an emoji's other half, a surrogate's
      // second), or take back what was kept with it, so the two are read
      // as one, as they would be whole.
      final joined = _graphemes(cells[before] + text);

      if (joined.first != cells[before]) {
        _cleave(cells, before + 1);
        cells.replaceRange(before, before + 1, const [' ']);
        _column = before;
        segments = joined;
      }
    }

    for (final segment in segments) {
      final size = graphemeWidth(segment);

      if (size == 0) {
        // A mark that combines with what was written before it.
        final at =
            _column - 1 >= 0 &&
                _column - 1 < cells.length &&
                cells[_column - 1] == ''
            ? _column - 2
            : _column - 1;

        if (at >= 0 && at < cells.length) {
          cells[at] += segment;
          continue;
        }
      }

      while (cells.length < _column) {
        cells.add(' ');
      }

      final taken = max(1, size);

      _cleave(cells, _column);
      _cleave(cells, _column + taken);
      cells.replaceRange(_column, min(_column + taken, cells.length), [
        segment,
        if (size > 1) '',
      ]);
      _column += taken;
    }
  }

  /// The cursor's line as cells, a wide character's second one empty.
  List<String> _line() => _cells.putIfAbsent(_row, () {
    final cells = <String>[];

    for (final segment in _graphemes(_lines[_row])) {
      final size = graphemeWidth(segment);
      final at = cells.isNotEmpty && cells.last == ''
          ? cells.length - 2
          : cells.length - 1;

      if (size == 0 && at >= 0) {
        // Kept with the character before it, as it was written.
        cells[at] += segment;
      } else {
        cells.addAll([segment, if (size > 1) '']);
      }
    }

    return cells;
  });

  TerminalText result(num limit, bool truncated) {
    for (final MapEntry(key: row, value: cells) in _cells.entries) {
      _lines[row] = cells.join();
    }

    var output = _lines.join('\n');
    var row = _lines.length - 1 - _row;
    final end = row == 0 && _at == null;
    var column = end ? 0 : _column;

    if (output.length > limit) {
      truncated = true;

      final from = output.length - limit.toInt();
      final start = output.indexOf('\n', from);

      if (start >= 0) {
        output = output.substring(start + 1);
      } else {
        final line = output.substring(output.lastIndexOf('\n') + 1);
        final cut = _graphemeAfter(line, line.length - limit.toInt());

        if (row == 0 && !end) {
          column = max(0, column - _width(line.substring(0, cut)));
        }

        output = line.substring(cut);
      }

      row = min(row, output.split('\n').length - 1);
    }

    return TerminalText(
      output,
      cursor: end ? null : TerminalCursor(row, column),
      escape: _escape,
      truncated: truncated,
    );
  }
}

/// The state after an `ESC` and what came after it, given one more byte.
OpenEscape? _afterEscape(EscapeOpen escape, String char, int code) {
  if (code < 0x30) return const EscapeOpen(intermediates: true);
  if (escape.intermediates) return null;
  if (char == '[') return const CsiOpen('');
  return ']PX^_'.contains(char) ? const StringOpen() : null;
}

/// Before [at], a wide character [at] falls inside of is half overwritten:
/// what is left of it is a blank, as a terminal leaves it.
void _cleave(List<String> cells, int at) {
  if (at > 0 && at < cells.length && cells[at] == '') {
    cells[at - 1] = ' ';
    cells[at] = ' ';
  }
}

/// The first grapheme boundary in [line] at or after [from], where a cut
/// leaves no character in halves: a cluster that does not fit whole goes
/// whole, however long its run of marks.
int _graphemeAfter(String line, int from) {
  // As JavaScript's slice reads (from - 1, from + 1), a negative start
  // counted from the end.
  final start = from - 1 < 0 ? max(line.length + from - 1, 0) : from - 1;
  final stop = min(from + 1, line.length);

  if (_isAscii(start < stop ? line.substring(start, stop) : '')) {
    return from;
  }

  var index = 0;

  for (final segment in _graphemes(line)) {
    final next = index + segment.length;

    if (from < next) return index == from ? from : next;
    index = next;
  }

  return from;
}

/// A move right from [column] to [to], stopped at the margin.
int _rightTo(int column, int to) => max(column, min(to, columnLimit));

bool _isPrintable(int code) => (code >= 0x20 && code < 0x7f) || code > 0x9f;

final _ascii = RegExp(r'^[\x20-\x7e]*$');

bool _isAscii(String text) => _ascii.hasMatch(text);

int _width(String line) => _isAscii(line) ? line.length : cellWidth(line);

/// [text]'s grapheme clusters, as the original's `Intl.Segmenter` reads
/// them: a lone high surrogate, a delta ending between a pair's halves, is
/// kept with the cluster before it, so the next delta's low half takes it
/// back whole.
List<String> _graphemes(String text) {
  final clusters = <String>[];

  for (final cluster in text.characters) {
    final code = cluster.length == 1 ? cluster.codeUnitAt(0) : 0;

    if (code >= 0xd800 && code <= 0xdbff && clusters.isNotEmpty) {
      clusters.last += cluster;
    } else {
      clusters.add(cluster);
    }
  }

  return clusters;
}
