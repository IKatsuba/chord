import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

import 'terminal_flush.dart' show check;

/// A delayed first flush followed by a usable output sink.
class DelayedOutput implements IOSink {
  final first = Completer<void>();
  var flushes = 0;
  @override
  void add(List<int> data) {}
  @override
  Future<void> flush() => ++flushes == 1 ? first.future : Future.value();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main(List<String> args) async {
  final scenario = args.single;
  final output = DelayedOutput();
  final terminal = scenario == 'default_deadline'
      ? StdioTerminal(input: const Stream.empty(), output: output)
      : StdioTerminal(
          input: const Stream.empty(),
          output: output,
          flushDeadline: Duration.zero,
        );
  check(
    terminal.flushDeadline ==
        (scenario == 'default_deadline'
            ? const Duration(seconds: 1)
            : Duration.zero),
    'uses the documented deadline',
  );
  final before = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
  final states = <TerminalState>[];
  final subscription = terminal.states.listen(states.add);
  terminal.enter();
  final clock = Stopwatch()..start();
  final first = terminal.leave();
  final second = terminal.leave();
  check(identical(first, second), 'concurrent leave shares its completion');
  final results = await Future.wait([
    for (final leaving in [first, second])
      leaving.then<Object?>((_) => null, onError: (Object error) => error),
  ]);
  check(
    results.every((error) => error is TimeoutException),
    'both callers fail',
  );
  check(output.flushes == 1, 'one flush for concurrent callers');
  check(clock.elapsed < const Duration(seconds: 3), 'release is bounded');
  check(
    before == Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout,
    'raw mode restored before failure reaches callers',
  );
  if (scenario == 'late_error') {
    output.first.completeError(StateError('late flush failure'));
  } else {
    output.first.complete();
  }
  await Future<void>.delayed(Duration.zero);
  terminal.enter();
  await terminal.leave();
  check(output.flushes == 2, 'a failed release permits the next run');
  check(
    states.join(',') ==
        [
          TerminalState.active,
          TerminalState.inactive,
          TerminalState.active,
          TerminalState.inactive,
        ].join(','),
    'ownership remains coherent after late completion',
  );
  check(
    before == Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout,
    'reused terminal restores raw mode',
  );
  await subscription.cancel();
  await terminal.close();
  stdout.writeln('TESTER_FLUSH_PASS=$scenario');
}
