import 'dart:async';
import 'dart:io';
import 'package:chord_tui/chord_tui.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

class ModeTerminal extends StdioTerminal {
  final writes = <String>[];
  String? failOn;
  final failure = StateError('mode write failed');
  @override
  void write(String bytes) {
    writes.add(bytes);
    if (bytes == failOn) {
      failOn = null;
      throw failure;
    }
    super.write(bytes);
  }
}

Future<void> main(List<String> args) async {
  final scenario = args.single;
  final before = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
  final terminal = ModeTerminal();
  var expected = 2;
  try {
    if (scenario.startsWith('startup_')) {
      final mode = int.parse(scenario.substring('startup_'.length));
      terminal.failOn =
          '\x1b[?$mode'
          'h';
      Object? failure;
      try {
        terminal.enter();
      } catch (error) {
        failure = error;
      }
      check(identical(failure, terminal.failure), 'startup failure identity');
      await terminal.leave();
      check(
        terminal.writes.where((s) => s == '\x1b[?1000l').length == 1,
        'partial tracking released',
      );
      check(
        terminal.writes.where((s) => s == '\x1b[?1002l').length ==
            (mode >= 1002 ? 1 : 0),
        'only attempted motion released',
      );
      check(
        terminal.writes.where((s) => s == '\x1b[?1006l').length ==
            (mode == 1006 ? 1 : 0),
        'only attempted SGR released',
      );
    } else {
      terminal.enter();
      terminal.enter();
      if (scenario == 'release_failure' || scenario == 'release_1002_failure') {
        expected = 1;
        terminal.failOn = scenario == 'release_failure'
            ? '\x1b[?1000l'
            : '\x1b[?1002l';
        Object? failure;
        try {
          await terminal.leave();
        } catch (error) {
          failure = error;
        }
        check(identical(failure, terminal.failure), 'release failure identity');
        check(
          terminal.writes.contains('\x1b[?1002l') &&
              terminal.writes.contains('\x1b[?1006l') &&
              terminal.writes.contains('\x1b[?2004l') &&
              terminal.writes.contains('\x1b[?1049l'),
          'remaining restoration attempted',
        );
      } else if (scenario == 'leave_suspended' ||
          scenario == 'close_suspended') {
        expected = 1;
        final started = Completer<void>(), release = Completer<void>();
        final operation = terminal.suspend(() async {
          terminal.writes.add('CHILD');
          started.complete();
          await release.future;
        });
        await started.future;
        final leaving = scenario == 'close_suspended'
            ? terminal.close()
            : terminal.leave();
        release.complete();
        await operation;
        await leaving;
      } else {
        Object? caught;
        try {
          await terminal.suspend(() async {
            terminal.writes.add('CHILD');
            check(
              terminal.writes.indexOf('\x1b[?1000l') <
                  terminal.writes.indexOf('CHILD'),
              'tracking off before child',
            );
            check(
              terminal.writes.indexOf('\x1b[?1002l') <
                  terminal.writes.indexOf('CHILD'),
              'motion off before child',
            );
            check(
              terminal.writes.indexOf('\x1b[?1006l') <
                  terminal.writes.indexOf('CHILD'),
              'SGR off before child',
            );
            if (scenario == 'restore_failure') terminal.failOn = '\x1b[?1006h';
            if (scenario == 'restore_1002_failure') {
              terminal.failOn = '\x1b[?1002h';
            }
            if (scenario == 'callback_failure') throw terminal.failure;
          });
        } catch (error) {
          caught = error;
        }
        if (scenario == 'callback_failure' || scenario.startsWith('restore_')) {
          check(
            identical(caught, terminal.failure),
            'callback/restore error preserved',
          );
        } else {
          check(caught == null, 'normal callback');
        }
        await terminal.leave();
      }
      for (final mode in [1000, 1002, 1006]) {
        final count = scenario == 'restore_1002_failure' && mode == 1006
            ? 1
            : expected;
        check(
          terminal.writes
                  .where(
                    (s) =>
                        s ==
                        '\x1b[?$mode'
                            'h',
                  )
                  .length ==
              count,
          'one enable per acquisition',
        );
        check(
          terminal.writes
                  .where(
                    (s) =>
                        s ==
                        '\x1b[?$mode'
                            'l',
                  )
                  .length ==
              count,
          'one disable per acquisition',
        );
      }
    }
    await terminal.leave();
  } finally {
    await terminal.close();
  }
  final after = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
  check(before == after, 'exact termios');
  stdout.writeln('MOUSE_MODE_PASS=$scenario');
}
