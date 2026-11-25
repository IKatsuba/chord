import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import '../text/width.dart';
import 'notifier.dart';

/// The text of an input and where its cursor is, counted in graphemes.
class TextEditingController extends ChangeNotifier {
  /// A controller holding [text], the cursor at its end.
  TextEditingController({String text = ''})
    : _chars = text.characters.toList(),
      _cursor = text.characters.length;

  List<String> _chars;
  int _cursor;

  /// The whole text; setting it puts the cursor at the end.
  String get text => _chars.join();
  set text(String value) {
    _chars = value.characters.toList();
    _cursor = _chars.length;
    notifyListeners();
  }

  /// The cursor, in graphemes from the start; set values are clamped to the text.
  int get cursor => _cursor;
  set cursor(int value) {
    final v = value.clamp(0, _chars.length);
    if (v == _cursor) return;
    _cursor = v;
    notifyListeners();
  }

  /// The text's length, in graphemes.
  int get length => _chars.length;

  /// The text before the cursor.
  String get beforeCursor => _chars.take(_cursor).join();

  /// The text after the cursor.
  String get afterCursor => _chars.skip(_cursor).join();

  /// Inserts [s] at the cursor and moves the cursor past it.
  void insert(String s) {
    final add = s.characters.toList();
    if (add.isEmpty) return;
    _chars.insertAll(_cursor, add);
    _cursor += add.length;
    notifyListeners();
  }

  /// Removes the grapheme before the cursor.
  void backspace() {
    if (_cursor == 0) return;
    _chars.removeAt(--_cursor);
    notifyListeners();
  }

  /// Removes the grapheme after the cursor.
  void delete() {
    if (_cursor >= _chars.length) return;
    _chars.removeAt(_cursor);
    notifyListeners();
  }

  /// Removes the word before the cursor and the spaces after it.
  void deleteWordBefore() {
    var i = _cursor;
    while (i > 0 && _chars[i - 1].trim().isEmpty) {
      i--;
    }
    while (i > 0 && _chars[i - 1].trim().isNotEmpty) {
      i--;
    }
    if (i == _cursor) return;
    _chars.removeRange(i, _cursor);
    _cursor = i;
    notifyListeners();
  }

  /// Removes everything before the cursor.
  void deleteToStart() {
    if (_cursor == 0) return;
    _chars.removeRange(0, _cursor);
    _cursor = 0;
    notifyListeners();
  }

  /// Removes everything after the cursor.
  void deleteToEnd() {
    if (_cursor >= _chars.length) return;
    _chars.removeRange(_cursor, _chars.length);
    notifyListeners();
  }

  /// Removes all the text.
  void clear() {
    if (_chars.isEmpty) return;
    _chars = [];
    _cursor = 0;
    notifyListeners();
  }
}

/// A range of the text: from [baseOffset], where it was started, to
/// [extentOffset], where the cursor is; in graphemes.
@immutable
class TextSelection {
  /// A selection from [baseOffset] to [extentOffset].
  const TextSelection({required this.baseOffset, required this.extentOffset});

  /// No selection: the cursor alone at [offset].
  const TextSelection.collapsed({required int offset})
    : baseOffset = offset,
      extentOffset = offset;

  /// Where the selection was started: the end that stays as it extends.
  final int baseOffset;

  /// Where the cursor is: the end that moves.
  final int extentOffset;

  /// The smaller of the two ends.
  int get start => baseOffset < extentOffset ? baseOffset : extentOffset;

  /// The larger of the two ends.
  int get end => baseOffset < extentOffset ? extentOffset : baseOffset;

  /// Whether nothing is selected: both ends at one offset.
  bool get isCollapsed => baseOffset == extentOffset;

  @override
  bool operator ==(Object other) =>
      other is TextSelection &&
      other.baseOffset == baseOffset &&
      other.extentOffset == extentOffset;

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);

  @override
  String toString() => 'TextSelection($baseOffset..$extentOffset)';
}

/// Which way a vertical move tried to leave a text area.
enum TextAreaDirection {
  /// Up, from the first row.
  up,

  /// Down, from the last row.
  down,
}

/// A [TextEditingController] for a multiline editor: lines split at `\n`,
/// moves by word and by line, and the edits a prompt needs. Plain Dart, so
/// a test drives it without a widget.
///
/// Offsets count grapheme clusters, a line break being one; `\r\n` and `\r`
/// become `\n` wherever text comes in. Every change notifies once, with the
/// cursor already where it ends; one that changes nothing does not notify.
///
/// A [selection] runs from an anchor to the cursor. Moves given `select`
/// extend it; plain moves collapse it to an edge, as OpenTUI's textarea
/// does; typing replaces it and deletes delete it.
class TextAreaController extends TextEditingController {
  /// A controller holding [text], the cursor at its end.
  TextAreaController({String text = ''}) : super(text: _normalized(text)) {
    _remembered = (this.text, _cursor);
  }

  /// The selection's base while something is selected; null otherwise.
  /// Never equal to the cursor.
  int? _anchor;

  /// The selection; collapsed at [cursor] when nothing is selected. Setting
  /// it clamps both ends to the text and moves the cursor to its extent.
  TextSelection get selection =>
      TextSelection(baseOffset: _anchor ?? _cursor, extentOffset: _cursor);
  set selection(TextSelection value) {
    _goal = null;
    final base = value.baseOffset.clamp(0, _chars.length);
    _place(value.extentOffset, base);
  }

  /// Whether some text is selected.
  bool get hasSelection => _anchor != null;

  /// The selected text; empty when nothing is selected.
  String get selectedText {
    final s = selection;
    return _chars.sublist(s.start, s.end).join();
  }

  /// Selects the whole text, the cursor at its end.
  void selectAll() =>
      selection = TextSelection(baseOffset: 0, extentOffset: _chars.length);

  /// Puts the cursor at [at] and the anchor at [base], both clamped, a base
  /// at the cursor selecting nothing; notifies if either changed.
  void _place(int at, int? base) {
    final cursor = at.clamp(0, _chars.length);
    final anchor = base == cursor ? null : base;
    if (cursor == _cursor && anchor == _anchor) return;
    _cursor = cursor;
    _anchor = anchor;
    notifyListeners();
  }

  /// A move to [target], or with [select] an extension of the selection to
  /// it; a plain move with a selection collapses to its start, when
  /// [backward], or its end instead.
  void _go(int target, {required bool select, required bool backward}) {
    _goal = null;
    if (select) return _place(target, _anchor ?? _cursor);
    final s = selection;
    if (!s.isCollapsed) return _place(backward ? s.start : s.end, null);
    _place(target, null);
  }

  /// Drops the selection without notifying; the edit that follows does.
  void _collapse() => _anchor = null;

  /// Removes the selected text, the cursor at its start, without
  /// notifying; false when nothing is selected.
  bool _cut() {
    final s = selection;
    if (s.isCollapsed) return false;
    _chars.removeRange(s.start, s.end);
    _cursor = s.start;
    _anchor = null;
    return true;
  }

  /// Deletes the selection, if any: true when it did.
  bool _deleteSelection() {
    _goal = null;
    if (!_cut()) return false;
    notifyListeners();
    return true;
  }

  late (String, int) _remembered;
  final _undo = <(String, int)>[];
  final _redo = <(String, int)>[];

  /// Whether edits now belong to one group, and whether it holds a step.
  bool _grouping = false, _grouped = false;

  /// Edits until [endUndoGroup] undo as one step: the text before the
  /// first of them.
  void beginUndoGroup() {
    _grouping = true;
    _grouped = false;
  }

  /// Ends the group [beginUndoGroup] began; an empty one adds no step.
  void endUndoGroup() => _grouping = false;

  /// Replaces the whole text and puts the cursor at grapheme [cursor], as
  /// one edit that undo takes back.
  void replace(String text, int cursor) {
    final chars = _normalized(text).characters.toList();
    final at = cursor.clamp(0, chars.length);
    // What changes nothing does not notify, as no other edit does.
    if (at == _cursor && _anchor == null && _sameChars(chars)) return;
    _chars = chars;
    _cursor = at;
    _anchor = null;
    notifyListeners();
  }

  /// Restores the text and cursor before the last edit, if any.
  void undo() => _restore(_undo, _redo);

  /// Restores the last undone edit, if no new edit has followed it.
  void redo() => _restore(_redo, _undo);

  void _restore(List<(String, int)> from, List<(String, int)> to) {
    _goal = null;
    _grouping = false;
    // Undo and redo drop a selection even with nothing to restore, as
    // OpenTUI's clear it before they look.
    if (from.isEmpty) return _place(_cursor, null);
    _anchor = null;
    to.add((text, _cursor));
    final state = from.removeLast();
    _chars = state.$1.characters.toList();
    _cursor = state.$2;
    _remembered = state;
    notifyListeners();
  }

  static String _normalized(String text) =>
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  /// Every change ends here: an edit can join graphemes across where it
  /// cut (a combining mark typed after a letter, a break deleted between
  /// them), so the text is segmented again and a cursor that fell inside
  /// a joined grapheme moves to its end.
  @override
  void notifyListeners() {
    final chars = _chars.join().characters.toList();
    if (!_sameChars(chars)) {
      var offset = 0;
      for (var i = 0; i < _cursor; i++) {
        offset += _chars[i].length;
      }
      var at = 0;
      var cursor = 0;
      while (at < offset) {
        at += chars[cursor++].length;
      }
      _chars = chars;
      _cursor = cursor;
    }
    final state = (text, _cursor);
    if (state.$1 != _remembered.$1) {
      // An edit around a selection (ctrl+u, ctrl+k) takes it with it.
      _anchor = null;
      if (!_grouping || !_grouped) {
        _undo.add(_remembered);
        if (_undo.length > 100) _undo.removeAt(0);
      }
      if (_grouping) _grouped = true;
      _redo.clear();
    }
    _remembered = state;
    _version++;
    _goal = null;
    super.notifyListeners();
  }

  /// Counts changes, so a layout taken before one is known to be stale.
  int _version = 0;

  /// The cell column up and down keep to while they repeat; any other
  /// change, or a new width, forgets it.
  int? _goal;

  /// The width the last layout wrapped to.
  int? _width;

  /// The layout given last: the one the text is drawn in now.
  TextAreaLayout? _last;

  /// The layout given last, as the area settled it while it laid out: what
  /// a widget beside the area (a gutter, a row count) draws from. Null
  /// before the first layout. Listeners hear of a change after layout.
  TextAreaLayout? get lastLayout => _last;

  /// What listeners last heard of the geometry: the rows, the cursor's place
  /// and the scroll.
  Object? _published;

  /// Notifies, after layout, when layout changed the geometry since
  /// listeners last heard: so a widget beside the area that draws from it
  /// (a gutter, a row count) settles in the same frame.
  @internal
  void notifyAfterLayout() {
    final last = _last;
    if (last == null || isDisposed) return;
    final geometry = (
      last.rows.length,
      last.rowOffset,
      last.cursorRow,
      last.cursorColumn,
      last.width,
      last.height,
      _version,
    );
    if (geometry == _published) return;
    _published = geometry;
    // Geometry alone is neither an edit nor a move: listeners hear it past
    // what an edit settles, while an edit they make settles as any other.
    super.notifyListeners();
  }

  int _rowOffset = 0;

  /// The first visual row shown, as the last [layout] settled it.
  int get rowOffset => _rowOffset;

  /// The text wrapped into rows of [width] cells, and the [maxHeight] rows
  /// or fewer it shows: scrolled as little as reveals the cursor. Settles
  /// [rowOffset] without notifying, so a widget may call it while it lays
  /// out.
  TextAreaLayout layout({required int width, required int maxHeight}) {
    if (width != _width) {
      _width = width;
      _goal = null;
    }
    final rows = _rows(width < 0 ? 0 : width);
    final cursorRow = _cursorRow(rows);
    final row = rows[cursorRow];
    final height = width <= 0 || maxHeight <= 0
        ? 0
        : (rows.length < maxHeight ? rows.length : maxHeight);
    var offset = _rowOffset.clamp(0, rows.length - height);
    if (cursorRow < offset) offset = cursorRow;
    if (height > 0 && cursorRow >= offset + height) {
      offset = cursorRow - height + 1;
    }
    _rowOffset = offset;
    return _last = TextAreaLayout._(
      rows: List.unmodifiable(rows),
      cursorRow: cursorRow,
      cursorColumn: _cells(row.start, _cursor),
      rowOffset: offset,
      width: width < 0 ? 0 : width,
      height: height,
      version: _version,
      maxHeight: maxHeight,
    );
  }

  /// The cells graphemes [from] to [to] take; a tab takes four.
  int _cells(int from, int to) {
    var cells = 0;
    for (var i = from; i < to; i++) {
      cells += _cellsOf(_chars[i]);
    }
    return cells;
  }

  static int _cellsOf(String g) => g == '\t' ? 4 : graphemeWidth(g);

  /// The rows: each line cut by grapheme where the next would pass [width]
  /// cells, a grapheme wider than a row alone on its own. A line that fills
  /// its last row gets an empty row after it, where a cursor at its end is
  /// drawn. A width of zero cuts nothing.
  List<TextAreaRow> _rows(int width) {
    final rows = <TextAreaRow>[];
    var line = 0;
    var start = 0;
    for (var i = 0; i <= _chars.length; i++) {
      if (i < _chars.length && _chars[i] != '\n') continue;
      var piece = 0;
      var rowStart = start;
      var cells = 0;
      for (var j = start; j < i; j++) {
        final w = _cellsOf(_chars[j]);
        if (width > 0 && cells + w > width && j > rowStart) {
          rows.add(_row(rowStart, j, line, piece++));
          rowStart = j;
          cells = 0;
        }
        cells += w;
      }
      rows.add(_row(rowStart, i, line, piece++));
      if (width > 0 && cells >= width) {
        rows.add(_row(i, i, line, piece));
      }
      line++;
      start = i + 1;
    }
    final last = rows.removeLast();
    rows.add(
      TextAreaRow._(
        last.text,
        last.line,
        last.piece,
        true,
        last.start,
        last.end,
      ),
    );
    return rows;
  }

  TextAreaRow _row(int start, int end, int line, int piece) => TextAreaRow._(
    _chars.sublist(start, end).join(),
    line,
    piece,
    false,
    start,
    end,
  );

  /// The row the cursor is drawn on: where a row ends inside a line, its
  /// end belongs to the row after.
  int _cursorRow(List<TextAreaRow> rows) {
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      if (_cursor < row.start) continue;
      if (_cursor < row.end || (_cursor == row.end && !_continues(rows, r))) {
        return r;
      }
    }
    return rows.length - 1;
  }

  /// Whether row [r] is followed by more of its line.
  static bool _continues(List<TextAreaRow> rows, int r) =>
      r + 1 < rows.length && rows[r + 1].line == rows[r].line;

  /// Moves the cursor one visual row up in [layout], to the column the
  /// first of a run of vertical moves started from, or the nearest before
  /// it; false, moving nothing, on the first row. With [select] it extends
  /// the selection; without, it first collapses one at the cursor, which
  /// is all it does on the first row.
  bool moveUp(TextAreaLayout layout, {bool select = false}) =>
      _moveRows(layout, -1, select);

  /// Moves the cursor one visual row down in [layout], as [moveUp] does;
  /// false, moving nothing, on the last row.
  bool moveDown(TextAreaLayout layout, {bool select = false}) =>
      _moveRows(layout, 1, select);

  /// Moves the cursor to the start of the visual row it is drawn on in
  /// [layout]; a cursor at a wrap boundary is on the row after it. With no
  /// layout, nothing being shown, to the start of its logical line, never
  /// past it. With [select] it extends the selection; without, a selection
  /// collapses to its start.
  void moveToRowStart(TextAreaLayout? layout, {bool select = false}) {
    if (layout == null) {
      return _go(_lineStart(_cursor), select: select, backward: true);
    }
    final current = _current(layout);
    final start = current.rows[current.cursorRow].start;
    _go(start, select: select, backward: true);
  }

  /// Moves the cursor to the end of the visual row it is drawn on in
  /// [layout]: before the row's last grapheme when its line goes on in the
  /// next row, so the cursor stays on this row; the line's end otherwise.
  /// With no layout, to the end of its logical line, never past it. With
  /// [select] it extends the selection; without, a selection collapses to
  /// its end.
  void moveToRowEnd(TextAreaLayout? layout, {bool select = false}) {
    if (layout == null) {
      return _go(_lineEnd(_cursor), select: select, backward: false);
    }
    final current = _current(layout);
    final rows = current.rows;
    final row = rows[current.cursorRow];
    final end = _continues(rows, current.cursorRow) ? row.end - 1 : row.end;
    _go(end, select: select, backward: false);
  }

  /// [given], or, for any but the latest layout or one taken before the
  /// last change, the text laid out again as the latest was: its offsets
  /// may no longer be this text's, nor its rows this width's.
  TextAreaLayout _current(TextAreaLayout given) {
    final last = _last ?? given;
    return identical(given, _last) && given._version == _version
        ? given
        : layout(width: last.width, maxHeight: last._maxHeight);
  }

  bool _moveRows(TextAreaLayout given, int by, bool select) {
    final layout = _current(given);
    final rows = layout.rows;
    final target = layout.cursorRow + by;
    // A plain vertical move drops a selection where the cursor is, as
    // OpenTUI's does, and moves from there.
    final anchor = select ? (_anchor ?? _cursor) : null;
    if (target < 0 || target >= rows.length) {
      if (!select && _anchor != null) _place(_cursor, null);
      return false;
    }
    final goal = _goal ?? layout.cursorColumn;
    final row = rows[target];
    // The end of a row its line goes on from is the next row's start.
    final limit = _continues(rows, target) ? row.end - 1 : row.end;
    var at = row.start;
    var cells = 0;
    while (at < limit) {
      final w = _cellsOf(_chars[at]);
      if (cells + w > goal) break;
      cells += w;
      at++;
    }
    // A move keeps the goal, so it skips what an edit settles; an edit a
    // listener makes in answer settles, and forgets the goal, as any other.
    _cursor = at;
    _anchor = anchor == at ? null : anchor;
    _remembered = (text, _cursor);
    _goal = goal;
    _version++;
    super.notifyListeners();
    return true;
  }

  @override
  set text(String value) {
    _undo.clear();
    _redo.clear();
    _goal = null;
    final chars = _normalized(value).characters.toList();
    if (_cursor == chars.length && _anchor == null && _sameChars(chars)) {
      return;
    }
    _chars = chars;
    _cursor = chars.length;
    _anchor = null;
    _remembered = (text, _cursor);
    notifyListeners();
  }

  bool _sameChars(List<String> chars) {
    if (chars.length != _chars.length) return false;
    for (var i = 0; i < chars.length; i++) {
      if (chars[i] != _chars[i]) return false;
    }
    return true;
  }

  // Every edit and every cursor move forgets the vertical goal, even one
  // that changes nothing and so does not notify.

  /// Setting it collapses any selection there.
  @override
  set cursor(int value) {
    _goal = null;
    _place(value, null);
  }

  /// Replaces the selection, if any, with [s].
  @override
  void insert(String s) {
    _goal = null;
    final add = _normalized(s).characters.toList();
    if (add.isEmpty) return;
    _cut();
    _chars.insertAll(_cursor, add);
    _cursor += add.length;
    notifyListeners();
  }

  /// Deletes the selection instead, if any.
  @override
  void backspace() {
    if (_deleteSelection()) return;
    super.backspace();
  }

  /// Deletes the selection instead, if any.
  @override
  void delete() {
    if (_deleteSelection()) return;
    super.delete();
  }

  @override
  void deleteToStart() {
    _goal = null;
    super.deleteToStart();
  }

  @override
  void deleteToEnd() {
    _goal = null;
    super.deleteToEnd();
  }

  @override
  void clear() => text = '';

  /// The line the cursor is on, from 0.
  int get cursorLine {
    var line = 0;
    for (var i = 0; i < _cursor; i++) {
      if (_chars[i] == '\n') line++;
    }
    return line;
  }

  /// The cursor's grapheme column in its line, from 0.
  int get cursorColumn => _cursor - _lineStart(_cursor);

  int _lineStart(int at) {
    var i = at;
    while (i > 0 && _chars[i - 1] != '\n') {
      i--;
    }
    return i;
  }

  int _lineEnd(int at) {
    var i = at;
    while (i < _chars.length && _chars[i] != '\n') {
      i++;
    }
    return i;
  }

  /// Moves the cursor one grapheme left, over a line break too. With
  /// [select] it extends the selection; without, a selection collapses to
  /// its start.
  void moveLeft({bool select = false}) =>
      _go(_cursor - 1, select: select, backward: true);

  /// Moves the cursor one grapheme right, over a line break too. With
  /// [select] it extends the selection; without, a selection collapses to
  /// its end.
  void moveRight({bool select = false}) =>
      _go(_cursor + 1, select: select, backward: false);

  /// Moves the cursor to the text's start, as [moveLeft] treats a selection.
  void moveToStart({bool select = false}) =>
      _go(0, select: select, backward: true);

  /// Moves the cursor to the text's end, as [moveRight] treats a selection.
  void moveToEnd({bool select = false}) =>
      _go(_chars.length, select: select, backward: false);

  /// Whether [g] separates words: ASCII whitespace and punctuation. Letters,
  /// digits, `_` and anything beyond ASCII make up words.
  static bool _separates(String g) {
    if (g.length != 1) return false;
    final c = g.codeUnitAt(0);
    if (c >= 0x80) return false;
    final letter =
        (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5a) ||
        (c >= 0x61 && c <= 0x7a) ||
        c == 0x5f;
    return !letter;
  }

  /// Where a word move right from the cursor lands, as OpenTUI's edit
  /// buffer moves: one grapheme on, to the end of the word there, then
  /// past the one separator after it. Stepping over a line break first
  /// stops it just after the break.
  int get _wordRight {
    final n = _chars.length;
    var i = _cursor;
    if (i >= n) return n;
    if (_chars[i++] == '\n') return i;
    while (i < n && !_separates(_chars[i])) {
      i++;
    }
    if (i < n) i++;
    return i;
  }

  /// Where a word move left from the cursor lands, as OpenTUI's edit
  /// buffer moves: one grapheme back, then to the start of the word before
  /// it. At a line's start, or reaching one, it stops at the end of the
  /// line before.
  int get _wordLeft {
    var i = _cursor;
    if (i == 0) return 0;
    if (_chars[i - 1] == '\n') return i - 1;
    i--;
    while (i > 0 && !_separates(_chars[i - 1])) {
      i--;
    }
    if (i > 0 && _chars[i - 1] == '\n') i--;
    return i;
  }

  /// Moves the cursor to the start of the word before it, as [moveLeft]
  /// treats a selection.
  void moveWordLeft({bool select = false}) =>
      _go(_wordLeft, select: select, backward: true);

  /// Moves the cursor past the word after it, as [moveRight] treats a
  /// selection.
  void moveWordRight({bool select = false}) =>
      _go(_wordRight, select: select, backward: false);

  /// Deletes back to where [moveWordLeft] would land; the selection
  /// instead, if any.
  @override
  void deleteWordBefore() => deleteBefore(_cursor - _wordLeft);

  /// Deletes on to where [moveWordRight] would land, a line break on the
  /// way included; the selection instead, if any.
  void deleteWordAfter() {
    if (_deleteSelection()) return;
    final end = _wordRight;
    if (end == _cursor) return;
    _chars.removeRange(_cursor, end);
    notifyListeners();
  }

  /// Deletes up to [count] graphemes before the cursor; the selection
  /// instead, if any.
  void deleteBefore(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    if (_deleteSelection()) return;
    _goal = null;
    final start = _cursor - (count < _cursor ? count : _cursor);
    if (start == _cursor) return;
    _chars.removeRange(start, _cursor);
    _cursor = start;
    notifyListeners();
  }

  /// Moves the cursor to the start of its line; already there, to the end
  /// of the line before, as OpenTUI's line-home steps. As [moveLeft] treats
  /// a selection.
  void moveToLineStart({bool select = false}) {
    final start = _lineStart(_cursor);
    final target = start == _cursor && _cursor > 0 ? _cursor - 1 : start;
    _go(target, select: select, backward: true);
  }

  /// Moves the cursor to the end of its line, before its line break;
  /// already there, to the start of the line after, as OpenTUI's line-end
  /// steps. As [moveRight] treats a selection.
  void moveToLineEnd({bool select = false}) {
    final end = _lineEnd(_cursor);
    final target = end == _cursor && _cursor < _chars.length
        ? _cursor + 1
        : end;
    _go(target, select: select, backward: false);
  }

  /// Deletes from the start of the cursor's line to the cursor; at a line's
  /// start, the break before it, joining the lines. Acts from the cursor
  /// whatever is selected, as OpenTUI's does: a selection goes only when
  /// something is deleted.
  void deleteToLineStart() {
    _goal = null;
    final line = _lineStart(_cursor);
    final start = line == _cursor && _cursor > 0 ? _cursor - 1 : line;
    if (start == _cursor) return;
    _chars.removeRange(start, _cursor);
    _cursor = start;
    notifyListeners();
  }

  /// Deletes from the cursor to the end of its line, keeping the break.
  /// Acts from the cursor whatever is selected, as [deleteToLineStart].
  void deleteToLineEnd() {
    _goal = null;
    final end = _lineEnd(_cursor);
    if (end == _cursor) return;
    _chars.removeRange(_cursor, end);
    notifyListeners();
  }

  /// Deletes the cursor's line and one line break: the one after it, the
  /// cursor going to the next line's start; on the last line the one
  /// before it, the cursor going to the previous line's end. A selection
  /// collapses at the cursor first.
  void deleteLine() {
    _goal = null;
    _collapse();
    final start = _lineStart(_cursor);
    final end = _lineEnd(_cursor);
    final (from, to) = end < _chars.length
        ? (start, end + 1)
        : (start > 0 ? start - 1 : start, end);
    if (from == to) return;
    _chars.removeRange(from, to);
    _cursor = from;
    notifyListeners();
  }

  /// Breaks the line at the cursor, which moves to the new line's start. A
  /// selection collapses at the cursor first.
  void newline() {
    _collapse();
    insert('\n');
  }

  /// Turns a backslash just before the cursor into a line break, the
  /// cursor after it; false, changing nothing, when there is none. A
  /// selection collapses at the cursor first.
  bool continueLine() {
    _goal = null;
    if (_cursor == 0 || _chars[_cursor - 1] != r'\') return false;
    _collapse();
    _chars[_cursor - 1] = '\n';
    notifyListeners();
    return true;
  }
}

/// The text of a [TextAreaController] wrapped to a width: every visual row,
/// the rows shown, and where the cursor is. A snapshot; the controller lays
/// out again after any change.
class TextAreaLayout {
  TextAreaLayout._({
    required this.rows,
    required this.cursorRow,
    required this.cursorColumn,
    required this.rowOffset,
    required this.width,
    required this.height,
    required int version,
    required int maxHeight,
  }) : _version = version,
       _maxHeight = maxHeight;

  /// Every visual row of the text, in order; one empty row for no text.
  final List<TextAreaRow> rows;

  /// The visual row the cursor is on.
  final int cursorRow;

  /// The cursor's column in its row, in cells.
  final int cursorColumn;

  /// The first row shown.
  final int rowOffset;

  /// The cells a row may take.
  final int width;

  /// How many rows are shown.
  final int height;

  final int _version;
  final int _maxHeight;

  /// The rows shown: [height] of them from [rowOffset].
  List<TextAreaRow> get shownRows =>
      rows.sublist(rowOffset, rowOffset + height);
}

/// One visual row of a [TextAreaLayout]: a piece of a line.
class TextAreaRow {
  const TextAreaRow._(
    this.text,
    this.line,
    this.piece,
    this.last,
    this.start,
    this.end,
  );

  /// The row's text, tabs kept.
  final String text;

  /// The line it is part of, from 0.
  final int line;

  /// Which piece of its line it is, from 0.
  final int piece;

  /// Whether it is the last row of the whole text.
  final bool last;

  /// The grapheme offset of its first grapheme.
  final int start;

  /// The grapheme offset just past its last grapheme; a line break after
  /// it is not in it.
  final int end;

  @override
  String toString() =>
      'TextAreaRow($line.$piece, $start..$end, "$text"'
      '${last ? ", last" : ""})';
}
