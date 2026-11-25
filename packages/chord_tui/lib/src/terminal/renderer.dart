import 'buffer.dart';
import 'style.dart';

/// The escape sequence that turns the screen from [prev] into [next],
/// writing only the cells that changed.
///
/// With [prev] null, or of another size, the whole screen is drawn.
String diffBuffers(Buffer? prev, Buffer next, {bool synchronized = true}) {
  final sb = StringBuffer();
  if (synchronized) sb.write('\x1b[?2026h');
  sb.write('\x1b[?25l');
  // The previous frame, or null when everything must be drawn. Kept as its
  // own nullable local and handed to [_unchanged] as non-null: reading
  // `prev` through a promotion carried by a separate bool miscompiled under
  // dart compile exe (CTUI-38) and crashed on the first frame.
  final Buffer? before =
      prev != null && prev.width == next.width && prev.height == next.height
      ? prev
      : null;
  if (before == null) sb.write('\x1b[0m\x1b[2J');

  Style? current;
  var cx = -1, cy = -1;
  for (var y = 0; y < next.height; y++) {
    for (var x = 0; x < next.width; x++) {
      final ch = next.charAt(x, y);
      if (ch == '') continue;
      final st = next.styleAt(x, y);
      final wide = x + 1 < next.width && next.charAt(x + 1, y) == '';
      if (before != null && _unchanged(before, x, y, ch, st, wide)) continue;
      if (x != cx || y != cy) sb.write('\x1b[${y + 1};${x + 1}H');
      if (st != current) {
        sb.write(st.sgr);
        current = st;
      }
      sb.write(ch);
      cx = x + (wide ? 2 : 1);
      cy = y;
    }
  }
  if (current != null || next.cursor != null) sb.write('\x1b[0m');
  final cursor = next.cursor;
  if (cursor != null) {
    sb.write('\x1b[${next.cursorStyle.index + 1} q');
    sb.write('\x1b[${cursor.y + 1};${cursor.x + 1}H\x1b[?25h');
  }
  if (synchronized) sb.write('\x1b[?2026l');
  return sb.toString();
}

/// Whether cell ([x], [y]) of [prev] already shows [ch] in [st], with the
/// same wide-or-narrow shape, so it need not be written again.
bool _unchanged(Buffer prev, int x, int y, String ch, Style st, bool wide) {
  if (prev.charAt(x, y) != ch || prev.styleAt(x, y) != st) return false;
  final nextIsTail = x + 1 < prev.width && prev.charAt(x + 1, y) == '';
  return wide == nextIsTail;
}
