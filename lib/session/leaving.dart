/// One way out of a process that runs agents with no window, and what a
/// crash or a signal waits to close before chord exits, as a quit closes
/// it, from the original's `session/leaving.ts`.
library;

import 'dart:async';
import 'dart:io';

import '../acp/process.dart';
import '../platform/process.dart';

/// The closes chord owns: what a quit closes and reaps, which a forced exit
/// must close too, or the agents outlive chord, a hung one never getting
/// its SIGKILL.
final class Owned {
  final _closes = <Future<void> Function()>{};

  /// Has a crash or a signal wait for [close] before chord exits, until the
  /// returned function is called. [close] must settle within its own
  /// bounds, as the exit waits for nothing else.
  void Function() closeOnForcedExit(Future<void> Function() close) {
    // An entry of its own, so one close given twice is owned twice.
    Future<void> entry() => close();
    _closes.add(entry);
    return () => _closes.remove(entry);
  }

  /// Starts all that is owned, which is then no longer owned, and gives each
  /// close's future for whoever is leaving to wait for.
  List<Future<void>> closeOwned() {
    // Taken out before any runs: a close may forget itself or another.
    final closes = [..._closes];
    _closes.clear();
    return [for (final close in closes) Future.sync(close)];
  }
}

/// chord's own.
final owned = Owned();

Future<void>? _leaving;

/// Closes all that [from] owns while [giveBack] gives the terminal back,
/// waits for both however they go, then sends SIGKILL to every group
/// [groups] still holds. A leave already under way is joined, not started
/// again: its closes are no longer owned, so a second one would find
/// nothing to wait for.
Future<void> leave({
  Owned? from,
  ProcessGroups? groups,
  Future<void> Function()? giveBack,
}) => _leaving ??= () async {
  try {
    final closing = (from ?? owned).closeOwned();
    await Future.wait([
      for (final future in [
        if (giveBack != null) Future.sync(giveBack),
        ...closing,
      ])
        future.then((_) {}, onError: (_) {}),
    ]);
    (groups ?? ProcessGroups.instance).killAll();
  } finally {
    _leaving = null;
  }
}();

/// One agent takes at most 6 s to stop, and a conversation awaits its tasks
/// before its own session, so a hung task and a hung main take 12 s.
const leaveTime = Duration(seconds: 15);

/// The most the answers to a client that may not be reading are waited for.
const drainTime = Duration(milliseconds: 500);

/// What started the way out of a process that runs agents with no window.
sealed class LeaveReason {
  const LeaveReason();
}

/// The client closed stdin, or went.
final class LeaveEof extends LeaveReason {
  /// The one end of input.
  const LeaveEof();
}

/// The connection can no longer serve: an oversized line, stdout gone.
final class LeaveBroken extends LeaveReason {
  /// The one broken connection.
  const LeaveBroken();
}

/// chord's own failure; the client is still there to be answered.
final class LeaveCrash extends LeaveReason {
  /// The one crash.
  const LeaveCrash();
}

/// A signal chord leaves on, and dies by.
final class LeaveSignal extends LeaveReason {
  /// The way out [signal] started.
  const LeaveSignal(this.signal);

  /// The signal to die by.
  final ProcessSignal signal;
}

/// How the process ends: an exit [code], or death by [signal].
final class LeaveExit {
  /// An exit with [code].
  const LeaveExit.code(int this.code) : signal = null;

  /// Death by [signal].
  const LeaveExit.signal(ProcessSignal this.signal) : code = null;

  /// The exit code, unless it dies by a signal.
  final int? code;

  /// The signal it dies by, unless it exits with a code.
  final ProcessSignal? signal;

  @override
  bool operator ==(Object other) =>
      other is LeaveExit && other.code == code && other.signal == signal;

  @override
  int get hashCode => Object.hash(code, signal);

  @override
  String toString() => code != null ? 'exit $code' : 'signal $signal';
}

/// Something to settle on the way out, beside the rest.
final class LeaveStep {
  /// A step called [name] that runs [run].
  const LeaveStep(this.name, this.run);

  /// Named on stderr when it failed, or had not settled at the deadline.
  final String name;

  /// Settles the step.
  final FutureOr<void> Function() run;
}

/// The one way out of a process that runs agents with no window, once,
/// whatever starts it, inside one deadline: the original's `createLeaving`.
final class Leaving {
  /// A way out that, once started, calls [answer] on a signal or a crash
  /// only, then in one tick waits [drained] at most [drainTime] before
  /// [closeConnection], beside every step [steps] gives; then SIGKILL to
  /// what [groups] still holds, and [exit]. [stderr] tells the person and
  /// must not throw into the way out.
  Leaving({
    required this._answer,
    required this._drained,
    required this._closeConnection,
    required this._steps,
    required this._stderr,
    required this._exit,
    this._groups,
    this._leaveTime = leaveTime,
    this._drainTime = drainTime,
  });

  final void Function() _answer;
  final Future<void> Function() _drained;
  final FutureOr<void> Function() _closeConnection;
  final List<LeaveStep> Function() _steps;
  final void Function(String line) _stderr;
  final void Function(LeaveExit how) _exit;
  final ProcessGroups? _groups;
  final Duration _leaveTime;
  final Duration _drainTime;

  Completer<void>? _leaving;

  /// New work is refused from the moment this holds.
  bool get started => _leaving != null;

  /// Runs it, once; a later call gets the first one's future.
  Future<void> leave(LeaveReason reason) {
    final running = _leaving;
    if (running != null) return running.future;
    // Held before it runs: what it calls may ask or start it again.
    final leaving = _leaving = Completer<void>();
    _run(reason, leaving);
    return leaving.future;
  }

  void _say(String line) {
    try {
      _stderr(line);
    } catch (_) {
      // Nothing is left to tell, and the way out goes on.
    }
  }

  void _run(LeaveReason reason, Completer<void> leaving) {
    final groups = _groups ?? ProcessGroups.instance;
    final open = <String>[];
    final failures = <String>[];
    var ended = false;
    late final Timer deadline;

    void end(LeaveExit how) {
      ended = true;
      deadline.cancel();
      _exit(how);
      leaving.complete();
    }

    // Armed first, so nothing below can hold the process past it.
    deadline = Timer(_leaveTime, () {
      if (ended) return;
      _say('chord: not settled at the deadline: ${open.join(', ')}');
      for (final pid in groups.killAll()) {
        _say('chord: killed process group $pid');
      }
      end(_exitOf(reason, unclean: true));
    });

    void failed(String name, Object error) {
      failures.add(name);
      _say('chord: $name: ${_messageOf(error)}');
    }

    if (reason is LeaveSignal || reason is LeaveCrash) {
      try {
        _answer();
      } catch (error) {
        failed('answers', error);
      }
    }

    final connection = LeaveStep('connection', () async {
      final drain = await settledWithin(Future.sync(_drained), _drainTime);
      // Out of time is the drain's best effort; a failure is a failure, and
      // the connection is closed all the same.
      if (drain case Rejected(:final error)) failed('drain', error);
      await _closeConnection();
    });
    final steps = [connection, ..._steps()];

    // Each starts here, in this one tick, so a hung one holds up none of the
    // rest, and a failed one is kept beside what the others do.
    final settled = [
      for (final step in steps)
        () async {
          open.add(step.name);
          try {
            await step.run();
          } catch (error) {
            failed(step.name, error);
          }
          open.remove(step.name);
        }(),
    ];
    Future.wait(settled).then((_) {
      if (ended) return;
      groups.killAll();
      end(_exitOf(reason, unclean: failures.isNotEmpty));
    });
  }
}

LeaveExit _exitOf(LeaveReason reason, {required bool unclean}) =>
    switch (reason) {
      LeaveSignal(:final signal) => LeaveExit.signal(signal),
      LeaveEof() when !unclean => const LeaveExit.code(0),
      _ => const LeaveExit.code(1),
    };

String _messageOf(Object error) => switch (error) {
  StateError(:final message) => message,
  ArgumentError(:final message) => '$message',
  Exception() => '$error'.replaceFirst(RegExp(r'^\w*Exception: '), ''),
  _ => '$error',
};
