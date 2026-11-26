import '../input/keys.dart';
import '../terminal/style.dart';
import '../text/span.dart';
import 'basic.dart';
import 'focus.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'listener.dart';
import 'press_bounds.dart';
import 'terminal_scope.dart';
import 'theme.dart';

/// One line of underlined link text that opens a [uri], runs [onPressed]
/// or invokes the [action] binding above it, whose key it shows after the
/// text (`GitHub ↗ g`). It is focusable; Enter or a click opens it.
class Link extends StatefulWidget {
  /// A link reading [text]; at most one of [uri], [onPressed] and
  /// [action], and none for a disabled one.
  const Link(
    this.text, {
    super.key,
    this.uri,
    this.onPressed,
    this.action,
    bool? external,
    this.focusNode,
    this.autofocus = false,
  }) : external = external ?? uri != null,
       assert(
         (uri == null ? 0 : 1) +
                 (onPressed == null ? 0 : 1) +
                 (action == null ? 0 : 1) <=
             1,
         'Give a Link one of uri, onPressed and action.',
       );

  /// What it reads.
  final String text;

  /// A page outside the app, opened through [TerminalScope]'s terminal.
  final Uri? uri;

  /// What it does inside the app, as opening a route.
  final void Function()? onPressed;

  /// The [Binding.id] of the binding it invokes, in an [Actions] above;
  /// its key, as a [Keymap] has moved it, shows after the text.
  final String? action;

  /// Whether it leads outside the app, drawn as ` ↗` after the text; true
  /// by default with a [uri], and for an [action] that opens one.
  final bool external;

  /// The node it holds focus with; one of its own when null.
  final FocusNode? focusNode;

  /// Whether it asks for focus when first built.
  final bool autofocus;

  @override
  State<Link> createState() => _LinkState();
}

class _LinkState extends State<Link> {
  FocusNode? _own;
  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());
  final _capture = PointerCaptureController();
  final _bounds = PressBounds();
  bool _pressing = false;
  void Function()? _press;

  @override
  void initState() {
    super.initState();
    _node.addListener(_changed);
  }

  @override
  void didUpdateWidget(Link oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.focusNode ?? _own;
    if (!identical(old, _node)) {
      old?.removeListener(_changed);
      _node.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_changed);
    _own?.dispose();
    _capture.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Binding? binding;
    final id = widget.action;
    if (id != null) {
      assert(
        actionDeclared(context, id),
        'No Actions above this link declares a binding with id "$id".',
      );
      binding = Actions.maybeBindingOf(context, id);
    }
    final uri = widget.uri;
    final terminal = uri == null ? null : TerminalScope.maybeOf(context);
    final press = _press = switch ((uri, id)) {
      (final Uri uri, _) when terminal != null => () {
        terminal.openUrl('$uri');
      },
      (_, String()) =>
        binding != null && binding.enabled ? binding.onInvoke : null,
      _ => widget.onPressed,
    };
    final enabled = press != null;
    final focused = enabled && _node.hasFocus;
    final face = !enabled
        ? theme.dim
        : focused
        ? theme.focus.merge(const Style(inverse: true, underline: true))
        : theme.link.merge(Style.underline);
    // Bound, not handled, so the help row lists them while it has focus.
    return Actions(
      bindings: [
        Binding(
          'enter',
          'open',
          () => press?.call(),
          id: 'link:open',
          enabled: press != null,
        ),
      ],
      child: Focus(
        focusNode: _node,
        // requestFocus does not ask canRequestFocus: a disabled one must not ask.
        autofocus: widget.autofocus && enabled,
        canRequestFocus: enabled,
        child: Listener(
          captureController: _capture,
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (press == null || event.button != MouseButton.primary) return;
            _capture.capture();
            _pressing = _capture.isCaptured;
          },
          onPointerUp: (event) {
            final was = _pressing;
            _pressing = false;
            if (!was || event.button != MouseButton.primary) return;
            // What the last build allowed: a lookup belongs to build.
            if (_bounds.contains(event.position)) _press?.call();
          },
          onPointerCancel: (_) => _pressing = false,
          child: PressBoundsBox(
            bounds: _bounds,
            child: Text.rich(
              TextSpan(
                '',
                children: [
                  TextSpan(
                    widget.external ? '${widget.text} ↗' : widget.text,
                    style: face,
                  ),
                  if (enabled && binding != null)
                    TextSpan(' ${binding.chord}', style: theme.dim),
                ],
              ),
              softWrap: false,
            ),
          ),
        ),
      ),
    );
  }
}
