import 'package:meta/meta.dart';

import '../input/keys.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'keymap.dart';

/// Marks a subtree where no [Focus] may ask for focus: the items of a
/// list, which are built and dropped as they scroll.
@internal
class NoFocusRequests extends InheritedWidget {
  /// Marks [child].
  const NoFocusRequests({super.key, required super.child});

  @override
  bool updateShouldNotify(NoFocusRequests oldWidget) => false;
}

class _FocusMarker extends InheritedWidget {
  const _FocusMarker({required this.node, required super.child});

  final FocusNode node;

  @override
  bool updateShouldNotify(_FocusMarker oldWidget) => node != oldWidget.node;
}

// The widget state that last attached each node: one going leaves a node
// another has since taken up, as when a list's children shift and the
// node's new Focus is built before its old one is disposed.
final _holders = Expando<State>();

// The focus a node took with it as it went this frame, and where the
// focus went instead, by manager.
final _lost = Expando<({FocusNode node, FocusNode? to})>();

/// Detaches [node], [holder]'s, unless another has taken it up, then calls
/// [then]. Focus it held is remembered until the frame's layout: a widget
/// built for the same node later in the same build, as when a column's
/// children shift and the old one goes first, takes the focus back.
void _release(
  BuildOwner? owner,
  FocusNode node,
  State holder, [
  void Function()? then,
]) {
  if (identical(_holders[node], holder)) {
    final manager = owner?.focusManager;
    final was = manager?.primaryFocus;
    final losing = manager != null && was != null && node.hasFocus;
    node.detach();
    if (losing) {
      final lost = (node: was, to: manager.primaryFocus);
      _lost[manager] = lost;
      owner!.afterLayout(() {
        if (identical(_lost[manager], lost)) _lost[manager] = null;
      });
    }
  }
  then?.call();
}

/// Gives [node] back the focus it took with it as it went earlier in this
/// frame, unless the focus has moved on since.
void _regain(BuildOwner owner, FocusNode node) {
  final manager = owner.focusManager;
  final lost = _lost[manager];
  if (lost == null || !identical(lost.node, node)) return;
  _lost[manager] = null;
  if (identical(manager.primaryFocus, lost.to)) node.requestFocus();
}

FocusNode _parentNode(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_FocusMarker>()?.node ??
    context.owner.focusManager.root;

/// Makes its subtree a place that can hold focus and receive keys.
class Focus extends StatefulWidget {
  /// A focus place for [child], with its own node unless [focusNode] is given.
  const Focus({
    super.key,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.onKey,
    this.onPaste,
    this.onKeyCapture,
    this.onPasteCapture,
    this.debugLabel,
    this.ignoreLayoutReadings = false,
  });

  /// What it makes a focus place.
  final Widget child;

  /// Readings of a press on another layout pass this node by, as
  /// [FocusNode.ignoreLayoutReadings]; editing widgets set it.
  final bool ignoreLayoutReadings;

  /// The node to use; one of its own when null.
  final FocusNode? focusNode;

  /// Whether it asks for focus when first built.
  final bool autofocus;

  /// Whether it can hold focus, or only passes keys through.
  final bool canRequestFocus;

  /// Handles keys that reach it; true stops them.
  final KeyHandler? onKey;

  /// Handles pasted text that reaches it; true stops it.
  final PasteHandler? onPaste;

  /// Sees keys ancestor-first before pending chords, handlers or editing.
  final KeyHandler? onKeyCapture;

  /// Sees paste, including empty text, before focused paste handlers.
  final PasteHandler? onPasteCapture;

  /// A name for the node, for debugging.
  final String? debugLabel;

  /// The nearest focus node above [context].
  static FocusNode of(BuildContext context) => _parentNode(context);

  @override
  State<Focus> createState() => _FocusState();
}

class _FocusState extends State<Focus> {
  FocusNode? _own;
  FocusNode get node =>
      widget.focusNode ?? (_own ??= FocusNode(debugLabel: widget.debugLabel));

  void _configure() {
    assert(
      !widget.canRequestFocus ||
          context.getInheritedWidgetOfExactType<NoFocusRequests>() == null,
      'An item of a ListView takes no focus.',
    );
    node
      ..onKey = widget.onKey
      ..onPaste = widget.onPaste
      ..onKeyCapture = widget.onKeyCapture
      ..onPasteCapture = widget.onPasteCapture
      ..canRequestFocus = widget.canRequestFocus
      ..ignoreLayoutReadings = widget.ignoreLayoutReadings;
  }

  @override
  void initState() {
    super.initState();
    _configure();
    if (widget.autofocus) node.requestFocus();
  }

  /// Where a focused node's detach waits for the frame's layout.
  BuildOwner? _owner;

  @override
  void didChangeDependencies() {
    _owner = context.owner;
    node.attach(_parentNode(context));
    _holders[node] = this;
    _regain(context.owner, node);
  }

  @override
  void didUpdateWidget(Focus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      final old = oldWidget.focusNode ?? _own;
      final hadFocus = old?.hasPrimaryFocus ?? false;
      old?.detach();
      node.attach(_parentNode(context));
      _holders[node] = this;
      if (hadFocus) node.requestFocus();
    }
    _configure();
  }

  @override
  void dispose() {
    _release(_owner, node, this, _own?.dispose);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _FocusMarker(node: node, child: widget.child);
}

/// Groups the focusable widgets under it: Tab and Shift+Tab move among
/// them, and focus goes back to where it came from when the scope goes.
class FocusScope extends StatefulWidget {
  /// A scope with [node], or one it makes and owns.
  const FocusScope({
    super.key,
    this.node,
    this.autofocus = false,
    required this.child,
  });

  /// The scope's node; made and owned when absent.
  final FocusScopeNode? node;

  /// Whether the scope asks for focus when it is first built.
  final bool autofocus;

  /// What is in the scope.
  final Widget child;

  @override
  State<FocusScope> createState() => _FocusScopeState();
}

class _FocusScopeState extends State<FocusScope> {
  FocusScopeNode? _own;
  FocusScopeNode get node => widget.node ?? (_own ??= FocusScopeNode());

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) node.requestFocus();
  }

  @override
  void didChangeDependencies() {
    node.attach(_parentNode(context));
  }

  @override
  void didUpdateWidget(FocusScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      _release(oldWidget.node ?? _own!);
      node.attach(_parentNode(context));
    }
  }

  void _release(FocusScopeNode n) {
    if (n.attached) context.owner.focusManager.releaseScope(n);
    n.detach();
  }

  @override
  void dispose() {
    _release(node);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _FocusMarker(node: node, child: widget.child);
}

/// Keeps the widgets under it from holding or taking focus while
/// [excluding], as Flutter's ExcludeFocus.
class ExcludeFocus extends StatefulWidget {
  /// Excludes focus from [child] while [excluding].
  const ExcludeFocus({super.key, this.excluding = true, required this.child});

  /// Whether focus is kept out.
  final bool excluding;

  /// What it guards.
  final Widget child;

  @override
  State<ExcludeFocus> createState() => _ExcludeFocusState();
}

class _ExcludeFocusState extends State<ExcludeFocus> {
  final _node = FocusNode(canRequestFocus: false, debugLabel: 'exclude focus');

  @override
  void initState() {
    super.initState();
    _node.descendantsAreFocusable = !widget.excluding;
  }

  @override
  void didChangeDependencies() {
    _node.attach(_parentNode(context));
  }

  @override
  void didUpdateWidget(ExcludeFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _node.descendantsAreFocusable = !widget.excluding;
  }

  @override
  void dispose() {
    _node.detach();
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _FocusMarker(node: _node, child: widget.child);
}

/// Binds keys to what they do for everything under it.
///
/// A key press goes from the focused widget up; the first scope with a
/// matching binding runs it. Two bindings of one scope cannot claim one
/// key, and a chord cannot start with another binding's key: both throw.
/// A [Keymap] above moves the keys of bindings that carry an id.
class Actions extends StatefulWidget {
  /// [bindings] for every key press under [child].
  const Actions({
    super.key,
    required this.bindings,
    required this.child,
    this.ignoreLayoutReadings = false,
  });

  /// The keys bound here and what they do.
  final List<Binding> bindings;

  /// What the bindings serve.
  final Widget child;

  /// Readings of a press on another layout pass these bindings by, as
  /// [FocusNode.ignoreLayoutReadings]: an editing widget's own keys.
  final bool ignoreLayoutReadings;

  /// The binding with [id] in the nearest [Actions] above [context] that
  /// holds one, with the [Keymap] above that [Actions] applied, so its
  /// [Binding.chord] is the key that works now; null when none holds it.
  /// [context] rebuilds when it changes.
  static Binding? maybeBindingOf(BuildContext context, String id) =>
      context.dependOnInheritedWidgetOfExactType<_ActionsScope>()?.bound[id];

  @override
  State<Actions> createState() => _ActionsState();
}

/// Whether an [Actions] above [context] declares a binding with [id],
/// though its [Keymap] may have taken every key from it.
@internal
bool actionDeclared(BuildContext context, String id) =>
    context
        .dependOnInheritedWidgetOfExactType<_ActionsScope>()
        ?.declared
        .contains(id) ??
    false;

/// The bindings of every [Actions] from here up, by id, the nearest first.
class _ActionsScope extends InheritedWidget {
  const _ActionsScope({
    required this.bound,
    required this.declared,
    required super.child,
  });

  final Map<String, Binding> bound;
  final Set<String> declared;

  @override
  bool updateShouldNotify(_ActionsScope oldWidget) =>
      !_sameBindings(bound, oldWidget.bound) ||
      declared.length != oldWidget.declared.length ||
      !declared.containsAll(oldWidget.declared);
}

bool _sameBindings(Map<String, Binding> a, Map<String, Binding> b) {
  if (a.length != b.length) return false;
  for (final MapEntry(:key, :value) in a.entries) {
    final other = b[key];
    if (other == null ||
        other.chord != value.chord ||
        other.enabled != value.enabled ||
        other.description != value.description ||
        !identical(other.onInvoke, value.onInvoke)) {
      return false;
    }
  }
  return true;
}

class _ActionsState extends State<Actions> {
  final FocusNode _node = FocusNode(
    canRequestFocus: false,
    debugLabel: 'actions',
  );

  KeymapData _keymap = const KeymapData();
  List<Binding> _bound = const [];
  _ActionsScope? _above;

  /// Where a focused node's detach waits for the frame's layout.
  BuildOwner? _owner;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didChangeDependencies() {
    _owner = context.owner;
    _node.attach(_parentNode(context));
    _holders[_node] = this;
    _above = context.dependOnInheritedWidgetOfExactType<_ActionsScope>();
    final keymap = Keymap.of(context);
    if (keymap != _keymap) {
      _keymap = keymap;
      _register();
    }
  }

  @override
  void didUpdateWidget(Actions oldWidget) {
    super.didUpdateWidget(oldWidget);
    _register();
  }

  /// The bindings as the keymap above moves them; what it could not bind
  /// is the app's to ask [KeymapData.apply] for.
  void _register() {
    final bindings = _keymap.apply(widget.bindings).bindings;
    checkBindings(bindings);
    _bound = bindings;
    _node
      ..bindings = bindings
      ..ignoreLayoutReadings = widget.ignoreLayoutReadings;
  }

  @override
  void dispose() {
    _release(_owner, _node, this, _node.dispose);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final above = _above;
    return _ActionsScope(
      bound: {...?above?.bound, for (final b in _bound.reversed) ?b.id: b},
      declared: {...?above?.declared, for (final b in widget.bindings) ?b.id},
      child: _FocusMarker(node: _node, child: widget.child),
    );
  }
}

/// Shorthand: the key this event would match in a binding.
extension KeyEventMatch on KeyEvent {
  /// Whether this event is the single key [keys] names, as `ctrl+o`.
  bool matches(String keys) => combo == KeyCombo.parse(keys);
}
