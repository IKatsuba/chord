import '../foundation/geometry.dart';
import '../foundation/scroll_state.dart';
import '../terminal/buffer.dart';
import '../widgets/framework.dart';
import '../widgets/scroll_controller.dart';
import 'box.dart';

/// A view of [child], laid out once at the view's width and any height, of
/// which the rows `[offset, offset + view)` show: the render box of
/// `SingleChildScrollView`.
class RenderSingleChildScrollView extends RenderBox
    with RenderWithChild
    implements ScrollClient {
  /// A view driven by [controller], [padding] around its child.
  RenderSingleChildScrollView({
    required ScrollController controller,
    required this.owner,
    this.padding = EdgeInsets.zero,
    this.onLayout,
  }) : _controller = controller {
    controller.attach(this);
  }

  /// The owner a scroll step asks for a frame through.
  final BuildOwner owner;

  /// The space around the child inside the content.
  EdgeInsets padding;

  /// Called after each layout, with the content's height known.
  void Function()? onLayout;

  ScrollController _controller;

  /// The controller that says where the view is.
  ScrollController get controller => _controller;
  set controller(ScrollController c) {
    if (identical(c, _controller)) return;
    _controller.detach(this);
    _controller = c;
    c.attach(this);
  }

  /// Lets go of the controller, when the view leaves the tree.
  void detachController() => _controller.detach(this);

  /// Rows of content: the child and the padding above and below it.
  int get contentRows => (child?.size.height ?? 0) + padding.vertical;

  @override
  void performLayout() {
    if (!constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
      final axis = constraints.hasBoundedHeight ? 'width' : 'height';
      throw StateError(
        'A SingleChildScrollView was given unbounded $axis. It takes the '
        'size it is given: wrap it in Expanded or a SizedBox.',
      );
    }
    size = constraints.biggest;
    final c = child;
    final width = size.width - padding.horizontal;
    if (c != null) {
      c.layout(
        BoxConstraints(
          minWidth: width < 0 ? 0 : width,
          maxWidth: width < 0 ? 0 : width,
        ),
      );
    }
    // A page never follows its end: a controller that would starts at the
    // top.
    var next = reduceMeasured(
      _controller.state,
      content: contentRows,
      view: size.height,
      follow: Follow.none,
    );
    if (next.following) next = reduceJump(next, 0, Follow.none);
    if (_controller.setFromLayout(next)) {
      owner.afterLayout(_controller.notifyAfterLayout);
    }
    if (c != null) {
      c.offset = Offset(padding.left, padding.top - next.offset);
    }
    final notify = onLayout;
    if (notify != null) owner.afterLayout(notify);
  }

  @override
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    final visible = clip.intersect(Rect.fromOffsetSize(origin, size));
    visitChildren((child) => visitor(child, origin + child.offset, visible));
  }

  @override
  void paint(Canvas canvas, Offset origin) => paintChildren(canvas, origin);

  // The content is one item: the child.
  @override
  int itemTop(int index) {
    assert(
      false,
      'A SingleChildScrollView has no items: jumpToAnchor does not apply.',
    );
    return 0;
  }

  @override
  int itemRows(int index) => contentRows;

  @override
  int itemAtRow(int row) => row >= 0 && row < contentRows ? 0 : -1;

  @override
  void scrollChanged() => owner.requestFrame();
}
