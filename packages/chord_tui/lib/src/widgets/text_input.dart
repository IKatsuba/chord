import 'package:characters/characters.dart';

import '../foundation/text_editing.dart';
import '../input/keys.dart';
import '../terminal/style.dart';
import '../terminal/cursor.dart';
import '../text/width.dart';
import '../text/span.dart';
import 'basic.dart';
import 'focus.dart';
import 'editor_cursor.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'theme.dart';

/// An editable text field. Enter submits; alt+enter adds a line.
class TextInput extends StatefulWidget {
  /// A field editing [controller]'s text, or its own when null.
  const TextInput({
    super.key,
    this.controller,
    this.focusNode,
    this.onSubmit,
    this.onChanged,
    this.placeholder,
    this.prefix,
    this.style,
    this.cursorStyle = CursorStyle.steadyBlock,
    this.showCursor = true,
    this.placeholderStyle,
    this.prefixStyle,
    this.autofocus = false,
  });

  /// Holds the text and cursor; one of its own when null.
  final TextEditingController? controller;

  /// The node it focuses with; one of its own when null.
  final FocusNode? focusNode;

  /// Called with the text when Enter is pressed.
  final void Function(String text)? onSubmit;

  /// Called with the text after each edit.
  final void Function(String text)? onChanged;

  /// Shown while the text is empty.
  final String? placeholder;

  /// Shown before the text.
  final String? prefix;

  /// The text's style over the default text style.
  final Style? style;

  /// The terminal's cursor shape and blink policy.
  final CursorStyle cursorStyle;

  /// Whether the terminal's cursor is shown while focused; false hides it,
  /// as while a chord waits for its next key, and keeps the focus.
  final bool showCursor;

  /// The placeholder; the theme's dim if null.
  final Style? placeholderStyle;

  /// The prefix; the theme's dim if null.
  final Style? prefixStyle;

  /// Whether it asks for focus when first built.
  final bool autofocus;

  @override
  State<TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<TextInput> {
  TextEditingController? _ownController;
  final FocusNode _ownNode = FocusNode(debugLabel: 'TextInput');

  TextEditingController get _c =>
      widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _node => widget.focusNode ?? _ownNode;

  String _lastText = '';

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final t = _c.text;
    if (t != _lastText) {
      _lastText = t;
      widget.onChanged?.call(t);
    }
  }

  @override
  void initState() {
    super.initState();
    _lastText = _c.text;
    _c.addListener(_changed);
    _node.addListener(_changed);
  }

  @override
  void didUpdateWidget(TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownController)?.removeListener(_changed);
      _c.addListener(_changed);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownNode).removeListener(_changed);
      _node.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _node.removeListener(_changed);
    _ownController?.dispose();
    _ownNode.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    final c = _c;
    switch (e.combo.toString()) {
      case 'enter':
        widget.onSubmit?.call(c.text);
      case 'alt+enter' || 'shift+enter':
        c.insert('\n');
      case 'backspace' || 'shift+backspace':
        c.backspace();
      case 'delete' || 'ctrl+d':
        c.delete();
      case 'left' || 'ctrl+b':
        c.cursor--;
      case 'right' || 'ctrl+f':
        c.cursor++;
      case 'home' || 'ctrl+a':
        c.cursor = 0;
      case 'end' || 'ctrl+e':
        c.cursor = c.length;
      case 'ctrl+w' || 'alt+backspace':
        c.deleteWordBefore();
      case 'ctrl+u':
        c.deleteToStart();
      case 'ctrl+k':
        c.deleteToEnd();
      default:
        final ch = e.char;
        if (ch == null) return false;
        c.insert(ch);
    }
    return true;
  }

  bool _onPaste(String text) {
    _c.insert(text);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final focused = _node.hasPrimaryFocus;
    final after = c.afterCursor.characters;
    final atNewline = after.isNotEmpty && after.first == '\n';
    final under = after.isEmpty || atNewline ? ' ' : after.first;
    final rest = after.isEmpty
        ? ''
        : (atNewline ? after.string : after.skip(1).string);
    final empty = c.length == 0 && widget.placeholder != null;
    final theme = Theme.of(context);
    final placeholder = widget.placeholderStyle ?? theme.dim;

    final spans = <TextSpan>[
      if (widget.prefix != null)
        TextSpan(widget.prefix!, style: widget.prefixStyle ?? theme.dim),
      if (empty) ...[
        if (focused) const TextSpan(' '),
        TextSpan(widget.placeholder!, style: placeholder),
      ] else ...[
        TextSpan(c.beforeCursor),
        if (focused) TextSpan(under) else if (!atNewline) TextSpan(under),
        TextSpan(rest),
      ],
    ];
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      // A reading on another layout never edits: its keys go to the app.
      ignoreLayoutReadings: true,
      onKey: _onKey,
      onPaste: _onPaste,
      child: EditorCursor(
        enabled: focused && widget.showCursor,
        style: widget.cursorStyle,
        sourceOffset:
            stripAnsi(widget.prefix ?? '').characters.length +
            stripAnsi(c.beforeCursor).characters.length,
        child: Text.rich(TextSpan('', children: spans), style: widget.style),
      ),
    );
  }
}
