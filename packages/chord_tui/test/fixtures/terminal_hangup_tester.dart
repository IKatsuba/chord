import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/terminal/terminal.dart' show terminalHungUp;

/// A sink that fails or never drains, without writing to the real tty.
class BrokenOutput implements IOSink {
  BrokenOutput(this.error);
  final bool error;
  @override
  void add(List<int> data) {}
  @override
  Future<void> flush() => error
      ? Future<void>.error(StateError('tester flush failure'))
      : Completer<void>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main(List<String> args) async {
  final scenario = args.single;
  final terminal = StdioTerminal(
    input: scenario.startsWith('supplied') ? const Stream.empty() : null,
    output: BrokenOutput(scenario.endsWith('error')),
    flushDeadline: const Duration(milliseconds: 20),
  );
  final ended = Completer<void>();
  final subscription = terminal.input.listen((_) {}, onDone: ended.complete);
  if (!scenario.startsWith('open')) await ended.future;
  final before = stdin.hasTerminal
      ? Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout
      : null;
  terminal.enter();
  Object? failure;
  try {
    await terminal.leave();
  } catch (error) {
    failure = error;
  }
  if (scenario.endsWith('error')
      ? failure is! StateError
      : failure is! TimeoutException) {
    throw StateError('flush failure was lost: $failure');
  }
  if (terminalHungUp(terminal)) {
    throw StateError('ordinary input was classified as a tty hangup');
  }
  if (before != null &&
      before != Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout) {
    throw StateError('release failed to restore exact termios');
  }
  await subscription.cancel();
  await terminal.close();
  stdout.writeln('NARROW_PASS=$scenario');
}
