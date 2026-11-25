import '../foundation/geometry.dart';
import '../rendering/basic.dart';
import '../rendering/box.dart';
import '../rendering/overlay.dart';
import 'focus.dart';
import 'focus_manager.dart';
import 'basic.dart';
import 'framework.dart';

/// A layer of an [Overlay]: built by [builder] at the overlay's place in
/// the tree, painted over the layers inserted before it.
class OverlayEntry {
  /// A layer that [builder] makes; [requestFocus] says whether it takes
  /// focus when it is shown.
  OverlayEntry({required this.builder, this.requestFocus = true});

  /// Makes what the layer shows.
  final Widget Function(BuildContext context) builder;

  /// Whether the layer takes focus when shown, or leaves it where it is.
  final bool requestFocus;

  OverlayState? _overlay;
  _EntryState? _state;
  var _disposed = false;
  bool _visible = false;

  /// Whether the latest layout gave this entry a paintable surface.
  ///
  /// False before layout and after removal or disposal. This is geometry,
  /// not focus or occlusion, and does not notify or rebuild its readers.
  bool get visible => _visible;
  late final Widget _widget = _EntryWidget(this);

  /// Whether the layer is built in an overlay now.
  bool get mounted => _state != null;

  /// Builds the layer again in the next frame.
  void markNeedsBuild() => _state?.rebuild();

  /// Takes the layer out of its overlay; harmless when it is not in one.
  void remove() {
    final overlay = _overlay;
    _overlay = null;
    _visible = false;
    overlay?._remove(this);
  }

  /// Releases a removed layer; it cannot be inserted again.
  void dispose() {
    assert(_overlay == null, 'Remove an OverlayEntry before disposing it.');
    _disposed = true;
    _visible = false;
  }
}

class _EntryWidget extends StatefulWidget {
  _EntryWidget(this.entry) : super(key: _EntryKey(entry));

  final OverlayEntry entry;

  @override
  State<_EntryWidget> createState() => _EntryState();
}

class _EntryKey extends Key {
  const _EntryKey(this.entry);

  final OverlayEntry entry;

  @override
  bool operator ==(Object other) =>
      other is _EntryKey && identical(other.entry, entry);

  @override
  int get hashCode => identityHashCode(entry);
}

class _EntryState extends State<_EntryWidget> {
  // Inactive until the overlay has laid the entry out and seen it shows.
  final FocusScopeNode scope = FocusScopeNode(
    debugLabel: 'overlay entry',
    active: false,
  );

  @override
  void initState() {
    super.initState();
    widget.entry._state = this;
    if (widget.entry.requestFocus) {
      final focus = context.owner.focusManager;
      scope.bindings = [
        Binding('tab', 'Next field', focus.focusNext),
        Binding('shift+tab', 'Previous field', focus.focusPrevious),
      ];
    }
  }

  void rebuild() => setState(() {});

  @override
  void dispose() {
    if (identical(widget.entry._state, this)) {
      widget.entry._state = null;
      widget.entry._visible = false;
    }
    scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: scope,
    child: Builder(builder: widget.entry.builder),
  );
}

/// Layers painted over one another, bottom first: the first entry is the
/// page, and those inserted later float over it.
///
/// Each layer is laid out at the overlay's size; the overlay needs a
/// bounded width and height. Entries build at the overlay's place, so what
/// they inherit must be above it.
class Overlay extends StatefulWidget {
  /// An overlay that starts with [initialEntries]; later changes to the
  /// list are not followed.
  const Overlay({super.key, this.initialEntries = const []});

  /// The entries it starts with, bottom first.
  final List<OverlayEntry> initialEntries;

  /// The nearest overlay above [context]; there must be one.
  static OverlayState of(BuildContext context) =>
      maybeOf(context) ?? (throw StateError('No Overlay above this widget.'));

  /// The nearest overlay above [context], if any.
  static OverlayState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<OverlayState>();

  @override
  State<Overlay> createState() => OverlayState();
}

/// The live entries of an [Overlay].
class OverlayState extends State<Overlay> {
  /// The state of an overlay with no entries yet.
  OverlayState();

  final List<OverlayEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    for (final e in widget.initialEntries) {
      _attach(e);
      _entries.add(e);
    }
  }

  void _attach(OverlayEntry entry) {
    if (entry._disposed) {
      throw StateError('A disposed OverlayEntry cannot be inserted.');
    }
    if (entry._overlay != null) {
      throw StateError('This OverlayEntry is already in an overlay.');
    }
    entry._visible = false;
    entry._overlay = this;
  }

  /// Puts [entry] on top, or just [below] or [above] an entry of this
  /// overlay.
  void insert(OverlayEntry entry, {OverlayEntry? below, OverlayEntry? above}) {
    if (below != null && above != null) {
      throw ArgumentError('Give below or above, not both.');
    }
    final anchor = below ?? above;
    if (anchor != null && !_entries.contains(anchor)) {
      throw ArgumentError('The anchor entry is not in this overlay.');
    }
    _attach(entry);
    setState(() {
      final at = anchor == null
          ? _entries.length
          : _entries.indexOf(anchor) + (above != null ? 1 : 0);
      _entries.insert(at, entry);
    });
  }

  void _remove(OverlayEntry entry) {
    if (!mounted) return;
    setState(() => _entries.remove(entry));
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e._overlay = null;
      e._visible = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Layers(List.of(_entries));
}

class _Layers extends RenderObjectWidget {
  const _Layers(this.entries);

  final List<OverlayEntry> entries;

  @override
  Element createElement() => _LayersElement(this);

  @override
  RenderBox createRenderObject(BuildContext context) => RenderOverlay(
    (context as _LayersElement)._buildMissing,
    onShown: context._shown,
  );
}

/// Builds the entries from inside layout, as a list builds its items; an
/// entry kept across changes keeps its element and is not rebuilt.
class _LayersElement extends RenderObjectElement {
  _LayersElement(_Layers super.widget);

  final Map<OverlayEntry, Element> _built = {};

  List<OverlayEntry> get _entries => (widget as _Layers).entries;

  @override
  void update(_Layers newWidget) {
    super.update(newWidget);
    final kept = newWidget.entries.toSet();
    for (final e in List.of(_built.keys)) {
      if (!kept.contains(e)) {
        _wasShown.remove(e);
        Element.unmountTree(_built.remove(e)!);
      }
    }
  }

  final Map<OverlayEntry, bool> _wasShown = {};

  // Focus moves after layout, never during it.
  void _shown(List<bool> shown) {
    final entries = [
      for (final e in _entries)
        if (_built.containsKey(e)) e,
    ];
    for (final (i, e) in entries.indexed) {
      e._visible = shown[i];
    }
    // The page is never suspended: it is what focus falls back to.
    if (shown.isNotEmpty) shown = [true, ...shown.skip(1)];
    var changed = false;
    for (final (i, e) in entries.indexed) {
      if (_wasShown[e] != shown[i]) changed = true;
    }
    if (!changed) return;
    owner.afterLayout(() => _apply(entries, shown));
  }

  void _apply(List<OverlayEntry> entries, List<bool> shown) {
    final focus = owner.focusManager;
    for (final (i, e) in entries.indexed) {
      final state = e._state;
      if (state == null || _wasShown[e] == shown[i]) continue;
      _wasShown[e] = shown[i];
      // The page moves focus as any page does; its keys stay unlisted.
      if (i == 0) state.scope.bindings = const [];
      // A newer entry that holds focus keeps it.
      final covered = entries
          .skip(i + 1)
          .any((o) => o.requestFocus && (o._state?.scope.hasFocus ?? false));
      focus.setScopeActive(
        state.scope,
        shown[i],
        takeFocus: i > 0 && e.requestFocus && !covered,
        autofocus: i == 0,
      );
    }
  }

  void _buildMissing() {
    for (final e in _entries) {
      if (_built.containsKey(e)) continue;
      _built[e] = owner.buildDuringLayout(() => updateChild(null, e._widget))!;
    }
    syncRenderChildren();
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    for (final e in _entries) {
      final c = _built[e];
      if (c != null) visitor(c);
    }
  }

  @override
  void syncRenderChildren() {
    (renderObject as RenderOverlay).children = [
      for (final e in _entries)
        ?RenderObjectElement.firstRenderObject(_built[e]),
    ];
  }
}

/// Marks its child as the place [link]'s followers are anchored to; it
/// must be in the page, the first entry, of the overlay they float in.
class CompositedTransformTarget extends SingleChildRenderObjectWidget {
  /// A target for [link].
  const CompositedTransformTarget({
    super.key,
    required this.link,
    required Widget super.child,
  });

  /// The link its followers use.
  final LayerLink link;

  @override
  RenderLayerTarget createRenderObject(BuildContext context) =>
      RenderLayerTarget(link);

  @override
  void updateRenderObject(BuildContext context, RenderLayerTarget r) =>
      r.link = link;
}

/// Shows its child in an overlay entry, placed against [link]'s target:
/// [followerAnchor] of the child on [targetAnchor] of the target, moved
/// by [offset].
///
/// The child is loosely constrained to the room between that point and
/// the overlay's edges, clipped to it, and covers what is under it. When
/// the target was not laid out this frame the child is hidden, unless
/// [showWhenUnlinked].
class CompositedTransformFollower extends SingleChildRenderObjectWidget {
  /// A follower of [link].
  const CompositedTransformFollower({
    super.key,
    required this.link,
    this.targetAnchor = Alignment.topLeft,
    this.followerAnchor = Alignment.topLeft,
    this.offset = Offset.zero,
    this.showWhenUnlinked = false,
    this.opaque = true,
    required Widget super.child,
  });

  /// The link to the target.
  final LayerLink link;

  /// The point of the target the child is placed at.
  final Alignment targetAnchor;

  /// The point of the child put on the target's point.
  final Alignment followerAnchor;

  /// Moves the target's point, in cells.
  final Offset offset;

  /// Whether the child shows at the overlay's corner when unlinked.
  final bool showWhenUnlinked;

  /// Fills and occludes the follower rectangle; false leaves only child paint/hits.
  final bool opaque;

  @override
  RenderFollower createRenderObject(BuildContext context) => RenderFollower(
    overlay: _overlayOf(context),
    link: link,
    targetAnchor: targetAnchor,
    followerAnchor: followerAnchor,
    followOffset: offset,
    showWhenUnlinked: showWhenUnlinked,
    opaque: opaque,
  );

  @override
  void updateRenderObject(BuildContext context, RenderFollower r) {
    r
      ..link = link
      ..targetAnchor = targetAnchor
      ..followerAnchor = followerAnchor
      ..followOffset = offset
      ..showWhenUnlinked = showWhenUnlinked
      ..opaque = opaque;
  }

  // The overlay finds a layer's follower down single-child render
  // objects only, to know whether the layer shows.
  static RenderOverlay _overlayOf(BuildContext context) {
    RenderOverlay? found;
    var branched = false;
    context.visitAncestorElements((e) {
      if (e is _LayersElement) {
        found = e.renderObject as RenderOverlay;
      } else if (e is RenderObjectElement &&
          e.renderObject is! RenderWithChild) {
        branched = true;
      }
      return found == null;
    });
    if (found == null) {
      throw StateError('A CompositedTransformFollower needs an Overlay.');
    }
    if (branched) {
      throw StateError(
        "A CompositedTransformFollower must be its entry's root or sit under "
        'widgets with one child each, not under a Stack, a Row or a Column.',
      );
    }
    return found!;
  }
}
