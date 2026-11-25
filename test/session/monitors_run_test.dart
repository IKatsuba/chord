@TestOn('posix')
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/session/monitors.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/shell.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

const _info = MonitorInfo(
  id: 'm1',
  description: 'dev server errors',
  command: 'tail -f dev.log',
  startedAt: 0,
  timeoutMs: 600000,
);

/// A command the test speaks for: [line] prints, [exit] ends it,
/// [shellExits] ends its shell with what it started still being reaped, and
/// a stop ends it as stopped, as `runShell` does once the group is gone.
final class _FakeCommand extends ShellProcess {
  _FakeCommand([this._failed]);

  final String? _failed;
  @override
  Future<String?> get failed => Future.value(_failed);
  final _ended = Completer<ShellEnd>(), _exited = Completer<ShellEnd>();
  final stops = <int>[];
  void Function(String line) _print = (_) {};

  @override
  Future<ShellEnd> get ended => _ended.future;
  @override
  Future<ShellEnd> get exited => _exited.future;

  ShellProcess run(String command, String cwd, void Function(String) onLine) {
    _print = onLine;
    return this;
  }

  void line(String text) => _print(text);

  void exit(int code, [String? signal]) {
    final end = ShellEnd(code: code, signal: signal);
    shellExits(end);
    reaped(end);
  }

  void shellExits(ShellEnd end) {
    if (!_exited.isCompleted) _exited.complete(end);
  }

  void reaped(ShellEnd end) {
    if (!_ended.isCompleted) _ended.complete(end);
  }

  @override
  void stop() {
    stops.add(clock.now().millisecondsSinceEpoch);
    shellExits(const ShellEnd(stopped: true));
    reaped(const ShellEnd(stopped: true));
  }
}

final class _Hooks implements MonitorHooks {
  final events = <List<String>>[];
  final ends = <(MonitorEnd, EventLines)>[];

  @override
  void event(EventLines lines) => events.add([...lines.lines]);

  @override
  void ended(MonitorEnd end, EventLines rest) => ends.add((end, rest));
}

/// A monitor on a fake command, with what it handed on.
({_FakeCommand command, MonitorRun monitor, _Hooks hooks}) _started(
  FakeAsync time, [
  MonitorInfo info = _info,
]) {
  final command = _FakeCommand();
  final hooks = _Hooks();
  Object? run;
  MonitorRun.start(info, hooks, '/', run: command.run).then((r) => run = r);
  time.flushMicrotasks();
  return (command: command, monitor: run as MonitorRun, hooks: hooks);
}

MonitorInfo _timeout(int ms) => MonitorInfo(
  id: _info.id,
  description: _info.description,
  command: _info.command,
  startedAt: 0,
  timeoutMs: ms,
);

/// [body] under a fake clock from the epoch.
void _fake(void Function(FakeAsync time) body) =>
    FakeAsync(initialTime: DateTime.fromMillisecondsSinceEpoch(0)).run(body);

/// Hooks whose hearing of the end fails, as a listener's bug would.
final class _FailingEnd extends _Hooks {
  @override
  void ended(MonitorEnd end, EventLines rest) => throw StateError('end failed');
}

void main() {
  // CTUI-114: a run the window's zone or chord's started is waited for by a
  // close from another; its end, failed, must still reach that close.
  test('an end failed in the zone the run started in reaches a waiter in '
      'another', () async {
    final command = _FakeCommand();
    late Future<Object> starting;
    runZonedGuarded(() {
      starting = MonitorRun.start(_info, _FailingEnd(), '/', run: command.run);
    }, (_, _) {});
    final run = await starting as MonitorRun;
    runZonedGuarded(() => command.exit(0), (_, _) {});
    Future<void> awaited() async => await run.ended;
    await expectLater(
      awaited().timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>()),
    );
  });

  test("lines within 200 ms of a batch's first go as one event, on a fixed "
      'window', () {
    _fake((time) {
      final (:command, :monitor, :hooks) = _started(time);
      command.line('one');
      time.elapse(const Duration(milliseconds: 100));
      command.line('two');
      time.elapse(const Duration(milliseconds: 99));
      expect(hooks.events, isEmpty);
      time.elapse(const Duration(milliseconds: 1));
      expect(hooks.events, [
        ['one', 'two'],
      ]);

      // A steady stream is not pushed back: every 200 ms a batch goes.
      for (var tick = 0; tick < 8; tick++) {
        command.line('steady $tick');
        time.elapse(const Duration(milliseconds: 50));
      }
      expect(hooks.events.skip(1), [
        ['steady 0', 'steady 1', 'steady 2', 'steady 3'],
        ['steady 4', 'steady 5', 'steady 6', 'steady 7'],
      ]);
      expect(monitor.running.events, 3);
      monitor.stop(StoppedBy.close);
      time.flushMicrotasks();
    });
  });

  test('a command that exits ends the monitor with its code, the lines not '
      'yet sent first', () {
    _fake((time) {
      final (:command, monitor: _, :hooks) = _started(time);
      command.line('\x1b[1mbuilt\x1b[0m');
      command.exit(1);
      time.flushMicrotasks();
      expect(hooks.events, isEmpty);
      expect(
        [
          for (final (end, rest) in hooks.ends) [end, rest.lines],
        ],
        [
          [
            const MonitorExited(1),
            ['built'],
          ],
        ],
      );
      // Nothing is sent twice: the batch went with the end.
      time.elapse(const Duration(milliseconds: 500));
      expect(hooks.events, isEmpty);
    });
  });

  test('a signal chord did not send ends it as killed by that signal', () {
    _fake((time) {
      final (:command, monitor: _, :hooks) = _started(time);
      command.exit(137, 'SIGKILL');
      time.flushMicrotasks();
      expect(
        [for (final (end, _) in hooks.ends) end],
        [const MonitorKilled('SIGKILL')],
      );
    });
  });

  test('a status that could not be read ends it with code 1', () {
    _fake((time) {
      final (:command, monitor: _, :hooks) = _started(time);
      command.shellExits(const ShellEnd(error: 'gone'));
      command.reaped(const ShellEnd(error: 'gone'));
      time.flushMicrotasks();
      expect(
        [for (final (end, _) in hooks.ends) end],
        [const MonitorExited(1)],
      );
    });
  });

  test('its timeout stops it and ends it as timed out', () {
    _fake((time) {
      final (:command, monitor: _, :hooks) = _started(time, _timeout(1000));
      time.elapse(const Duration(milliseconds: 999));
      expect(command.stops, isEmpty);
      time.elapse(const Duration(milliseconds: 1));
      expect(command.stops, [1000]);
      expect(
        [for (final (end, _) in hooks.ends) end],
        [const MonitorTimedOut(1000)],
      );
    });
  });

  test('once its shell exits, that code is its end, though a timeout or a '
      'flood comes while what it left is reaped', () {
    _fake((time) {
      final (:command, monitor: _, :hooks) = _started(time, _timeout(1000));
      command.line('pid 42');
      command.shellExits(const ShellEnd(code: 7));
      time.flushMicrotasks();

      // What is still in the pipe is batched as before; the timeout is gone.
      time.elapse(const Duration(milliseconds: 2000));
      expect(hooks.events, [
        ['pid 42'],
      ]);
      expect(command.stops, isEmpty);
      for (var i = 0; i <= 1000; i++) {
        command.line('late $i');
      }
      expect(command.stops, isEmpty);
      command.reaped(const ShellEnd(code: 7));
      time.flushMicrotasks();
      expect(
        [
          for (final (end, rest) in hooks.ends)
            (end, rest.lines.length, rest.dropped),
        ],
        [(const MonitorExited(7), 100, 901)],
      );
    });
  });

  test('a flood stops it at once, with the first 100 lines as the sample', () {
    _fake((time) {
      final (:command, monitor: _, :hooks) = _started(time);
      for (var i = 1; i <= 1500; i++) {
        command.line('GET /health $i');
      }
      time.flushMicrotasks();
      expect(command.stops, [0]);
      expect(hooks.events, isEmpty);
      final [(end, rest)] = hooks.ends;
      expect(end, const MonitorFlooded(FloodBy.lines));
      expect(rest.lines.length, 100);
      expect(rest.lines.first, 'GET /health 1');
      // The 1,001st line flooded it; nothing after it was read.
      expect(rest.dropped, 901);
    });
  });

  test("the person's stop is told; the agent's and a close's are not", () {
    _fake((time) {
      final person = _started(time);
      final agent = _started(time);
      final close = _started(time);
      person.command.line('half a batch');
      person.monitor.stop(StoppedBy.person);
      agent.monitor.stop(StoppedBy.agent);
      close.monitor.stop(StoppedBy.close);
      time.elapse(const Duration(milliseconds: 1000));
      expect(
        [
          for (final (end, rest) in person.hooks.ends) [end, rest.lines],
        ],
        [
          [
            const MonitorStopped(),
            ['half a batch'],
          ],
        ],
      );
      expect(agent.hooks.ends, isEmpty);
      expect(close.hooks.ends, isEmpty);
      expect(person.hooks.events, isEmpty);
    });
  });

  test('a shell that does not start is the refusal', () async {
    final command = _FakeCommand('/bin/nope did not start')
      ..reaped(const ShellEnd(error: 'No such file or directory'));
    final hooks = _Hooks();
    expect(await MonitorRun.start(_info, hooks, '/', run: command.run), (
      error: 'Could not start the command: /bin/nope did not start',
    ));
    await pumpEventQueue();
    // The refusal is all the agent hears: no end follows it.
    expect(hooks.ends, isEmpty);
    expect(hooks.events, isEmpty);
  });

  group('a real shell that does not start is the refusal', () {
    Future<Object> start(String cwd, List<String> shell) => MonitorRun.start(
      _info,
      _Hooks(),
      cwd,
      run: (command, cwd, onLine) => runShell(
        command,
        ShellOptions(cwd: cwd, shell: shell, onLine: onLine, reap: true),
      ),
    );

    test('in a directory that is not there', () async {
      expect(await start('/nonexistent-chord-dir', ['/bin/sh', '-c']), (
        error: 'Could not start the command: /bin/sh did not start',
      ));
    });

    test('a shell that is not there', () async {
      expect(await start('/', ['/nonexistent/sh', '-c']), (
        error: 'Could not start the command: /nonexistent/sh did not start',
      ));
    });

    // The launcher says `ok` before its execv, and only a failure after
    // it: a shell that is there and fails exec starts, and ends at once
    // with the launcher's code (a decision of CTUI-36).
    test(
      'a shell whose exec fails ends at once with what that means',
      () async {
        final dir = await Directory.systemTemp.createTemp('chord-monitor-');
        addTearDown(() => dir.delete(recursive: true));
        final shell = File('${dir.path}/sh')
          ..writeAsStringSync('#!/nonexistent/interpreter\n');
        await Process.run('chmod', ['+x', shell.path]);
        final hooks = _Hooks();
        final run = await MonitorRun.start(
          _info,
          hooks,
          dir.path,
          run: (command, cwd, onLine) => runShell(
            command,
            ShellOptions(
              cwd: cwd,
              shell: [shell.path, '-c'],
              onLine: onLine,
              reap: true,
            ),
          ),
        );
        await (run as MonitorRun).ended;
        final (end, _) = hooks.ends.single;
        expect(end, const MonitorExited(127));
        expect(
          endSentence(end, 0),
          'Exited with code 127 (command not found) after 0s.',
        );
      },
    );
  });

  test("a monitor keeps its last batch's lines and when it went, the lines "
      'its end carried too; none before the first', () {
    _fake((time) {
      final (:command, :monitor, hooks: _) = _started(time);
      expect(monitor.running.lastEvent, isNull);
      command
        ..line('first')
        ..line('second');
      time.elapse(const Duration(milliseconds: 200));
      expect(_last(monitor), [
        ['first', 'second'],
        200,
      ]);
      expect(monitor.running.events, 1);
      time.elapse(const Duration(milliseconds: 1000));
      command.line('third');
      time.elapse(const Duration(milliseconds: 200));
      expect(_last(monitor), [
        ['third'],
        1400,
      ]);

      // Lines still unsent when it ends go with its end, and are the last.
      command
        ..line('last words')
        ..exit(1);
      time.flushMicrotasks();
      expect(monitor.running.lastEvent?.lines, ['last words']);
    });
  });

  test('a person stop keeps final pending lines at the end time; an agent '
      'stop keeps its last sent batch', () {
    _fake((time) {
      final person = _started(time);
      person.command.line('sent');
      time.elapse(const Duration(milliseconds: 300));
      person.command.line('pending');
      person.monitor.stop(StoppedBy.person);
      time.flushMicrotasks();
      expect(_last(person.monitor), [
        ['pending'],
        300,
      ]);
      expect(person.monitor.running.events, 1);

      final agent = _started(time);
      agent.command.line('sent');
      time.elapse(const Duration(milliseconds: 200));
      agent.command.line('unsent');
      agent.monitor.stop(StoppedBy.agent);
      time.flushMicrotasks();
      expect(_last(agent.monitor), [
        ['sent'],
        500,
      ]);
      expect(agent.hooks.events, [
        ['sent'],
      ]);
      expect(agent.hooks.ends, isEmpty);
    });
  });

  group('a real command', () {
    /// [runReal]'s run, with how long after the start its shell's exit
    /// was heard, null when it never was, and when the run ended; null as
    /// a whole for the refusal of a run its timeout stopped before its
    /// shell started, as a loaded machine's slow launcher allows: its shell
    /// ended stopped, at or past the timeout. Any other refusal fails.
    Future<((MonitorEnd, List<String>, bool), int?, int)?> runTimed(
      String command, {
      required int timeoutMs,
    }) async {
      final hooks = _Hooks();
      final watch = Stopwatch();
      int? heard;
      ShellProcess? shell;
      final run = await MonitorRun.start(
        MonitorInfo(
          id: 'm1',
          description: 'real',
          command: command,
          startedAt: 0,
          timeoutMs: timeoutMs,
        ),
        hooks,
        Directory.current.path,
        run: (command, cwd, onLine) {
          watch.start();
          final process = runShell(
            command,
            ShellOptions(
              cwd: cwd,
              shell: ['/bin/sh', '-c'],
              onLine: onLine,
              reap: true,
            ),
          );
          process.exited.then((_) => heard = watch.elapsedMilliseconds);
          return shell = process;
        },
      );
      if (run is! MonitorRun) {
        // Reaped first, whatever it was.
        final end = await shell!.ended;
        final at = watch.elapsedMilliseconds;
        if (end.stopped && at >= timeoutMs) return null;
        fail('refused after ${at}ms, not by its ${timeoutMs}ms timeout: $run');
      }
      await run.ended;
      final ended = watch.elapsedMilliseconds;
      final (end, rest) = hooks.ends.single;
      final lines = [...hooks.events.expand((e) => e), ...rest.lines];
      final pid = int.tryParse(lines.firstOrNull ?? '');
      final alive = pid != null && Process.killPid(pid, ProcessSignal.sigcont);
      if (alive) Process.killPid(pid, ProcessSignal.sigkill);
      return ((end, lines, alive), heard, ended);
    }

    /// Runs [command] as a monitor with [timeoutMs], until its end, with the
    /// lines it sent and whether the PID it printed first outlived it.
    Future<(MonitorEnd, List<String>, bool)> runReal(
      String command, {
      int timeoutMs = 600000,
    }) async =>
        (await runTimed(command, timeoutMs: timeoutMs))?.$1 ??
        fail('the run was refused within its ${timeoutMs}ms timeout');

    /// [command] run with a timeout its shell's exit was heard within,
    /// and, with [whileReaped], one that came before the run ended. On a
    /// loaded machine the shell may take longer than a short timeout to
    /// start and exit, which proves nothing about a timeout coming while it
    /// is reaped; such a run is tried again, at most four times, with a
    /// timeout a second past when the last one's exit was heard, aiming
    /// inside the 2 s a stubborn leftover is given before SIGKILL. Each
    /// attempt's timings are in the failure.
    Future<(MonitorEnd, List<String>, bool)> runExitingFirst(
      String command, {
      bool whileReaped = false,
    }) async {
      final tried = <String>[];
      var timeoutMs = 1000;
      for (var attempt = 0; attempt < 4; attempt++) {
        final timed = await runTimed(command, timeoutMs: timeoutMs);
        if (timed == null) {
          tried.add('timeout ${timeoutMs}ms: stopped before its shell started');
          timeoutMs *= 2;
          continue;
        }
        final (result, heard, ended) = timed;
        if (heard != null &&
            heard < timeoutMs &&
            (!whileReaped || ended > timeoutMs)) {
          return result;
        }
        tried.add(
          'timeout ${timeoutMs}ms: exit heard at ${heard}ms, '
          'ended at ${ended}ms as ${result.$1}',
        );
        timeoutMs = heard == null ? timeoutMs * 2 : heard + 1000;
      }
      fail('no run proved the case: ${tried.join('; ')}');
    }

    test("a progress bar's 1,001 redraws are one line, not a flood", () async {
      final (end, lines, _) = await runReal(
        "i=0; while [ \$i -lt 1001 ]; do printf 'x\\r'; i=\$((i+1)); done; "
        "sleep 0.2; printf 'done\\n'",
      );
      expect(end, const MonitorExited(0));
      expect(lines, hasLength(1));
      expect(lines.single, startsWith('x\rx\r'));
    });

    test('a command that exits takes what it left running in the '
        'background with it, its code kept', () async {
      final (end, lines, alive) = await runReal(
        r'sleep 30 >/dev/null 2>&1 & echo $!',
      );
      expect(end, const MonitorExited(0));
      expect(lines, hasLength(1));
      expect(alive, isFalse);
    });

    test('a shell that exits while what it started still holds stdout ends '
        'with its own code, not the timeout', () async {
      final (end, _, alive) = await runExitingFirst(
        r'sleep 30 & echo $!; exit 7',
      );
      expect(end, const MonitorExited(7));
      expect(alive, isFalse);
      // Up to four runs of runExitingFirst, each its timeout and reaping.
    }, timeout: const Timeout(Duration(minutes: 2)));

    test("a shell's code stays its end while what it left shrugs off SIGTERM "
        'past the timeout', () async {
      final (end, _, alive) = await runExitingFirst(
        r"(trap '' TERM; sleep 30) >/dev/null 2>&1 & echo $!; sleep 0.1; "
        'exit 7',
        whileReaped: true,
      );
      expect(end, const MonitorExited(7));
      expect(alive, isFalse);
      // Up to four runs of runExitingFirst, each its timeout and reaping.
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('CTUI-36 tester: runner lifecycle boundaries', () {
    test('ended waits for reaping and late input after ending is ignored', () {
      _fake((time) {
        final (:command, :monitor, :hooks) = _started(time);
        var ended = false;
        monitor.ended.then((_) => ended = true);
        command.shellExits(const ShellEnd(code: 9));
        time.flushMicrotasks();
        expect(ended, isFalse);
        expect(hooks.ends, isEmpty);
        command.line('last pipe output');
        command.reaped(const ShellEnd(code: 9));
        time.flushMicrotasks();
        expect(ended, isTrue);
        expect(hooks.ends.single.$1, const MonitorExited(9));
        expect(hooks.ends.single.$2.lines, ['last pipe output']);
        command.line('too late');
        monitor.stop(StoppedBy.person);
        time.elapse(const Duration(hours: 1));
        expect(command.stops, isEmpty);
        expect(hooks.ends, hasLength(1));
        expect(hooks.events, isEmpty);
        expect(time.pendingTimers, isEmpty);
      });
    });

    test('silent close during reaping withdraws a pending natural end', () {
      _fake((time) {
        final (:command, :monitor, :hooks) = _started(time);
        command.line('unsent');
        command.shellExits(const ShellEnd(code: 7));
        time.flushMicrotasks();
        monitor.stop(StoppedBy.close);
        time.flushMicrotasks();
        time.elapse(const Duration(hours: 1));
        expect(command.stops, [0]);
        expect(hooks.ends, isEmpty);
        expect(hooks.events, isEmpty);
        expect(time.pendingTimers, isEmpty);
      });
    });

    test('the first stop wins and no second stop or timeout is delivered', () {
      for (final first in StoppedBy.values) {
        _fake((time) {
          final (:command, :monitor, :hooks) = _started(time);
          command.line('pending');
          monitor.stop(first);
          for (final later in StoppedBy.values) {
            monitor.stop(later);
          }
          command.line('late');
          time.elapse(const Duration(hours: 1));
          expect(command.stops, [0]);
          expect(hooks.events, isEmpty);
          if (first == StoppedBy.person) {
            expect(hooks.ends.single.$1, const MonitorStopped());
            expect(hooks.ends.single.$2.lines, ['pending']);
          } else {
            expect(hooks.ends, isEmpty);
          }
          expect(time.pendingTimers, isEmpty);
        });
      }
    });

    test(
      'a bytes flood counts raw UTF-8 before escape stripping and cutting',
      () {
        _fake((time) {
          final (:command, monitor: _, :hooks) = _started(time);
          command.line('\x1b[31m${'😀' * (floodBytes ~/ 4)}\x1b[0m');
          time.flushMicrotasks();
          expect(command.stops, [0]);
          final (end, rest) = hooks.ends.single;
          expect(end, const MonitorFlooded(FloodBy.bytes));
          expect(rest.lines, ['${'😀' * lineChars}… (+64536 characters)']);
          expect(rest.dropped, 0);
          expect(hooks.events, isEmpty);
        });
      },
    );

    test('two runs keep their clocks, lines and ends separate', () {
      _fake((time) {
        final a = _started(time, _timeout(1000));
        final b = _started(time, _timeout(2000));
        a.command.line('A');
        time.elapse(const Duration(milliseconds: 100));
        b.command.line('B');
        time.elapse(const Duration(milliseconds: 100));
        expect(a.hooks.events, [
          ['A'],
        ]);
        expect(b.hooks.events, isEmpty);
        time.elapse(const Duration(milliseconds: 100));
        expect(a.monitor.running.lastEvent?.at, 200);
        expect(b.monitor.running.lastEvent?.at, 300);
        time.elapse(const Duration(milliseconds: 700));
        expect(a.hooks.ends.single.$1, const MonitorTimedOut(1000));
        expect(b.hooks.ends, isEmpty);
        b.command.line('B pending');
        b.monitor.stop(StoppedBy.person);
        time.flushMicrotasks();
        expect(b.hooks.ends.single.$1, const MonitorStopped());
        expect(b.hooks.ends.single.$2.lines, ['B pending']);
        expect(a.monitor.running.lastEvent?.lines, ['A']);
        time.elapse(const Duration(hours: 1));
        expect(time.pendingTimers, isEmpty);
      });
    });

    test('an empty end retains the last sent batch without resending it', () {
      _fake((time) {
        final (:command, :monitor, :hooks) = _started(time);
        command.line('kept');
        time.elapse(const Duration(milliseconds: 200));
        command.exit(0);
        time.flushMicrotasks();
        expect(monitor.running.events, 1);
        expect(monitor.running.lastEvent?.lines, ['kept']);
        expect(monitor.running.lastEvent?.at, 200);
        expect(hooks.ends.single.$2.lines, isEmpty);
        expect(hooks.events, [
          ['kept'],
        ]);
        expect(time.pendingTimers, isEmpty);
      });
    });
  });
}

/// [monitor]'s last batch as its lines and when it went.
List<Object?> _last(MonitorRun monitor) => [
  monitor.running.lastEvent?.lines,
  monitor.running.lastEvent?.at,
];
