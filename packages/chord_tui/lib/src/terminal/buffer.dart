import 'package:characters/characters.dart';

import '../foundation/geometry.dart';
import '../text/width.dart';
import 'style.dart';
import 'cursor.dart';

/// A grid of cells: what the screen shows in one frame.
///
/// A wide grapheme sits in its first cell; the cell after it holds `''`.
class Buffer {
  /// A blank grid of [width] by [height] cells.
  Buffer(this.width, this.height)
    : _chars = List.filled(width * height, ' '),
      _styles = List.filled(width * height, Style.plain);

  /// The width, in cells.
  final int width;

  /// The height, in rows.
  final int height;
  final List<String> _chars;
  final List<Style> _styles;

  /// Where the terminal cursor shows after the frame; hidden when null.
  Offset? cursor;

  /// The shape and blink policy of the frame's cursor claim.
  CursorStyle cursorStyle = CursorStyle.steadyBlock;

  /// The grid's width and height.
  Size get size => Size(width, height);

  /// The grapheme at ([x], [y]); `''` after a wide one.
  String charAt(int x, int y) => _chars[y * width + x];

  /// The style of the cell at ([x], [y]).
  Style styleAt(int x, int y) => _styles[y * width + x];

  /// Puts grapheme [g] of [w] cells at ([x], [y]).
  void set(int x, int y, String g, int w, Style style) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    // A lone zero-width mark, written as a cell of its own, joins the glyph
    // to its left on a terminal that never advances past it: the screen
    // and the frame would part, and a redraw of the cell would leave the
    // mark behind (CTUI-96). It takes its cell as a space in its style.
    if (w == 0) {
      g = ' ';
      w = 1;
    }
    if (w == 2 && x == width - 1) {
      g = ' ';
      w = 1;
    }
    final i = y * width + x;
    final caret = cursor;
    if (caret != null && caret.y == y) {
      // Replacing either half of a wide glyph also erases the other half.
      final left = _chars[i] == '' && x > 0 ? x - 1 : x;
      var right = x + w;
      if (right < width && _chars[y * width + right] == '') right++;
      var caretLeft = caret.x;
      var caretRight = caret.x + 1;
      if (_chars[y * width + caret.x] == '' && caret.x > 0) caretLeft--;
      if (caretRight < width && _chars[y * width + caretRight] == '') {
        caretRight++;
      }
      if (left < caretRight && right > caretLeft) cursor = null;
    }
    // Writing over half of a wide grapheme blanks its other half.
    if (_chars[i] == '' && x > 0) _chars[i - 1] = ' ';
    if (x + 1 < width && _chars[i + 1] == '' && w == 1) _chars[i + 1] = ' ';
    _chars[i] = g;
    _styles[i] = style;
    if (w == 2) {
      if (x + 2 < width && _chars[i + 2] == '') _chars[i + 2] = ' ';
      _chars[i + 1] = '';
      _styles[i + 1] = style;
    }
  }

  /// The text of row [y], without styles and trailing spaces kept.
  String line(int y) {
    final sb = StringBuffer();
    for (var x = 0; x < width; x++) {
      sb.write(_chars[y * width + x]);
    }
    return sb.toString();
  }

  /// Every row as text.
  List<String> get lines => [for (var y = 0; y < height; y++) line(y)];

  @override
  String toString() => lines.map((l) => l.trimRight()).join('\n');
}

/// Draws into a [Buffer] within a clip rectangle.
class Canvas {
  /// A canvas over [buffer], clipped to [clip] or the whole buffer.
  Canvas(this.buffer, [Rect? clip])
    : clip = clip ?? Rect(0, 0, buffer.width, buffer.height);

  /// The buffer drawn into.
  final Buffer buffer;

  /// The rectangle drawing is kept within.
  final Rect clip;

  /// A canvas on the same buffer, clipped also to [r].
  Canvas clipped(Rect r) => Canvas(buffer, clip.intersect(r));

  /// Draws one grapheme, keeping the background already under it.
  void put(int x, int y, String g, int w, Style style) {
    if (!clip.contains(x, y)) return;
    if (w == 2 && !clip.contains(x + 1, y)) {
      g = ' ';
      w = 1;
    }
    if (style.bg == null) {
      final under = buffer.styleAt(x, y).bg;
      if (under != null) style = style.copyWith(bg: under);
    }
    buffer.set(x, y, g, w, style);
  }

  /// Draws [text] on one line from ([x], [y]); returns the cells it took.
  int drawText(int x, int y, String text, [Style style = Style.plain]) {
    var cx = x;
    for (final g in text.characters) {
      final w = graphemeWidth(g);
      if (w == 0) continue;
      put(cx, y, g, w, style);
      cx += w;
      if (cx >= clip.right) break;
    }
    return cx - x;
  }

  /// Fills [r] with [char] in [style], replacing what was there.
  void fill(Rect r, [Style style = Style.plain, String char = ' ']) {
    final area = clip.intersect(r);
    for (var y = area.top; y < area.bottom; y++) {
      for (var x = area.left; x < area.right; x++) {
        buffer.set(x, y, char, 1, style);
      }
    }
  }

  /// Claims the terminal cursor at [p], within the clip and buffer bounds.
  void setCursor(Offset p, {CursorStyle style = CursorStyle.steadyBlock}) {
    if (!clip.contains(p.x, p.y) ||
        p.x < 0 ||
        p.y < 0 ||
        p.x >= buffer.width ||
        p.y >= buffer.height) {
      return;
    }
    buffer.cursor = p;
    buffer.cursorStyle = style;
  }
}
