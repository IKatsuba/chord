// What the original's fake takes from the JavaScript runtime: AbortSignal,
// AbortController and their timers, so the plays read as the original's.
import 'dart:async';

/// The reason an aborted signal gives when it was given none, as a
/// DOMException `AbortError` is.
final class AbortError implements Exception {
  const AbortError([this.message = 'This operation was aborted']);

  final String message;

  @override
  String toString() => 'AbortError: $message';
}

/// A signal that aborts once, with a reason, telling its listeners.
final class Signal {
  Signal._();

  /// A signal aborted already, with [reason].
  factory Signal.aborted([Object? reason]) =>
      Signal._().._abort(reason ?? const AbortError());

  bool _aborted = false;
  Object? _reason;
  final _listeners = <void Function()>[];

  bool get aborted => _aborted;
  Object? get reason => _reason;

  /// Throws the reason when aborted.
  void throwIfAborted() {
    if (_aborted) throw _reason!;
  }

  /// Calls [listener] once on the abort; returns what removes it.
  void Function() onAbort(void Function() listener) {
    if (_aborted) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _abort(Object? reason) {
    if (_aborted) return;
    _aborted = true;
    _reason = reason ?? const AbortError();
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  /// Aborts once any of [signals] does, with its reason.
  static Signal any(List<Signal> signals) {
    final any = Signal._();
    for (final signal in signals) {
      if (signal.aborted) return any.._abort(signal.reason);
    }
    final removes = <void Function()>[];
    for (final signal in signals) {
      removes.add(
        signal.onAbort(() {
          any._abort(signal.reason);
          for (final remove in removes) {
            remove();
          }
        }),
      );
    }
    return any;
  }

  /// Aborts after [ms], as `AbortSignal.timeout` does. Node never waits
  /// on such a timer to exit; here [cancelTimeouts] ends those left.
  static Signal timeout(int ms) {
    final signal = Signal._();
    late final Timer timer;
    timer = Timer(Duration(milliseconds: ms), () {
      _timeouts.remove(timer);
      signal._abort(const AbortError('The operation timed out.'));
    });
    _timeouts.add(timer);
    return signal;
  }
}

/// The timers of [Signal.timeout] still to fire.
final _timeouts = <Timer>{};

/// Cancels every [Signal.timeout] still to fire, so none keeps the process
/// alive once its client has gone, as none does in Node.
void cancelTimeouts() {
  for (final timer in _timeouts) {
    timer.cancel();
  }
  _timeouts.clear();
}

/// An AbortController: its [signal], and [abort].
final class Aborter {
  final Signal signal = Signal._();

  void abort([Object? reason]) => signal._abort(reason);
}

/// Completes once [signal] aborts; fails with [unless]'s reason if [unless]
/// aborts first, as `once(signal, 'abort', {signal: unless})` does.
Future<void> untilAborted(Signal signal, {Signal? unless}) {
  if (unless != null && unless.aborted) return Future.error(unless.reason!);
  final done = Completer<void>();
  void Function()? removeUnless;
  final remove = signal.onAbort(() {
    removeUnless?.call();
    if (!done.isCompleted) done.complete();
  });
  removeUnless = unless?.onAbort(() {
    remove();
    if (!done.isCompleted) done.completeError(unless.reason!);
  });
  return done.future;
}

/// [ms] on, or the abort of [signal] first, failing with its reason.
Future<void> sleep(Signal signal, int ms) {
  if (signal.aborted) return Future.error(signal.reason!);
  final done = Completer<void>();
  late final void Function() remove;
  final timer = Timer(Duration(milliseconds: ms), () {
    remove();
    done.complete();
  });
  remove = signal.onAbort(() {
    timer.cancel();
    done.completeError(signal.reason!);
  });
  return done.future;
}

/// Runs [callback] after [ms], as `setTimeout` does; zero is the next turn
/// of the event loop.
Timer later(int ms, void Function() callback) =>
    Timer(Duration(milliseconds: ms < 0 ? 0 : ms), callback);

/// A monotonic clock in milliseconds, as `performance.now()`.
final Stopwatch _clock = Stopwatch()..start();

/// Milliseconds since the fake started, on a monotonic clock.
double now() => _clock.elapsedMicroseconds / 1000;
