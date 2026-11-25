import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Match StdioTerminal's decoded source subscription: the child must receive
// its line without that line replaying into the app after source resume.
Future<void> main() async {
  final first = Completer<void>();
  final resumed = Completer<void>();
  final seen = <String>[];
  final source = stdin
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen((data) {
        seen.add(data);
        if (data.contains('app-before')) first.complete();
        if (data.contains('app-after')) resumed.complete();
      });
  try {
    stdout.writeln('APP_READY');
    await stdout.flush();
    await first.future.timeout(const Duration(seconds: 5));
    source.pause();
    final child = await Process.start('/bin/sh', [
      '-c',
      r'''printf 'CHILD_READY\n'; IFS= read -r line; printf 'CHILD_GOT=%s\n' "$line"; test "$line" = child-only''',
    ], mode: ProcessStartMode.inheritStdio);
    final code = await child.exitCode.timeout(const Duration(seconds: 5));
    source.resume();
    stdout.writeln('APP_RESUMED');
    await stdout.flush();
    await resumed.future.timeout(const Duration(seconds: 5));
    final text = seen.join();
    stdout.writeln('PROBE_EXIT=$code');
    stdout.writeln('NO_REPLAY=${!text.contains('child-only')}');
    stdout.writeln('APP_INPUT=${text == 'app-before\napp-after\n'}');
    exitCode = code == 0 && !text.contains('child-only') ? 0 : 1;
  } finally {
    await source.cancel();
  }
}
