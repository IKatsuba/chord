import '../foundation/geometry.dart';
import '../rendering/box.dart';
import '../rendering/layout_builder.dart';
import 'framework.dart';

/// Builds a widget from the constraints its parent gives.
typedef LayoutWidgetBuilder =
    Widget Function(BuildContext context, BoxConstraints constraints);

/// Builds its child during layout, from the constraints the parent passes,
/// so what is shown can depend on the room there is.
///
/// The builder runs again when the constraints change, when the widget is
/// replaced, or when an inherited widget it looked up changes; not
/// otherwise.
class LayoutBuilder extends RenderObjectWidget {
  /// A widget whose child [builder] makes.
  const LayoutBuilder({super.key, required this.builder});

  /// Makes the child for the given constraints.
  final LayoutWidgetBuilder builder;

  @override
  Element createElement() => _LayoutBuilderElement(this);

  @override
  RenderBox createRenderObject(BuildContext context) =>
      RenderLayoutBuilder((context as _LayoutBuilderElement)._layout);
}

class _LayoutBuilderElement extends RenderObjectElement {
  _LayoutBuilderElement(LayoutBuilder super.widget);

  Element? _child;

  RenderLayoutBuilder get _render => renderObject as RenderLayoutBuilder;

  @override
  void update(LayoutBuilder newWidget) {
    super.update(newWidget);
    _render.markNeedsBuild();
  }

  // Reached when an inherited widget the builder depends on changed: the
  // builder gets this element as its context.
  @override
  void performRebuild() {
    super.performRebuild();
    _render.markNeedsBuild();
  }

  void _layout(BoxConstraints constraints) {
    owner.buildDuringLayout(() {
      Widget built;
      try {
        built = (widget as LayoutBuilder).builder(this, constraints);
      } catch (e, s) {
        built = buildError(e, s);
      }
      return _child = updateChild(_child, built);
    });
    syncRenderChildren();
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    if (_child != null) visitor(_child!);
  }

  @override
  void syncRenderChildren() {
    _render.child = RenderObjectElement.firstRenderObject(_child);
  }
}
