import '../foundation/geometry.dart';
import '../foundation/picker_state.dart';
import '../rendering/basic.dart';
import '../rendering/fold.dart';
import '../rendering/flex.dart';
import '../terminal/style.dart';
import '../text/layout.dart';
import 'basic.dart';
import 'focus.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'layout_builder.dart';
import 'picker_row.dart';
import 'theme.dart';

/// A framed question, as chord's dialogs: a title, a body, numbered
/// [choices] and a hint, in a rounded frame that takes the focus colour
/// while it holds focus.
///
/// Where rows run short the body gives way first, folding under
/// `… N more lines`, then the hint; the title and the choices stay. Up and
/// down (or k and j) go round the choices; Enter or a number chooses; Esc
/// calls [onCanceled]. With no choices it is a notice that Esc closes.
class Dialog<T> extends StatefulWidget {
  /// A dialog titled [title] over [child].
  const Dialog({
    super.key,
    required this.title,
    required this.child,
    this.choices = const [],
    this.onSelected,
    required this.onCanceled,
    this.hint,
  });

  /// The title, one row, bold in the focus colour.
  final Widget title;

  /// The body.
  final Widget child;

  /// The choices; their values must be unique.
  final List<PickerItem<T>> choices;

  /// Called with the value chosen.
  final void Function(T value)? onSelected;

  /// Called when Esc closes the dialog.
  final void Function() onCanceled;

  /// Replaces the hint's words, not its keys.
  final Widget? hint;

  @override
  State<Dialog<T>> createState() => _DialogState<T>();
}

class _DialogState<T> extends State<Dialog<T>> {
  final _node = FocusNode(debugLabel: 'dialog');
  late final FocusManager _focus = context.owner.focusManager;
  late PickerState<T> _state = PickerState.initial(widget.choices);
  var _visible = 0;
  var _active = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted && _node.hasFocus != _active) {
      setState(() => _active = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _node.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(Dialog<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.choices, widget.choices)) {
      _state = _state
          .withItems(widget.choices, const FzfPickerFilter())
          .within(_visible);
    }
  }

  // Round the choices that have rows, as the original's ChoiceList.
  void _move(int step) =>
      setState(() => _state = _state.moved(step, wrap: true, limit: _visible));

  void _choose(int index) =>
      widget.onSelected?.call(widget.choices[index].value);

  @override
  Widget build(BuildContext context) {
    final acts = _visible > 0;
    return Actions(
      bindings: [
        Binding('up', 'Previous choice', () => _move(-1), enabled: acts),
        Binding('k', 'Previous choice', () => _move(-1), enabled: acts),
        Binding('down', 'Next choice', () => _move(1), enabled: acts),
        Binding('j', 'Next choice', () => _move(1), enabled: acts),
        Binding(
          'enter',
          'Choose highlighted item',
          () => _choose(_state.highlighted),
          enabled: acts,
        ),
        for (var n = 1; n <= 9; n++)
          Binding(
            '$n',
            'Choose item $n',
            () => _choose(n - 1),
            enabled: n <= _visible,
          ),
        Binding('esc', 'Close dialog', widget.onCanceled),
      ],
      child: Focus(
        focusNode: _node,
        autofocus: true,
        child: LayoutBuilder(builder: _layout),
      ),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final bounded = constraints.hasBoundedHeight;
    // Inside the frame's top and bottom.
    final rows = bounded ? constraints.maxHeight - 2 : unbounded;
    final count = widget.choices.length;
    var left = rows - 1;
    final choiceRows = left <= 0 ? 0 : (count < left ? count : left);
    left -= choiceRows;
    final hintRows = left >= 2 ? 2 : 0;
    left -= hintRows;
    final gap = count > 0 && left >= 2 ? 1 : 0;
    final bodyRows = count > 0 ? (gap == 0 ? 0 : left - 1) : left;
    if (choiceRows != _visible) {
      _visible = choiceRows;
      _state = _state.within(choiceRows);
      context.owner.afterLayout(() {
        if (mounted) setState(() {});
      });
    }
    if (rows <= 0) return const SizedBox();
    final hint =
        widget.hint ??
        Text(
          [
            if (choiceRows > 0) ...[
              '↑↓ or j/k to move',
              'Enter or 1–9 to select',
            ],
            'Esc to close',
          ].join(' · '),
          style: theme.dim,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        );
    final box = Box(
      border: Border.rounded.withStyle(_active ? theme.focus : theme.border),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 1,
            child: DefaultTextStyle(
              style: DefaultTextStyle.of(
                context,
              ).merge(theme.focus.merge(Style.bold)),
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              child: widget.title,
            ),
          ),
          if (bodyRows > 0)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: bodyRows),
              child: _Body(child: widget.child, countStyle: theme.dim),
            ),
          if (gap > 0) Text(''),
          for (var i = 0; i < choiceRows; i++)
            PickerRow(
              index: i,
              count: count,
              label: widget.choices[i].label,
              highlighted: _active && i == _state.highlighted,
            ),
          if (hintRows > 0) ...[Text(''), SizedBox(height: 1, child: hint)],
        ],
      ),
    );
    return constraints.hasBoundedWidth
        ? SizedBox(width: constraints.maxWidth, child: box)
        : box;
  }
}

/// A dialog's body: folded under `… N more lines` where it has too few
/// rows, with no header.
class _Body extends SingleChildRenderObjectWidget {
  const _Body({required Widget super.child, required this.countStyle});

  final Style countStyle;

  @override
  RenderFold createRenderObject(BuildContext context) => RenderFold(
    title: null,
    open: true,
    markerStyle: countStyle,
    titleStyle: countStyle,
    countStyle: countStyle,
  );

  @override
  void updateRenderObject(BuildContext context, RenderFold r) =>
      r.countStyle = countStyle;
}
