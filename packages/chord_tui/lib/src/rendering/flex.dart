import '../foundation/geometry.dart';
import '../terminal/buffer.dart';
import 'box.dart';

/// The direction a flex lays its children along.
enum Axis {
  /// Left to right, as a row.
  horizontal,

  /// Top to bottom, as a column.
  vertical,
}

/// Where a flex puts its children along its main axis when they leave
/// space free.
enum MainAxisAlignment {
  /// Packed at the start.
  start,

  /// Packed at the end.
  end,

  /// Packed in the middle.
  center,

  /// The free space between children, none at the ends.
  spaceBetween,

  /// Half a gap at each end and a whole one between children.
  spaceAround,

  /// Equal gaps between children and at both ends.
  spaceEvenly,
}

/// Where a flex puts each child across its main axis.
enum CrossAxisAlignment {
  /// At the start of the cross axis.
  start,

  /// At the end of the cross axis.
  end,

  /// In the middle of the cross axis.
  center,

  /// Stretched to fill the cross axis.
  stretch,
}

/// How much of its main axis a flex takes.
enum MainAxisSize {
  /// Only what its children need.
  min,

  /// All that its constraints allow.
  max,
}

/// Whether a flexible child must fill the share it is given.
enum FlexFit {
  /// The child must fill its share.
  tight,

  /// The child may be smaller than its share.
  loose,
}

/// Marks a child of a flex with its share of the free space.
class RenderFlexible extends RenderProxyBox {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderFlexible);

  /// A child taking [flex] shares of the free space, fitted by [fit].
  RenderFlexible({this.flex = 1, this.fit = FlexFit.tight});

  /// The child's shares of the free space.
  int flex;

  /// Whether the child must fill its share.
  FlexFit fit;
}

/// Lays children out in a row or a column, Flutter's way, in whole cells.
class RenderFlex extends RenderBox with RenderWithChildren {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderFlex);

  /// A flex along [direction].
  RenderFlex({
    required this.direction,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.spacing = 0,
  });

  /// The main axis: a row or a column.
  Axis direction;

  /// Where children go along the main axis.
  MainAxisAlignment mainAxisAlignment;

  /// Where children go across the main axis.
  CrossAxisAlignment crossAxisAlignment;

  /// How much of the main axis the flex takes.
  MainAxisSize mainAxisSize;

  /// The cells left between neighbouring children.
  int spacing;

  bool get _horizontal => direction == Axis.horizontal;
  int _main(Size s) => _horizontal ? s.width : s.height;
  int _cross(Size s) => _horizontal ? s.height : s.width;

  BoxConstraints _box(int minMain, int maxMain, int minCross, int maxCross) =>
      _horizontal
      ? BoxConstraints(
          minWidth: minMain,
          maxWidth: maxMain,
          minHeight: minCross,
          maxHeight: maxCross,
        )
      : BoxConstraints(
          minWidth: minCross,
          maxWidth: maxCross,
          minHeight: minMain,
          maxHeight: maxMain,
        );

  @override
  void performLayout() {
    final maxMain = _horizontal ? constraints.maxWidth : constraints.maxHeight;
    final maxCross = _horizontal ? constraints.maxHeight : constraints.maxWidth;
    final bounded = maxMain < unbounded;
    final stretch =
        crossAxisAlignment == CrossAxisAlignment.stretch &&
        maxCross < unbounded;
    final minCross = stretch ? maxCross : 0;

    final gaps = children.isEmpty ? 0 : spacing * (children.length - 1);
    var allocated = gaps;
    var totalFlex = 0;
    var crossSize = 0;

    for (final c in children) {
      final flex = c is RenderFlexible ? c.flex : 0;
      if (flex > 0 && bounded) {
        totalFlex += flex;
        continue;
      }
      c.layout(_box(0, unbounded, minCross, maxCross));
      allocated += _main(c.size);
      if (_cross(c.size) > crossSize) crossSize = _cross(c.size);
    }

    if (totalFlex > 0) {
      final free = maxMain - allocated > 0 ? maxMain - allocated : 0;
      var remainder = free;
      var flexSeen = 0;
      for (final c in children) {
        if (c is! RenderFlexible || c.flex <= 0) continue;
        flexSeen += c.flex;
        // Shares are rounded so that together they fill the free space.
        final upTo = free * flexSeen ~/ totalFlex;
        final share = upTo - (free - remainder);
        remainder -= share;
        final tight = c.fit == FlexFit.tight;
        c.layout(_box(tight ? share : 0, share, minCross, maxCross));
        allocated += _main(c.size);
        if (_cross(c.size) > crossSize) crossSize = _cross(c.size);
      }
    }

    final mainSize = mainAxisSize == MainAxisSize.max && bounded
        ? maxMain
        : allocated;
    if (stretch) crossSize = maxCross;
    size = _horizontal ? Size(mainSize, crossSize) : Size(crossSize, mainSize);
    size = constraints.constrain(size);
    final actualMain = _main(size);
    final actualCross = _cross(size);

    final free = actualMain - allocated > 0 ? actualMain - allocated : 0;
    final n = children.length;
    var lead = 0;
    var between = spacing;
    switch (mainAxisAlignment) {
      case MainAxisAlignment.start:
        break;
      case MainAxisAlignment.end:
        lead = free;
      case MainAxisAlignment.center:
        lead = free ~/ 2;
      case MainAxisAlignment.spaceBetween:
        if (n > 1) between += free ~/ (n - 1);
      case MainAxisAlignment.spaceAround:
        if (n > 0) {
          final unit = free ~/ n;
          lead = unit ~/ 2;
          between += unit;
        }
      case MainAxisAlignment.spaceEvenly:
        if (n > 0) {
          final unit = free ~/ (n + 1);
          lead = unit;
          between += unit;
        }
    }

    var pos = lead;
    for (final c in children) {
      final cs = _cross(c.size);
      final crossPos = switch (crossAxisAlignment) {
        CrossAxisAlignment.start || CrossAxisAlignment.stretch => 0,
        CrossAxisAlignment.end => actualCross - cs,
        CrossAxisAlignment.center => (actualCross - cs) ~/ 2,
      };
      c.offset = _horizontal ? Offset(pos, crossPos) : Offset(crossPos, pos);
      pos += _main(c.size) + between;
    }
  }

  @override
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    final visible = clip.intersect(Rect.fromOffsetSize(origin, size));
    for (final child in children) {
      final at = origin + child.offset;
      if (visible.intersect(Rect.fromOffsetSize(at, child.size)).isEmpty) {
        continue;
      }
      visitor(child, at, visible);
    }
  }

  @override
  void paint(Canvas canvas, Offset origin) => paintChildren(canvas, origin);
}

/// Children stacked on top of one another; later ones paint over earlier.
class RenderStack extends RenderBox with RenderWithChildren {
  /// A stack with no children yet.
  RenderStack();

  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderStack);

  @override
  void performLayout() {
    var w = 0, h = 0, sized = false;
    for (final c in children) {
      if (c is RenderPositioned) continue;
      sized = true;
      c.layout(constraints.loosen());
      c.offset = Offset.zero;
      if (c.size.width > w) w = c.size.width;
      if (c.size.height > h) h = c.size.height;
    }
    if (sized) {
      size = constraints.constrain(Size(w, h));
    } else {
      // With only positioned children there is nothing to hug: fill what
      // is bounded.
      size = Size(
        constraints.hasBoundedWidth
            ? constraints.maxWidth
            : constraints.minWidth,
        constraints.hasBoundedHeight
            ? constraints.maxHeight
            : constraints.minHeight,
      );
    }
    for (final c in children) {
      if (c is! RenderPositioned) continue;
      final (minW, maxW) = _extent(c.left, c.right, c.width, size.width);
      final (minH, maxH) = _extent(c.top, c.bottom, c.height, size.height);
      c.layout(
        BoxConstraints(
          minWidth: minW,
          maxWidth: maxW,
          minHeight: minH,
          maxHeight: maxH,
        ),
      );
      c.offset = Offset(
        _place(c.left, c.right, c.size.width, size.width),
        _place(c.top, c.bottom, c.size.height, size.height),
      );
    }
  }

  static (int, int) _extent(int? start, int? end, int? extent, int room) {
    if (start != null && end != null) {
      final e = room - start - end;
      return e < 0 ? (0, 0) : (e, e);
    }
    if (extent != null) return (extent, extent);
    return (0, room);
  }

  static int _place(int? start, int? end, int child, int room) =>
      start ?? (end != null ? room - end - child : 0);

  @override
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    final visible = clip.intersect(Rect.fromOffsetSize(origin, size));
    visitChildren((child) => visitor(child, origin + child.offset, visible));
  }

  @override
  void paint(Canvas canvas, Offset origin) => paintChildren(canvas, origin);
}

/// Marks a child of a stack with where it goes: edges from the stack's
/// sides and a size, in cells.
class RenderPositioned extends RenderProxyBox {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderPositioned);

  /// A child placed by the given edges and size.
  RenderPositioned({
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
  });

  /// Cells from the stack's left side to the child's.
  int? left;

  /// Cells from the stack's top to the child's.
  int? top;

  /// Cells from the child's right side to the stack's.
  int? right;

  /// Cells from the child's bottom to the stack's.
  int? bottom;

  /// The child's width.
  int? width;

  /// The child's height.
  int? height;
}
