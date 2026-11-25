// Tester-owned signal and cleanup probes, without a real terminal.
import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

class _Terminal extends Terminal {
  final _input = StreamController<String>();
  var _ready = false;

  @override
  Size get size => const Size(80, 24);

  @override
  Stream<String> get input => _input.stream;

  @override
  Stream<Size> get resizes => const Stream.empty();

  @override
  void enter() {}

  @override
  Future<void> leave() async => stdout.writeln('left');

  @override
  void write(String data) {
    if (data.isEmpty || data == '\x1b]11;?\x07' || _ready) return;
    _ready = true;
    stdout.writeln('ready');
  }
}

Future<void> main(List<String> args) async {
  final signal = switch (args[0]) {
    'hup' => ProcessSignal.sighup,
    'int' => ProcessSignal.sigint,
    _ => ProcessSignal.sigterm,
  };
  var cleaned = false;
  var seen = 0;
  late final StreamSubscription<ProcessSignal> owner;
  owner = signal.watch().listen((received) async {
    if (++seen < 2) return;
    if (!cleaned) exit(91);
    stdout.writeln('reraised after cleanup');
    if (args[1] == 'ignored') return;
    await owner.cancel();
    Process.killPid(pid, received);
  });
  await runApp(
    Text('signal probe'),
    terminal: _Terminal(),
    environment: const {},
    beforeExit: () async {
      stdout.writeln('cleanup started');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cleaned = true;
      stdout.writeln('cleanup ended');
    },
  );
}
