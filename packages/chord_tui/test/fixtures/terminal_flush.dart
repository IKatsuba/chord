import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

/// Output whose flush never completes or fails, as a terminal gone away.
class DeadOutput implements IOSink {
  DeadOutput(this.failure);
  final Object? failure;
  var flushes = 0;
  @override
  void add(List<int> data) {}
  @override
  Future<void> flush() {
    flushes++;
    final error = failure;
    return error == null ? Completer<void>().future : Future.error(error);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Object?> settle(Future<void> Function() step) async {
  try {
    await step();
    return null;
  } catch (error) {
    return error;
  }
}

Future<void> main(List<String> args) async {
  final scenario = args.single;
  final before = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
  final broken = StateError('output failed');
  final output = DeadOutput(scenario.endsWith('error') ? broken : null);
  const deadline = Duration(milliseconds: 200);
  final terminal = StdioTerminal(
    input: const Stream.empty(),
    output: output,
    flushDeadline: deadline,
  );
  bool expected(Object? failure) => scenario.endsWith('error')
      ? identical(failure, broken)
      : failure is TimeoutException;
  final clock = Stopwatch()..start();
  terminal.enter();
  switch (scenario) {
    case 'leave_hang' || 'leave_error':
      final failure = await settle(terminal.leave);
      check(expected(failure), 'leave reports the flush: $failure');
    case 'suspend_hang' || 'suspend_error':
      var called = false;
      final failure = await settle(
        () => terminal.suspend(() async => called = true),
      );
      check(expected(failure), 'suspend reports the flush: $failure');
      check(!called, 'callback needs a released terminal');
      await settle(terminal.leave);
  }
  check(
    clock.elapsed < const Duration(seconds: 3),
    'bounded: ${clock.elapsed}',
  );
  check(output.flushes > 0, 'flushed');
  final after = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
  check(before == after, 'raw mode restored despite the flush');
  await terminal.close();
  stdout.writeln('FLUSH_PASS=$scenario');
}
