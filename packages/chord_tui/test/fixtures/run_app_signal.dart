// runApp handling signals on a terminal of its own, for
// run_app_signal_test.dart, which sends SIGTERM once `ready` is said.
// `self`: nobody else watches the signal. `owner`: another listener takes
// the re-raised signal, then ends the process by it, which it can do only
// if runApp waits for it before exiting. `ignored`: another listener takes
// the re-raised signal and does nothing.
import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

class _Terminal extends Terminal {
  final _input = StreamController<String>();
  var _ready = false;

  @override
  Size get size => const Size(20, 2);

  @override
  Stream<String> get input => _input.stream;

  @override
  Stream<Size> get resizes => const Stream.empty();

  @override
  void enter() {}

  @override
  Future<void> leave() async {}

  @override
  void write(String data) {
    if (data.isEmpty || data == '\x1b]11;?\x07' || _ready) return;
    _ready = true;
    stdout.writeln('ready');
  }
}

Future<void> main(List<String> args) async {
  final [how] = args;
  if (how != 'self') {
    var seen = 0;
    late final StreamSubscription<ProcessSignal> other;
    other = ProcessSignal.sigterm.watch().listen((signal) async {
      // The first is the one sent to runApp; the second, its re-raise.
      if (++seen < 2 || how == 'ignored') return;
      await other.cancel();
      Process.killPid(pid, signal);
    });
  }
  await runApp(Text('app'), terminal: _Terminal(), environment: const {});
}
