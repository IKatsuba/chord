import 'dart:async';
import 'dart:io';

import 'package:chord/ui/app/crash_screen.dart';
import 'package:chord/ui/app/renderer.dart';
import 'package:chord_tui/chord_tui.dart';

class _Terminal extends Terminal {
  final source = StreamController<String>();
  bool restored = false;
  bool sent = false;
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => source.stream;
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() {}
  @override
  Future<void> leave() async {
    restored = true;
    stdout.writeln('RESTORED');
  }

  @override
  void write(String data) {
    if (data == '\x1b]11;?\x07') source.add('\x1b]11;rgb:0000/0000/0000\x07');
    if (!sent && data.contains('any key to quit')) {
      sent = true;
      source.add('x');
    }
  }
}

Future<void> main() async {
  final terminal = _Terminal();
  final failure = WindowCrash();
  await runApp(
    CrashBoundary(
      onCrash: failure.caught,
      child: Builder(
        builder: (_) => Error.throwWithStackTrace(
          StateError('window failed'),
          StackTrace.fromString('#0 Throws (fixture.dart:1:1)'),
        ),
      ),
    ),
    terminal: terminal,
    beforeExit: () async {
      if (!terminal.restored) throw StateError('terminal was not restored');
      stderr.writeln('OWNED_CLOSED');
      failure.rethrowIfCaught();
    },
  );
}
