import 'package:meta/meta.dart';

import '../text/selection_layout.dart';
import 'geometry.dart';
import 'selection.dart';

/// A current painted source, independent of widget and render-box lifetimes.
@internal
class SelectionSurface {
  /// Uses actual paint origin, effective clip and a shared immutable shape.
  const SelectionSurface({
    required this.owner,
    required this.layout,
    required this.origin,
    required this.clip,
    required this.bounds,
    required this.order,
  });

  /// Identity used by the paint coverage traversal.
  final Object owner;

  /// Authoritative glyph and source-boundary map.
  final SelectionLayout layout;

  /// Global paint origin.
  final Offset origin;

  /// Effective global clip.
  final Rect clip;

  /// Full current source-box geometry before viewport clipping.
  final Rect bounds;

  /// This surface's position in the existing paint traversal.
  final int order;
}

/// A source endpoint resolved from actual exposed geometry.
@internal
class SelectionHit {
  /// Keeps only the current surface and its source-local endpoint.
  const SelectionHit(this.surface, this.position);

  /// The source surface that most recently supplied an eligible hit.
  final SelectionSurface surface;

  /// Its source-local grapheme endpoint.
  final SelectionPosition position;
}

/// The last known self-paint write at one terminal cell.
@internal
class SelectionCellOwner {
  /// Associates paint ownership with traversal order, without reading a buffer.
  const SelectionCellOwner(this.owner, this.order);

  /// Exact box identity that painted the cell.
  final Object owner;

  /// Its phase position in paint order.
  final int order;
}

/// Pure endpoint projection through settled glyphs and paint coverage.
@internal
class SelectionGeometry {
  /// Freezes current sources and the terminal-cell exposure map.
  SelectionGeometry(
    List<SelectionSurface> surfaces,
    Map<Offset, SelectionCellOwner> cells,
  ) : surfaces = List.unmodifiable(surfaces),
      cells = Map.unmodifiable(cells);

  /// Selectable surfaces in paint order.
  final List<SelectionSurface> surfaces;

  /// Current last self-paint writers.
  final Map<Offset, SelectionCellOwner> cells;

  /// Whether every cell of a source glyph is currently exposed.
  bool exposed(SelectionSurface surface, int x, int y, int width) {
    if (width <= 0) return false;
    for (var dx = 0; dx < width; dx++) {
      final at = Offset(x + dx, y);
      if (!surface.clip.contains(at.x, at.y) ||
          cells[at]?.owner != surface.owner) {
        return false;
      }
    }
    return true;
  }

  /// Finds a complete glyph or genuine blank LF boundary, frontmost first.
  SelectionHit? hit(Offset point) {
    for (final surface in surfaces.reversed) {
      if (!surface.clip.contains(point.x, point.y)) continue;
      final y = point.y - surface.origin.y;
      if (y < 0 || y >= surface.layout.rows.length) continue;
      final row = surface.layout.rows[y];
      for (final glyph in row.glyphs.reversed) {
        final x = surface.origin.x + glyph.x;
        if (glyph.sourceId != null &&
            glyph.offset != null &&
            point.x >= x &&
            point.x < x + glyph.glyph.width &&
            exposed(surface, x, point.y, glyph.glyph.width)) {
          return SelectionHit(
            surface,
            SelectionPosition(glyph.sourceId!, glyph.offset!),
          );
        }
      }
      final lane = row.blankLane;
      final lastWriter = cells[point];
      if (row.sourceId != null &&
          row.hardBreak != null &&
          lane != null &&
          point.x >= surface.origin.x + lane.$1 &&
          point.x < surface.origin.x + lane.$2 &&
          (lastWriter == null ||
              lastWriter.owner == surface.owner ||
              lastWriter.order <= surface.order)) {
        return SelectionHit(
          surface,
          SelectionPosition(row.sourceId!, row.hardBreak!),
        );
      }
    }
    return null;
  }

  /// Retains the previous eligible fragment on a miss, clamping within it.
  SelectionHit? resolve(Offset point, SelectionPosition? previous) {
    final direct = hit(point);
    if (direct != null || previous == null) return direct;
    final surface = surfaces
        .where(
          (s) => s.layout.rows.any((row) => row.sourceId == previous.sourceId),
        )
        .firstOrNull;
    if (surface == null) return null;
    if (!surface.clip.contains(point.x, point.y) &&
        surface.bounds.contains(point.x, point.y)) {
      return SelectionHit(surface, previous);
    }
    final rows = [
      for (final (y, row) in surface.layout.rows.indexed)
        if (row.sourceId == previous.sourceId) (y, row),
    ];
    if (rows.isEmpty) return null;
    final local = point - surface.origin;
    final pair =
        rows.where((pair) => pair.$1 >= local.y).firstOrNull ?? rows.last;
    final row = pair.$2;
    final int offset;
    if (local.y < rows.first.$1) {
      offset = rows.first.$2.start;
    } else if (local.y > rows.last.$1) {
      offset = rows.last.$2.end;
    } else {
      final semantic = row.glyphs.where(
        (cell) => cell.sourceId == previous.sourceId && cell.offset != null,
      );
      if (semantic.isEmpty) {
        final lane = row.blankLane;
        offset = lane != null && local.x >= lane.$1 && local.x < lane.$2
            ? previous.offset
            : row.hardBreak ?? row.start;
      } else if (local.x < semantic.first.x) {
        offset = row.start;
      } else if (local.x >= semantic.last.x + semantic.last.glyph.width) {
        offset = row.end;
      } else {
        // A known-covered interior is not a hidden glyph hit or a nearest
        // boundary. Keep the last exact endpoint until an eligible hit/edge.
        offset = previous.offset;
      }
    }
    return SelectionHit(surface, SelectionPosition(previous.sourceId, offset));
  }
}
