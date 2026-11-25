import '../foundation/geometry.dart';
import '../terminal/buffer.dart';
import '../terminal/style.dart';
import 'basic.dart';
import 'box.dart';

/// Ties a [RenderFollower] to the [RenderLayerTarget] it is placed by.
///
/// The overlay whose page holds the target records its rectangle at each
/// layout, so a follower in that overlay is placed in the same frame.
class LayerLink {
  /// A link no target has recorded a rectangle in yet.
  LayerLink();

  RenderOverlay? _overlay;
  Rect? _rect;

  /// The target's rectangle in [overlay], if it was laid out in [overlay]'s
  /// page this frame.
  Rect? rectIn(RenderOverlay overlay) =>
      identical(_overlay, overlay) ? _rect : null;
}

/// The layers of an overlay, bottom first, each laid out at the overlay's
/// whole size; `Overlay` is the widget to use.
///
/// After laying out the first layer, the page, it records where the
/// [RenderLayerTarget]s in it are, for the followers in later layers.
class RenderOverlay extends RenderBox with RenderWithChildren {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderOverlay);

  /// An overlay that calls [onLayout] before laying out its layers and
  /// [onShown] after.
  RenderOverlay(this.onLayout, {this.onShown});

  /// Builds the layers not built yet and points [children] at them.
  void Function() onLayout;

  /// Told, after each layout, which layers show: none when the overlay
  /// has no cells, else all but those whose [RenderFollower], at the root
  /// or under single-child wrappers, is unlinked or has no room.
  void Function(List<bool> shown)? onShown;

  final List<LayerLink> _links = [];

  /// Where the overlay was painted last; followers paint from it.
  Offset paintOrigin = Offset.zero;

  @override
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    final visible = clip.intersect(Rect.fromOffsetSize(origin, size));
    visitChildren((child) => visitor(child, origin + child.offset, visible));
  }

  @override
  void performLayout() {
    assert(
      constraints.hasBoundedWidth && constraints.hasBoundedHeight,
      'An Overlay needs a bounded width and height.',
    );
    size = constraints.biggest;
    onLayout();
    for (final l in _links) {
      if (identical(l._overlay, this)) {
        l
          .._overlay = null
          .._rect = null;
      }
    }
    _links.clear();
    final layer = BoxConstraints.tight(size);
    for (final (i, c) in children.indexed) {
      c.layout(layer);
      c.offset = Offset.zero;
      if (i == 0) _collectTargets(c, Offset.zero);
    }
    // With no cells at all, no layer has room.
    final room = !size.isEmpty;
    onShown?.call([
      for (final c in children) room && (_followerIn(c)?.showing ?? true),
    ]);
  }

  // A follower sits at its layer's root or under single-child wrappers.
  static RenderFollower? _followerIn(RenderBox box) {
    RenderBox? b = box;
    while (b != null && b is! RenderOverlay) {
      if (b is RenderFollower) return b;
      b = b is RenderWithChild ? b.child : null;
    }
    return null;
  }

  // A nested overlay owns the targets in its own page.
  // A box its parent did not lay out this frame keeps an old offset.
  void _collectTargets(RenderBox box, Offset origin) {
    if (!box.laidOutThisPass) return;
    final at = origin + box.offset;
    if (box is RenderLayerTarget) {
      final link = box.link;
      if (identical(link._overlay, this)) {
        throw StateError('Two targets in one overlay share a LayerLink.');
      }
      link
        .._overlay = this
        .._rect = Rect.fromOffsetSize(at, box.size);
      _links.add(link);
    }
    if (box is RenderOverlay) return;
    box.visitChildren((c) => _collectTargets(c, at));
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    paintOrigin = origin;
    paintChildren(canvas, origin);
  }
}

/// Marks where [link]'s followers are placed from: its own rectangle,
/// which may have no rows.
class RenderLayerTarget extends RenderProxyBox {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderLayerTarget);

  /// A target for [link].
  RenderLayerTarget(this.link);

  /// The link its followers use.
  LayerLink link;
}

/// Places its child against [link]'s target, inside the room between the
/// anchor and the overlay's edges, and blanks the cells the child covers
/// before painting it.
class RenderFollower extends RenderBox with RenderWithChild {
  /// A follower in [overlay] placed by [link].
  RenderFollower({
    required this.overlay,
    required this.link,
    this.targetAnchor = Alignment.topLeft,
    this.followerAnchor = Alignment.topLeft,
    this.followOffset = Offset.zero,
    this.showWhenUnlinked = false,
    this.opaque = true,
  });

  /// The overlay the follower is a layer of.
  RenderOverlay overlay;

  /// The link to the target.
  LayerLink link;

  /// The point of the target the child is placed at.
  Alignment targetAnchor;

  /// The point of the child put on the target's point.
  Alignment followerAnchor;

  /// Moves the target's point, in cells.
  Offset followOffset;

  /// Whether the child shows at the overlay's corner when the target was
  /// not laid out this frame.
  bool showWhenUnlinked;

  /// Whether this follower fills, occludes and self-hits its whole child rectangle.
  bool opaque;

  Rect _room = Rect.zero;
  Offset _at = Offset.zero;

  /// Whether the child is laid out and painted: the target is linked, or
  /// [showWhenUnlinked], there is room, and the child takes some of it.
  bool get showing => _showing;
  var _showing = false;

  @override
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    final c = child;
    if (!_showing || c == null) return;
    final room = Rect(
      origin.x + _room.left,
      origin.y + _room.top,
      _room.width,
      _room.height,
    );
    visitor(c, origin + _at, clip.intersect(room));
  }

  @override
  bool hitTestSelf(Offset position) {
    final c = child;
    return opaque &&
        _showing &&
        c != null &&
        _room.contains(position.x, position.y) &&
        Rect.fromOffsetSize(_at, c.size).contains(position.x, position.y);
  }

  @override
  void performLayout() {
    size = constraints.constrain(overlay.size);
    final bounds = Rect.fromOffsetSize(Offset.zero, overlay.size);
    final target = link.rectIn(overlay);
    final c = child;
    if (target == null) {
      _room = bounds;
      _at = followOffset;
      _showing = showWhenUnlinked && !bounds.isEmpty && c != null;
      if (_showing) {
        c!.layout(BoxConstraints.loose(overlay.size));
        _showing = !c.size.isEmpty;
      }
      return;
    }
    final point =
        Offset(target.left, target.top) +
        targetAnchor.along(Size(target.width, target.height)) +
        followOffset;
    final fx = (followerAnchor.x + 1) / 2, fy = (followerAnchor.y + 1) / 2;
    final (left, w) = _span(point.x, fx, bounds.width);
    final (top, h) = _span(point.y, fy, bounds.height);
    _room = Rect(left, top, w, h);
    _showing = !_room.isEmpty && c != null;
    if (!_showing) return;
    c!.layout(BoxConstraints(maxWidth: w, maxHeight: h));
    // A child that takes no cells shows nothing, so its keys go too.
    _showing = !c.size.isEmpty;
    final pull = followerAnchor.along(c.size);
    _at = Offset(point.x - pull.x, point.y - pull.y);
  }

  /// The start and length of the room on one axis, for an anchor at [a]
  /// that a fraction [f] of the child lies before.
  static (int, int) _span(int a, double f, int length) {
    if (a < 0) a = 0;
    if (a > length) a = length;
    final int room;
    if (f <= 0) {
      room = length - a;
    } else if (f >= 1) {
      room = a;
    } else {
      final before = (a / f).floor(), after = ((length - a) / (1 - f)).floor();
      room = before < after ? before : after;
    }
    return (a - (room * f).floor(), room);
  }

  @override
  PaintCoverage describePaintCoverage(Rect localClip) {
    final c = child;
    return PaintCoverage(
      declaredFor: RenderFollower,
      beforeChildren: [
        if (opaque && _showing && c != null)
          Rect.fromOffsetSize(
            _at,
            c.size,
          ).intersect(_room).intersect(localClip),
      ],
    );
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    final o = overlay.paintOrigin;
    if (origin != o) {
      throw StateError(
        "A CompositedTransformFollower must sit at its entry's origin: "
        "make it the entry's root, or put it under widgets that do not "
        "move it.",
      );
    }
    final c = child;
    if (!_showing || c == null) return;
    final room = Rect(
      o.x + _room.left,
      o.y + _room.top,
      _room.width,
      _room.height,
    );
    final clipped = canvas.clipped(room);
    final at = o + _at;
    // Opaque: what is under the child is gone, colours and blanks alike.
    if (opaque) clipped.fill(Rect.fromOffsetSize(at, c.size), Style.plain);
    paintChildren(canvas, origin);
  }
}
