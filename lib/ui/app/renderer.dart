/// How chord's window leaves on a signal or a crash, from the original's
/// `ui/app/renderer.tsx`: what it owns closed and the terminal given back
/// first, then it dies as it would have.
library;

import 'dart:async';
import 'dart:io';

/// An uncaught error's way out: [leave], then [error] and [stack] on
/// stderr, after the terminal is given back, and exit 1.
Future<Never> crash(
  Object error,
  StackTrace stack,
  Future<void> Function() leave,
) async {
  await leave();
  stderr
    ..writeln(error)
    ..writeln(stack);
  await stderr.flush();
  exit(1);
}

/// A drawing failure retained outside the unmounted window until owned shutdown.
final class WindowCrash {
  Object? _error;
  StackTrace? _stack;

  /// Remembers the first drawing failure without writing over the terminal.
  void caught(Object error, StackTrace stack) {
    if (_error != null) return;
    _error = error;
    _stack = stack;
  }

  /// Rethrows the original failure from the post-restore, post-shutdown hook.
  void rethrowIfCaught() {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _stack!);
  }
}
