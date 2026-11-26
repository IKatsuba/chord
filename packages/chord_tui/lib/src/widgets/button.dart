import '../foundation/geometry.dart';
import '../input/keys.dart';
import '../rendering/basic.dart';
import '../rendering/flex.dart';
import '../terminal/style.dart';
import '../text/span.dart';
import 'basic.dart';
import 'focus.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'listener.dart';
import 'press_bounds.dart';
import 'theme.dart';
import 'theme_data.dart';

/// A button filled with the theme's accent, its label in the terminal's
/// background colour: Flutter's `FilledButton`, with a key.
///
/// Give it [onPressed], or the [action] id of a [Binding] in an [Actions]
/// above: it then presses by invoking that binding, is disabled while the
/// binding is, and shows the binding's current key under its face.
class FilledButton extends _Button {
  /// A filled button for [child]; exactly one of [onPressed] and [action],
  /// or neither for a disabled one.
  const FilledButton({
    super.key,
    super.onPressed,
    super.action,
    required super.child,
    super.focusNode,
    super.autofocus,
    super.showShortcut,
  }) : super(filled: true);
}

/// A button framed by a rounded border around its bold label: Flutter's
/// `OutlinedButton`, with a key, as [FilledButton] has.
class OutlinedButton extends _Button {
  /// An outlined button for [child]; exactly one of [onPressed] and
  /// [action], or neither for a disabled one.
  const OutlinedButton({
    super.key,
    super.onPressed,
    super.action,
    required super.child,
    super.focusNode,
    super.autofocus,
    super.showShortcut,
  }) : super(filled: false);
}

abstract class _Button extends StatefulWidget {
  const _Button({
    super.key,
    this.onPressed,
    this.action,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.showShortcut = true,
    required this.filled,
  }) : assert(
         onPressed == null || action == null,
         'Give a button onPressed or action, not both.',
       );

  /// What a press does; null, with no [action], disables the button.
  final void Function()? onPressed;

  /// The [Binding.id] of the binding a press invokes, in an [Actions]
  /// above; its key, as a [Keymap] has moved it, shows under the face.
  final String? action;

  /// The label, usually a [Text].
  final Widget child;

  /// The node it holds focus with; one of its own when null.
  final FocusNode? focusNode;

  /// Whether it asks for focus when first built.
  final bool autofocus;

  /// Whether an [action] button draws its key row under the face; a button
  /// without [action] never does.
  final bool showShortcut;

  final bool filled;

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
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
  void didUpdateWidget(_Button oldWidget) {
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

  /// The binding [_Button.action] names, as the keymap leaves it; null when
  /// it is unbound, or there is no action.
  Binding? _binding(BuildContext context) {
    final id = widget.action;
    if (id == null) return null;
    assert(
      actionDeclared(context, id),
      'No Actions above this button declares a binding with id "$id".',
    );
    return Actions.maybeBindingOf(context, id);
  }

  void Function()? _onPress(Binding? binding) {
    if (widget.action == null) return widget.onPressed;
    return binding != null && binding.enabled ? binding.onInvoke : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final binding = _binding(context);
    final press = _press = _onPress(binding);
    final enabled = press != null;
    final focused = enabled && _node.hasFocus;
    final face = widget.filled
        ? _filledFace(theme, enabled: enabled, focused: focused)
        : _outlinedFace(theme, enabled: enabled, focused: focused);
    final keyRow =
        widget.action != null && widget.showShortcut && binding != null
        ? Text.rich(
            TextSpan(
              '',
              children: [
                TextSpan('press ', style: theme.dim),
                TextSpan(
                  '${binding.chord}',
                  style: theme.text.merge(Style.bold),
                ),
              ],
            ),
            softWrap: false,
          )
        : null;
    // Bound, not handled, so the help row lists them while it has focus.
    return Actions(
      bindings: [
        Binding(
          'enter',
          'press',
          () => press?.call(),
          id: 'button:press',
          enabled: press != null,
        ),
        Binding(
          'space',
          'press',
          () => press?.call(),
          id: 'button:press',
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
            // The key row under the face is not the button: a press starts on
            // the face, as the release must end there.
            if (press == null ||
                event.button != MouseButton.primary ||
                !_bounds.contains(event.position)) {
              return;
            }
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PressBoundsBox(bounds: _bounds, child: face),
              ?keyRow,
            ],
          ),
        ),
      ),
    );
  }

  Widget _filledFace(
    ThemeData theme, {
    required bool enabled,
    required bool focused,
  }) {
    final role = !enabled
        ? theme.dim
        : focused
        ? theme.focus
        : theme.accent;
    final style = role.merge(const Style(bold: true, inverse: true));
    return DecoratedBox(
      background: style,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        // Focus underlines the label too, so it shows without colour.
        child: DefaultTextStyle(
          style: focused ? style.merge(Style.underline) : style,
          child: widget.child,
        ),
      ),
    );
  }

  Widget _outlinedFace(
    ThemeData theme, {
    required bool enabled,
    required bool focused,
  }) {
    final frame = !enabled
        ? theme.dim
        : focused
        ? theme.focus
        : theme.border;
    final label = enabled
        ? theme.text.merge(Style.bold)
        : theme.dim.merge(Style.bold);
    return DecoratedBox(
      border: Border.rounded.withStyle(frame),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: DefaultTextStyle(
          style: focused ? label.merge(Style.underline) : label,
          child: widget.child,
        ),
      ),
    );
  }
}
