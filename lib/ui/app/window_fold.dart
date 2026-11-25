/// The window's one ordered event path: every agent's events, shown or
/// not, and every intent the window dispatches, fold synchronously and in
/// the order they come into the windowed state, as the original's window
/// folds what `OpenAgents` hears. The widgets read the front session's
/// state through [WindowFold.app].
library;

import 'package:chord_tui/chord_tui.dart';

import '../../session/conversation.dart';
import 'state.dart';

/// The key main's session has for the window's life.
const mainKey = 1;

/// A session in one of its launches: where a result begun for it goes.
typedef Target = ({int key, int launch});

/// The windowed state, folded in order, with the front's view.
final class WindowFold {
  /// A window of main alone, as [initial] fills it.
  WindowFold([AppState initial = const AppState()])
    : windowed = ValueNotifier(WindowedState.of(initial, mainKey)) {
    _shownFrom = windowed.value;
    app = FrontApp._(this, initial);
  }

  /// Every session's state, the window's and the front.
  final ValueNotifier<WindowedState> windowed;

  /// The front session's state, as the widgets read and write it.
  late final FrontApp app;

  /// The key of the session in front.
  int get front => windowed.value.front;

  // Each session's launch: bumped when it is cleared or closes, so a
  // result begun for the session before is dropped.
  final _launches = <int, int>{};

  /// Where a result begun now goes: the front session, in its launch.
  Target get target => targetOf(front);

  /// Session [key] in the launch it is on now.
  Target targetOf(int key) => (key: key, launch: _launches[key] ?? 0);

  /// Whether [target] is still open, in the launch it was taken in.
  bool isLive(Target target) =>
      windowed.value.sessions.containsKey(target.key) &&
      (_launches[target.key] ?? 0) == target.launch;

  /// Session [key]'s state as the window would draw it in front; null for
  /// a key not open.
  AppState? stateOf(int key) {
    final state = windowed.value;
    if (key == state.front) return app.value;
    final session = state.sessions[key];
    return session == null ? null : appStateOf(state.window, session);
  }

  /// One of session [key]'s events, folded at once, whether it is shown or
  /// not.
  void heard(int key, ConversationEvent event) {
    if (event is Cleared || event is Closing) {
      _launches[key] = (_launches[key] ?? 0) + 1;
    }
    dispatch(SessionHeard(key, event));
  }

  /// [action] folded into the windowed state.
  void dispatch(WindowedAction action) =>
      _set(reduceWindowed(windowed.value, action));

  // The windowed state [app] shows. The front's view is made current
  // before the windowed state is told, so a listener that reads or writes
  // [app] then works on what it has just heard; one that folds again makes
  // a newer view, which is the one told, never the older after it.
  late WindowedState _shownFrom;

  void _set(WindowedState next) {
    if (identical(next, windowed.value)) return;
    final before = _shownFrom;
    _shownFrom = next;
    final moved = _frontMoved(before, next);
    final shown = moved ? next.frontState : app._current;
    app._current = shown;
    windowed.value = next;
    if (moved && identical(app._current, shown)) app.notifyListeners();
  }
}

/// Whether the front's view differs between [a] and [b].
bool _frontMoved(WindowedState a, WindowedState b) =>
    a.front != b.front ||
    !identical(a.window, b.window) ||
    !identical(a.sessions[a.front], b.sessions[b.front]);

/// The front session's state: reading it gives the front's view; writing
/// it sets the window's part and the front session's own.
final class FrontApp extends ValueNotifier<AppState> {
  FrontApp._(this._fold, AppState initial) : _current = initial, super(initial);

  final WindowFold _fold;
  AppState _current;

  @override
  AppState get value => _current;

  @override
  set value(AppState state) {
    if (identical(state, _current)) return;
    final written = _fold.windowed.value.withFront(state);
    _fold._shownFrom = written;
    _current = state;
    _fold.windowed.value = written;
    // A listener that folded again in front has told the newer view.
    if (identical(_current, state)) notifyListeners();
  }
}
