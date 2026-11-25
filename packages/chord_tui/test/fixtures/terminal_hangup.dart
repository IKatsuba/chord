import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

/// Output that never drains, as a terminal that hung up takes nothing.
class DeadOutput implements IOSink {
  @override
  void add(List<int> data) {}
  @override
  Future<void> flush() => Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An app on a pty that the test closes. `owner`: runApp leaves SIGHUP to
/// an embedder whose handler takes 700 ms before it dies by the signal, as
/// chord's way out does while it closes its agents. `self`: runApp handles
/// signals. `silent`: the embedder takes SIGHUP and never ends the process.
Future<void> main(List<String> args) async {
  final scenario = args.single;
  if (scenario != 'self') {
    late final StreamSubscription<ProcessSignal> owner;
    owner = ProcessSignal.sighup.watch().listen((signal) async {
      if (scenario == 'silent') return;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await owner.cancel();
      Process.killPid(pid, signal);
      Timer(const Duration(milliseconds: 500), () => exit(129));
    });
  }
  var ready = false;
  await runApp(
    // Built only once runApp has the tty raw and its input subscribed, so
    // the test closes the pty under an app that can see the hang-up.
    Builder(
      builder: (context) {
        if (!ready) {
          ready = true;
          stdout.writeln('HANGUP_READY');
        }
        return Text('hang up here');
      },
    ),
    terminal: StdioTerminal(
      output: DeadOutput(),
      flushDeadline: const Duration(milliseconds: 200),
      mouse: false,
    ),
    handleSignals: scenario == 'self',
  );
}
