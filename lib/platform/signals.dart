/// How chord dies by a signal it leaves on, from the original's `main.tsx`:
/// what it owns closed first, then the signal raised with no handler left.
library;

import 'dart:async';
import 'dart:io';

/// The signals chord leaves on, as CTUI-12's way out names them: the
/// terminal's own never reach an agent in a session of its own.
const leaveSignals = [
  ProcessSignal.sigterm,
  ProcessSignal.sigint,
  ProcessSignal.sighup,
];

/// Has every signal of [signals] run [leave], then [raise] the first one
/// with the handlers off, so chord dies by it as it would have without
/// them. A signal that comes while the leave is under way is held: let
/// through, its default action would kill chord before a hung agent's
/// SIGKILL. A [leave] that fails still raises the signal. Returns the
/// function that takes the handlers off.
void Function() dieBySignal(
  Future<void> Function() leave, {
  List<ProcessSignal> signals = leaveSignals,
  Stream<ProcessSignal> Function(ProcessSignal signal)? watch,
  void Function(ProcessSignal signal) raise = raiseSignal,
}) {
  ProcessSignal? first;
  late final List<StreamSubscription<ProcessSignal>> subscriptions;
  void off() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  }

  subscriptions = [
    for (final signal in signals)
      (watch ?? (signal) => signal.watch())(signal).listen((_) async {
        if (first != null) return;
        first = signal;
        // As the original's leave, which settles however it went: a failure
        // here would hold the signal, and chord would live on unseen.
        try {
          await leave();
        } catch (_) {}
        off();
        raise(signal);
      }),
  ];
  return off;
}

/// Dies by [signal]: sent to chord itself with no handler left, and, should
/// it still be running a moment later, the exit a shell would show for it.
void raiseSignal(ProcessSignal signal) {
  Process.killPid(pid, signal);
  Timer(
    const Duration(milliseconds: 500),
    () => exit(128 + signal.signalNumber),
  );
}
