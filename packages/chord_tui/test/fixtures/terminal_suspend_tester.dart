import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

void _check(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

String _modes() =>
    (Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout as String)
        .trim();

class _Terminal extends StdioTerminal {
  final writes = <String>[];
  @override
  void write(String bytes) {
    writes.add(bytes);
    super.write(bytes);
  }
}

Future<void> main(List<String> args) async {
  final scenario = args.single;
  final before = _modes();
  final states = <TerminalState>[];
  final terminal = _Terminal();
  final subscription = terminal.states.listen(states.add);
  try {
    terminal.enter();
    if (scenario == 'close_after_failure') {
      final began = Completer<void>();
      final release = Completer<void>();
      final original = StateError('owned callback failed');
      final operation = terminal.suspend<void>(() async {
        _check(
          _modes() == before,
          'callback starts after exact mode restoration',
        );
        began.complete();
        await release.future;
        throw original;
      });
      await began.future;
      final leaving = terminal.leave();
      final closing = terminal.close();
      var called = false;
      try {
        await terminal.suspend(() async {
          called = true;
        });
      } on StateError {
        // The closing terminal may not lend ownership again.
      }
      _check(!called, 'close rejects another callback');
      release.complete();
      Object? failure;
      try {
        await operation;
      } catch (error) {
        failure = error;
      }
      await leaving;
      await closing;
      _check(
        identical(failure, original),
        'callback error survives close race',
      );
      _check(
        states.where((s) => s == TerminalState.active).length == 1,
        'close suppresses reentry',
      );
      _check(states.last == TerminalState.inactive, 'close leaves inactive');
    } else {
      for (var i = 0; i < 3; i++) {
        final result = await terminal.suspend<int>(() async {
          _check(
            _modes() == before,
            'callback modes match original on every cycle',
          );
          _check(
            states.last == TerminalState.suspended,
            'suspended state before callback',
          );
          return i + 40;
        });
        _check(result == i + 40, 'generic callback value');
        _check(states.last == TerminalState.active, 'active after every cycle');
        await terminal.leave();
        _check(_modes() == before, 'leave modes match original on every cycle');
        terminal.enter();
      }
      await terminal.leave();
      _check(
        states.where((s) => s == TerminalState.suspended).length == 3,
        'one suspension event per cycle',
      );
    }
    _check(_modes() == before, 'final exact modes');
  } finally {
    await terminal.close();
    await subscription.cancel();
  }
  _check(
    terminal.writes.where((s) => s.contains('?1049h')).length ==
        terminal.writes.where((s) => s.contains('?1049l')).length,
    'balanced screen ownership',
  );
  stdout.writeln('TESTER_SUSPEND_PASS=$scenario');
}
