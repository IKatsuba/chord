import '../foundation/selection_delegate.dart';
import 'dart:typed_data';

import '../foundation/geometry.dart';
import '../foundation/item_extents.dart';
import '../foundation/scroll_state.dart';
import '../terminal/buffer.dart';
import '../widgets/framework.dart';
import '../widgets/scroll_controller.dart';
import 'box.dart';

export '../foundation/item_extents.dart' show ItemExtents;

/// What a [RenderListViewport] asks of the element that owns its items.
abstract interface class ListChildManager {
  /// How many items the list has now.
  int get itemCount;

  /// The version item [index] is measured under; null without one.
  Object? versionOf(int index);

  /// The indices of the items built now.
  Iterable<int> get builtIndices;

  /// The render box of item [index], built if it is not. Called only from
  /// inside layout.
  RenderBox itemAt(int index);

  /// Unmounts item [index]. Called only from inside layout.
  void release(int index);
}

/// Lays out and paints only the items of a list that fall in its rows,
/// after measuring every item whose height is unknown.
class RenderListViewport extends RenderBox implements ScrollClient {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderListViewport);

  /// A viewport over [manager]'s items, placed as [controller] says.
  RenderListViewport({
    required this.manager,
    required ScrollController controller,
    required this.owner,
    this.selectionDelegate,
    int Function(int index, int width)? itemExtentBuilder,
    Object? itemExtentVersion,
  }) : _controller = controller,
       _itemExtentBuilder = itemExtentBuilder,
       _itemExtentVersion = itemExtentVersion {
    controller.attach(this);
  }

  /// The element that builds and releases the items.
  ListChildManager manager;

  /// Where layout's notifications go, after layout.
  final BuildOwner owner;

  /// Immutable logical sources; measurement-only children never register.
  SelectionChildDelegate? selectionDelegate;

  /// Current painted items and their logical indices.
  Iterable<(int, RenderBox)> get placedItems => _placed;

  /// The heights of the items at the viewport's width: the controller's,
  /// so a viewport built again over it measures only what changed; an exact
  /// [itemExtentBuilder] keeps its own, projected per viewport.
  ItemExtents get extents =>
      _itemExtentBuilder == null ? _controller.itemExtents : _exactExtents;

  final ItemExtents _exactExtents = ItemExtents();

  int Function(int index, int width)? _itemExtentBuilder;
  Object? _itemExtentVersion;
  bool _exactDirty = true;
  int? _exactWidth;
  int? _exactCount;
  Int64List _exactNext = Int64List(0);

  /// Updates the exact-height contract; null revisions invalidate on rebuild.
  /// Equal explicit revisions preserve geometry across inline callbacks.
  void updateItemExtents(
    int Function(int index, int width)? builder,
    Object? version,
  ) {
    if ((_itemExtentBuilder == null) != (builder == null)) {
      _controller.itemExtents.clear();
      _exactExtents.clear();
    }
    if (builder == null ||
        version == null ||
        version != _itemExtentVersion ||
        _itemExtentBuilder == null) {
      _exactDirty = true;
    }
    if (builder == null) _exactNext = Int64List(0);
    _itemExtentBuilder = builder;
    _itemExtentVersion = version;
  }

  void _recordMeasured(int index, int height) {
    if (_itemExtentBuilder != null) {
      if (height != extents.heightOf(index)) {
        throw StateError(
          'Item $index measured $height rows, but its exact '
          'extent is ${extents.heightOf(index)}.',
        );
      }
    } else {
      extents.record(index, height, manager.versionOf(index));
    }
  }

  ScrollController _controller;

  /// The controller that says where the view is.
  ScrollController get controller => _controller;
  set controller(ScrollController c) {
    if (identical(c, _controller)) return;
    _controller.detach(this);
    _controller = c;
    c.attach(this);
  }

  /// Lets go of the controller, when the viewport leaves the tree.
  void detachController() => _controller.detach(this);

  /// The built items' boxes by index, as the element last synced them.
  Map<int, RenderBox> items = {};

  final List<(int, RenderBox)> _placed = [];

  @override
  void visitChildren(void Function(RenderBox child) visitor) {
    for (final (_, box) in _placed) {
      visitor(box);
    }
  }

  @override
  void performLayout() {
    if (!constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
      final axis = constraints.hasBoundedHeight ? 'width' : 'height';
      throw StateError(
        'A ListView was given unbounded $axis. It takes the size it is '
        'given: wrap it in Expanded or a SizedBox.',
      );
    }
    size = constraints.biggest;
    final width = size.width;
    final count = manager.itemCount;
    if (_exactWidth != width) _exactDirty = true;
    if (selectionDelegate != null && selectionDelegate!.itemCount != count) {
      throw ArgumentError('Selection delegate and viewport counts must agree.');
    }
    extents
      ..width = width
      ..length = count;
    _placed.clear();
    final laidOut = <int>{};

    if (width > 0) {
      final item = BoxConstraints(minWidth: width, maxWidth: width);
      final exact = _itemExtentBuilder;
      if (exact != null &&
          (_exactDirty || _exactWidth != width || _exactCount != count)) {
        _exactNext = Int64List(count);
        int? previous;
        for (var i = 0; i < count; i++) {
          final height = exact(i, width);
          if (height < 0) {
            throw ArgumentError.value(
              height,
              'itemExtentBuilder',
              'Negative height for item $i',
            );
          }
          if (height > 0) {
            if (previous != null) _exactNext[previous] = i;
            _exactNext[i] = count;
            previous = i;
          }
          extents.record(i, height, null);
        }
        _exactDirty = false;
        _exactWidth = width;
        _exactCount = count;
      }
      // What is built was in sight: lay it out again, since its height may
      // have changed with no new version.
      for (final i in List.of(manager.builtIndices)) {
        if (i >= count) continue;
        final box = manager.itemAt(i)..layout(item);
        _recordMeasured(i, box.size.height);
        laidOut.add(i);
      }
      for (var i = 0; exact == null && i < count; i++) {
        if (extents.isKnown(i)) continue;
        final box = manager.itemAt(i)..layout(item);
        _recordMeasured(i, box.size.height);
        // Released at once, so measuring never holds every item mounted.
        manager.release(i);
      }
    }

    final s = _controller.state;
    final content = width > 0 ? extents.total : 0;
    var anchor = _controller.anchor;
    if (anchor != null && count > 0 && anchor.index >= count) {
      anchor = ListAnchor(count - 1, 0);
    }
    final top = anchor == null || count == 0 ? null : extents.topOf(anchor);
    final next = reduceMeasured(
      s,
      content: content,
      view: size.height,
      top: top,
      follow: _controller.follow,
    );
    if (_controller.setFromLayout(next)) {
      owner.afterLayout(_controller.notifyAfterLayout);
    }
    _controller.anchor = next.following || content == 0
        ? null
        : extents.anchorAt(next.top);

    final visible = <int>{};
    if (width > 0 && content > 0 && size.height > 0) {
      final offset = next.offset;
      final end = offset + size.height;
      final item = BoxConstraints(minWidth: width, maxWidth: width);
      for (
        var i = extents.anchorAt(offset)!.index;
        i < count && extents.itemTop(i) < end;
        i = _itemExtentBuilder == null ? i + 1 : _exactNext[i]
      ) {
        final box = manager.itemAt(i);
        if (!laidOut.contains(i)) {
          box.layout(item);
          _recordMeasured(i, box.size.height);
        }
        box.offset = Offset(0, extents.itemTop(i) - offset);
        _placed.add((i, box));
        visible.add(i);
      }
    }
    for (final i in List.of(manager.builtIndices)) {
      if (!visible.contains(i)) manager.release(i);
    }
  }

  @override
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    final visible = clip.intersect(Rect.fromOffsetSize(origin, size));
    visitChildren((child) => visitor(child, origin + child.offset, visible));
  }

  @override
  void paint(Canvas canvas, Offset origin) => paintChildren(canvas, origin);

  @override
  int itemTop(int index) => extents.itemTop(index);

  @override
  int itemRows(int index) => extents.heightOf(index) ?? 0;

  @override
  int itemAtRow(int row) {
    if (row >= extents.total) return -1;
    return extents.anchorAt(row)?.index ?? -1;
  }

  @override
  void scrollChanged() {
    // A step moved top in the reducer; the anchor follows it, read against
    // the heights the step was taken over.
    final s = _controller.state;
    _controller.anchor = s.following || extents.length == 0
        ? null
        : extents.anchorAt(s.top);
    owner.requestFrame();
  }
}
