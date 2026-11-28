import '../foundation/selection_delegate.dart';
import 'framework.dart';
import 'list_viewport.dart';
import 'listener.dart';
import 'scroll_controller.dart';

/// A list that builds only the items it shows.
///
/// It binds no keys and takes no focus: the app binds a controller's steps
/// with [scrollBindings]. With [scrollsOnWheel] the wheel scrolls it.
class ListView extends StatefulWidget {
  /// A list of [itemCount] items built by [itemBuilder]; a controller is
  /// made and owned when [controller] is absent.
  const ListView.builder({
    super.key,
    this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.itemVersion,
    this.itemExtentBuilder,
    this.itemExtentVersion,
    this.selectionDelegate,
    this.scrollsOnWheel = false,
  });

  /// Where the view is, and the steps that move it.
  final ScrollController? controller;

  /// Whether the wheel scrolls it, a row a step; off by default, for a list
  /// whose app handles the wheel itself.
  final bool scrollsOnWheel;

  /// How many items the list has.
  final int itemCount;

  /// Logical immutable sources for selection across unmounted history.
  final SelectionChildDelegate? selectionDelegate;

  /// Builds an item; called only for items being measured or in sight.
  final IndexedWidgetBuilder itemBuilder;

  /// A value that changes with anything that changes item `index`'s height,
  /// global inputs included; without it every rebuild drops every height.
  /// Heights are kept on [controller], so a list built again over it reuses
  /// each one whose version is unchanged; when one controller serves
  /// different lists, the version names the item, not only its look.
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
  State<ListView> createState() => _ListViewState();
}

class _ListViewState extends State<ListView> {
  ScrollController? _own;

  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void didUpdateWidget(ListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && _own != null) {
      _own!.dispose();
      _own = null;
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ListViewport(
      controller: _controller,
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
      itemVersion: widget.itemVersion,
      itemExtentBuilder: widget.itemExtentBuilder,
      itemExtentVersion: widget.itemExtentVersion,
      selectionDelegate: widget.selectionDelegate,
    );
    if (!widget.scrollsOnWheel) return list;
    return Listener(
      onPointerSignal: (event) => scrollByWheel(_controller, event),
      child: list,
    );
  }
}
