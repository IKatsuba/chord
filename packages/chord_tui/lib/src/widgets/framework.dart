import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../rendering/box.dart';
import '../rendering/listener.dart';
import '../terminal/buffer.dart';
import '../terminal/style.dart';
import '../terminal/terminal.dart';
import 'focus_manager.dart';

part 'error_boundary.dart';

/// Tells widgets of one type apart across rebuilds.
@immutable
abstract class Key {
  /// Lets subclasses be constant.
  const Key();
}

/// A key that tells widgets apart by [value].
class ValueKey<T> extends Key {
  /// A key equal to every other [ValueKey] of the same type and value.
  const ValueKey(this.value);

  /// What the key compares by.
  final T value;

  @override
  bool operator ==(Object other) =>
      other is ValueKey<T> && other.value == value;

  @override
  int get hashCode => Object.hash(T, value);

  @override
  String toString() => 'ValueKey($value)';
}

/// An immutable description of part of the interface.
@immutable
abstract class Widget {
  /// Lets subclasses take a [key].
  const Widget({this.key});

  /// Tells this widget apart from siblings of its type across rebuilds.
  final Key? key;

  /// Makes the element that holds this widget's place in the tree.
  Element createElement();

  /// Whether an element showing [a] can be updated to show [b].
  static bool canUpdate(Widget a, Widget b) =>
      a.runtimeType == b.runtimeType && a.key == b.key;
}

/// A widget described by what [build] returns, with no state of its own.
abstract class StatelessWidget extends Widget {
  /// Lets subclasses take a [key].
  const StatelessWidget({super.key});

  /// Describes this widget's part of the interface in [context].
  Widget build(BuildContext context);

  @override
  Element createElement() => StatelessElement(this);
}

/// A widget whose [State] lives on across rebuilds.
abstract class StatefulWidget extends Widget {
  /// Lets subclasses take a [key].
  const StatefulWidget({super.key});

  /// Makes the state this widget keeps while it is in the tree.
  State createState();

  @override
  Element createElement() => StatefulElement(this);
}

/// The state a [StatefulWidget] keeps, and what builds it.
abstract class State<T extends StatefulWidget> {
  /// For subclasses; the framework attaches it to its element.
  State();

  T? _widget;
  StatefulElement? _element;

  /// The current configuration of this state.
  T get widget => _widget!;

  /// Where this state's widget sits in the tree.
  BuildContext get context => _element!;

  /// Whether this state is still in the tree.
  bool get mounted => _element != null;

  /// Called once, when this state is put into the tree.
  @mustCallSuper
  void initState() {}

  /// Called when the widget is replaced by [oldWidget]'s successor of the same
  /// type.
  @mustCallSuper
  void didUpdateWidget(covariant T oldWidget) {}

  /// Called after [initState] and whenever an inherited widget this state
  /// depends on changes.
  void didChangeDependencies() {}

  /// Called when this state leaves the tree for good; releases what it holds.
  @mustCallSuper
  void dispose() {}

  /// Runs [fn], then rebuilds this widget in the next frame.
  @protected
  void setState(void Function() fn) {
    fn();
    _element?.markNeedsBuild();
  }

  /// Describes this state's part of the interface in [context].
  Widget build(BuildContext context);
}

/// Data handed down the tree; dependents rebuild when it changes.
abstract class InheritedWidget extends Widget {
  /// Hands its data down to [child] and the widgets below it.
  const InheritedWidget({super.key, required this.child});

  /// The subtree that can read this widget.
  final Widget child;

  /// Whether dependents must rebuild now that [oldWidget] is replaced.
  bool updateShouldNotify(covariant InheritedWidget oldWidget);

  @override
  Element createElement() => InheritedElement(this);
}

/// A widget's place in the tree.
abstract class BuildContext {
  /// For implementations.
  const BuildContext();

  /// The widget at this place.
  Widget get widget;

  /// The owner that builds this tree.
  BuildOwner get owner;

  /// Whether this place is still in the tree.
  bool get mounted;

  /// Settles this attached context's input geometry without paint or selection.
  ///
  /// Shares the host's remaining two-pass budget; false is unresolved, not a
  /// reason to retry. Call outside layout/paint and recheck action state afterward.
  bool ensureCurrentInputGeometry();

  /// The nearest [T] above, rebuilding this place when it changes.
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>();

  /// The nearest [T] above, without depending on it.
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>();

  /// The state of the nearest stateful ancestor whose state is a [T].
  T? findAncestorStateOfType<T extends State>();

  /// The nearest ancestor widget whose type is exactly [T].
  T? findAncestorWidgetOfExactType<T extends Widget>();

  /// Calls [visitor] on each ancestor, nearest first, until it returns false.
  void visitAncestorElements(bool Function(Element element) visitor);

  /// The first render box at or below this place.
  RenderBox? findRenderObject();
}

/// Runs builds and holds what the whole tree shares.
class BuildOwner {
  /// An owner whose focus manager waits [chordTimeout] between chord keys
  /// and reads a press that does nothing through [layoutFallback].
  BuildOwner({
    this.onNeedsFrame,
    this.onExit,
    Duration chordTimeout = defaultChordTimeout,
    KeyLayoutFallback? layoutFallback,
  }) : focusManager = FocusManager(
         chordTimeout: chordTimeout,
         layoutFallback: layoutFallback,
       );

  /// Called when something changed and a frame should be drawn.
  void Function()? onNeedsFrame;

  /// The terminal the app runs in, as its host was given it; widgets read
  /// it through `TerminalScope.of`.
  Terminal? terminal;

  /// Called when the app asks to quit.
  void Function()? onExit;

  /// Tracks focus and dispatches keys for this tree.
  final FocusManager focusManager;

  /// Pointer ownership local to this tree, independent of keyboard focus.
  @internal
  late final PointerRouter pointerRouter = PointerRouter(
    deferCancellation: (notify) {
      if (doingLayoutOrPaint || settlingInputGeometry) {
        _afterInputGeometry.add(notify);
      } else {
        notify();
      }
    },
  );

  /// Invalidates current input geometry even when no element needs rebuilding.
  @internal
  int get inputGeometryEpoch => _inputGeometryEpoch;
  int _inputGeometryEpoch = 0;

  /// Total layout passes, used to share a public operation's bounded budget.
  @internal
  int inputLayoutPasses = 0;

  /// The host's bounded build/layout synchronization hook.
  @internal
  bool Function(int maxPasses)? synchronizeInputGeometry;

  /// Guards public synchronized queries against recursive layout or paint.
  @internal
  bool doingLayoutOrPaint = false;

  /// Whether the host is inside its bounded geometry settlement operation.
  @internal
  bool settlingInputGeometry = false;

  /// The host root used by current-geometry clients, never a retained frame.
  @internal
  RenderBox? Function()? inputRenderRoot;

  /// Clients projected after bounded layout has unwound, before drawing.
  @internal
  final Set<void Function(bool)> inputGeometryObservers = {};

  /// Requests a highlight-only frame without invalidating settled geometry.
  @internal
  void requestPaint() => onNeedsFrame?.call();

  final List<void Function()> _afterInputGeometry = [];

  /// Delivers deferred pointer cancellation after settlement has unwound.
  @internal
  void flushInputGeometryNotifications() {
    final callbacks = List.of(_afterInputGeometry);
    _afterInputGeometry.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  /// Settles current input geometry without paint or terminal effects.
  @internal
  bool ensureCurrentInputGeometry({int maxPasses = 2}) {
    if (doingLayoutOrPaint) {
      throw StateError(
        'Cannot synchronize input geometry during layout or paint.',
      );
    }
    if (maxPasses < 0 || maxPasses > 2) {
      throw ArgumentError.value(maxPasses, 'maxPasses');
    }
    return synchronizeInputGeometry?.call(maxPasses) ?? false;
  }

  final List<Element> _dirty = [];
  final Set<Element> _elements = {};

  /// Set when elements were mounted or unmounted, so the render tree's
  /// child lists must be synced before layout.
  bool structureChanged = true;

  /// Queues [e] to be rebuilt in the next frame.
  void scheduleBuildFor(Element e) {
    _dirty.add(e);
    requestFrame();
  }

  /// Asks for a frame, invalidating current input geometry.
  void requestFrame() {
    _inputGeometryEpoch++;
    onNeedsFrame?.call();
  }

  /// Asks the app to quit.
  void requestExit() => onExit?.call();

  /// Rebuilds every element queued for building.
  void buildScope() => _drainBuilds();

  void _drainBuilds([Element? subtree]) {
    bool included(Element element) {
      if (subtree == null) return true;
      for (
        Element? current = element;
        current != null;
        current = current._parent
      ) {
        if (identical(current, subtree)) return true;
      }
      return false;
    }

    while (_dirty.isNotEmpty) {
      _dirty.removeWhere((e) => !e._active || !e._dirty);
      final batch = _dirty.where(included).toList()
        ..sort((a, b) => a._depth - b._depth);
      if (batch.isEmpty) return;
      _dirty.removeWhere(batch.contains);
      for (final e in batch) {
        try {
          e.rebuild();
        } catch (error, stack) {
          final boundary = _findErrorBoundary(e);
          if (boundary == null) rethrow;
          _recoverBoundary(boundary, error, stack);
        }
      }
    }
  }

  /// Whether a mounted element is waiting to be rebuilt.
  bool get hasDirtyElements => _dirty.any((e) => e._active && e._dirty);

  /// Recovers a descendant drawing failure after layout or paint has unwound.
  bool recoverDrawingError(Object error, StackTrace stack) {
    if (error is! _BoundaryFailure) return false;
    _recoverBoundary(error.boundary, error.error, error.stack);
    return true;
  }

  /// Builds from inside layout: runs [build], which mounts or updates an
  /// element, and syncs the render subtree of the element it returns.
  ///
  /// [structureChanged] is left as it was, so the next frame does not walk
  /// the whole tree for what the caller already synced.
  Element? buildDuringLayout(Element? Function() build) {
    final before = structureChanged;
    _layoutBuildDepth++;
    try {
      final e = build();
      if (e != null) {
        // A later child can invalidate an earlier sibling during this build.
        // Settle only this returned subtree before laying out its render boxes.
        _drainBuilds(e);
        syncRenderTree(e);
      }
      return e;
    } finally {
      _layoutBuildDepth--;
      structureChanged = before;
    }
  }

  int _layoutBuildDepth = 0;

  final List<void Function()> _afterLayout = [];

  /// Calls [fn] after the frame's layout, never during it: how a render
  /// object that changed some state during layout tells the listeners.
  void afterLayout(void Function() fn) => _afterLayout.add(fn);

  /// Runs what [afterLayout] queued.
  void flushAfterLayout() {
    if (_afterLayout.isEmpty) return;
    final fns = List.of(_afterLayout);
    _afterLayout.clear();
    for (final fn in fns) {
      fn();
    }
  }
}

/// A widget's instance at one place in the tree.
abstract class Element implements BuildContext {
  /// An element that will show [widget].
  Element(Widget widget) : _widget = widget;

  Widget _widget;
  Element? _parent;
  int _depth = 0;
  BuildOwner? _owner;
  bool _dirty = true;
  bool _active = false;
  Map<Type, InheritedElement>? _inherited;
  Set<InheritedElement>? _dependencies;

  @override
  Widget get widget => _widget;

  @override
  BuildOwner get owner => _owner!;

  @override
  bool get mounted => _active;

  /// Delegates once, rejecting receivers detached or moved by callbacks.
  @override
  bool ensureCurrentInputGeometry() {
    if (!mounted) return false;
    final capturedOwner = owner;
    final settled = capturedOwner.ensureCurrentInputGeometry();
    return settled && mounted && identical(owner, capturedOwner);
  }

  /// The element above this one, if any.
  Element? get parent => _parent;

  /// How far this element is from the root.
  int get depth => _depth;

  /// Attaches the root of a tree to [owner] before it is mounted.
  void attachRootOwner(BuildOwner owner) => _owner = owner;

  /// Puts this element into the tree under [parent].
  @mustCallSuper
  void mount(Element? parent) {
    _parent = parent;
    _depth = parent == null ? 0 : parent._depth + 1;
    _owner = parent?._owner ?? _owner;
    _active = true;
    owner._elements.add(this);
    updateInheritance();
    owner.structureChanged = true;
  }

  /// Takes the inherited widgets this element can see from its parent.
  @protected
  void updateInheritance() {
    _inherited = _parent?._inherited;
  }

  /// Shows [newWidget], a widget that can update this element.
  @mustCallSuper
  void update(covariant Widget newWidget) {
    _widget = newWidget;
  }

  /// Takes this element out of the tree.
  @mustCallSuper
  void unmount() {
    final deps = _dependencies;
    if (deps != null) {
      for (final d in deps) {
        d._dependents.remove(this);
      }
    }
    _dependencies = null;
    _active = false;
    owner._elements.remove(this);
    owner.structureChanged = true;
  }

  /// Calls [visitor] on each child element.
  void visitChildren(void Function(Element child) visitor) {}

  /// Updates [child] to show [newWidget], replacing it when it cannot.
  @protected
  Element? updateChild(Element? child, Widget? newWidget) {
    if (newWidget == null) {
      if (child != null) unmountTree(child);
      return null;
    }
    if (child != null) {
      if (identical(child.widget, newWidget)) return child;
      if (Widget.canUpdate(child.widget, newWidget)) {
        child.update(newWidget);
        return child;
      }
      unmountTree(child);
    }
    final e = newWidget.createElement();
    e.mount(this);
    return e;
  }

  /// Unmounts [e] and every element below it.
  static void unmountTree(Element e) {
    if (!e.mounted) return;
    e.visitChildren(unmountTree);
    e.unmount();
  }

  /// Schedules this element to rebuild in the next frame.
  void markNeedsBuild() {
    if (!_active || _dirty) return;
    _dirty = true;
    owner.scheduleBuildFor(this);
  }

  /// Rebuilds this element now, if it is mounted and marked to rebuild.
  void rebuild() {
    if (!_active || !_dirty) return;
    // Cleared first: a descendant mounted by this build may mark this
    // element dirty again (a focus change, say), and that must not be lost.
    _dirty = false;
    performRebuild();
  }

  /// Does this element's own part of a rebuild.
  @protected
  void performRebuild();

  /// Keeps the root error widget, or lets an enclosing boundary catch a build.
  Widget buildError(Object error, StackTrace stack) {
    if (_findErrorBoundary(this) != null) {
      Error.throwWithStackTrace(error, stack);
    }
    return ErrorWidget(error, stack);
  }

  /// Called when an inherited widget this element depends on changes.
  void didChangeDependencies() => markNeedsBuild();

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>() {
    final e = _inherited?[T];
    if (e == null) return null;
    (_dependencies ??= {}).add(e);
    e._dependents.add(this);
    return e.widget as T;
  }

  @override
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      _inherited?[T]?.widget as T?;

  @override
  T? findAncestorStateOfType<T extends State>() {
    var p = _parent;
    while (p != null) {
      if (p is StatefulElement && p.state is T) return p.state as T;
      p = p._parent;
    }
    return null;
  }

  @override
  T? findAncestorWidgetOfExactType<T extends Widget>() {
    var p = _parent;
    while (p != null) {
      if (p.widget.runtimeType == T) return p.widget as T;
      p = p._parent;
    }
    return null;
  }

  @override
  void visitAncestorElements(bool Function(Element element) visitor) {
    var p = _parent;
    while (p != null && visitor(p)) {
      p = p._parent;
    }
  }

  @override
  RenderBox? findRenderObject() {
    Element? e = this;
    while (e != null) {
      if (e is RenderObjectElement) return e.renderObject;
      Element? only;
      e.visitChildren((c) => only = c);
      e = only;
    }
    return null;
  }
}

/// An element that shows what its widget builds.
abstract class ComponentElement extends Element {
  /// An element for [widget].
  ComponentElement(super.widget);

  Element? _child;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    firstBuild();
  }

  /// Builds for the first time, when mounted.
  @protected
  void firstBuild() => rebuild();

  @override
  void update(Widget newWidget) {
    final old = widget;
    super.update(newWidget);
    didUpdate(old);
    _dirty = true;
    rebuild();
  }

  /// Called after the widget was replaced, before the rebuild.
  @protected
  void didUpdate(Widget oldWidget) {}

  @override
  void performRebuild() {
    Widget built;
    try {
      built = build();
    } catch (e, s) {
      built = buildError(e, s);
    }
    _child = updateChild(_child, built);
  }

  /// The widget this element shows below itself.
  Widget build();

  @override
  void visitChildren(void Function(Element child) visitor) {
    if (_child != null) visitor(_child!);
  }
}

/// The element of a [StatelessWidget].
class StatelessElement extends ComponentElement {
  /// An element for [widget].
  StatelessElement(StatelessWidget super.widget);

  @override
  Widget build() => (widget as StatelessWidget).build(this);
}

/// The element of a [StatefulWidget], holding its [State].
class StatefulElement extends ComponentElement {
  /// An element for [widget], with the state it creates.
  StatefulElement(StatefulWidget widget)
    : state = widget.createState(),
      super(widget) {
    state._element = this;
    state._widget = widget;
  }

  /// The state this element keeps.
  final State state;

  @override
  void firstBuild() {
    state.initState();
    state.didChangeDependencies();
    super.firstBuild();
  }

  @override
  void didUpdate(Widget oldWidget) {
    state._widget = widget as StatefulWidget;
    state.didUpdateWidget(oldWidget as StatefulWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    state.didChangeDependencies();
  }

  @override
  void unmount() {
    super.unmount();
    state.dispose();
    state._element = null;
  }

  @override
  Widget build() => state.build(this);
}

/// The element of an [InheritedWidget], which tracks its dependents.
class InheritedElement extends ComponentElement {
  /// An element for [widget].
  InheritedElement(InheritedWidget super.widget);

  final Set<Element> _dependents = {};

  @override
  void updateInheritance() {
    _inherited = {...?_parent?._inherited, widget.runtimeType: this};
  }

  @override
  void didUpdate(Widget oldWidget) {
    if ((widget as InheritedWidget).updateShouldNotify(
      oldWidget as InheritedWidget,
    )) {
      for (final d in List.of(_dependents)) {
        d.didChangeDependencies();
      }
    }
  }

  @override
  Widget build() => (widget as InheritedWidget).child;
}

// ---------------------------------------------------------------------------
// Render object widgets

/// A widget drawn by a render box it configures.
abstract class RenderObjectWidget extends Widget {
  /// Lets subclasses take a [key].
  const RenderObjectWidget({super.key});

  /// Makes the render box that draws this widget.
  RenderBox createRenderObject(BuildContext context);

  /// Configures [renderObject] to match this widget.
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) {}
}

/// A render object widget with no children.
abstract class LeafRenderObjectWidget extends RenderObjectWidget {
  /// Lets subclasses take a [key].
  const LeafRenderObjectWidget({super.key});

  @override
  Element createElement() => LeafRenderObjectElement(this);
}

/// A render object widget with at most one child.
abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  /// Lets subclasses take a [key] and a [child].
  const SingleChildRenderObjectWidget({super.key, this.child});

  /// The widget below this one, if any.
  final Widget? child;

  @override
  Element createElement() => SingleChildRenderObjectElement(this);
}

/// A render object widget with a list of children.
abstract class MultiChildRenderObjectWidget extends RenderObjectWidget {
  /// Lets subclasses take a [key] and [children].
  const MultiChildRenderObjectWidget({super.key, this.children = const []});

  /// The widgets below this one, in order.
  final List<Widget> children;

  @override
  Element createElement() => MultiChildRenderObjectElement(this);
}

/// The element of a [RenderObjectWidget], which owns its render box.
abstract class RenderObjectElement extends Element {
  /// An element for [widget].
  RenderObjectElement(RenderObjectWidget super.widget);

  /// The render box this element's widget configures.
  late final RenderBox renderObject;

  RenderObjectWidget get _row => widget as RenderObjectWidget;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    renderObject = _row.createRenderObject(this);
    _dirty = false;
  }

  @override
  void update(RenderObjectWidget newWidget) {
    super.update(newWidget);
    _row.updateRenderObject(this, renderObject);
  }

  @override
  void performRebuild() => _row.updateRenderObject(this, renderObject);

  /// Points the render object at the render objects of child elements.
  void syncRenderChildren();

  /// The first render box at or below [e].
  static RenderBox? firstRenderObject(Element? e) {
    while (e != null) {
      if (e is RenderObjectElement) return e.renderObject;
      Element? only;
      e.visitChildren((c) => only = c);
      e = only;
    }
    return null;
  }
}

/// The element of a [LeafRenderObjectWidget].
class LeafRenderObjectElement extends RenderObjectElement {
  /// An element for [widget].
  LeafRenderObjectElement(LeafRenderObjectWidget super.widget);

  @override
  void syncRenderChildren() {}
}

/// The element of a [SingleChildRenderObjectWidget].
class SingleChildRenderObjectElement extends RenderObjectElement {
  /// An element for [widget].
  SingleChildRenderObjectElement(SingleChildRenderObjectWidget super.widget);

  Element? _child;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    _child = updateChild(null, (widget as SingleChildRenderObjectWidget).child);
  }

  @override
  void update(SingleChildRenderObjectWidget newWidget) {
    super.update(newWidget);
    _child = updateChild(_child, newWidget.child);
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    if (_child != null) visitor(_child!);
  }

  @override
  void syncRenderChildren() {
    final ro = renderObject;
    if (ro is RenderWithChild) {
      ro.child = RenderObjectElement.firstRenderObject(_child);
    }
  }
}

/// The element of a [MultiChildRenderObjectWidget].
class MultiChildRenderObjectElement extends RenderObjectElement {
  /// An element for [widget].
  MultiChildRenderObjectElement(MultiChildRenderObjectWidget super.widget);

  List<Element> _children = [];

  @override
  void mount(Element? parent) {
    super.mount(parent);
    _children = [
      for (final w in (widget as MultiChildRenderObjectWidget).children)
        updateChild(null, w)!,
    ];
  }

  @override
  void update(MultiChildRenderObjectWidget newWidget) {
    super.update(newWidget);
    _children = updateChildren(_children, newWidget.children);
    // Keyed children that only moved mount nothing, so nothing else would
    // put their render objects in the new order.
    syncRenderChildren();
  }

  /// Matches new widgets to old elements: by key first, then in order.
  @protected
  List<Element> updateChildren(List<Element> old, List<Widget> widgets) {
    final keyed = <Key, Element>{};
    final unkeyed = <Element>[];
    for (final e in old) {
      final k = e.widget.key;
      if (k != null) {
        keyed[k] = e;
      } else {
        unkeyed.add(e);
      }
    }
    var next = 0;
    final result = <Element>[];
    for (final w in widgets) {
      Element? candidate;
      final k = w.key;
      if (k != null) {
        candidate = keyed.remove(k);
      } else if (next < unkeyed.length) {
        candidate = unkeyed[next++];
      }
      result.add(updateChild(candidate, w)!);
    }
    for (final e in keyed.values) {
      Element.unmountTree(e);
    }
    for (var i = next; i < unkeyed.length; i++) {
      Element.unmountTree(unkeyed[i]);
    }
    return result;
  }

  @override
  void visitChildren(void Function(Element child) visitor) =>
      _children.forEach(visitor);

  @override
  void syncRenderChildren() {
    final ro = renderObject;
    if (ro is RenderWithChildren) {
      ro.children = [
        for (final c in _children) ?RenderObjectElement.firstRenderObject(c),
      ];
    }
  }
}

/// Points every render object at its children's render objects.
void syncRenderTree(Element root) {
  void walk(Element e) {
    if (e is RenderObjectElement) e.syncRenderChildren();
    e.visitChildren(walk);
  }

  walk(root);
}

/// Shown in place of a widget whose build threw.
class ErrorWidget extends LeafRenderObjectWidget {
  /// A widget showing [error]; an optional [stackTrace] is kept for
  /// diagnostics, not shown.
  ErrorWidget(this.error, [this.stackTrace]) : message = '$error';

  /// What the build threw.
  final Object error;

  /// Where it was thrown, if known.
  final StackTrace? stackTrace;

  /// The text shown.
  final String message;

  @override
  RenderBox createRenderObject(BuildContext context) => RenderError(message);

  @override
  void updateRenderObject(BuildContext context, RenderError renderObject) {
    renderObject.message = message;
  }
}

/// Draws an error message in white on red, filling the space it is given.
class RenderError extends RenderBox {
  /// A box showing [message].
  RenderError(this.message);

  /// The text shown.
  String message;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    size = Size(
      constraints.hasBoundedWidth ? constraints.maxWidth : message.length + 2,
      constraints.hasBoundedHeight ? constraints.maxHeight : 1,
    );
  }

  @override
  PaintCoverage describePaintCoverage(Rect localClip) => PaintCoverage(
    declaredFor: RenderError,
    beforeChildren: [
      Rect.fromOffsetSize(Offset.zero, size).intersect(localClip),
    ],
  );

  @override
  void paint(Canvas canvas, Offset origin) {
    const st = Style(fg: Colors.white, bg: Colors.red);
    final r = Rect.fromOffsetSize(origin, size);
    canvas.fill(r, st);
    final c = canvas.clipped(r);
    var y = origin.y;
    for (final line in message.split('\n')) {
      if (y >= r.bottom) break;
      c.drawText(origin.x, y++, line, st);
    }
  }
}
