import '../foundation/fold.dart';
import '../foundation/geometry.dart';
import '../terminal/buffer.dart';
import '../terminal/style.dart';
import '../text/width.dart';
import 'box.dart';
import 'paint_coverage.dart';

/// A one-line header over a body that shows only when [open], folded
/// under a `… N more lines` row where the rows run out; `Fold` is the
/// widget to use. With no [title] there is no header, as a dialog's body.
class RenderFold extends RenderBox with RenderWithChild {
  /// A fold titled [title].
  RenderFold({
    required this.title,
    required this.open,
    required this.markerStyle,
    required this.titleStyle,
    required this.countStyle,
  });

  /// What the header says after its marker; no header when null.
  String? title;

  /// Whether the body is laid out and painted.
  bool open;

  /// The style of the `▸` or `▾` marker.
  Style markerStyle;

  /// The style of the title.
  Style titleStyle;

  /// The style of the `… N more lines` row.
  Style countStyle;

  Folded _folded = (shown: 0, more: 0);

  int get _header => title == null ? 0 : 1;

  @override
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    final c = child;
    if (!open || c == null || _folded.shown <= 0) return;
    final visible = clip
        .intersect(Rect.fromOffsetSize(origin, size))
        .intersect(
          Rect(origin.x, origin.y + _header, size.width, _folded.shown),
        );
    visitor(c, origin + c.offset, visible);
  }

  @override
  bool hitTestSelf(Offset position) =>
      position.y < _header ||
      (_folded.more > 0 && position.y == _header + _folded.shown);

  @override
  void performLayout() {
    final room = constraints.maxHeight;
    final c = child;
    _folded = (shown: 0, more: 0);
    final t = title;
    var width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : (t == null ? 0 : cellWidth('▸ $t'));
    if (!open || c == null || room <= _header) {
      size = constraints.constrain(Size(width, room < _header ? 0 : _header));
      return;
    }
    // Measured at the width it gets, with no limit on its rows.
    c.layout(
      constraints.hasBoundedWidth
          ? BoxConstraints(minWidth: width, maxWidth: width)
          : const BoxConstraints(),
    );
    c.offset = Offset(0, _header);
    if (!constraints.hasBoundedWidth && c.size.width > width) {
      width = c.size.width;
    }
    final bodyRoom = constraints.hasBoundedHeight
        ? room - _header
        : c.size.height;
    _folded = foldOf(c.size.height, bodyRoom);
    size = constraints.constrain(
      Size(width, _header + _folded.shown + (_folded.more > 0 ? 1 : 0)),
    );
  }

  @override
  PaintCoverage describePaintCoverage(Rect localClip) {
    final clip = localClip.intersect(Rect.fromOffsetSize(Offset.zero, size));
    final t = title;
    final marker = open ? '▾ ' : '▸ ';
    final room = size.width - cellWidth(marker);
    return PaintCoverage(
      declaredFor: RenderFold,
      beforeChildren: [
        if (t != null && size.height > 0) ...[
          ...textCoverage(0, 0, marker, clip),
          if (room > 0)
            ...textCoverage(cellWidth(marker), 0, truncate(t, room), clip),
        ],
      ],
      afterChildren: [
        if (open && child != null && _folded.more > 0)
          ...textCoverage(
            0,
            _header + _folded.shown,
            truncate('  ${moreLines(_folded.more)}', size.width),
            clip,
          ),
      ],
    );
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    if (size.height <= 0) return;
    final clip = canvas.clipped(Rect.fromOffsetSize(origin, size));
    final t = title;
    if (t != null) {
      final marker = open ? '▾ ' : '▸ ';
      clip.drawText(origin.x, origin.y, marker, markerStyle);
      final room = size.width - cellWidth(marker);
      if (room > 0) {
        clip.drawText(
          origin.x + cellWidth(marker),
          origin.y,
          truncate(t, room),
          titleStyle,
        );
      }
    }
    final c = child;
    if (!open || c == null) return;
    final (:shown, :more) = _folded;
    paintChildren(canvas, origin);
    if (more > 0) {
      clip.drawText(
        origin.x,
        origin.y + _header + shown,
        truncate('  ${moreLines(more)}', size.width),
        countStyle,
      );
    }
  }
}
