import 'dart:async';
import 'package:chord/shell.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/terminal.dart';
import 'package:test/test.dart';

class _Process extends ShellProcess {
  final done = Completer<ShellEnd>();
  var stops = 0;
  @override
  Future<ShellEnd> get ended => done.future;
  @override
  void stop() {
    stops++;
  }
}

void main() {
  test(
    'one process per session; old output and end cannot target a replacement',
    () async {
      final events = <(Object, TranscriptAction)>[],
          processes = <_Process>[],
          options = <ShellOptions>[];
      final commands = ShellCommands(
        onAction: (key, action) => events.add((key, action)),
        runner: (script, opts) {
          expect(script, anyOf('one', 'two'));
          options.add(opts);
          final process = _Process();
          processes.add(process);
          return process;
        },
      );
      expect(commands.run('session', 'one', cwd: '.'), isTrue);
      expect(commands.run('session', 'two', cwd: '.'), isFalse);
      options.first.onOutput!(ShellStream.stdout, 'first');
      commands.retire('session');
      expect(processes.first.stops, 1);
      expect(commands.run('session', 'two', cwd: '.'), isTrue);
      final count = events.length;
      options.first.onOutput!(ShellStream.stderr, 'old');
      processes.first.done.complete(const ShellEnd(code: 1));
      await Future<void>.delayed(Duration.zero);
      expect(events.length, count);
      options.last.onOutput!(ShellStream.stderr, 'new');
      processes.last.done.complete(const ShellEnd(code: 0));
      await commands.close();
      expect(events.where((e) => e.$2 is ShellOutputAction).length, 2);
      expect(events.every((e) => e.$1 == 'session'), isTrue);
    },
  );
  test(
    'stop during synchronous launch and reentrant close retain cleanup barrier',
    () async {
      final process = _Process();
      late final ShellCommands commands;
      Future<void>? closing;
      commands = ShellCommands(
        onAction: (_, action) {
          if (action is ShellOutputAction) closing = commands.close();
        },
        runner: (_, options) {
          options.onOutput!(ShellStream.stdout, 'start');
          return process;
        },
      );
      expect(commands.run('s', 'script', cwd: '.'), isTrue);
      expect(process.stops, 1);
      var finished = false;
      closing!.then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(commands.run('s', 'later', cwd: '.'), isFalse);
      process.done.complete(const ShellEnd(stopped: true));
      await closing;
      expect(finished, isTrue);
      expect(commands.close(), same(closing));
    },
  );
  test(
    'retiring from started prevents launch; stop from started is remembered',
    () async {
      late final ShellCommands commands;
      var launches = 0;
      final process = _Process();
      commands = ShellCommands(
        onAction: (key, action) {
          if (action is ShellStartedAction) {
            if (key == 'retired') {
              commands.retire(key);
            } else {
              commands.stop(key);
            }
          }
        },
        runner: (_, _) {
          launches++;
          return process;
        },
      );
      expect(commands.run('retired', 'script', cwd: '.'), isFalse);
      expect(launches, 0);
      expect(commands.run('stopped', 'script', cwd: '.'), isTrue);
      expect(process.stops, 1);
      process.done.complete(const ShellEnd(stopped: true));
      await commands.close();
    },
  );
}
