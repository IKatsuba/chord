import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../foundation/selection_source.dart';
import '../terminal/buffer.dart';
import '../terminal/style.dart';
import '../text/selection_layout.dart';
import '../widgets/theme_data.dart';
import 'box.dart';
import 'paint_coverage.dart';

/// Draws the same immutable projection used for offscreen selection resolution.
@internal
class RenderSelectionContent extends RenderBox {
  /// Uses framework sources only; no application data or clipboard policy.
  RenderSelectionContent({
    required this.source,
    required this.theme,
    required this.base,
    this.language,
    this.growing,
    this.selectedCodeBlock,
  });

  /// Current immutable source snapshot.
  SelectionSource source;

  /// Current presentation palette.
  ThemeData theme;

  /// Inherited starting style.
  Style base;

  /// Optional code highlighting language, independent of source geometry.
  String? language;

  /// Optional highlighting override, independent of source geometry.
  bool? growing;

  /// Optional current code frame emphasis; it never changes source geometry.
  CodeBlockId? selectedCodeBlock;
  (SelectionSource, ThemeData, Style, String?, bool?, CodeBlockId?, int)? _key;
  SelectionLayout? _projection;

  /// Glyphs and semantic maps from the latest layout.
  SelectionLayout get projection => _projection!;

  @override
  bool hitTestSelf(Offset position) {
    final kind = selectionSourceKind(source);
    final geometry = selectionSourceGeometry(source);
    if (kind == SelectionSourceKind.code ||
        (kind == SelectionSourceKind.diff &&
            (!geometry.showTitle || geometry.title == null))) {
      return true;
    }
    return projection.hitRects.any(
      (rect) => rect.contains(position.x, position.y),
    );
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : unbounded;
    final key = (
      source,
      theme,
      base,
      language,
      growing,
      selectedCodeBlock,
      width,
    );
    if (_key != key) {
      _projection = shapeSelectionSource(
        source,
        width: width,
        theme: theme,
        base: base,
        language: language,
        growing: growing,
        selectedCodeBlock: selectedCodeBlock,
      );
      _key = key;
    }
    size = Size(projection.width, projection.height);
  }

  @override
  PaintCoverage describePaintCoverage(Rect localClip) {
    final clip = localClip.intersect(Rect.fromOffsetSize(Offset.zero, size));
    return PaintCoverage(
      declaredFor: RenderSelectionContent,
      beforeChildren: [
        for (final (y, row) in projection.rows.indexed) ...[
          if (row.background != null) Rect(0, y, size.width, 1).intersect(clip),
          for (final cell in row.glyphs)
            ?glyphCoverage(cell.x, y, cell.glyph.width, clip),
        ],
      ],
    );
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    final visible = canvas.clipped(Rect.fromOffsetSize(origin, size));
    final start = (visible.clip.top - origin.y).clamp(0, projection.height);
    final end = (visible.clip.bottom - origin.y).clamp(0, projection.height);
    for (var y = start; y < end; y++) {
      final row = projection.rows[y];
      if (row.background case final style?) {
        visible.fill(Rect(origin.x, origin.y + y, size.width, 1), style);
      }
      for (final cell in row.glyphs) {
        visible.put(
          origin.x + cell.x,
          origin.y + y,
          cell.glyph.text,
          cell.glyph.width,
          selectionGlyphStyle?.call(
                cell.x,
                y,
                cell.glyph.width,
                cell.glyph.style,
              ) ??
              cell.glyph.style,
        );
      }
    }
  }
}
