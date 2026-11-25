import '../foundation/geometry.dart';
import '../terminal/buffer.dart';
import 'box.dart';

/// A box that has its child built during its own layout, from the
/// constraints it is given; `LayoutBuilder` is the widget to use.
class RenderLayoutBuilder extends RenderBox with RenderWithChild {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderLayoutBuilder);

  /// A box that calls [onBuild] when its child must be built.
  RenderLayoutBuilder(this.onBuild);

  /// Builds the child for the constraints and points [child] at it.
  void Function(BoxConstraints constraints) onBuild;

  BoxConstraints? _built;

  /// Builds the child at the next layout even if the constraints are the
  /// same: the widget or what its builder depends on changed.
  void markNeedsBuild() => _built = null;

  @override
  void performLayout() {
    if (_built != constraints) {
      _built = constraints;
      onBuild(constraints);
    }
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
