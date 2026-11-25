import '../foundation/selection_delegate.dart';
import 'dart:collection';

import '../rendering/box.dart';
import '../rendering/list_viewport.dart';
import 'focus.dart';
import 'framework.dart';
import 'scroll_controller.dart';

/// Builds item [index] of a list.
typedef IndexedWidgetBuilder = Widget Function(BuildContext context, int index);

/// A box that shows part of a list of [itemCount] items, building only the
/// items it lays out. [ListView] is the widget to use.
class ListViewport extends RenderObjectWidget {
  /// A viewport placed by [controller].
  const ListViewport({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.itemVersion,
    this.itemExtentBuilder,
    this.itemExtentVersion,
    this.selectionDelegate,
  });

  /// Where the view is.
  final ScrollController controller;

  /// How many items the list has.
  final int itemCount;

  /// Logical immutable sources for selection across unmounted history.
  final SelectionChildDelegate? selectionDelegate;

  /// Builds an item.
  final IndexedWidgetBuilder itemBuilder;

  /// A value that changes with anything that changes item `index`'s
  /// height; without it every rebuild drops every height. Heights are kept
  /// on [controller], so a list built again over it reuses each one whose
  /// version is unchanged; when one controller serves different lists, the
  /// version names the item, not only its look.
  final Object? Function(int index)? itemVersion;

  /// Supplies exact nonnegative heights at the final item width, without
  /// mounting offscreen widgets. Supersedes [itemVersion] when supplied.
  /// The callback must be pure; it returns a height, not an estimate.
  /// Negative heights throw ArgumentError. A mounted row differing from its
  /// promised height throws StateError, including in compiled executables.
  final int Function(int index, int width)? itemExtentBuilder;

  /// A nonnull revision promises all exact-height inputs are unchanged.
  /// Change it for data, order or captured callback semantics; inline callback
  /// identity is ignored with an equal revision. Null recomputes on rebuild.
  /// Only the current width/revision is cached; a cold width projects all items.
  final Object? itemExtentVersion;

  @override
  Element createElement() => ListViewportElement(this);

  @override
  RenderBox createRenderObject(BuildContext context) => RenderListViewport(
    manager: context as ListViewportElement,
    controller: controller,
    owner: context.owner,
    selectionDelegate: selectionDelegate,
    itemExtentBuilder: itemExtentBuilder,
    itemExtentVersion: itemExtentVersion,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderListViewport renderObject,
  ) {
    if (selectionDelegate != null &&
        selectionDelegate!.itemCount != itemCount) {
      throw ArgumentError('Selection delegate and viewport counts must agree.');
    }
    renderObject
      ..controller = controller
      ..selectionDelegate = selectionDelegate;
  }
}

/// The element of a [ListViewport]: it builds and releases the items its
/// render object asks for, from inside layout.
class ListViewportElement extends RenderObjectElement
    implements ListChildManager {
  /// The element of [widget].
  ListViewportElement(ListViewport super.widget);

  final SplayTreeMap<int, Element> _items = SplayTreeMap();

  ListViewport get _list => widget as ListViewport;
  RenderListViewport get _render => renderObject as RenderListViewport;

  @override
  int get itemCount => _list.itemCount;

  @override
  Object? versionOf(int index) => _list.itemVersion?.call(index);

  @override
  Iterable<int> get builtIndices => _items.keys;

  // The controller may bring heights an earlier list over it measured;
  // they are checked as a rebuild checks its own.
  @override
  void mount(Element? parent) {
    super.mount(parent);
    _rebuildItems();
  }

  @override
  void update(ListViewport newWidget) {
    super.update(newWidget);
    _rebuildItems();
  }

  // The builders get this element as their context, so an inherited widget
  // they depend on rebuilds the list as a new widget would.
  @override
  void performRebuild() {
    super.performRebuild();
    _rebuildItems();
  }

  void _rebuildItems() {
    final newWidget = _list;
    final extents = _render.extents..length = newWidget.itemCount;
    _render.updateItemExtents(
      newWidget.itemExtentBuilder,
      newWidget.itemExtentVersion,
    );
    if (newWidget.itemExtentBuilder == null) {
      final version = newWidget.itemVersion;
      if (version == null) {
        extents.clear();
      } else {
        extents.checkVersions(version);
      }
    }
    for (final i in List.of(_items.keys)) {
      if (i >= newWidget.itemCount) {
        Element.unmountTree(_items.remove(i)!);
      } else {
        _items[i] = updateChild(_items[i], _build(i))!;
      }
    }
  }

  Widget _build(int index) {
    Widget item;
    try {
      item = _list.itemBuilder(this, index);
    } catch (e, s) {
      item = buildError(e, s);
    }
    return NoFocusRequests(child: item);
  }

  @override
  RenderBox itemAt(int index) {
    var e = _items[index];
    if (e == null) {
      e = owner.buildDuringLayout(() => updateChild(null, _build(index)))!;
      _items[index] = e;
    }
    return RenderObjectElement.firstRenderObject(e)!;
  }

  @override
  void release(int index) {
    final e = _items.remove(index);
    if (e == null) return;
    owner.buildDuringLayout(() {
      Element.unmountTree(e);
      return null;
    });
  }

  @override
  void visitChildren(void Function(Element child) visitor) =>
      _items.values.forEach(visitor);

  @override
  void syncRenderChildren() {
    _render.items = {
      for (final MapEntry(:key, :value) in _items.entries)
        key: ?RenderObjectElement.firstRenderObject(value),
    };
  }

  @override
  void unmount() {
    _render.detachController();
    super.unmount();
  }
}
