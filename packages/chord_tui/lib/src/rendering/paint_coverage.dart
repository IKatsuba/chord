import 'package:characters/characters.dart';

import '../foundation/geometry.dart';
import '../text/width.dart';

/// Mirrors Canvas.put, including its blank fallback for clipped wide glyphs.
Rect? glyphCoverage(int x, int y, int width, Rect clip) {
  if (!clip.contains(x, y)) return null;
  if (width == 2 && !clip.contains(x + 1, y)) width = 1;
  return width > 0 ? Rect(x, y, width, 1) : null;
}

/// Mirrors Canvas.drawText without interpreting terminal control strings.
Iterable<Rect> textCoverage(int x, int y, String text, Rect clip) sync* {
  for (final grapheme in text.characters) {
    final width = graphemeWidth(grapheme);
    if (width == 0) continue;
    final rect = glyphCoverage(x, y, width, clip);
    if (rect != null) yield rect;
    x += width;
    if (x >= clip.right) break;
  }
}
