/// A future kept to be awaited later, from whatever error zone (CTUI-114).
library;

import 'dart:async';

import 'package:async/async.dart' show Result;

/// A future kept for later waits, its outcome taken in the zone that made
/// it. An error does not cross error zones: awaited from another, a future
/// that failed never resumes its waiter, so a close the window's zone began
/// would hold a signal's way out for ever. A waiter in the zone that made it
/// gets the future itself; one in another, a future of its own zone that
/// settles as it did.
final class Kept<T> {
  /// Keeps [future], which the current zone must have made.
  Kept(Future<T> future)
    : _future = future,
      _zone = Zone.current,
      _outcome = Result.capture(future);

  final Future<T> _future;
  final Zone _zone;
  final Future<Result<T>> _outcome;

  /// The kept future, as the calling zone can hear it.
  Future<T> get future =>
      Zone.current.inSameErrorZone(_zone) ? _future : Result.release(_outcome);
}
