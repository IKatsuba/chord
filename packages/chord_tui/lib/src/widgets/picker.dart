import '../input/keys.dart';
import '../foundation/geometry.dart';
import '../foundation/picker_state.dart';
import '../rendering/flex.dart';
import 'basic.dart';
import 'focus.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'layout_builder.dart';
import 'list_view.dart';
import 'picker_row.dart';
import 'scroll_bindings.dart';
import 'scroll_controller.dart';
import '../foundation/text_editing.dart';
import 'text_input.dart';
import 'theme.dart';

/// Builds a picker row's content for [item], given the label's matched
/// positions; the picker draws the gutter and the number beside it.
typedef PickerItemBuilder<T> =
    Widget Function(
      BuildContext context,
      PickerItem<T> item,
      List<int> matchedPositions,
    );

/// A numbered list of choices with a highlight, chosen by Enter or by
/// number: chord's pickers, with no frame of their own.
///
/// Up and down (or k and j) move the highlight and stop at the ends; a row
/// taller than the list is read a line a press. With [searchable], `/`
/// edits a filter that ranks the choices by [filter].
class Picker<T> extends StatefulWidget {
  /// A picker of [items].
  const Picker({
    super.key,
    required this.items,
    required this.onSelected,
    required this.onCanceled,
    this.initialValue,
    this.onChanged,
    this.maxVisibleRows = 8,
    this.searchable = false,
    this.filter = const FzfPickerFilter(),
    this.itemBuilder,
    this.itemExtentBuilder,
    this.itemExtentVersion,
    this.autofocus = true,
    this.enabled = true,
    this.focusNode,
    this.unhandledKeys = const {},
    this.wrapNavigation = false,
    this.showNumbers = true,
    this.showInitialSelectionAtTop = true,
    this.countHiddenItemsAbove = false,
  });

  /// The choices; their values must be unique.
  final List<PickerItem<T>> items;

  /// Called with the value chosen.
  final void Function(T value) onSelected;

  /// Reports a non-null highlighted value changing, without accepting it.
  /// No initial notification; item reconciliation notifies after layout.
  final void Function(T value)? onChanged;

  /// Called when Esc leaves the picker.
  final void Function() onCanceled;

  /// The value highlighted first, when it is one of the items.
  final T? initialValue;

  /// The most rows the choices take.
  final int maxVisibleRows;

  /// Whether the choices can be filtered.
  final bool searchable;

  /// Ranks the choices against the filter's text.
  final PickerFilter filter;

  /// Builds a row's content; the label on one line, cut, when null.
  final PickerItemBuilder<T>? itemBuilder;

  /// Supplies exact nonnegative content heights at the content width after
  /// marker, number and edge gutters. Picker keeps at least one furniture row.
  /// Must be pure. Negative heights report ArgumentError through normal build
  /// error handling. A mounted height differing from the promise throws
  /// StateError during layout, including in compiled executables.
  final int Function(
    PickerItem<T> item,
    List<int> matchedPositions,
    int contentWidth,
  )?
  itemExtentBuilder;

  /// A nonnull revision promises captured exact-height inputs are unchanged.
  /// Inline callback identity is ignored with equal revisions; null reprojects
  /// on widget updates. Query, order and gutter changes still invalidate.
  final Object? itemExtentVersion;

  /// Whether the picker takes focus when it is built.
  final bool autofocus;

  /// Whether input and focus are available; false leaves choices unmarked.
  /// Selection, query and viewport are preserved while disabled.
  final bool enabled;

  /// The picker's focus node; made and owned by the picker when absent.
  /// The caller owns a supplied node and may request it after enabling.
  final FocusNode? focusNode;

  /// Keys whose picker-owned bindings are omitted, so ancestors can act.
  /// TextInput keeps its editing keys while the filter is being edited.
  final Set<String> unhandledKeys;

  /// Whether moving beyond the first or last choice goes around.
  /// A tall highlighted row is read to its edge before changing choices.
  final bool wrapNavigation;

  /// Whether to draw the padded number column; numeric shortcuts still work.
  /// False lets a custom label include its own number and wrap as one text.
  final bool showNumbers;

  /// Whether the initial view starts at the selected item's first row.
  /// False retains preceding rows, scrolling only enough to reveal selection,
  /// including on resize, measurement and equivalent-item updates.
  final bool showInitialSelectionAtTop;

  /// Whether the footer counts wholly hidden choices above as well as below.
  /// Its row is reserved whenever choices overflow, except for a tall selection.
  final bool countHiddenItemsAbove;

  @override
  State<Picker<T>> createState() => _PickerState<T>();
}

class _PickerState<T> extends State<Picker<T>> {
  late PickerState<T> _state;
  PickerView _view = (highlighted: 0, top: 0);
  PickerGeometry _geometry = PickerGeometry(const []);
  bool _exactDirty = true;
  int? _exactOuterWidth;
  int? _exactBudget;
  int? _exactContentWidth;
  bool get _usesExact =>
      widget.itemBuilder == null || widget.itemExtentBuilder != null;
  int _budget = 0;
  bool _opening = true;
  T? _reported;
  var _highlightRevision = 0;
  Set<KeyCombo> _unhandled = const {};

  void _parseUnhandled() => _unhandled = {
    for (final key in widget.unhandledKeys) KeyCombo.parse(key),
  };

  List<Binding> _handled(List<Binding> bindings) => [
    for (final binding in bindings)
      if (!_unhandled.contains(binding.chord.combos.first)) binding,
  ];
  var _rows = 0;

  final _scroll = ScrollController();
  final _query = TextEditingController();
  final _gate = FocusNode(canRequestFocus: false, debugLabel: 'picker gate');
  FocusNode? _ownNode;
  FocusNode get _node =>
      widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'picker'));

  void _configureNode() {
    _gate.descendantsAreFocusable = widget.enabled;
    _node
      ..canRequestFocus = widget.enabled
      ..descendantsAreFocusable = widget.enabled;
    if (!widget.enabled) _node.unfocus();
  }

  @override
  void initState() {
    super.initState();
    _parseUnhandled();
    _state = PickerState.initial(
      widget.items,
      initialValue: widget.initialValue,
    );
    _reported = _state.selected;
    _reset();
    _configureNode();
    _scroll.addListener(_scrolled);
    _focus.addListener(_focusChanged);
  }

  late final FocusManager _focus = context.owner.focusManager;
  var _focused = false;

  // The highlight is drawn only while the picker, or its editor, has focus.
  void _focusChanged() {
    if (mounted && _node.hasFocus != _focused) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void didUpdateWidget(Picker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = _state.selected;
    if ((widget.itemExtentBuilder != null &&
            widget.itemExtentVersion == null) ||
        widget.itemExtentVersion != oldWidget.itemExtentVersion ||
        (widget.itemExtentBuilder == null) !=
            (oldWidget.itemExtentBuilder == null) ||
        widget.showNumbers != oldWidget.showNumbers ||
        (widget.itemBuilder == null) != (oldWidget.itemBuilder == null)) {
      _exactDirty = true;
    }
    if (oldWidget.unhandledKeys != widget.unhandledKeys) _parseUnhandled();
    if (oldWidget.focusNode != widget.focusNode) {
      final old = oldWidget.focusNode ?? _ownNode;
      old?.descendantsAreFocusable = true;
      _focused = _node.hasFocus;
    }
    _configureNode();
    if (!widget.enabled && oldWidget.enabled) {
      _state = _state.withMode(PickerMode.navigation);
    }
    if (!widget.searchable && oldWidget.searchable) {
      // No filter row any more: its query goes, and keys go back to
      // navigation.
      _query.text = '';
      _state = _state
          .withMode(PickerMode.navigation)
          .withQuery('', widget.filter);
      _reset();
      if (_node.hasFocus) _node.requestFocus();
    }
    if ((oldWidget.countHiddenItemsAbove != widget.countHiddenItemsAbove ||
            oldWidget.showInitialSelectionAtTop !=
                widget.showInitialSelectionAtTop) &&
        _geometry.length > 0) {
      _view = _placedView(_budget);
    }
    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.filter != widget.filter) {
      _state = _state.withItems(widget.items, widget.filter);
      _reset();
    }
    _highlightChanged(before, deferred: true);
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _scroll.dispose();
    _query.dispose();
    _node.descendantsAreFocusable = true;
    _ownNode?.dispose();
    _gate.dispose();
    super.dispose();
  }

  // New results: unmeasured, the highlighted one revealed from its top.
  void _reset() {
    _geometry = PickerGeometry(List.filled(_state.results.length, 1));
    _exactDirty = true;
    final at = _state.highlighted;
    _view = _geometry.length == 0
        ? (highlighted: 0, top: 0)
        : _geometry.open(
            at < 0 ? 0 : at,
            _budget,
            countHiddenItemsAbove: widget.countHiddenItemsAbove,
            top: widget.showInitialSelectionAtTop || _opening ? 0 : _view.top,
          );
  }

  PickerView _placedView(int budget) => widget.showInitialSelectionAtTop
      ? _geometry.fromFirstLine(
          _view,
          budget,
          countHiddenItemsAbove: widget.countHiddenItemsAbove,
        )
      : _geometry.open(
          _view.highlighted,
          budget,
          top: _opening ? 0 : _view.top,
          countHiddenItemsAbove: widget.countHiddenItemsAbove,
        );

  void _measureExact(int outerWidth, int budget) {
    if (!_exactDirty &&
        _exactOuterWidth == outerWidth &&
        _exactBudget == budget) {
      return;
    }
    final number = widget.showNumbers
        ? pickerNumber(0, _state.results.length).length + 1
        : 0;
    var finalWidth = 0;
    PickerGeometry project(bool edge) {
      final width = (outerWidth - 2 - number - (edge ? 2 : 0)).clamp(
        0,
        unbounded,
      );
      finalWidth = width;
      if (!_exactDirty && width == _exactContentWidth) return _geometry;
      return PickerGeometry([
        for (var i = 0; i < _state.results.length; i++) _exactHeight(i, width),
      ]);
    }

    final edge = _state.results.length > budget;
    var geometry = project(edge);
    if (!edge && geometry.total > budget) geometry = project(true);
    _geometry = geometry;
    _view = _placedView(budget);
    _exactDirty = false;
    _exactContentWidth = finalWidth;
    _exactOuterWidth = outerWidth;
    _exactBudget = budget;
  }

  int _exactHeight(int index, int width) {
    final height =
        widget.itemExtentBuilder?.call(
          _state.resultAt(index),
          _state.results[index].matchedPositions,
          width,
        ) ??
        1;
    if (height < 0) {
      throw ArgumentError.value(
        height,
        'itemExtentBuilder',
        'Negative content height',
      );
    }
    return height < 1 ? 1 : height;
  }

  // The list measured its rows, or a scroll key moved it.
  void _scrolled() {
    if (!mounted || _state.results.isEmpty) return;
    if (_usesExact) {
      if (_scroll.offset != _top) {
        setState(
          () => _view = (highlighted: _view.highlighted, top: _scroll.offset),
        );
      }
      return;
    }
    final List<int> heights;
    try {
      heights = [
        for (var i = 0; i < _state.results.length; i++) _scroll.itemRows(i),
      ];
    } on StateError {
      return;
    }
    if (heights.any((h) => h == 0)) return;
    var same = heights.length == _geometry.length;
    for (var i = 0; same && i < heights.length; i++) {
      same = heights[i] == _geometry.heightOf(i);
    }
    if (!same) {
      setState(() {
        _geometry = PickerGeometry(heights);
        _view = _placedView(_budget);
      });
      _jump();
    } else if (_scroll.offset != _top) {
      setState(
        () => _view = (highlighted: _view.highlighted, top: _scroll.offset),
      );
    }
  }

  int _top = 0;

  bool get _navigating =>
      _state.mode == PickerMode.navigation &&
      _rows > 0 &&
      _state.results.isNotEmpty;

  void _move(int step) {
    final before = _state.selected;
    final next = _geometry.move(
      _view,
      _budget,
      step,
      wrap: widget.wrapNavigation,
      countHiddenItemsAbove: widget.countHiddenItemsAbove,
    );
    if (next == null) return;
    setState(() {
      _state = _state.moved(next.highlighted - _view.highlighted);
      _view = next;
    });
    _jump();
    _highlightChanged(before);
  }

  void _choose(T? value) {
    if (value != null || null is T) widget.onSelected(value as T);
  }

  void _edit(bool editing) {
    setState(() {
      _state = _state.withMode(
        editing ? PickerMode.editing : PickerMode.navigation,
      );
    });
    if (!editing) _node.requestFocus();
  }

  void _queryChanged(String text) {
    final before = _state.selected;
    setState(() {
      _state = _state.withQuery(text, widget.filter);
      _reset();
    });
    _jump();
    _highlightChanged(before);
  }

  void _highlightChanged(T? before, {bool deferred = false}) {
    final value = _state.selected;
    if (before == value) return;
    final revision = ++_highlightRevision;
    if (value == null) {
      _reported = null;
      return;
    }
    void notify() {
      if (!mounted ||
          revision != _highlightRevision ||
          _state.selected != value ||
          _reported == value) {
        return;
      }
      // Set before invoking user code: it may rebuild or remove this picker.
      _reported = value;
      widget.onChanged?.call(value);
    }

    if (deferred) {
      context.owner.afterLayout(notify);
    } else {
      notify();
    }
  }

  // Puts the list where the view says, outside layout.
  void _jump() {
    if (_geometry.length == 0 || _budget <= 0) return;
    final lines = _geometry
        .lines(
          _view,
          _budget,
          countHiddenItemsAbove: widget.countHiddenItemsAbove,
        )
        .lines;
    final top = _geometry.itemTop(lines.first.index) + lines.first.line;
    _top = top;
    if (_scroll.offset != top) _scroll.jumpTo(top);
  }

  @override
  Widget build(BuildContext context) {
    final count = _state.results.length;
    final editing = _state.mode == PickerMode.editing;
    return Focus(
      focusNode: _gate,
      canRequestFocus: false,
      child: Actions(
        bindings: widget.enabled
            ? _handled([
                Binding(
                  'up',
                  'Previous choice',
                  () => _move(-1),
                  enabled: _navigating,
                ),
                Binding(
                  'k',
                  'Previous choice',
                  () => _move(-1),
                  enabled: _navigating,
                ),
                Binding(
                  'down',
                  'Next choice',
                  () => _move(1),
                  enabled: _navigating,
                ),
                Binding(
                  'j',
                  'Next choice',
                  () => _move(1),
                  enabled: _navigating,
                ),
                Binding(
                  'enter',
                  'Choose highlighted item',
                  () => _choose(_state.resultAt(_view.highlighted).value),
                  enabled: _navigating,
                ),
                for (var n = 1; n <= 9; n++)
                  Binding(
                    '$n',
                    'Choose item $n',
                    () => _choose(_state.valueOf(n)),
                    enabled: _navigating && n <= count,
                  ),
                for (final b in scrollBindings(_scroll))
                  Binding(
                    b.chord.toString(),
                    b.description,
                    b.onInvoke,
                    enabled: !editing && _rows > 0,
                  ),
                if (widget.searchable)
                  Binding(
                    '/',
                    'Edit filter',
                    () => _edit(true),
                    enabled: !editing,
                  ),
                Binding(
                  'esc',
                  'Cancel picker',
                  widget.onCanceled,
                  enabled: !editing,
                ),
              ])
            : const [],
        child: Focus(
          focusNode: _node,
          autofocus: widget.autofocus && widget.enabled,
          canRequestFocus: widget.enabled,
          child: LayoutBuilder(builder: _layout),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    var room = constraints.hasBoundedHeight ? constraints.maxHeight : unbounded;
    if (widget.searchable) {
      room--;
      rows.add(
        widget.enabled && _state.mode == PickerMode.editing
            ? Actions(
                bindings: _handled([
                  // TextInput takes Enter itself and submits; this lists it.
                  Binding('enter', 'Finish editing filter', () => _edit(false)),
                  Binding('esc', 'Finish editing filter', () => _edit(false)),
                ]),
                child: TextInput(
                  controller: _query,
                  autofocus: true,
                  prefix: 'Filter: ',
                  onChanged: _queryChanged,
                  onSubmit: (_) => _edit(false),
                ),
              )
            : Text('Filter: ${_query.text}', softWrap: false),
      );
    }
    final budget = room < 0
        ? 0
        : (room < widget.maxVisibleRows ? room : widget.maxVisibleRows);
    if (_usesExact && _state.results.isNotEmpty && budget > 0) {
      try {
        _measureExact(constraints.maxWidth, budget);
      } catch (_) {
        // Build errors replace the list, so old choice bindings must not
        // remain active while the framework presents that failure.
        if (_rows > 0) {
          _rows = 0;
          context.owner.afterLayout(() {
            if (mounted) setState(() {});
          });
        }
        rethrow;
      }
    }
    if (budget != _budget) {
      _budget = budget;
      if (_geometry.length > 0) {
        _view = _placedView(budget);
      }
    }
    if (_opening && budget > 0) {
      context.owner.afterLayout(() {
        _opening = false;
      });
    }
    var listRows = 0;
    if (_state.results.isEmpty) {
      if (budget > 0) {
        rows.add(
          Text(
            widget.items.isEmpty ? 'No choices.' : 'No matches.',
            style: theme.dim,
            softWrap: false,
          ),
        );
      }
    } else if (budget > 0) {
      final (:lines, :hidden) = _geometry.lines(
        _view,
        budget,
        countHiddenItemsAbove: widget.countHiddenItemsAbove,
      );
      listRows = lines.length;
      final top = _geometry.itemTop(lines.first.index) + lines.first.line;
      _top = top;
      if (_scroll.offset != top) {
        // The list is told after layout, never during it; the frame is
        // laid out again with it.
        context.owner.afterLayout(() {
          if (!mounted) return;
          _scroll.jumpTo(_top);
          setState(() {});
        });
      }
      final scrolls = lines.first.edge != null;
      rows.add(
        SizedBox(
          // Keyed: the filter row above it comes and goes, and the list
          // must keep its element and its controller.
          key: const ValueKey('list'),
          height: listRows,
          child: Stack(
            children: [
              ListView.builder(
                controller: _scroll,
                itemCount: _state.results.length,
                itemExtentBuilder: _usesExact
                    ? (i, width) => _geometry.heightOf(i)
                    : null,
                itemExtentVersion: _usesExact ? _geometry : null,
                itemBuilder: (context, i) => _row(context, i, scrolls),
              ),
              if (lines.first.edge == '↑')
                Positioned(left: 2, top: 0, child: Text('↑', style: theme.dim)),
              if (lines.last.edge == '↓')
                Positioned(
                  left: 2,
                  bottom: 0,
                  child: Text('↓', style: theme.dim),
                ),
            ],
          ),
        ),
      );
      if (hidden > 0) {
        rows.add(
          Text('    … +$hidden more', style: theme.dim, softWrap: false),
        );
      }
    }
    if (!_usesExact && listRows > 0) {
      // A changed row distribution can keep the same total and send no scroll
      // notification; reconcile its exact heights after every fallback layout.
      context.owner.afterLayout(_scrolled);
    }
    // Keys that act on visible rows follow the rows this layout gave.
    if (listRows != _rows) {
      _rows = listRows;
      context.owner.afterLayout(() {
        if (mounted) setState(() {});
      });
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _row(BuildContext context, int i, bool scrolls) {
    final item = _state.resultAt(i);
    return PickerRow(
      index: i,
      count: _state.results.length,
      label: item.label,
      highlighted: widget.enabled && _focused && i == _view.highlighted,
      edgeColumn: scrolls,
      showNumbers: widget.showNumbers,
      content: widget.itemBuilder?.call(
        context,
        item,
        _state.results[i].matchedPositions,
      ),
    );
  }
}
