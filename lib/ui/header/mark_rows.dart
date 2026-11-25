import 'package:color_models/color_models.dart' as cm;
import 'mark.dart';

/// The middle stop on Chorded's diagonal sRGB gradient.
const middle = 0.55;

/// The mark's colour information, without terminal depth guessing.
sealed class MarkColour {
  const MarkColour();
}

/// Three sRGB stops, at zero, middle and one.
final class MarkGradient extends MarkColour {
  const MarkGradient(this.stops);
  final List<String> stops;
}

/// One theme tone for every filled half.
final class MarkTone extends MarkColour {
  const MarkTone(this.tone);
  final String tone;
}

/// No explicit foreground or background.
final class MarkPlain extends MarkColour {
  const MarkPlain();
}

/// A run of glyphs with common foreground and background.
typedef MarkSegment = ({String text, String? color, String? backgroundColor});

/// Paints the original gradient in sRGB through the tried colour package.
String Function(double) markPaint(List<String> stops) {
  final colors = stops.map(cm.RgbColor.fromHex).toList();
  return (t) {
    final first = t <= middle;
    return colors[first ? 0 : 1]
        .interpolate(
          colors[first ? 1 : 2],
          first ? t / middle : (t - middle) / (1 - middle),
        )
        .hex;
  };
}

/// Two half rows become one row, merging adjacent equal styles.
List<List<MarkSegment>> markRows(MarkGrid grid, MarkColour colour) {
  final String? Function(double) paint = switch (colour) {
    MarkGradient(:final stops) => markPaint(stops),
    MarkTone(:final tone) => (_) => tone,
    MarkPlain() => (_) => null,
  };
  final rows = <List<MarkSegment>>[];
  for (var half = 0; half < grid.length; half += 2) {
    final top = grid[half];
    final bottom = half + 1 < grid.length ? grid[half + 1] : <double?>[];
    final row = <MarkSegment>[];
    for (var column = 0; column < top.length; column++) {
      final upper = top[column];
      final lower = column < bottom.length ? bottom[column] : null;
      final fg = upper == null ? null : paint(upper);
      final bg = lower == null ? null : paint(lower);
      final segment = upper != null && lower != null
          ? fg == bg
                ? (text: '█', color: fg, backgroundColor: null)
                : (text: '▀', color: fg, backgroundColor: bg)
          : upper != null
          ? (text: '▀', color: fg, backgroundColor: null)
          : lower != null
          ? (text: '▄', color: bg, backgroundColor: null)
          : (text: ' ', color: null, backgroundColor: null);
      if (row.isNotEmpty &&
          row.last.color == segment.color &&
          row.last.backgroundColor == segment.backgroundColor) {
        final last = row.removeLast();
        row.add((
          text: last.text + segment.text,
          color: last.color,
          backgroundColor: last.backgroundColor,
        ));
      } else {
        row.add(segment);
      }
    }
    rows.add(row);
  }
  return rows;
}
