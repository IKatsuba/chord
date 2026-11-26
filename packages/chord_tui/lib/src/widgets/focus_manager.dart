import 'dart:async';

import 'package:characters/characters.dart';

import '../foundation/notifier.dart';
import '../input/keys.dart';
import 'keymap.dart' show Keymap;

/// Returns true when the event was handled and should go no further.
typedef KeyHandler = bool Function(KeyEvent event);

/// Returns true when the pasted text was handled and should go no further.
typedef PasteHandler = bool Function(String text);

/// A key, or a chord of keys, bound to what it does and a description.
///
/// The description is what a shortcuts panel shows.
class Binding {
  /// Binds [keys], one key or a chord such as `ctrl+x a`, to [onInvoke].
  Binding(
    String keys,
    this.description,
    this.onInvoke, {
    this.enabled = true,
    this.id,
  }) : chord = Chord.parse(keys);

  Binding._(this.chord, this.description, this.onInvoke, this.enabled, this.id);

  /// The keys that invoke it.
  final Chord chord;

  /// What it does, as a shortcuts panel says it.
  final String description;

  /// What runs when its keys are pressed.
  final void Function() onInvoke;

  /// Whether it acts now; a disabled binding lets the key go on.
  final bool enabled;

  /// The action this binding is one key of, for a [Keymap] to move its keys
  /// by; several bindings may share it. None keeps the key fixed.
  final String? id;

  /// This binding with what is given changed; the [id] is kept.
  Binding copyWith({
    Chord? chord,
    String? description,
    void Function()? onInvoke,
    bool? enabled,
  }) => Binding._(
    chord ?? this.chord,
    description ?? this.description,
    onInvoke ?? this.onInvoke,
    enabled ?? this.enabled,
    id,
  );

  @override
  String toString() => '$chord: $description';
}

/// Throws when two bindings of one scope claim one key, or when one
/// binding's chord is the start of another's.
void checkBindings(List<Binding> bindings) {
  for (var i = 0; i < bindings.length; i++) {
    for (var j = i + 1; j < bindings.length; j++) {
      final a = bindings[i], b = bindings[j];
      if (a.chord == b.chord) {
        throw ArgumentError(
          '"${a.chord}" is bound twice in one scope: '
          '"${a.description}" and "${b.description}".',
        );
      }
      if (a.chord.startsWith(b.chord.combos) ||
          b.chord.startsWith(a.chord.combos)) {
        final (short, long) = a.chord.length < b.chord.length ? (a, b) : (b, a);
        throw ArgumentError(
          '"${short.chord}" ("${short.description}") is the start of '
          '"${long.chord}" ("${long.description}") in one scope, so the '
          'longer chord could never be pressed.',
        );
      }
    }
  }
}

/// The existing binding match for one stroke and its current pending prefix.
enum KeyBindingMatchKind {
  /// One enabled binding matches the complete sequence.
  exact,

  /// Enabled bindings have this sequence as a proper prefix.
  prefix,

  /// An existing pending chord has no continuation.
  dropped,

  /// No pending chord or matching binding exists.
  none,
}

/// An immutable binding preview with a one-use, same-input dispatch capability.
class KeyBindingMatch {
  KeyBindingMatch._(
    this._manager,
    this._input,
    this._decision,
    List<KeyCombo> sequence, {
    bool Function(Binding)? where,
  }) : _where = where,
       kind = _decision.kind,
       binding = _decision.binding,
       sequence = List.unmodifiable(sequence),
       _pendingEpoch = _manager._pendingEpoch;

  /// Binding-only lookup; ordinary focused handlers may still consume input.
  final KeyBindingMatchKind kind;

  /// The matched binding, present only for [KeyBindingMatchKind.exact].
  final Binding? binding;

  /// The current pending prefix followed by this stroke.
  final List<KeyCombo> sequence;
  final FocusManager _manager;
  final _InputDispatch? _input;
  final _BindingDecision _decision;
  final int _pendingEpoch;
  final bool Function(Binding)? _where;
  bool _used = false;

  /// Consumes an exact/prefix once during its unchanged active key dispatch.
  /// Stale, dropped, none and already-used capabilities have no effects.
  bool dispatch() {
    if (_used) return false;
    _used = true;
    final input = _input;
    if ((kind != KeyBindingMatchKind.exact &&
            kind != KeyBindingMatchKind.prefix) ||
        input == null ||
        input.event == null ||
        input.consumed ||
        !_manager._validInput(input) ||
        _manager._pendingEpoch != _pendingEpoch) {
      return false;
    }
    final eligible = kind == KeyBindingMatchKind.exact
        ? (_where == null || _where(binding!))
        : _decision.prefixBindings.any(
            (binding) => _where == null || _where(binding),
          );
    if (!eligible ||
        !_manager._validInput(input) ||
        _manager._pendingEpoch != _pendingEpoch) {
      return false;
    }
    input.consumed = true;
    if (kind == KeyBindingMatchKind.prefix) {
      _manager._setPending(sequence);
      return true;
    }
    var expectedPending = _pendingEpoch;
    if (_manager._pending.isNotEmpty) {
      expectedPending++;
      _manager._setPending(const []);
    }
    final receiver = _decision.receiver;
    if (_manager._validInput(input) &&
        _manager._pendingEpoch == expectedPending &&
        receiver != null &&
        _manager._live(receiver.node)) {
      binding!.onInvoke();
    }
    return true;
  }
}

/// A place in the focus tree: something that can hold focus, or a scope
/// of bindings that key presses pass through.
class FocusNode extends ChangeNotifier {
  /// A node with the given handlers, not yet attached.
  FocusNode({
    this.onKey,
    this.onPaste,
    this.onKeyCapture,
    this.onPasteCapture,
    this.canRequestFocus = true,
    this.debugLabel,
    this.ignoreLayoutReadings = false,
  });

  /// Handles keys that reach this node; true stops them.
  KeyHandler? onKey;

  /// Readings of a press on another layout pass this node by: its capture,
  /// its [onKey] and its own bindings. An editing widget sets it, so a
  /// reading never edits and a key it binds is the app's when read.
  bool ignoreLayoutReadings;

  /// Handles pasted text that reaches this node; true stops it.
  PasteHandler? onPaste;

  /// Sees keys ancestor-first before ordinary key handling.
  KeyHandler? onKeyCapture;

  /// Sees paste, including empty text, before ordinary paste handling.
  PasteHandler? onPasteCapture;

  /// Whether it can hold focus, or only passes keys through.
  bool canRequestFocus;

  /// A name for the node, for debugging.
  final String? debugLabel;
  List<Binding> _bindings = const [];

  /// The keys this node binds. A change of what they are, say or whether
  /// they act tells the manager's listeners, as a shortcuts panel. Registration
  /// lists are read-only snapshots; replace them through this setter.
  List<Binding> get bindings => _bindings;
  set bindings(List<Binding> value) {
    final old = _bindings;
    _bindings = List.unmodifiable(value);
    if (_manager != null && !_sameRegistrations(old, _bindings)) {
      _manager!._bindingsEpoch++;
    }
    if (_manager != null && !_sameBindings(old, _bindings)) {
      _manager!.notifyListeners();
    }
  }

  static bool _sameRegistrations(List<Binding> a, List<Binding> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  static bool _sameBindings(List<Binding> a, List<Binding> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].chord != b[i].chord ||
          a[i].description != b[i].description ||
          a[i].enabled != b[i].enabled) {
        return false;
      }
    }
    return true;
  }

  FocusNode? _parent;
  final List<FocusNode> _children = [];
  var _descendantsAreFocusable = true;

  /// Whether the nodes under this one can hold and take focus: false for a
  /// subtree that stays mounted but is off screen, as a closed fold's body.
  /// Turned off while focus is under it, focus falls back in its scope.
  bool get descendantsAreFocusable => _descendantsAreFocusable;
  set descendantsAreFocusable(bool value) {
    if (value == _descendantsAreFocusable) return;
    _descendantsAreFocusable = value;
    if (!value) _manager?._excluded(this);
  }

  FocusManager? _manager;
  bool _wantsFocus = false;

  /// The node above this one, if attached.
  FocusNode? get parent => _parent;

  /// The nodes under this one.
  List<FocusNode> get children => List.unmodifiable(_children);

  /// Whether it is in a manager's tree.
  bool get attached => _manager != null;

  /// Whether this node itself has focus.
  bool get hasPrimaryFocus => _manager?.primaryFocus == this;

  /// Whether this node or one under it has focus.
  bool get hasFocus {
    var n = _manager?.primaryFocus;
    while (n != null) {
      if (n == this) return true;
      n = n._parent;
    }
    return false;
  }

  /// Moves focus here, or once attached if it is not yet.
  void requestFocus() {
    final m = _manager;
    if (m == null) {
      _wantsFocus = true;
      return;
    }
    m._request(this);
  }

  /// Gives focus up, if this node holds it.
  void unfocus() {
    if (hasPrimaryFocus) _manager!._setPrimary(null);
  }

  /// Attaches this node under [parent], which must be attached.
  void attach(FocusNode parent) {
    if (_parent == parent) return;
    // Moved within its tree, as when the widget holding it is built anew
    // elsewhere, it keeps the focus it or a node under it holds.
    final m = _manager;
    if (m != null && identical(parent._manager, m)) {
      final focused = hasFocus;
      final scope = m._scopeOf(m._primary);
      final above = m._scopeAbove(this);
      _parent?._children.remove(this);
      _parent = parent;
      parent._children.add(this);
      m._bindingsEpoch++;
      if (focused) m._moved(scope, above);
      return;
    }
    detach();
    _parent = parent;
    parent._children.add(this);
    _setManager(parent._manager);
  }

  /// Takes this node, with those under it, out of its parent; focus inside goes to the scope above.
  void detach() {
    final p = _parent;
    if (p == null) return;
    final m = _manager;
    // The scope around a node that goes keeps the focus, so closing the
    // scope can hand it back where it came from.
    if (m != null && hasFocus) m._setPrimary(m._scopeAbove(this));
    p._children.remove(this);
    _parent = null;
    _setManager(null);
  }

  void _setManager(FocusManager? m) {
    if (!identical(_manager, m)) {
      _manager?._bindingsEpoch++;
      m?._bindingsEpoch++;
    }
    _manager = m;
    if (m != null && _wantsFocus) {
      _wantsFocus = false;
      m._request(this);
    }
    for (final c in _children) {
      c._setManager(m);
    }
  }

  @override
  String toString() => 'FocusNode(${debugLabel ?? ''})';
}

/// A node that groups the nodes under it: Tab and Shift+Tab move among
/// them only, it can hold focus itself when none can, and it remembers
/// where focus was before it took it, to give it back when it closes.
class FocusScopeNode extends FocusNode {
  /// A scope; an inactive one takes no focus and reaches no keys until
  /// [FocusManager.setScopeActive] turns it on.
  FocusScopeNode({super.debugLabel, bool active = true}) : _active = active;

  bool _active;
  FocusNode? _saved;
  FocusNode? _autofocus;

  /// Whether the scope and the nodes under it can hold focus now.
  bool get active => _active;

  @override
  String toString() => 'FocusScopeNode(${debugLabel ?? ''})';
}

/// The default wait for the next key of an unfinished chord.
const defaultChordTimeout = Duration(seconds: 3);

/// The US keys a press of the single character [typed] would have been,
/// had the layout been US, most likely first; empty when it knows none.
typedef KeyLayoutFallback = List<String> Function(String typed);

/// Holds the focus and routes key presses along the focus path.
class FocusManager extends ChangeNotifier {
  /// A focus manager that waits [chordTimeout] for the next chord key and
  /// reads a press that does nothing through [layoutFallback].
  FocusManager({this.chordTimeout = defaultChordTimeout, this.layoutFallback}) {
    root._manager = this;
  }

  /// How long an unfinished chord waits before returning to ordinary input.
  final Duration chordTimeout;

  /// The app's table of the US keys a typed character stands for; none
  /// reads only the terminal's base-layout key.
  final KeyLayoutFallback? layoutFallback;

  /// The presses [event] is read as when it does nothing as typed: the
  /// terminal's base-layout key first, then [layoutFallback]'s, without
  /// repeats and without the press itself.
  List<KeyEvent> readingsOf(KeyEvent event) {
    final seen = {event.combo};
    final out = <KeyEvent>[];
    void add(KeyEvent reading) {
      if (seen.add(reading.combo)) out.add(reading);
    }

    if (event.onBaseLayout case final base?) add(base);
    final fallback = layoutFallback;
    if (fallback != null && event.key.characters.length == 1) {
      for (final key in fallback(event.key)) {
        if (key.isEmpty) continue;
        final combo = KeyCombo.normalized(
          key,
          ctrl: event.ctrl,
          alt: event.alt,
          shift: event.shift,
          superKey: event.superKey,
          hyper: event.hyper,
          meta: event.meta,
        );
        add(
          KeyEvent(
            combo.key,
            ctrl: combo.ctrl,
            alt: combo.alt,
            shift: combo.shift,
            superKey: combo.superKey,
            hyper: combo.hyper,
            meta: combo.meta,
            typed: event,
          ),
        );
      }
    }
    return out;
  }

  Timer? _pendingTimer;

  /// The top of the focus tree.
  final FocusNode root = FocusNode(canRequestFocus: false, debugLabel: 'root');
  FocusNode? _primary;
  List<KeyCombo> _pending = const [];
  int _inputEpoch = 0, _focusEpoch = 0, _bindingsEpoch = 0, _pendingEpoch = 0;
  _InputDispatch? _activeInput;

  /// The node that has focus, if any.
  FocusNode? get primaryFocus => _primary;

  /// The keys of a chord pressed so far, waiting for the rest.
  List<KeyCombo> get pendingChord => _pending;

  final List<FocusNode> _history = [];

  void _setPrimary(FocusNode? node) {
    if (node == _primary) return;
    _focusEpoch++;
    final old = _primary;
    // A chord begun in one scope does not go on in another.
    if (_scopeOf(old) != _scopeOf(node)) {
      _pendingTimer?.cancel();
      _pendingTimer = null;
      _pending = const [];
    }
    _primary = node;
    if (node != null) {
      _history
        ..remove(node)
        ..add(node);
      if (_history.length > 32) _history.removeAt(0);
    }
    if (old != null && !old.isDisposed) old.notifyListeners();
    node?.notifyListeners();
    notifyListeners();
  }

  // The focus moved with a node to another place in the tree: where it may
  // not be held there, it goes to [above], the scope the node left, as a
  // detach gives it; held in another scope, a chord begun in [scope] ends.
  void _moved(FocusScopeNode? scope, FocusScopeNode? above) {
    if (!_eligible(_primary)) {
      _setPrimary(above);
      return;
    }
    if (_scopeOf(_primary) != scope) {
      _focusEpoch++;
      _pendingTimer?.cancel();
      _pendingTimer = null;
      _pending = const [];
      notifyListeners();
    }
  }

  /// The scope [n] is in: itself when it is one.
  FocusScopeNode? _scopeOf(FocusNode? n) =>
      n is FocusScopeNode ? n : (n == null ? null : _scopeAbove(n));

  FocusScopeNode? _scopeAbove(FocusNode n) {
    var p = n._parent;
    while (p != null) {
      if (p is FocusScopeNode) return p;
      p = p._parent;
    }
    return null;
  }

  static bool _within(FocusNode? n, FocusNode ancestor) {
    while (n != null) {
      if (identical(n, ancestor)) return true;
      n = n._parent;
    }
    return false;
  }

  bool _hasEligibleBelow(FocusNode node) {
    for (final c in node._children) {
      if (_eligible(c) || _hasEligibleBelow(c)) return true;
    }
    return false;
  }

  bool _eligible(FocusNode? n) {
    if (n == null || n._manager != this || n.isDisposed) return false;
    if (!n.canRequestFocus) return false;
    for (FocusNode? p = n; p != null; p = p._parent) {
      if (p is FocusScopeNode && !p._active) return false;
      if (!identical(p, n) && !p._descendantsAreFocusable) return false;
    }
    return true;
  }

  // Focus under [node], whose descendants were just excluded, goes to the
  // most recent eligible node of its scope, else that scope's first, else
  // the scope, else nowhere.
  void _excluded(FocusNode node) {
    final p = _primary;
    if (p == null || identical(p, node) || !_within(p, node)) return;
    final scope = _scopeAbove(node);
    final area = scope ?? root;
    FocusNode? target;
    for (final n in _history.reversed) {
      if (_within(n, area) && _eligible(n)) {
        target = n;
        break;
      }
    }
    target ??= traversalIn(area).firstOrNull;
    target ??= _eligible(scope) ? scope : null;
    _setPrimary(target);
  }

  /// The nearest scope above [node], not [node] itself, that is off.
  FocusScopeNode? _offAbove(FocusNode node) {
    for (FocusNode? p = node._parent; p != null; p = p._parent) {
      if (p is FocusScopeNode && !p._active) return p;
    }
    return null;
  }

  // A node in an inactive scope waits for the scope to be shown.
  void _request(FocusNode n) {
    for (FocusNode? p = n._parent; p != null; p = p._parent) {
      // Under an excluding node a request is dropped, not kept for later.
      if (!p._descendantsAreFocusable) return;
    }
    for (FocusNode? p = n; p != null; p = p._parent) {
      if (p is FocusScopeNode && !p._active) {
        p._autofocus = n;
        return;
      }
    }
    _setPrimary(n);
  }

  /// Turns [scope] on or off.
  ///
  /// Turned off, it gives focus back as [releaseScope] does. Turned on with
  /// [takeFocus], it remembers the focused node and takes focus: to the
  /// node under it that last had it or asked for it, else to itself. With
  /// [autofocus] only, a node under it that asked for focus gets it.
  ///
  /// Under a scope that is off, neither moves the focus: the node that
  /// would have taken it (the one that asked, else [scope] for
  /// [takeFocus]) becomes that scope's request instead, as a request made
  /// there would, replacing an earlier one. It takes the focus when that
  /// scope is turned on with [takeFocus] or [autofocus].
  void setScopeActive(
    FocusScopeNode scope,
    bool active, {
    bool takeFocus = false,
    bool autofocus = false,
  }) {
    if (scope._active == active) return;
    scope._active = active;
    if (!active) {
      _giveBack(scope);
      return;
    }
    final asked = scope._autofocus;
    scope._autofocus = null;
    if (_offAbove(scope) case final off?) {
      final wanted = takeFocus
          ? (asked ?? scope)
          : autofocus
          ? asked
          : null;
      if (wanted != null) off._autofocus = wanted;
      return;
    }
    if (takeFocus) {
      if (!_within(_primary, scope)) scope._saved = _primary;
      FocusNode? last;
      for (final n in _history.reversed) {
        if (_within(n, scope) && _eligible(n)) {
          last = n;
          break;
        }
      }
      _setPrimary(
        _eligible(asked) ? asked : (last ?? (_eligible(scope) ? scope : null)),
      );
    } else if (autofocus && _eligible(asked)) {
      _setPrimary(asked);
    }
  }

  /// Gives up [scope], which is going away: if focus is in it, focus goes
  /// back to the node it came from when that can still take it, else to
  /// the node most recently focused in the scope around it, else to that
  /// scope's first node, else to that scope, else nowhere.
  void releaseScope(FocusScopeNode scope) {
    scope._active = false;
    _giveBack(scope);
  }

  void _giveBack(FocusScopeNode scope) {
    // Scopes opened from inside this one go back where this one would.
    void pass(FocusNode n) {
      if (n is FocusScopeNode && n != scope && _within(n._saved, scope)) {
        n._saved = scope._saved;
      }
      n._children.forEach(pass);
    }

    pass(root);
    if (!_within(_primary, scope)) return;
    final outer = _scopeAbove(scope);
    final area = outer ?? root;
    FocusNode? target;
    if (_eligible(scope._saved)) {
      target = scope._saved;
    } else {
      for (final n in _history.reversed) {
        if (_within(n, area) && _eligible(n)) {
          target = n;
          break;
        }
      }
      target ??= traversalIn(area).firstOrNull;
      target ??= _eligible(outer) ? outer : null;
    }
    _setPrimary(target);
  }

  /// The node key presses start from: the focused one, or the deepest
  /// first descendant of the root when nothing is focused.
  ///
  /// A scope that holds the focus itself, with no descendant that could take
  /// it, starts presses from its own deepest first descendant, the same
  /// fallback, so bindings under it with no focusable widget of their own
  /// still get their keys. A scope with a focusable descendant starts them
  /// from itself, as any focused node does.
  FocusNode get effectiveFocus {
    final p = _primary;
    if (p != null && (p is! FocusScopeNode || _hasEligibleBelow(p))) {
      return p;
    }
    var n = p ?? root;
    while (true) {
      // Keys never reach into an excluded subtree, as a closed fold.
      if (!n._descendantsAreFocusable) return n;
      final next = n._children.where((c) => c is! FocusScopeNode || c._active);
      if (next.isEmpty) return n;
      n = next.first;
    }
  }

  /// From the focused node up to the root.
  List<FocusNode> get focusPath {
    final out = <FocusNode>[];
    FocusNode? n = effectiveFocus;
    while (n != null) {
      out.add(n);
      n = n._parent;
    }
    return out;
  }

  /// The bindings a key press can reach now; inner ones shadow outer ones.
  List<Binding> get activeBindings {
    final seen = <Chord>{};
    final out = <Binding>[];
    for (final n in focusPath) {
      for (final b in n.bindings) {
        if (b.enabled && seen.add(b.chord)) out.add(b);
      }
    }
    return out;
  }

  /// Cancels an unfinished chord without dispatching a key or moving focus.
  void cancelPendingChord() => _setPending(const []);

  void _setPending(List<KeyCombo> p) {
    _pendingEpoch++;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pending = List.unmodifiable(p);
    if (p.isNotEmpty) {
      _pendingTimer = Timer(chordTimeout, () => _setPending(const []));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _inputEpoch++;
    _activeInput = null;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pending = const [];
    _primary = null;
    _history.clear();
    root._setManager(null);
    super.dispose();
  }

  /// Previews enabled bindings through the existing pending-chord matcher.
  /// Filtering precedes shadowing; focused handlers are not invoked or predicted.
  KeyBindingMatch matchKey(KeyEvent event, {bool Function(Binding)? where}) {
    final input = _activeInput;
    final sameStroke = input?.event?.combo == event.combo;
    final receivers = sameStroke && input != null && _validInput(input)
        ? input.receivers
        : [
            for (final node in focusPath)
              // A reading previews as it would dispatch: past editing nodes.
              if (event.typed == null || !node.ignoreLayoutReadings)
                _KeyReceiver(node),
          ];
    final sequence = [..._pending, event.combo];
    final decision = _matchBindings(
      receivers,
      sequence,
      pending: _pending.isNotEmpty,
      where: where,
    );
    return KeyBindingMatch._(
      this,
      sameStroke ? input : null,
      decision,
      sequence,
      where: where,
    );
  }

  bool _live(FocusNode node) =>
      !node.isDisposed && identical(node._manager, this);

  bool _validInput(_InputDispatch input) =>
      !isDisposed &&
      identical(_activeInput, input) &&
      _inputEpoch == input.epoch &&
      _focusEpoch == input.focusEpoch &&
      _bindingsEpoch == input.bindingsEpoch &&
      input.receivers.every(
        (receiver) =>
            _live(receiver.node) &&
            FocusNode._sameRegistrations(
              receiver.bindings,
              receiver.node.bindings,
            ),
      );

  _InputDispatch _beginInput(KeyEvent? event) =>
      _InputDispatch(event, ++_inputEpoch, _focusEpoch, _bindingsEpoch, [
        for (final node in focusPath)
          // A reading goes on to the ancestors of a node that ignores them.
          if (event?.typed == null || !node.ignoreLayoutReadings)
            _KeyReceiver(node),
      ]);

  _BindingDecision _matchBindings(
    List<_KeyReceiver> receivers,
    List<KeyCombo> sequence, {
    required bool pending,
    bool Function(Binding)? where,
  }) {
    final prefixes = <Binding>[];
    for (final receiver in receivers) {
      if (!_live(receiver.node)) continue;
      final bindings = receiver.bindings
          .where(
            (binding) => binding.enabled && (where == null || where(binding)),
          )
          .toList();
      for (final binding in bindings) {
        if (binding.chord.matches(sequence)) {
          return _BindingDecision(
            KeyBindingMatchKind.exact,
            binding: binding,
            receiver: receiver,
          );
        }
      }
      final candidates = bindings.where(
        (binding) => binding.chord.startsWith(sequence),
      );
      prefixes.addAll(candidates);
      if (!pending && prefixes.isNotEmpty) {
        return _BindingDecision(
          KeyBindingMatchKind.prefix,
          prefixBindings: prefixes,
        );
      }
    }
    return _BindingDecision(
      prefixes.isNotEmpty
          ? KeyBindingMatchKind.prefix
          : pending
          ? KeyBindingMatchKind.dropped
          : KeyBindingMatchKind.none,
      prefixBindings: prefixes,
    );
  }

  /// Sends keys through ancestor capture, then the existing ordinary route.
  /// A press that goes unhandled is sent again as each of [readingsOf] in
  /// turn, until one is handled; a waiting chord tries them before it is
  /// dropped and the press swallowed.
  bool dispatchKey(KeyEvent event) {
    if (isDisposed) return false;
    final previous = _activeInput;
    try {
      final waiting = _pending.isNotEmpty;
      final input = _beginInput(event);
      _activeInput = input;
      if (_route(input, event)) return true;
      for (final reading in readingsOf(event)) {
        if (isDisposed) return true;
        final read = _beginInput(reading);
        _activeInput = read;
        if (_route(read, reading)) return true;
      }
      if (!waiting || _pending.isEmpty) return false;
      // A full-path miss clears/swallow the chord; filtered previews cannot.
      _activeInput?.consumed = true;
      _setPending(const []);
      return true;
    } finally {
      _activeInput = previous;
    }
  }

  /// One press, as typed or as a reading, along [input]'s route: whether
  /// it was handled, or the input changed under it.
  bool _route(_InputDispatch input, KeyEvent event) {
    for (final receiver in input.receivers.reversed) {
      if (!_live(receiver.node)) continue;
      final handled = receiver.onKeyCapture?.call(event) ?? false;
      if (handled || input.consumed || !_validInput(input)) return true;
    }
    if (_pending.isNotEmpty) {
      final match = matchKey(event);
      if (match.dispatch()) return true;
      return !_validInput(input);
    }
    for (final receiver in input.receivers) {
      if (!_live(receiver.node)) continue;
      if (receiver.onKey?.call(event) ?? false) return true;
      if (input.consumed || !_validInput(input)) return true;
      final sequence = [event.combo];
      final decision = _matchBindings([receiver], sequence, pending: false);
      final match = KeyBindingMatch._(this, input, decision, sequence);
      if (match.dispatch()) return true;
    }
    return false;
  }

  /// Sends paste through ancestor capture before the normal focused handlers.
  bool dispatchPaste(String text) {
    if (isDisposed) return false;
    final previous = _activeInput;
    final input = _beginInput(null);
    _activeInput = input;
    try {
      for (final receiver in input.receivers.reversed) {
        if (!_live(receiver.node)) continue;
        final handled = receiver.onPasteCapture?.call(text) ?? false;
        if (handled || !_validInput(input)) return true;
      }
      for (final receiver in input.receivers) {
        if (!_live(receiver.node)) continue;
        if (receiver.onPaste?.call(text) ?? false) return true;
        if (!_validInput(input)) return true;
      }
      return false;
    } finally {
      _activeInput = previous;
    }
  }

  /// Nodes that can take focus in the focused node's scope, in tree
  /// order: the ones Tab moves among.
  List<FocusNode> get traversalOrder => traversalIn(_scopeOf(_primary) ?? root);

  /// Nodes under [area] that can take focus, in tree order; scopes and
  /// what is in an inactive scope are left out.
  List<FocusNode> traversalIn(FocusNode area) {
    final out = <FocusNode>[];
    void walk(FocusNode n) {
      if (n is FocusScopeNode && !n._active) return;
      if (n is! FocusScopeNode && n != root && _eligible(n)) out.add(n);
      n._children.forEach(walk);
    }

    area._children.forEach(walk);
    return out;
  }

  /// Moves focus to the next node in traversal order.
  void focusNext() => _move(1);

  /// Moves focus to the previous node in traversal order.
  void focusPrevious() => _move(-1);

  void _move(int delta) {
    final order = traversalOrder;
    if (order.isEmpty) {
      // With nothing to move to, the scope itself holds focus.
      final scope = _scopeOf(_primary);
      if (_eligible(scope)) _setPrimary(scope);
      return;
    }
    final i = _primary == null ? -1 : order.indexOf(_primary!);
    final next = i < 0
        ? (delta > 0 ? 0 : order.length - 1)
        : (i + delta) % order.length;
    _setPrimary(order[next]);
  }
}

class _KeyReceiver {
  _KeyReceiver(this.node)
    : bindings = List.of(node.bindings),
      onKeyCapture = node.onKeyCapture,
      onPasteCapture = node.onPasteCapture,
      onKey = node.onKey,
      onPaste = node.onPaste;
  final FocusNode node;
  final List<Binding> bindings;
  final KeyHandler? onKeyCapture, onKey;
  final PasteHandler? onPasteCapture, onPaste;
}

class _InputDispatch {
  _InputDispatch(
    this.event,
    this.epoch,
    this.focusEpoch,
    this.bindingsEpoch,
    this.receivers,
  );
  final KeyEvent? event;
  final int epoch, focusEpoch, bindingsEpoch;
  final List<_KeyReceiver> receivers;
  bool consumed = false;
}

class _BindingDecision {
  const _BindingDecision(
    this.kind, {
    this.binding,
    this.receiver,
    this.prefixBindings = const [],
  });
  final KeyBindingMatchKind kind;
  final Binding? binding;
  final _KeyReceiver? receiver;
  final List<Binding> prefixBindings;
}
