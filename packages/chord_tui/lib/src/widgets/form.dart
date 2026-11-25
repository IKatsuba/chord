import 'package:characters/characters.dart';

import '../foundation/form.dart';
import '../foundation/geometry.dart';
import '../input/keys.dart';
import '../rendering/flex.dart';
import '../terminal/style.dart';
import '../text/span.dart';
import '../text/width.dart';
import 'basic.dart';
import 'focus.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'layout_builder.dart';
import 'theme.dart';
import 'theme_data.dart';

export '../foundation/form.dart';

/// A form: a column of fields with their labels lined up, a status mark, a
/// note under a field, then the buttons and a hint naming the keys. The
/// fields are [controller]'s; the keys move between them, edit the focused
/// one and submit.
///
/// A submit with problems is refused: every problem shows, the focus goes
/// to the first field with one, and the buttons count them.
class Form extends StatefulWidget {
  /// A form of [controller]'s fields.
  const Form({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onCanceled,
    this.onDeclined,
    this.submitLabel = 'Submit',
    this.declineLabel = 'Decline',
    this.maxRows,
    this.autofocus = true,
    this.focusNode,
    this.enabled = true,
    this.showHint = true,
    this.onLeave,
  });

  /// The form's state, kept by the app.
  final FormController controller;

  /// Called with the values when a submit finds nothing wrong.
  final void Function(Map<String, Object> values) onSubmitted;

  /// Called when Esc leaves the form.
  final void Function() onCanceled;

  /// Called by the decline button; without it there is no second button.
  final void Function()? onDeclined;

  /// The submit button's words.
  final String submitLabel;

  /// The decline button's words.
  final String declineLabel;

  /// The most rows the fields take; they scroll by whole fields past it.
  final int? maxRows;

  /// Whether the form takes focus when it is built.
  final bool autofocus;

  /// The form's focus node; made and owned by the form when absent.
  final FocusNode? focusNode;

  /// Whether the keys are the form's; false draws no `❯`, no highlight and
  /// no hint, keeping all state.
  final bool enabled;

  /// Whether the hint line is drawn.
  final bool showHint;

  /// Called by ↓ on the buttons, for an app with something below.
  final void Function()? onLeave;

  @override
  State<Form> createState() => _FormState();
}

class _FormState extends State<Form> {
  FocusNode? _ownNode;
  FocusNode get _node =>
      widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'form'));

  FormData get _data => widget.controller.value;

  void _changed() {
    if (mounted) setState(() {});
  }

  void _configure() {
    _node
      ..canRequestFocus = widget.enabled
      ..descendantsAreFocusable = widget.enabled;
    if (!widget.enabled) _node.unfocus();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _configure();
  }

  @override
  void didUpdateWidget(Form oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    _configure();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _ownNode?.dispose();
    super.dispose();
  }

  void _do(FormData Function(FormData data) action) =>
      widget.controller.value = action(_data);

  void _submit() {
    final (:form, :values) = _data.submit();
    widget.controller.value = form;
    if (values != null) widget.onSubmitted(values);
  }

  bool get _typing =>
      !_data.listOpen &&
      (_data.focused is TextFormItem || _data.focused is NumberFormItem);

  bool _onKey(KeyEvent event) {
    if (!widget.enabled || !_typing) return false;
    final char = event.char;
    if (char == null) return false;
    _do((data) => data.type(char));
    return true;
  }

  bool _onPaste(String text) {
    if (!widget.enabled || !_typing) return false;
    _do((data) => data.type(text));
    return true;
  }

  Binding _bind(
    String keys,
    String id,
    String description,
    void Function() action,
  ) => Binding(keys, description, action, id: 'form.$id');

  Binding _edit(
    String keys,
    String id,
    String description,
    FormData Function(FormData data) action,
  ) => _bind(keys, id, description, () => _do(action));

  List<Binding> _bindings() {
    final data = _data;
    final field = data.focused;
    final cancel = _bind('esc', 'cancel', 'Cancel', widget.onCanceled);
    if (data.listOpen) {
      return [
        _edit(
          'up',
          'previousOption',
          'Previous option',
          (d) => d.previousOption(),
        ),
        _edit(
          'k',
          'previousOption',
          'Previous option',
          (d) => d.previousOption(),
        ),
        _edit('down', 'nextOption', 'Next option', (d) => d.nextOption()),
        _edit('j', 'nextOption', 'Next option', (d) => d.nextOption()),
        _edit('left', 'closeList', 'Close the list', (d) => d.closeList()),
        _edit('esc', 'closeList', 'Close the list', (d) => d.closeList()),
        if (field is ChoiceFormItem) ...[
          for (var n = 1; n <= 9 && n <= field.options.length; n++)
            _edit('$n', 'pick$n', 'Pick option $n', (d) => d.pick(n)),
          _edit('enter', 'pick', 'Pick', (d) => d.pick()),
        ] else ...[
          _edit('space', 'tick', 'Tick', (d) => d.tick()),
          _edit('enter', 'closeList', 'Close the list', (d) => d.closeList()),
        ],
      ];
    }
    final moves = [
      _edit('up', 'previous', 'Previous field', (d) => d.previous()),
      _edit('shift+tab', 'previous', 'Previous field', (d) => d.previous()),
      if (field == null)
        _bind('down', 'leave', 'Leave the form', () => widget.onLeave?.call())
      else
        _edit('down', 'next', 'Next field', (d) => d.next()),
      _edit('tab', 'next', 'Next field', (d) => d.next()),
      cancel,
    ];
    if (field == null) {
      return [
        ...moves,
        if (widget.onDeclined != null) ...[
          _edit('left', 'toSubmit', 'Switch button', (d) => d.toSubmit()),
          _edit('right', 'toDecline', 'Switch button', (d) => d.toDecline()),
        ],
        data.focus == FormFocus.decline && widget.onDeclined != null
            ? _bind('enter', 'decline', 'Decline', widget.onDeclined!)
            : _bind('enter', 'submit', 'Submit', _submit),
      ];
    }
    return [
      ...moves,
      _edit('enter', 'next', 'Next field', (d) => d.next()),
      ...switch (field) {
        TextFormItem() || NumberFormItem() => [
          _edit('left', 'cursorLeft', 'Cursor left', (d) => d.cursorLeft()),
          _edit('right', 'cursorRight', 'Cursor right', (d) => d.cursorRight()),
          _edit('home', 'cursorHome', 'Cursor to start', (d) => d.cursorHome()),
          _edit(
            'ctrl+a',
            'cursorHome',
            'Cursor to start',
            (d) => d.cursorHome(),
          ),
          _edit('end', 'cursorEnd', 'Cursor to end', (d) => d.cursorEnd()),
          _edit('ctrl+e', 'cursorEnd', 'Cursor to end', (d) => d.cursorEnd()),
          _edit(
            'backspace',
            'backspace',
            'Delete before',
            (d) => d.backspace(),
          ),
          _edit('delete', 'delete', 'Delete', (d) => d.delete()),
          _edit(
            'ctrl+u',
            'deleteToStart',
            'Delete to start',
            (d) => d.deleteToStart(),
          ),
          _edit(
            'ctrl+k',
            'deleteToEnd',
            'Delete to end',
            (d) => d.deleteToEnd(),
          ),
          _edit(
            'ctrl+w',
            'deleteWord',
            'Delete word',
            (d) => d.deleteWordBefore(),
          ),
        ],
        BoolFormItem() => [
          _edit('space', 'toggle', 'Toggle', (d) => d.toggle()),
          _edit('backspace', 'clear', 'Clear', (d) => d.clear()),
          _edit('delete', 'clear', 'Clear', (d) => d.clear()),
        ],
        ChoiceFormItem() || MultiChoiceFormItem() => [
          _edit('right', 'openList', 'Open the list', (d) => d.openList()),
          _edit('space', 'openList', 'Open the list', (d) => d.openList()),
          _edit('backspace', 'clear', 'Clear', (d) => d.clear()),
          _edit('delete', 'clear', 'Clear', (d) => d.clear()),
        ],
        UnsupportedFormItem() => const <Binding>[],
      },
    ];
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: widget.enabled ? _bindings() : const [],
    // A text field never hears a reading on another layout; a list does.
    ignoreLayoutReadings: _typing,
    child: Focus(
      focusNode: _node,
      autofocus: widget.autofocus && widget.enabled,
      canRequestFocus: widget.enabled,
      ignoreLayoutReadings: _typing,
      onKey: _onKey,
      onPaste: _onPaste,
      child: LayoutBuilder(builder: _layout),
    ),
  );

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final data = _data;
    final width = constraints.maxWidth;
    final on = widget.enabled;
    final labelWidth = [
      0,
      for (final field in data.fields) cellWidth(field.label),
    ].reduce((a, b) => a > b ? a : b).clamp(0, width ~/ 3);
    final valueAt = 4 + labelWidth + 2;
    final rows = data.rows(widget.maxRows);
    final fix = data.toFix;
    final focus = on ? data.focus : null;
    Widget gutter(bool marked) => SizedBox(
      width: 2,
      child: Text(marked ? '❯' : ' ', style: theme.focus, softWrap: false),
    );
    Widget cut(String text, {Style? style}) =>
        Text(text, style: style, softWrap: false, maxLines: 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          switch (row) {
            FormFieldRow() => _field(row, on, labelWidth, theme),
            FormNoteRow(:final text, :final error) => Padding(
              padding: EdgeInsets.only(left: valueAt),
              child: cut(text, style: error ? theme.error : theme.dim),
            ),
            FormOptionRow() => Padding(
              padding: EdgeInsets.only(left: valueAt),
              child: Row(
                children: [
                  gutter(on && row.highlighted),
                  Expanded(
                    child: cut(
                      row.number == null
                          ? '${row.ticked == true ? '☒' : '☐'} ${row.label}'
                          : '${row.number}. ${row.label}${row.current ? ' ✔' : ''}',
                      style: on && row.highlighted ? theme.focus : null,
                    ),
                  ),
                ],
              ),
            ),
            // At the options' label column, past their gutter.
            FormMoreOptionsRow(:final up, :final count) => Padding(
              padding: EdgeInsets.only(left: valueAt + 2),
              child: cut(
                '${up ? '↑' : '↓'} $count more option${count == 1 ? '' : 's'}',
                style: theme.dim,
              ),
            ),
            FormMoreRow(:final up, :final count) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: cut(
                '${up ? '↑' : '↓'} $count more field${count == 1 ? '' : 's'}',
                style: theme.dim,
              ),
            ),
          },
        if (rows.isNotEmpty) const SizedBox(height: 1),
        Row(
          children: [
            gutter(focus == FormFocus.submit),
            Text(
              widget.submitLabel,
              style: focus == FormFocus.submit
                  ? theme.success.merge(Style.bold)
                  : null,
              softWrap: false,
            ),
            if (widget.onDeclined != null) ...[
              const SizedBox(width: 1),
              gutter(focus == FormFocus.decline),
              Text(
                widget.declineLabel,
                style: focus == FormFocus.decline ? theme.error : null,
                softWrap: false,
              ),
            ],
            if (fix > 0)
              Expanded(
                child: cut(
                  '     $fix field${fix == 1 ? '' : 's'} to fix',
                  style: theme.error,
                ),
              ),
          ],
        ),
        if (on && widget.showHint) ...[
          const SizedBox(height: 1),
          cut(
            data.hint(
              width,
              submitLabel: widget.submitLabel,
              declineLabel: widget.onDeclined == null
                  ? null
                  : widget.declineLabel,
            ),
            style: theme.dim,
          ),
        ],
      ],
    );
  }

  Widget _field(FormFieldRow row, bool on, int labelWidth, ThemeData theme) {
    final focused = on && row.focused;
    final invalid = row.status == FormFieldStatus.invalid;
    final label = focused
        ? (invalid ? theme.error : theme.focus).merge(Style.bold)
        : null;
    final value = row.value;
    final cursor = on ? value.cursor : null;
    final Widget shown;
    if (cursor == null) {
      shown = Text(
        value.text,
        style: value.dim ? theme.dim : null,
        softWrap: false,
        maxLines: 1,
      );
    } else {
      final chars = value.text.characters;
      final at = chars.skip(cursor);
      shown = Text.rich(
        TextSpan(
          '',
          children: [
            TextSpan(chars.take(cursor).string),
            TextSpan(at.isEmpty ? ' ' : at.first, style: Style.inverse),
            TextSpan(at.isEmpty ? '' : at.skip(1).string),
          ],
        ),
        softWrap: false,
        maxLines: 1,
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 2,
          child: Text(focused ? '❯' : ' ', style: theme.focus, softWrap: false),
        ),
        SizedBox(
          width: 2,
          child: Text(
            switch (row.status) {
              FormFieldStatus.required => '*',
              FormFieldStatus.invalid => '⚠',
              FormFieldStatus.valid => '✔',
              FormFieldStatus.none => ' ',
            },
            style: row.status == FormFieldStatus.valid
                ? theme.dim
                : theme.error,
            softWrap: false,
          ),
        ),
        SizedBox(
          width: labelWidth + 2,
          child: Text(
            row.item.label,
            style: label,
            softWrap: false,
            maxLines: 1,
          ),
        ),
        Expanded(child: shown),
      ],
    );
  }
}
