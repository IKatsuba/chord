import '../foundation/geometry.dart';
import '../input/keys.dart';
import '../rendering/box.dart';
import '../rendering/scroll_view.dart';
import 'editor_cursor.dart';
import 'focus.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'listener.dart';
import 'scroll_controller.dart';

/// A page that scrolls over live widgets: its [child] is laid out once at
/// the view's width and kept mounted, with its state and focus, and the
/// view shows a window of it. Flutter's widget of the same name.
///
/// It binds no keys; a page puts its scroll keys above it, so a focused
/// child's own keys win. The wheel scrolls it, unless something under the
/// pointer absorbs the wheel. When focus moves to a widget inside it, or a
/// focused editor's cursor moves, it scrolls the least that shows it.
class SingleChildScrollView extends StatefulWidget {
  /// A scrolling view of [child].
  const SingleChildScrollView({
    super.key,
    this.controller,
    this.padding = EdgeInsets.zero,
    required this.child,
  });

  /// Where the view is; one of its own when null. The same controller a
  /// [Scrollbar] beside it reads.
  final ScrollController? controller;

  /// The space around [child] inside the content.
  final EdgeInsets padding;

  /// The content.
  final Widget child;

  @override
  State<SingleChildScrollView> createState() => _SingleChildScrollViewState();
}

class _SingleChildScrollViewState extends State<SingleChildScrollView> {
  ScrollController? _own;
  ScrollController get _scroll =>
      widget.controller ?? (_own ??= ScrollController());

  RenderSingleChildScrollView? _render;
  FocusNode? _lastFocus;
  Offset? _lastCursor;

  @override
  void dispose() {
    _render?.detachController();
    _own?.dispose();
    super.dispose();
  }

  /// [box]'s top row in the content, or null when it is not inside.
  int? _rowOf(RenderBox box) {
    final view = _render;
    final content = view?.child;
    if (view == null || content == null) return null;
    int? found;
    void visit(RenderBox b, int top) {
      if (found != null) return;
      if (identical(b, box)) {
        found = top;
        return;
      }
      b.visitChildren((c) => visit(c, top + c.offset.y));
    }

    visit(content, view.padding.top);
    return found;
  }

  /// Where the first editor cursor under [box] is, relative to it.
  Offset? _cursorIn(RenderBox box) {
    Offset? found;
    void visit(RenderBox b, int top) {
      if (found != null) return;
      final at = editorCursorIn(b);
      if (at != null) {
        found = Offset(at.x, top + at.y);
        return;
      }
      b.visitChildren((c) => visit(c, top + c.offset.y));
    }

    visit(box, 0);
    return found;
  }

  /// Scrolls the least that shows rows [top] to [top] + [rows]; one taller
  /// than the view shows [cursor] if given, else its top.
  void _show(int top, int rows, {int? cursor}) {
    final scroll = _scroll;
    final view = scroll.viewRows;
    if (view <= 0) return;
    if (rows > view) {
      if (cursor == null) return scroll.jumpTo(top);
      return _showRow(cursor);
    }
    if (top < scroll.offset) {
      scroll.jumpTo(top);
    } else if (top + rows > scroll.offset + view) {
      scroll.jumpTo(top + rows - view);
    }
  }

  void _showRow(int row) {
    final scroll = _scroll;
    if (row < scroll.offset) {
      scroll.jumpTo(row);
    } else if (row >= scroll.offset + scroll.viewRows) {
      scroll.jumpTo(row - scroll.viewRows + 1);
    }
  }

  // After every layout: focus that moved in is brought into sight, and so
  // is a focused editor's cursor that moved, along its row or to another.
  void _laidOut() {
    if (!mounted) return;
    final focus = context.owner.focusManager.primaryFocus;
    final element = focus == null
        ? null
        : focusElementFor(context as Element, focus);
    final box = element == null
        ? null
        : RenderObjectElement.firstRenderObject(element);
    final top = box == null ? null : _rowOf(box);
    if (box == null || top == null) {
      _lastFocus = null;
      _lastCursor = null;
      return;
    }
    final inside = _cursorIn(box);
    final cursor = inside == null ? null : Offset(inside.x, top + inside.y);
    if (!identical(focus, _lastFocus)) {
      _show(top, box.size.height, cursor: cursor?.y);
    } else if (cursor != null && cursor != _lastCursor) {
      // The focused editor took a key: its cursor moved.
      _showRow(cursor.y);
    }
    _lastFocus = focus;
    _lastCursor = cursor;
  }

  void _wheel(MouseEvent event) {
    final scroll = _scroll;
    for (var i = 0; i < event.scrollDelta.y.abs(); i++) {
      event.scrollDelta.y < 0 ? scroll.lineUp() : scroll.lineDown();
    }
  }

  @override
  Widget build(BuildContext context) => _ScrollViewScope(
    state: this,
    child: Listener(
      onPointerSignal: _wheel,
      child: _ScrollViewport(
        controller: _scroll,
        padding: widget.padding,
        state: this,
        child: widget.child,
      ),
    ),
  );
}

class _ScrollViewport extends SingleChildRenderObjectWidget {
  const _ScrollViewport({
    required this.controller,
    required this.padding,
    required this.state,
    required super.child,
  });

  final ScrollController controller;
  final EdgeInsets padding;
  final _SingleChildScrollViewState state;

  @override
  RenderSingleChildScrollView createRenderObject(BuildContext context) =>
      state._render = RenderSingleChildScrollView(
        controller: controller,
        owner: context.owner,
        padding: padding,
        onLayout: state._laidOut,
      );

  @override
  void updateRenderObject(BuildContext context, RenderSingleChildScrollView r) {
    r
      ..controller = controller
      ..padding = padding
      ..onLayout = state._laidOut;
    state._render = r;
  }
}

class _ScrollViewScope extends InheritedWidget {
  const _ScrollViewScope({required this.state, required super.child});

  final _SingleChildScrollViewState state;

  @override
  bool updateShouldNotify(_ScrollViewScope oldWidget) =>
      !identical(state, oldWidget.state);
}

/// Positions inside the nearest [SingleChildScrollView]: Flutter's
/// `Scrollable`, for what a page reads and scrolls to.
abstract final class Scrollable {
  /// [context]'s widget's top row in the content of the scroll view around
  /// it; null outside one, or before it is laid out.
  static int? rowOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_ScrollViewScope>();
    final box = context.findRenderObject();
    if (scope == null || box == null) return null;
    return scope.state._rowOf(box);
  }

  /// Scrolls the nearest scroll view so [context]'s widget shows: by the
  /// least move when [alignment] is null, or with its top at [alignment]
  /// of the view, 0 its top and 1 its bottom.
  static void ensureVisible(BuildContext context, {double? alignment}) {
    final scope = context.getInheritedWidgetOfExactType<_ScrollViewScope>();
    final box = context.findRenderObject();
    if (scope == null || box == null) return;
    final state = scope.state;
    final top = state._rowOf(box);
    if (top == null) return;
    if (alignment == null) return state._show(top, box.size.height);
    final scroll = state._scroll;
    scroll.jumpTo(top - ((scroll.viewRows - 1) * alignment).round());
  }
}
