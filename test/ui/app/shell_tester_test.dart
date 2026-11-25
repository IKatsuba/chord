import 'dart:async';

import 'package:chord/session/transcript/types.dart';
import 'package:chord/shell.dart';
import 'package:chord/ui/app/terminal.dart';
import 'package:test/test.dart';

class _Process extends ShellProcess {
  final done = Completer<ShellEnd>();
  int stops = 0;
  @override
  Future<ShellEnd> get ended => done.future;
  @override
  void stop() => stops++;
}

void main() {
  group(
    'tester: local commands retain session ownership through retirement',
    () {
      test(
        'close waits for retired and concurrent runs and rejects late actions',
        () async {
          final events = <(Object, TranscriptAction)>[];
          final processes = <_Process>[];
          final outputs = <ShellOptions>[];
          final commands = ShellCommands(
            onAction: (session, action) => events.add((session, action)),
            runner: (_, options) {
              outputs.add(options);
              final process = _Process();
              processes.add(process);
              return process;
            },
          );
          expect(commands.run('a', 'first', cwd: 'one'), isTrue);
          expect(commands.run('b', 'second', cwd: 'two'), isTrue);
          commands.retire('a');
          expect(commands.run('a', 'replacement', cwd: 'three'), isTrue);
          expect(outputs.map((o) => o.cwd), ['one', 'two', 'three']);
          outputs[0].onOutput!(ShellStream.stdout, 'retired');
          outputs[1].onOutput!(ShellStream.stderr, 'current');
          expect(events.where((e) => e.$2 is ShellOutputAction).single.$1, 'b');
          final closing = commands.close();
          expect(commands.close(), same(closing));
          final count = events.length;
          var finished = false;
          unawaited(closing.then((_) => finished = true));
          for (final output in outputs) {
            output.onOutput!(ShellStream.stdout, 'late');
          }
          processes[1].done.complete(const ShellEnd(stopped: true));
          processes[2].done.complete(const ShellEnd(stopped: true));
          await Future<void>.delayed(Duration.zero);
          expect(finished, isFalse, reason: 'retired run still owns cleanup');
          processes[0].done.complete(const ShellEnd(stopped: true));
          await closing;
          expect(finished, isTrue);
          expect(events, hasLength(count));
          expect(processes.map((p) => p.stops), [1, 1, 1]);
          expect(commands.run('b', 'closed', cwd: '.'), isFalse);
        },
      );

      test(
        'retirement and replacement inside launch cannot inherit old output',
        () async {
          late final ShellCommands commands;
          final old = _Process(), replacement = _Process();
          final actions = <TranscriptAction>[];
          ShellOptions? oldOptions;
          commands = ShellCommands(
            onAction: (_, action) => actions.add(action),
            runner: (script, options) {
              if (script == 'old') {
                oldOptions = options;
                commands.retire('session');
                expect(commands.run('session', 'new', cwd: '.'), isTrue);
                return old;
              }
              return replacement;
            },
          );
          expect(commands.run('session', 'old', cwd: '.'), isTrue);
          expect(old.stops, 1);
          oldOptions!.onOutput!(ShellStream.stdout, 'obsolete');
          old.done.complete(const ShellEnd(code: 3));
          await Future<void>.delayed(Duration.zero);
          expect(actions.whereType<ShellEndedAction>(), isEmpty);
          expect(actions.whereType<ShellOutputAction>(), isEmpty);
          replacement.done.complete(const ShellEnd(code: 0));
          await Future<void>.delayed(Duration.zero);
          expect(
            actions.whereType<ShellEndedAction>().single.turnId,
            actions.whereType<ShellStartedAction>().last.turnId,
          );
          await commands.close();
        },
      );

      test(
        'synchronous launch failure releases only its session slot',
        () async {
          final process = _Process();
          final events = <(Object, TranscriptAction)>[];
          final commands = ShellCommands(
            onAction: (session, action) => events.add((session, action)),
            runner: (script, _) {
              if (script == 'fail') throw StateError('cannot launch');
              return process;
            },
          );
          commands.run('other', 'running', cwd: '.');
          commands.run('broken', 'fail', cwd: '.');
          expect(commands.run('other', 'duplicate', cwd: '.'), isFalse);
          expect(
            events.where((e) => e.$2 is ShellEndedAction).single.$1,
            'broken',
          );
          process.done.complete(const ShellEnd(code: 0));
          await commands.close();
        },
      );
    },
  );
}
