import 'package:characters/characters.dart';

import '../foundation/geometry.dart';
import '../foundation/text_editing.dart';
import '../input/keys.dart';
import '../terminal/style.dart';
import '../terminal/cursor.dart';
import '../text/layout.dart';
import '../text/span.dart';
import '../text/text_area_span.dart';
import 'basic.dart';
import 'focus.dart';
import 'editor_cursor.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'layout_builder.dart';
import 'theme.dart';
import 'selection.dart';

/// A multiline editor: text wrapped by cells, growing from one row to
/// [maxHeight] and then scrolling to keep the cursor in view.
///
/// Enter submits, unless a backslash before the cursor asks for a line
/// break instead; shift, alt or ctrl with enter, and ctrl+j, add one. The
/// rest of [editingKeys] are OpenTUI's textarea defaults, a keyboard
/// selection among them, drawn on the theme's selection. Its edits are
/// bound through [Actions], so the shortcuts panel lists them.
/// Draws no prefix, border or gutter: those go around it.
class TextArea extends StatefulWidget {
  /// An editor of [controller]'s text, or of its own.
  const TextArea({
    super.key,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.maxHeight = 10,
    this.placeholder,
    this.onSubmit,
    this.onChanged,
    this.onLayoutChanged,
    this.onKey,
    this.shouldHandleKey,
    this.onEdge,
    this.unhandledKeys = const {'home', 'end'},
    this.style,
    this.textSpanBuilder,
    this.cursorStyle = CursorStyle.steadyBlock,
    this.showCursor = true,
    this.placeholderStyle,
    this.placeholderGap = true,
    this.selectionStyle,
  }) : assert(maxHeight > 0);

  /// Every key the area binds, as [KeyCombo.parse] spells it, with the
  /// description key help shows for it.
  static const Map<String, String> editingKeys = {
    'enter': 'Submit',
    'shift+enter': 'Insert newline',
    'alt+enter': 'Insert newline',
    'ctrl+enter': 'Insert newline',
    'ctrl+j': 'Insert newline',
    'left': 'Move cursor left',
    'ctrl+b': 'Move cursor left',
    'right': 'Move cursor right',
    'ctrl+f': 'Move cursor right',
    'up': 'Move cursor up',
    'down': 'Move cursor down',
    'alt+b': 'Move cursor back a word',
    'alt+left': 'Move cursor back a word',
    'ctrl+left': 'Move cursor back a word',
    'alt+f': 'Move cursor forward a word',
    'alt+right': 'Move cursor forward a word',
    'ctrl+right': 'Move cursor forward a word',
    'backspace': 'Delete character before cursor',
    'shift+backspace': 'Delete character before cursor',
    'delete': 'Delete character after cursor',
    'ctrl+d': 'Delete character after cursor',
    'shift+delete': 'Delete character after cursor',
    'ctrl+w': 'Delete word before cursor',
    'alt+backspace': 'Delete word before cursor',
    'ctrl+backspace': 'Delete word before cursor',
    'alt+d': 'Delete word after cursor',
    'alt+delete': 'Delete word after cursor',
    'ctrl+delete': 'Delete word after cursor',
    'ctrl+u': 'Delete to line start',
    'ctrl+k': 'Delete to line end',
    'ctrl+shift+d': 'Delete line',
    'ctrl+a': 'Move to line start',
    'ctrl+e': 'Move to line end',
    'super+left': 'Move to row start',
    'alt+a': 'Move to row start',
    'super+right': 'Move to row end',
    'alt+e': 'Move to row end',
    'home': 'Move to text start',
    'super+up': 'Move to text start',
    'end': 'Move to text end',
    'super+down': 'Move to text end',
    'ctrl+z': 'Undo',
    'ctrl+-': 'Undo',
    'super+z': 'Undo',
    'ctrl+y': 'Redo',
    'ctrl+.': 'Redo',
    'shift+super+z': 'Redo',
    'shift+left': 'Select left',
    'shift+right': 'Select right',
    'shift+up': 'Select up',
    'shift+down': 'Select down',
    'alt+shift+left': 'Select back a word',
    'alt+shift+b': 'Select back a word',
    'alt+shift+right': 'Select forward a word',
    'alt+shift+f': 'Select forward a word',
    'ctrl+shift+a': 'Select to line start',
    'ctrl+shift+e': 'Select to line end',
    'alt+shift+a': 'Select to row start',
    'shift+super+left': 'Select to row start',
    'alt+shift+e': 'Select to row end',
    'shift+super+right': 'Select to row end',
    'shift+home': 'Select to text start',
    'shift+super+up': 'Select to text start',
    'shift+end': 'Select to text end',
    'shift+super+down': 'Select to text end',
    'super+a': 'Select all',
  };

  /// The text and cursor; the area makes and owns one if null. One
  /// controller serves one area at a time.
  final TextAreaController? controller;

  /// The area's focus; it makes and owns one if null.
  final FocusNode? focusNode;

  /// Whether it takes focus when it first shows.
  final bool autofocus;

  /// The most rows it grows to before it scrolls; positive.
  final int maxHeight;

  /// Shown, dim, while there is no text.
  final String? placeholder;

  /// Called with the text when Enter submits it; the text stays.
  final void Function(String text)? onSubmit;

  /// Called with the text after each edit that changes it.
  final void Function(String text)? onChanged;

  /// Reports the settled viewport after layout, initially and when its
  /// public values change, so a sibling can draw matching row furniture.
  final void Function(TextAreaLayout layout)? onLayoutChanged;

  /// Sees each key before the area does, but those in [unhandledKeys]:
  /// true takes the key, false lets the area handle it. Where a popup or
  /// history walking takes Tab, Enter, Escape or arrows.
  final bool Function(KeyEvent event)? onKey;

  /// Read for each incoming key before text insertion; false delegates to
  /// Actions. Unlike a rebuilt key set, this can read the live controller.
  final bool Function(KeyEvent event)? shouldHandleKey;

  /// Called when up is pressed on the first row or down on the last, the
  /// key then taken; without it those keys go on to the widgets above.
  final void Function(TextAreaDirection direction)? onEdge;

  /// Keys, as [KeyCombo] parses them, that the area leaves alone: they go
  /// past [onKey] and its edits to the widgets above, unchanged.
  final Set<String> unhandledKeys;

  /// The text; the theme's text if null.
  final Style? style;

  /// Pure full-text style projection, without changing editing or layout.
  ///
  /// Receives the exact normalized controller text on each content build.
  /// The returned span must contain that exact text; a mismatch rejects with
  /// [ArgumentError] through normal build-error handling, including in AOT.
  /// A visible placeholder bypasses this callback. Styles use each raw
  /// grapheme's first UTF16 unit and the existing per-row text sanitation.
  /// Captured style changes require a normal rebuild. Stale decoration falls
  /// back to current plain rows until the normal next build, without retries.
  /// The callback must not edit, notify, move focus, perform IO or lay out a
  /// controller. Invalid projections replace the editor's normal subtree.
  final TextSpan Function(BuildContext context, String text)? textSpanBuilder;

  /// The terminal's cursor shape and blink policy.
  final CursorStyle cursorStyle;

  /// Whether the terminal's cursor is shown while focused; false hides it,
  /// as while a chord waits for its next key, and keeps the focus.
  final bool showCursor;

  /// The placeholder; the theme's dim if null.
  final Style? placeholderStyle;

  /// Whether a focused, empty area draws a blank cell for the cursor before
  /// its placeholder; false puts the cursor on the placeholder's first cell.
  final bool placeholderGap;

  /// Selected text; the theme's selection if null.
  final Style? selectionStyle;

  @override
  State<TextArea> createState() => _TextAreaState();
}

/// The area each controller is attached to: one at a time.
final _areas = Expando<_TextAreaState>('text area');
final _attachments = Expando<Set<_TextAreaState>>('text area attachments');

class _TextAreaState extends State<TextArea> {
  TextAreaController? _ownController;
  FocusNode? _ownNode;
  Set<KeyCombo> _unhandled = const {};
  String _lastText = '';
  int _spanBuild = 0;
  TextAreaLayout? _publishedLayout;

  /// The width and height the area was last laid out to.
  (int, int)? _geometry;

  TextAreaController get _c =>
      widget.controller ?? (_ownController ??= TextAreaController());
  FocusNode get _node =>
      widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'TextArea'));

  void _attach(TextAreaController c) {
    final attached = _attachments[c] ??= <_TextAreaState>{};
    attached.add(this);
    // Sibling reconciliation can mount the replacement before disposing
    // the old state. Only the newest attachment listens to edits.
    _areas[c]?._release(c);
    _areas[c] = this;
    c.addListener(_changed);
    context.owner.afterLayout(() {
      if (attached.length > 1) {
        throw StateError('A TextAreaController is attached to two TextAreas.');
      }
    });
  }

  void _release(TextAreaController c) => c.removeListener(_changed);

  void _detach(TextAreaController c) {
    _attachments[c]?.remove(this);
    if (_areas[c] != this) return;
    _release(c);
    _areas[c] = null;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final text = _c.text;
    if (text != _lastText) {
      _lastText = text;
      widget.onChanged?.call(text);
    }
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _parseUnhandled() {
    _unhandled = {
      for (final keys in widget.unhandledKeys) KeyCombo.parse(keys),
    };
  }

  @override
  void initState() {
    super.initState();
    _parseUnhandled();
    _attach(_c);
    _lastText = _c.text;
    _node.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(TextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.onLayoutChanged != widget.onLayoutChanged) {
      _publishedLayout = null;
    }
    if (oldWidget.controller != widget.controller) {
      final old = oldWidget.controller ?? _ownController;
      if (old != null) _detach(old);
      if (oldWidget.controller == null) {
        _ownController?.dispose();
        _ownController = null;
      }
      _attach(_c);
      _lastText = _c.text;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownNode)?.removeListener(_focusChanged);
      if (oldWidget.focusNode == null) {
        _ownNode?.dispose();
        _ownNode = null;
      }
      _node.addListener(_focusChanged);
    }
    if (oldWidget.unhandledKeys != widget.unhandledKeys) _parseUnhandled();
  }

  @override
  void dispose() {
    _detach(_c);
    _node.removeListener(_focusChanged);
    _ownController?.dispose();
    _ownNode?.dispose();
    super.dispose();
  }

  /// The layout as the area shows it now: at the last width and height,
  /// for the text as it is. Null before the first layout.
  TextAreaLayout? _current() {
    final g = _geometry;
    return g == null ? null : _c.layout(width: g.$1, maxHeight: g.$2);
  }

  /// Moves the cursor a row; at the edge, tells [TextArea.onEdge].
  void _vertical(TextAreaDirection direction) {
    final layout = _current();
    if (layout == null || layout.height == 0) return;
    final moved = direction == TextAreaDirection.up
        ? _c.moveUp(layout)
        : _c.moveDown(layout);
    if (!moved) widget.onEdge?.call(direction);
  }

  /// Moves the cursor in the row it is drawn on; before the first layout,
  /// with no row shown to move in, in its logical line.
  void _row(void Function(TextAreaLayout? layout) move) {
    final layout = _current();
    move(layout == null || layout.height == 0 ? null : layout);
  }

  void _submit() {
    if (!_c.continueLine()) widget.onSubmit?.call(_c.text);
  }

  /// Selects a row up or down; it does not tell [TextArea.onEdge].
  void _selectRow(TextAreaDirection direction) {
    final layout = _current();
    if (layout == null || layout.height == 0) return;
    direction == TextAreaDirection.up
        ? _c.moveUp(layout, select: true)
        : _c.moveDown(layout, select: true);
  }

  List<Binding> _bindings() {
    final c = _c;
    final layout = _current();
    // Up and down act while there is a row to go to, or someone to tell
    // there is none; otherwise they go on, as do keys without room.
    final shown = layout != null && layout.height > 0;
    final edge = widget.onEdge != null;
    final above = shown && layout.cursorRow > 0;
    final below = shown && layout.cursorRow < layout.rows.length - 1;
    void up() => _vertical(TextAreaDirection.up);
    void down() => _vertical(TextAreaDirection.down);
    void selectUp() => _selectRow(TextAreaDirection.up);
    void selectDown() => _selectRow(TextAreaDirection.down);
    void rowStart() => _row(c.moveToRowStart);
    void rowEnd() => _row(c.moveToRowEnd);
    void selectRowStart() => _row((l) => c.moveToRowStart(l, select: true));
    void selectRowEnd() => _row((l) => c.moveToRowEnd(l, select: true));
    final actions = <String, (void Function(), bool)>{
      'enter': (_submit, true),
      'shift+enter': (c.newline, true),
      'alt+enter': (c.newline, true),
      'ctrl+enter': (c.newline, true),
      'ctrl+j': (c.newline, true),
      'left': (c.moveLeft, true),
      'ctrl+b': (c.moveLeft, true),
      'right': (c.moveRight, true),
      'ctrl+f': (c.moveRight, true),
      'up': (up, edge ? shown : above),
      'down': (down, edge ? shown : below),
      'alt+b': (c.moveWordLeft, true),
      'alt+left': (c.moveWordLeft, true),
      'ctrl+left': (c.moveWordLeft, true),
      'alt+f': (c.moveWordRight, true),
      'alt+right': (c.moveWordRight, true),
      'ctrl+right': (c.moveWordRight, true),
      'backspace': (c.backspace, true),
      'shift+backspace': (c.backspace, true),
      'delete': (c.delete, true),
      'ctrl+d': (c.delete, true),
      'shift+delete': (c.delete, true),
      'ctrl+w': (c.deleteWordBefore, true),
      'alt+backspace': (c.deleteWordBefore, true),
      'ctrl+backspace': (c.deleteWordBefore, true),
      'alt+d': (c.deleteWordAfter, true),
      'alt+delete': (c.deleteWordAfter, true),
      'ctrl+delete': (c.deleteWordAfter, true),
      'ctrl+u': (c.deleteToLineStart, true),
      'ctrl+k': (c.deleteToLineEnd, true),
      'ctrl+shift+d': (c.deleteLine, true),
      'ctrl+a': (c.moveToLineStart, true),
      'ctrl+e': (c.moveToLineEnd, true),
      'super+left': (rowStart, true),
      'alt+a': (rowStart, true),
      'super+right': (rowEnd, true),
      'alt+e': (rowEnd, true),
      'home': (c.moveToStart, true),
      'super+up': (c.moveToStart, true),
      'end': (c.moveToEnd, true),
      'super+down': (c.moveToEnd, true),
      'ctrl+z': (c.undo, true),
      'ctrl+-': (c.undo, true),
      'super+z': (c.undo, true),
      'ctrl+y': (c.redo, true),
      'ctrl+.': (c.redo, true),
      'shift+super+z': (c.redo, true),
      'shift+left': (() => c.moveLeft(select: true), true),
      'shift+right': (() => c.moveRight(select: true), true),
      'shift+up': (selectUp, above),
      'shift+down': (selectDown, below),
      'alt+shift+left': (() => c.moveWordLeft(select: true), true),
      'alt+shift+b': (() => c.moveWordLeft(select: true), true),
      'alt+shift+right': (() => c.moveWordRight(select: true), true),
      'alt+shift+f': (() => c.moveWordRight(select: true), true),
      'ctrl+shift+a': (() => c.moveToLineStart(select: true), true),
      'ctrl+shift+e': (() => c.moveToLineEnd(select: true), true),
      'alt+shift+a': (selectRowStart, true),
      'shift+super+left': (selectRowStart, true),
      'alt+shift+e': (selectRowEnd, true),
      'shift+super+right': (selectRowEnd, true),
      'shift+home': (() => c.moveToStart(select: true), true),
      'shift+super+up': (() => c.moveToStart(select: true), true),
      'shift+end': (() => c.moveToEnd(select: true), true),
      'shift+super+down': (() => c.moveToEnd(select: true), true),
      'super+a': (c.selectAll, true),
    };
    return [
      for (final MapEntry(key: keys, value: description)
          in TextArea.editingKeys.entries)
        if (!_unhandled.contains(KeyCombo.parse(keys)))
          Binding(
            keys,
            description,
            actions[keys]!.$1,
            enabled: actions[keys]!.$2,
          ),
    ];
  }

  bool _onKey(KeyEvent event) {
    if (widget.shouldHandleKey?.call(event) == false) return false;
    if (_unhandled.contains(event.combo)) return false;
    if (widget.onKey?.call(event) ?? false) return true;
    final char = event.char;
    if (char == null) return false;
    _c.insert(char);
    return true;
  }

  bool _onPaste(String text) {
    _c.insert(text);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final focused = _node.hasPrimaryFocus;
    final theme = Theme.of(context);
    final placeholder = widget.placeholderStyle ?? theme.dim;
    final generation = ++_spanBuild;
    final configured = widget;
    final controller = _c;
    final builder = widget.textSpanBuilder;
    final text = builder == null ? '' : controller.text;
    final decorate =
        builder != null && !(text.isEmpty && widget.placeholder != null);
    final base = decorate
        ? DefaultTextStyle.of(context).merge(widget.style)
        : null;
    // Validate before creating editor handlers: an ordinary build failure
    // must not leave a hidden editor under an inner error widget.
    final spans = decorate
        ? TextAreaSpanStyles(text, builder(context, text), base: base!)
        : null;
    // A reading on another layout never edits: its keys go to the app.
    return Actions(
      bindings: _bindings(),
      ignoreLayoutReadings: true,
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        ignoreLayoutReadings: true,
        onKey: _onKey,
        onPaste: _onPaste,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= unbounded) {
              throw StateError('A TextArea needs a bounded width.');
            }
            final width = constraints.maxWidth;
            final room = constraints.maxHeight;
            final height = room < widget.maxHeight ? room : widget.maxHeight;
            _geometry = (width, height);
            final c = _c;
            final layout = c.layout(width: width, maxHeight: height);
            final callback = widget.onLayoutChanged;
            context.owner.afterLayout(() {
              if (!mounted || c != _c || callback != widget.onLayoutChanged) {
                return;
              }
              c.notifyAfterLayout();
              if (!mounted || c != _c || callback != widget.onLayoutChanged) {
                return;
              }
              if (callback != null && !_sameLayout(_publishedLayout, layout)) {
                _publishedLayout = layout;
                callback(layout);
              }
            });
            final empty = c.length == 0 && widget.placeholder != null;
            final selection = c.selection;
            final selected = widget.selectionStyle ?? theme.selection;
            final currentSpans =
                spans != null &&
                    identical(c, controller) &&
                    c.text == text &&
                    identical(widget, configured) &&
                    widget.textSpanBuilder == builder &&
                    _spanBuild == generation &&
                    Theme.of(context) == theme &&
                    DefaultTextStyle.of(context).merge(widget.style) == base
                ? spans
                : null;
            return SelectionEditor(
              controller: c,
              layout: layout,
              child: EditorCursor(
                enabled: focused && widget.showCursor,
                style: widget.cursorStyle,
                position: Offset(
                  layout.cursorColumn,
                  layout.cursorRow - layout.rowOffset,
                ),
                child: SizedBox(
                  width: width,
                  height: layout.height,
                  child: Column(
                    children: [
                      for (final row in layout.shownRows)
                        Text.rich(
                          empty
                              ? TextSpan(
                                  '',
                                  children: [
                                    if (focused && widget.placeholderGap)
                                      const TextSpan(' '),
                                    TextSpan(
                                      widget.placeholder!,
                                      style: placeholder,
                                    ),
                                  ],
                                )
                              : currentSpans?.rowSpan(
                                      row,
                                      selection: selection,
                                      selectionStyle: selected,
                                    ) ??
                                    _plainRow(row, selection, selected),
                          style: widget.style,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// [row]'s text, its graphemes inside [selection] in [style].
TextSpan _plainRow(TextAreaRow row, TextSelection selection, Style style) {
  final from = selection.start.clamp(row.start, row.end) - row.start;
  final to = selection.end.clamp(row.start, row.end) - row.start;
  if (from == to) return TextSpan(row.text);
  final graphemes = row.text.characters;
  return TextSpan(
    '',
    children: [
      TextSpan(graphemes.take(from).join()),
      TextSpan(graphemes.skip(from).take(to - from).join(), style: style),
      TextSpan(graphemes.skip(to).join()),
    ],
  );
}

bool _sameLayout(TextAreaLayout? a, TextAreaLayout b) {
  if (a == null ||
      a.width != b.width ||
      a.height != b.height ||
      a.rowOffset != b.rowOffset ||
      a.cursorRow != b.cursorRow ||
      a.cursorColumn != b.cursorColumn ||
      a.rows.length != b.rows.length) {
    return false;
  }
  for (var i = 0; i < a.rows.length; i++) {
    final x = a.rows[i];
    final y = b.rows[i];
    if (x.text != y.text ||
        x.line != y.line ||
        x.piece != y.piece ||
        x.last != y.last ||
        x.start != y.start ||
        x.end != y.end) {
      return false;
    }
  }
  return true;
}
