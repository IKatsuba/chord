part of 'framework.dart';

/// Replaces a failed drawing subtree with a latched, caller-built fallback.
class ErrorBoundary extends RenderObjectWidget {
  /// Catches descendant build, layout and paint errors until replaced by key.
  const ErrorBoundary({
    super.key,
    required this.child,
    required this.errorBuilder,
    this.onError,
  });

  /// The subtree to draw until it fails.
  final Widget child;

  /// Builds the fallback using the surviving context outside the failed child.
  final Widget Function(BuildContext, Object, StackTrace) errorBuilder;

  /// Called once after the failed drawing operation has unwound.
  final void Function(Object, StackTrace)? onError;

  @override
  Element createElement() => _ErrorBoundaryElement(this);

  @override
  RenderBox createRenderObject(BuildContext context) =>
      _RenderErrorBoundary(context as _ErrorBoundaryElement);
}

_ErrorBoundaryElement? _findErrorBoundary(Element element) {
  var parent = element.parent;
  while (parent != null) {
    if (parent is _ErrorBoundaryElement && !parent.failed) return parent;
    parent = parent.parent;
  }
  return null;
}

class _BoundaryFailure {
  _BoundaryFailure(this.boundary, this.error, this.stack);
  final _ErrorBoundaryElement boundary;
  final Object error;
  final StackTrace stack;
}

class _ErrorBoundaryElement extends RenderObjectElement {
  _ErrorBoundaryElement(ErrorBoundary super.widget);

  Element? _child;
  bool failed = false;
  bool _pendingFailure = false;
  Object? _error;
  StackTrace? _stack;

  ErrorBoundary get boundary => widget as ErrorBoundary;
  _RenderErrorBoundary get box => renderObject as _RenderErrorBoundary;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    _build();
  }

  @override
  void update(ErrorBoundary newWidget) {
    super.update(newWidget);
    _build();
  }

  @override
  void performRebuild() => _build();

  void _build() {
    if (_pendingFailure) return;
    try {
      _child = updateChild(
        _child,
        failed ? boundary.errorBuilder(this, _error!, _stack!) : boundary.child,
      );
    } catch (error, stack) {
      if (failed || error is _BoundaryFailure) rethrow;
      if (owner._layoutBuildDepth > 0) {
        // Let the lazy parent attach this element before replacing its child.
        _pendingFailure = true;
        owner.afterLayout(() {
          if (!mounted) return;
          _pendingFailure = false;
          _recoverBoundary(this, error, stack);
        });
        return;
      }
      recover(error, stack);
    }
  }

  void recover(Object error, StackTrace stack) {
    failed = true;
    _error = error;
    _stack = stack;
    // A mount can fail before updateChild returns it to its parent.
    // Track mounted elements so even that partial subtree is released.
    final descendants = owner._elements.where((element) {
      var parent = element.parent;
      while (parent != null) {
        if (identical(parent, this)) return true;
        parent = parent.parent;
      }
      return false;
    }).toList()..sort((a, b) => b.depth - a.depth);
    for (final element in descendants) {
      if (element.mounted) element.unmount();
    }
    _child = null;
    box.child = null;
    boundary.onError?.call(error, stack);
    _build();
    owner.structureChanged = true;
    markNeedsBuild();
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    if (_child != null) visitor(_child!);
  }

  @override
  void syncRenderChildren() {
    box.child = RenderObjectElement.firstRenderObject(_child);
  }
}

class _RenderErrorBoundary extends RenderProxyBox {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(_RenderErrorBoundary);

  _RenderErrorBoundary(this.element);
  final _ErrorBoundaryElement element;

  @override
  void performLayout() {
    try {
      super.performLayout();
    } catch (error, stack) {
      if (error is _BoundaryFailure || element.failed) rethrow;
      throw _BoundaryFailure(element, error, stack);
    }
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    try {
      super.paint(canvas, origin);
    } catch (error, stack) {
      if (error is _BoundaryFailure || element.failed) rethrow;
      throw _BoundaryFailure(element, error, stack);
    }
  }
}

void _recoverBoundary(
  _ErrorBoundaryElement boundary,
  Object error,
  StackTrace stack,
) {
  try {
    boundary.owner.pointerRouter.cancel();
    boundary.recover(error, stack);
  } catch (nextError, nextStack) {
    final outer = _findErrorBoundary(boundary);
    if (outer == null) rethrow;
    _recoverBoundary(outer, nextError, nextStack);
  }
}
