/// Each session's transcript `ScrollController`, kept while the session is
/// open so a session shown again finds its place: the one authority for
/// its scroll.
library;

import 'package:chord_tui/chord_tui.dart';

/// The window's scroll controllers, by session key.
final class SessionScrolls {
  final _byKey = <int, ScrollController>{};

  /// Session [key]'s controller, made the first time it is shown.
  ScrollController of(int key) =>
      _byKey[key] ??= ScrollController(follow: Follow.bottom);

  /// A cleared session starts at its new transcript's end: a new
  /// controller, the old one disposed.
  ScrollController cleared(int key) {
    _byKey.remove(key)?.dispose();
    return of(key);
  }

  /// Session [key] closed: its controller goes.
  void closed(int key) => _byKey.remove(key)?.dispose();

  /// Session [key]'s controller where it has been shown; none is made.
  ScrollController? made(int key) => _byKey[key];

  /// The sessions with a controller.
  Iterable<int> get keys => _byKey.keys;

  /// The window goes: every controller with it.
  void dispose() {
    for (final controller in _byKey.values) {
      controller.dispose();
    }
    _byKey.clear();
  }
}
