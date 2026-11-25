import '../foundation/geometry.dart';
import '../terminal/buffer.dart';
import '../terminal/style.dart';
import 'package:meta/meta.dart';

/// Visits one painted child at its global origin and effective clip.
typedef PaintChildVisitor =
    void Function(RenderBox child, Offset origin, Rect clip);

/// The cells a box writes before and after painting its children.
class PaintCoverage {
  /// Freezes local written rectangles for one exact declaring render type.
  PaintCoverage({
    required this.declaredFor,
    List<Rect> beforeChildren = const [],
    List<Rect> afterChildren = const [],
  }) : beforeChildren = List.unmodifiable(beforeChildren),
       afterChildren = List.unmodifiable(afterChildren);

  /// Declares that this exact render type writes no cells itself.
  const PaintCoverage.empty(this.declaredFor)
    : beforeChildren = const [],
      afterChildren = const [];

  /// The concrete render type authorizing this declaration.
  final Type declaredFor;

  /// Local cells written before the existing child traversal.
  final List<Rect> beforeChildren;

  /// Local cells written after the existing child traversal.
  final List<Rect> afterChildren;
}

/// A box in the render tree: takes constraints, picks a size, paints.
///
/// Constraints go down, sizes go up, and the parent sets [offset].
abstract class RenderBox {
  /// For subclasses.
  RenderBox();

  /// The size this box took in its last layout, in cells.
  Size size = Size.zero;

  /// Current whole-glyph highlight bridge; syntax remains the starting style.
  @internal
  Style Function(int x, int y, int width, Style style)? selectionGlyphStyle;

  /// Position of this box within its parent, set by the parent's layout.
  Offset offset = Offset.zero;

  /// The constraints of this box's last layout.
  BoxConstraints constraints = const BoxConstraints();

  static int _pass = 0;

  /// Starts a frame's layout, so [laidOutThisPass] can tell boxes laid
  /// out in it from those left as an earlier frame laid them out.
  static void beginLayoutPass() => _pass++;

  int _laidOutIn = -1;

  /// Whether this box was laid out since the last [beginLayoutPass]: a
  /// mounted child its parent skipped this frame was not.
  bool get laidOutThisPass => _laidOutIn == _pass;

  /// The layout stamp, compared with the root's to exclude stale geometry.
  int get layoutPass => _laidOutIn;

  /// Lays this box out within [c], keeping the size it takes inside them.
  void layout(BoxConstraints c) {
    _laidOutIn = _pass;
    constraints = c;
    performLayout();
    size = c.constrain(size);
  }

  /// Sets [size] from [constraints], laying out children first.
  void performLayout();

  /// Paints this box with its origin at [origin].
  void paint(Canvas canvas, Offset origin);

  /// Describes actual self-paint under [localClip] without painting or layout.
  /// Null means unknown; subclasses must declare their own exact runtime type.
  PaintCoverage? describePaintCoverage(Rect localClip) => null;

  /// Calls [visitor] with each child of this box.
  void visitChildren(void Function(RenderBox child) visitor) {}

  /// Visits children in paint order using the geometry that [paint] uses.
  /// Custom boxes that translate, clip or suppress children override this
  /// hook and use [paintChildren], keeping hit testing and drawing together.
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    visitChildren((child) => visitor(child, origin + child.offset, clip));
  }

  /// Paints the child traversal shared with pointer hit testing.
  void paintChildren(Canvas canvas, Offset origin) {
    visitPaintChildren(origin, canvas.clip, (child, at, clip) {
      child.paint(canvas.clipped(clip), at);
    });
  }

  /// Whether a position inside this box hits its own painted surface.
  /// Layout-only boxes leave this false; paint leaves and decorations opt in.
  bool hitTestSelf(Offset position) => false;
}

/// A render box with at most one child.
mixin RenderWithChild on RenderBox {
  /// The one child, if there is one.
  RenderBox? child;

  @override
  void visitChildren(void Function(RenderBox child) visitor) {
    if (child != null) visitor(child!);
  }
}

/// A render box with a list of children.
mixin RenderWithChildren on RenderBox {
  /// The children, in order.
  List<RenderBox> children = const [];

  @override
  void visitChildren(void Function(RenderBox child) visitor) {
    children.forEach(visitor);
  }
}

/// Sizes itself like its child, or as small as allowed without one.
class RenderProxyBox extends RenderBox with RenderWithChild {
  /// A box with no child yet.
  RenderProxyBox();

  @override
  PaintCoverage? describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderProxyBox);

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints);
    c.offset = Offset.zero;
    size = c.size;
  }

  @override
  void paint(Canvas canvas, Offset origin) => paintChildren(canvas, origin);
}
