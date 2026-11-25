import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/process.dart';
import 'package:chord/platform/process.dart' show ProcessGroups;
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('commandArgv', () {
    // Each line with what shell-quote 1.12.0's parse gives it, as the
    // original calls it.
    const words = {
      '"a b" \'c d\'': ['a b', 'c d'],
      r'a\ b': ['a b'],
      r'"q\"x"': ['q"x'],
      r"'it'\''s'": ["it's"],
      '--flag=val "x y"z': ['--flag=val', 'x yz'],
      r'$HOME': [r'$HOME'],
      r"x '$Y'": ['x', r'$Y'],
      r'x "${X}y"': ['x', r'$Xy'],
      '"unclosed': ['unclosed'],
      'npx -y @zed-industries/claude-code-acp': [
        'npx',
        '-y',
        '@zed-industries/claude-code-acp',
      ],
      "x 'unclosed": ['x', 'unclosed'],
      'a  b\tc': ['a', 'b', 'c'],
      r'x "a\nb"': ['x', r'a\nb'],
      r'x ${A}${B}': ['x', r'$A$B'],
      r"x $'a\nb'": ['x', 'a\nb'],
      r"x $'it\'s'": ['x', "it's"],
      r'x "$"': ['x', r'$'],
      r'x $/x': ['x', r'$/x'],
      r'x "${a${b}c}"': ['x', r'$a${b}c'],
      r'x $': ['x', r'$'],
      r'x a\': ['x', 'a'],
      r'x $1x': ['x', r'$1x'],
    };

    for (final MapEntry(key: line, value: argv) in words.entries) {
      test('splits $line', () => expect(commandArgv(line), argv));
    }

    for (final line in [
      'a|b',
      'x && y',
      'x > f',
      'x ; y',
      r'x $(id)',
      'x *.ts',
      'x # comment',
      'a#b',
      r'x \*x',
      'x?',
      'x <(y)',
      'x &> f',
    ]) {
      test('refuses $line', () {
        expect(
          () => commandArgv(line),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'The agent command "$line" holds shell syntax; '
                  'give a plain command line.',
            ),
          ),
        );
      });
    }

    test('refuses a bad substitution as shell-quote does', () {
      expect(
        () => commandArgv(r'x "${}"'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            r'Bad substitution: ${}',
          ),
        ),
      );
    });

    test('refuses an empty command, as a line or a list', () {
      for (final command in <Object>[
        '',
        '  ',
        '"" \'\'',
        '""',
        <String>[],
        [''],
      ]) {
        expect(
          () => commandArgv(command),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'The agent command is empty.',
            ),
          ),
          reason: '$command',
        );
      }
    });

    test('takes a list as it is', () {
      expect(commandArgv(['a b', r'$X', '|', '']), ['a b', r'$X', '|', '']);
    });
  });

  group('StderrTail', () {
    Tail endOf(List<String> chunks) {
      final tail = StderrTail();
      chunks.forEach(tail.add);
      return tail.end();
    }

    test('the last non-empty lines as they came, indents kept, and how many '
        'came before', () {
      expect(
        endOf([
          'a\n\n  b',
          ' still b\n',
          for (var i = 0; i < 300; i++) '    at frame $i\n',
        ]),
        Tail([for (var i = 294; i < 300; i++) '    at frame $i'], 296),
      );
    });

    test('an unfinished last line is a line of the end, and one past the '
        'bound is cut there and marked', () {
      final end = endOf(['  first\n', '${'0' * 2000}\n', 'Error: no newline']);
      expect(end.cut, 0);
      expect(end.lines, [
        '  first',
        '${'0' * stderrLineMax}…',
        'Error: no newline',
      ]);
    });

    test('a line past the bound is marked though what was dropped was its '
        'end, and counted though its kept start is blank', () {
      expect(
        endOf(['a' * 1024, ' b\n', ' ' * 1025, 'Error\n']),
        Tail(['${'a' * stderrLineMax}…', '${' ' * stderrLineMax}…'], 0),
      );
    });

    test('CRLF fragments, blank lines and content beyond a capped blank '
        'prefix count exactly once', () {
      final chunks = [
        'first\r',
        '\n \t\r',
        '\n  second',
        ' continued\r',
        '\n\nthird\nfourth\r\nfifth\nsixth\n',
        ' ' * stderrLineMax,
        ' ',
        'Error beyond the kept prefix',
        '\r',
        '\n',
        ' \t\r\n',
        'last unfinished',
      ];
      final tail = StderrTail();
      for (final (index, chunk) in chunks.indexed) {
        tail.add(chunk);
        if (index == 0 || index == 1) {
          expect(tail.end(), const Tail(['first'], 0));
        }
        if (index == 6) {
          expect(
            tail.end(),
            const Tail([
              'first',
              '  second continued',
              'third',
              'fourth',
              'fifth',
              'sixth',
            ], 0),
          );
        }
        if (index == 9) {
          expect(
            tail.end(),
            Tail([
              '  second continued',
              'third',
              'fourth',
              'fifth',
              'sixth',
              '${' ' * stderrLineMax}…',
            ], 1),
          );
        }
      }
      expect(
        tail.end(),
        Tail([
          'third',
          'fourth',
          'fifth',
          'sixth',
          '${' ' * stderrLineMax}…',
          'last unfinished',
        ], 2),
      );
    });

    test('the tail is the last 4096 characters as they came', () {
      final tail = StderrTail()
        ..add('x' * 5000)
        ..add('\r\nend');
      expect(tail.tail.length, stderrTailLength);
      expect(tail.tail, endsWith('x\r\nend'));
      expect(StderrTail().tail, '');
      expect(StderrTail().end(), const Tail([], 0));
    });
  });

  group('tester: command and stderr boundaries', () {
    test('carries over the original command line example', () {
      expect(
        commandArgv(r'''deno run --config '/a b/deno.json' "x y" a\ b $HOME'''),
        ['deno', 'run', '--config', '/a b/deno.json', 'x y', 'a b', r'$HOME'],
      );
    });

    test('quoted and escaped shell punctuation stays literal', () {
      expect(commandArgv('agent "|" ";" "#" "*.dart"'), [
        'agent',
        '|',
        ';',
        '#',
        '*.dart',
      ]);
      expect(commandArgv(r'agent a\;b x\|y \#tag'), [
        'agent',
        'a;b',
        'x|y',
        '#tag',
      ]);
      expect(commandArgv('agent "界👩‍💻e\u0301"'), ['agent', '界👩‍💻e\u0301']);
    });

    test(
      'ANSI C quotes decode escapes and stop at NUL as shell-quote does',
      () {
        expect(commandArgv(r"agent $'a\0drop' $'\U0001F600' $'\x41\101'"), [
          'agent',
          'a',
          '😀',
          'AA',
        ]);
      },
    );

    test('list arguments are copied without interpreting or aliasing them', () {
      final input = ['agent', '', r'$NAME', '|', '界'];
      final output = commandArgv(input);
      input[0] = 'changed';
      output[1] = 'changed';
      expect(output.first, 'agent');
      expect(input[1], '');
      expect(output.sublist(2), [r'$NAME', '|', '界']);
    });

    test('tail and line caps hold across a thousand chunks', () {
      final tail = StderrTail();
      for (var i = 0; i < 1000; i++) {
        tail.add('界😀e\u0301\u001b[31m');
      }
      const chunk = '界😀e\u0301\u001b[31m';
      final all = chunk * 1000;
      expect(tail.tail, all.substring(all.length - stderrTailLength));
      expect(tail.end(), Tail(['${all.substring(0, stderrLineMax)}…'], 0));
      tail.add('\nlast');
      expect(tail.end().lines.last, 'last');
    });

    test('line bounds distinguish exact capacity from truncation', () {
      final tail = StderrTail()..add('${'x' * stderrLineMax}\n');
      expect(tail.end(), Tail(['x' * stderrLineMax], 0));
      tail.add('${'y' * stderrLineMax}z');
      expect(
        tail.end(),
        Tail(['x' * stderrLineMax, '${'y' * stderrLineMax}…'], 0),
      );
    });

    test('end snapshots do not consume or expose the live ring', () {
      final tail = StderrTail()..add('first\r\nsecond');
      final before = tail.end();
      expect(tail.end(), before);
      before.lines.clear();
      expect(tail.end(), const Tail(['first', 'second'], 0));
      tail.add(' continued\n');
      expect(tail.end(), const Tail(['first', 'second continued'], 0));
    });
  });

  group('settledWithin', () {
    test('a value, an error, or null once the bound passes', () {
      fakeAsync((async) {
        Settled<int>? value;
        Settled<int>? error;
        Settled<int>? late = const Fulfilled(0);
        settledWithin(
          Future.value(1),
          const Duration(seconds: 1),
        ).then((s) => value = s);
        settledWithin(
          Future<int>.error(StateError('x')),
          const Duration(seconds: 1),
        ).then((s) => error = s);
        settledWithin(
          Completer<int>().future,
          const Duration(seconds: 1),
        ).then((s) => late = s);
        async.elapse(const Duration(milliseconds: 999));
        expect((value as Fulfilled<int>).value, 1);
        expect((error as Rejected<int>).error, isStateError);
        expect(late, isNotNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(late, isNull);
      });
    });
  });

  group('the stop ladder', () {
    // Runs [process]'s stop under fake time; what the test reads afterwards.
    ({Object? error, bool done, Duration at}) run(
      MemoryAgentProcess Function() make,
      void Function(FakeAsync async) during,
    ) {
      // Built inside the fake zone, so its futures complete in fake time.
      return fakeAsync((async) {
        final process = make();
        Object? error;
        var done = false;
        var at = Duration.zero;
        process.stop().then(
          (_) {
            done = true;
            at = async.elapsed;
          },
          onError: (Object e) {
            error = e;
            at = async.elapsed;
          },
        );
        during(async);
        async.elapse(const Duration(seconds: 10));
        return (error: error, done: done, at: at);
      });
    }

    test('ends stdin first, and an exit then is swept with SIGKILL', () {
      late MemoryAgentProcess process;
      final result = run(() => process = MemoryAgentProcess(), (async) {
        expect(process.stdin.ended, isTrue);
        expect(process.signals, isEmpty);
        async.elapse(const Duration(milliseconds: 1999));
        expect(process.signals, isEmpty);
        process.exit();
      });
      expect(result.done, isTrue);
      expect(result.at, const Duration(milliseconds: 1999));
      expect(process.signals, [ProcessSignal.sigkill]);
    });

    test('SIGTERM only once the exit bound passed', () {
      late MemoryAgentProcess process;
      final result = run(() => process = MemoryAgentProcess(onSignal: (_) {}), (
        async,
      ) {
        async.elapse(const Duration(milliseconds: 1999));
        expect(process.signals, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(process.signals, [ProcessSignal.sigterm]);
        process.exit(const Exit(143, 'SIGTERM'));
      });
      expect(result.done, isTrue);
      expect(result.at, const Duration(seconds: 2));
      expect(process.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
    });

    test('SIGKILL once the term bound passed, then the sweep', () {
      late MemoryAgentProcess process;
      final result = run(() => process = MemoryAgentProcess(), (async) {
        async.elapse(const Duration(milliseconds: 3999));
        expect(process.signals, [ProcessSignal.sigterm]);
        async.elapse(const Duration(milliseconds: 1));
        expect(process.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
        async.elapse(const Duration(milliseconds: 100));
        process.exit(const Exit(137, 'SIGKILL'));
      });
      expect(result.done, isTrue);
      expect(result.at, const Duration(milliseconds: 4100));
      expect(process.signals, [
        ProcessSignal.sigterm,
        ProcessSignal.sigkill,
        ProcessSignal.sigkill,
      ]);
    });

    test('AgentExitError when no exit comes even after SIGKILL', () {
      late MemoryAgentProcess process;
      final result = run(() => process = MemoryAgentProcess(pid: 77), (_) {});
      expect(
        result.error,
        isA<AgentExitError>()
            .having((e) => e.pids, 'pids', [77])
            .having(
              (e) => e.toString(),
              'message',
              'Agent process 77 did not exit after SIGKILL.',
            ),
      );
      expect(result.at, const Duration(seconds: 6));
      expect(process.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
    });

    test('an exit already seen ends it at once, with the sweep', () {
      late MemoryAgentProcess process;
      final result = run(() => process = MemoryAgentProcess()..exit(), (_) {});
      expect(result.done, isTrue);
      expect(result.at, Duration.zero);
      expect(process.signals, [ProcessSignal.sigkill]);
    });

    test('an exit that failed counts as seen', () {
      fakeAsync((async) {
        final status = Completer<Exit>();
        final signals = <ProcessSignal>[];
        var done = false;
        stopLadder(
          pid: 1,
          status: status.future,
          end: () {},
          signal: (s) {
            signals.add(s);
            return true;
          },
        ).then((_) => done = true);
        async.elapse(const Duration(milliseconds: 500));
        status.completeError(const CannotStart('x', 'it ended'));
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(signals, [ProcessSignal.sigkill]);
      });
    });

    test('is idempotent: a second stop joins the first ladder', () {
      fakeAsync((async) {
        final process = MemoryAgentProcess();
        final first = process.stop();
        final second = process.stop(
          const StopBounds(exit: Duration.zero, term: Duration.zero),
        );
        expect(identical(first, second), isTrue);
        var both = 0;
        first.then((_) => both++);
        second.then((_) => both++);
        async.elapse(const Duration(seconds: 3));
        expect(process.signals, [ProcessSignal.sigterm]);
        process.exit();
        async.flushMicrotasks();
        expect(both, 2);
        expect(process.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
      });
    });

    test('the given bounds are used', () {
      fakeAsync((async) {
        final process = MemoryAgentProcess();
        Object? error;
        process
            .stop(
              const StopBounds(
                exit: Duration(milliseconds: 100),
                term: Duration(milliseconds: 300),
                kill: Duration(milliseconds: 2000),
              ),
            )
            .catchError((Object e) => error = e);
        async.elapse(const Duration(milliseconds: 100));
        expect(process.signals, [ProcessSignal.sigterm]);
        async.elapse(const Duration(milliseconds: 300));
        expect(process.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
        async.elapse(const Duration(milliseconds: 1999));
        expect(error, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(error, isA<AgentExitError>());
      });
    });
  });

  group('stdin ends once the writer is idle', () {
    // What the connection's writer does: after a flush, whatever it queued
    // meanwhile is added and flushed in the microtasks that follow.
    test('a message queued during a pending flush goes out before the end', () {
      fakeAsync((async) {
        final input = MemoryInput()..hold = true;
        input.add(utf8.encode('a\n'));
        input.flush().then((_) {
          input.add(utf8.encode('b\n'));
          return input.flush();
        });
        input.end();
        async.elapse(const Duration(seconds: 1));
        expect(input.closed, isFalse, reason: 'a flush is pending');
        input.release();
        async.elapse(Duration.zero);
        expect(input.closed, isTrue);
        expect(input.closedAt, 4);
        expect(input.addsWhileFlushing, 0);
        expect(input.addsAfterClose, 0);
      });
    });

    test('a message queued in the same turn as the end, with no flush pending, '
        'goes out before it', () {
      fakeAsync((async) {
        final input = MemoryInput();
        scheduleMicrotask(() {
          input.add(utf8.encode('b\n'));
          input.flush();
        });
        input.end();
        async.elapse(Duration.zero);
        expect(input.closed, isTrue);
        expect(input.closedAt, 2);
      });
    });

    test('an idle writer\'s stdin ends at the next turn', () {
      fakeAsync((async) {
        final input = MemoryInput();
        var done = false;
        input.done.then((_) => done = true);
        input.end();
        input.end();
        expect(input.closed, isFalse);
        async.elapse(Duration.zero);
        expect(input.closed, isTrue);
        expect(done, isTrue);
      });
    });
  });

  group('a real agent', () {
    // The original's test bounds.
    const bounds = StopBounds(
      exit: Duration(milliseconds: 100),
      term: Duration(milliseconds: 300),
      kill: Duration(milliseconds: 2000),
    );
    late ProcessGroups groups;
    final agents = <AgentProcess>[];

    setUp(() => groups = ProcessGroups());
    tearDown(() async {
      for (final agent in agents) {
        await agent.stop(bounds).catchError((_) {});
      }
      agents.clear();
      groups.killAll();
    });

    Future<AgentProcess> spawn(
      String script, {
      CancellationToken? token,
      void Function(String)? onStderr,
    }) async {
      final agent = await spawnAgent(
        command: ['sh', '-c', script],
        cwd: Directory.systemTemp.path,
        groups: groups,
        stop: bounds,
        cancellationToken: token,
        onStderr: onStderr,
      );
      agents.add(agent);
      return agent;
    }

    bool running(int pid) =>
        Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

    List<String> inGroup(int pgid) => [
      for (final line in LineSplitter.split(
        Process.runSync('ps', ['-A', '-o', 'pid=,pgid=']).stdout as String,
      ))
        if (line.trim().split(RegExp(r'\s+')) case [
          final pid,
          final group,
        ] when group == '$pgid')
          pid,
    ];

    /// [pgid]'s members once a stop's last SIGKILL has been delivered and
    /// the dead reaped: kill(2) returns once the signal is queued, and an
    /// orphan is reaped by launchd or init in its own time, which a loaded
    /// machine stretches. Polled within a bound, so a member that lives on
    /// still fails.
    Future<List<String>> inGroupAfterStop(int pgid) async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      var members = inGroup(pgid);
      while (members.isNotEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        members = inGroup(pgid);
      }
      return members;
    }

    Future<int> grandchildOf(AgentProcess agent) => agent.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map(int.parse)
        .first;

    test(
      'SIGTERM reaches the group once stdin\'s end did not end it',
      () async {
        final agent = await spawn(r'sleep 30 & echo $!; wait');
        final grandchild = await grandchildOf(agent);
        final watch = Stopwatch()..start();
        await agent.stop(bounds);
        expect(await agent.status, const Exit(143, 'SIGTERM'));
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
        expect(await inGroupAfterStop(agent.pid), isEmpty);
        expect(running(grandchild), isFalse);
      },
    );

    test('a TERM trap is ended by SIGKILL, and nothing is left', () async {
      final agent = await spawn(r'trap "" TERM; sleep 30 & echo $!; wait');
      final grandchild = await grandchildOf(agent);
      final watch = Stopwatch()..start();
      await agent.stop(bounds);
      expect(await agent.status, const Exit(137, 'SIGKILL'));
      expect(
        watch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 400)),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      expect(await inGroupAfterStop(agent.pid), isEmpty);
      expect(running(grandchild), isFalse);
    });

    test('an agent that goes at stdin\'s end takes no signal but the sweep, '
        'which still ends what it left behind', () async {
      final agent = await spawn(
        r'sleep 30 >/dev/null 2>&1 & echo $!; cat >/dev/null',
      );
      final grandchild = await grandchildOf(agent);
      // Observe the cooperative exit before the sweep: this test checks
      // cleanup of an exited agent, not how fast the shell is scheduled.
      agent.stdin.end();
      expect(
        await agent.status.timeout(const Duration(seconds: 10)),
        const Exit(0),
      );
      expect(running(grandchild), isTrue);
      await agent.stop(bounds);
      expect(await inGroupAfterStop(agent.pid), isEmpty);
      expect(running(grandchild), isFalse);
    });

    test('a start cancelled while the launcher starts stops it before the '
        'handshake and leaves nothing', () async {
      final token = CancellationToken();
      final groupsBefore = groups;
      final opening = spawnAgent(
        command: ['sh', '-c', 'sleep 30'],
        cwd: Directory.systemTemp.path,
        groups: groupsBefore,
        stop: bounds,
        cancellationToken: token,
      );
      token.cancel();
      await expectLater(opening, throwsA(isA<CancelledException>()));
      final pids = groupsBefore.killAll();
      expect(pids, isEmpty, reason: 'no group holds a process');
    });

    for (final cancel in [false, true]) {
      test(
        'a ${cancel ? 'cancelled' : 'failed'} launch surfaces a stop failure',
        () async {
          final token = CancellationToken();
          final signals = <int>[];
          int? child;
          final opening = spawnAgent(
            command: ['sh'],
            cwd: Directory.systemTemp.path,
            groups: groups,
            cancellationToken: token,
            launcher: (nonce, path) => [
              'sh',
              '-c',
              cancel
                  ? 'exec sleep 30'
                  : 'echo "chord-exec $nonce fail setsid 1" >&2; exec sleep 30',
            ],
            kill: (pid, signal) {
              child = pid.abs();
              signals.add(signal);
              return 1;
            },
            stop: const StopBounds(
              exit: Duration(milliseconds: 10),
              term: Duration(milliseconds: 10),
              kill: Duration(milliseconds: 10),
            ),
          );
          try {
            if (cancel) {
              // A partial handshake stays pending, so cancel before any frame.
              token.cancel();
            }
            await expectLater(opening, throwsA(isA<AgentExitError>()));
            expect(signals, [15, 9]);
            expect(child, isNotNull);
          } finally {
            if (child != null) {
              Process.killPid(child!, ProcessSignal.sigkill);
              for (var i = 0; i < 100 && running(child!); i++) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
              expect(running(child!), isFalse);
            }
          }
        },
      );
    }

    test('a token cancelled before the call starts nothing', () async {
      final token = CancellationToken()..cancel();
      await expectLater(
        spawn('sleep 30', token: token),
        throwsA(isA<CancelledException>()),
      );
      expect(groups.killAll(), isEmpty);
    });

    test('a grandchild holding stderr: last words come at the settle, and '
        'the stop stays bounded', () async {
      final heard = StringBuffer();
      final agent = await spawn(
        '(sleep 5; echo late >&2) & echo bye >&2; exit 1',
        onStderr: heard.write,
      );
      expect(await agent.status, const Exit(1));
      final watch = Stopwatch()..start();
      expect(await agent.lastWords(), 'bye\n');
      expect(
        watch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 400)),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(agent.stderrEnd(), const Tail(['bye'], 0));
      expect(agent.stderrTail(), 'bye\n');
      expect(heard.toString(), 'bye\n');
      watch.reset();
      await agent.stop(bounds);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(await inGroupAfterStop(agent.pid), isEmpty);
    });

    test('last words come at once when stderr ends', () async {
      final agent = await spawn('echo gone >&2; exit 2');
      expect(await agent.status, const Exit(2));
      final watch = Stopwatch()..start();
      expect(await agent.lastWords(), 'gone\n');
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 400)));
    });

    test('an agent closing its stdin while chord writes does not end '
        'chord', () async {
      final agent = await spawn('exec 0<&-; sleep 0.3');
      final chunk = List.filled(64 * 1024, 0x61);
      Object? failed;
      try {
        for (var i = 0; i < 64; i++) {
          agent.stdin.add(chunk);
          await agent.stdin.flush();
        }
      } catch (error) {
        failed = error;
      }
      expect(failed, isNotNull);
      await agent.stop(bounds);
      await agent.status;
    });

    test('what the writer adds after a flush that was pending at the end '
        'reaches the agent before its stdin ends', () async {
      final agent = await spawn('cat');
      final out = agent.stdout.transform(utf8.decoder).join();
      agent.stdin.add(utf8.encode('a\n'));
      final second = agent.stdin.flush().then((_) {
        agent.stdin.add(utf8.encode('b\n'));
        return agent.stdin.flush();
      });
      agent.stdin.end();
      await second;
      expect(await out, 'a\nb\n');
      expect(await agent.status, const Exit(0));
    });

    test('a command refused by commandArgv starts nothing', () async {
      await expectLater(
        spawnAgent(command: 'a | b', cwd: Directory.systemTemp.path),
        throwsFormatException,
      );
      await expectLater(
        spawnAgent(command: 'chord-no-such-agent', cwd: '/'),
        throwsA(
          isA<CannotStart>().having(
            (e) => e.toString(),
            'message',
            startsWith('cannot start chord-no-such-agent: '),
          ),
        ),
      );
    });
  });

  group('tester: pre-handshake cleanup preserves the initiating error', () {
    late ProcessGroups groups;
    const bounds = StopBounds(
      exit: Duration(milliseconds: 100),
      term: Duration(milliseconds: 300),
      kill: Duration(seconds: 2),
    );

    setUp(() => groups = ProcessGroups());
    tearDown(() => groups.killAll());

    test('a failed handshake retains its program and setsid reason', () async {
      await expectLater(
        spawnAgent(
          command: ['sh'],
          cwd: Directory.systemTemp.path,
          groups: groups,
          stop: bounds,
          launcher: (nonce, path) => [
            'sh',
            '-c',
            'echo "chord-exec $nonce fail setsid 1" >&2; exec cat',
          ],
        ),
        throwsA(
          isA<CannotStart>()
              .having((error) => error.program, 'program', 'sh')
              .having(
                (error) => error.reason,
                'reason',
                startsWith('setsid: '),
              ),
        ),
      );
      expect(groups.killAll(), isEmpty);
    });

    test('cancellation retains the exact exception after cleanup', () async {
      final token = CancellationToken();
      final opening = spawnAgent(
        command: ['sh'],
        cwd: Directory.systemTemp.path,
        groups: groups,
        stop: bounds,
        cancellationToken: token,
        launcher: (nonce, path) => ['sh', '-c', 'exec cat'],
      );
      token.cancel();
      await expectLater(opening, throwsA(same(token.exception)));
      expect(groups.killAll(), isEmpty);
    });
  });

  group('tester: agent lifecycle boundaries', () {
    test('a timed-out future can fail late without changing the outcome', () {
      fakeAsync((async) {
        final pending = Completer<int>();
        var completions = 0;
        Settled<int>? outcome = const Fulfilled(1);
        settledWithin(pending.future, const Duration(milliseconds: 10)).then((
          v,
        ) {
          outcome = v;
          completions++;
        });
        async.elapse(const Duration(milliseconds: 10));
        expect(outcome, isNull);
        pending.completeError(StateError('late'));
        async.flushMicrotasks();
        expect(completions, 1);
        expect(outcome, isNull);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test(
      'a failed stop is shared and a late exit never starts another ladder',
      () {
        fakeAsync((async) {
          final process = MemoryAgentProcess(pid: 77);
          Object? firstError;
          Object? secondError;
          final first = process.stop(
            const StopBounds(
              exit: Duration.zero,
              term: Duration.zero,
              kill: Duration.zero,
            ),
          );
          first.catchError((Object e) {
            firstError = e;
          });
          async.elapse(Duration.zero);
          final second = process.stop();
          second.catchError((Object e) {
            secondError = e;
          });
          async.flushMicrotasks();
          expect(identical(first, second), isTrue);
          expect(firstError, isA<AgentExitError>());
          expect(identical(firstError, secondError), isTrue);
          process.exit();
          async.elapse(const Duration(seconds: 10));
          expect(process.signals, [
            ProcessSignal.sigterm,
            ProcessSignal.sigkill,
          ]);
          expect(async.pendingTimers, isEmpty);
        });
      },
    );

    test('last words follow stderr independently of stdout and exit', () {
      fakeAsync((async) {
        final process = MemoryAgentProcess();
        process.closeStdout();
        process.exit(const Exit(1));
        String? words;
        process.lastWords().then((value) {
          words = value;
        });
        async.elapse(const Duration(milliseconds: 250));
        expect(words, isNull);
        process.writeStderr('界👩‍💻e\u0301\n');
        process.closeStderr();
        async.flushMicrotasks();
        expect(words, '界👩‍💻e\u0301\n');
        expect(process.stderrEnd(), const Tail(['界👩‍💻e\u0301'], 0));
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('last words return current stderr exactly at the settle bound', () {
      fakeAsync((async) {
        final process = MemoryAgentProcess()..writeStderr('first');
        String? words;
        process.lastWords().then((value) {
          words = value;
        });
        async.elapse(const Duration(milliseconds: 499));
        process.writeStderr(' last');
        expect(words, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(words, 'first last');
        process.closeStderr();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    const bounds = StopBounds(
      exit: Duration(milliseconds: 100),
      term: Duration(milliseconds: 300),
      kill: Duration(milliseconds: 2000),
    );

    Future<AgentProcess> child(String script) async {
      final groups = ProcessGroups();
      addTearDown(groups.killAll);
      final process = await spawnAgent(
        command: ['sh', '-c', script],
        cwd: Directory.systemTemp.path,
        groups: groups,
        stop: bounds,
      );
      addTearDown(() => process.stop(bounds));
      return process;
    }

    test('stopping a non-reading child bypasses a pending flush', () async {
      final process = await child('trap "" TERM; sleep 30');
      process.stdin.add(List<int>.filled(4 * 1024 * 1024, 0x61));
      final flushed = process.stdin.flush().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await process.stop(bounds).timeout(const Duration(seconds: 4));
      expect(await process.status, const Exit(137, 'SIGKILL'));
      await flushed.timeout(const Duration(seconds: 1));
    });

    test('every flush continuation precedes the requested stdin end', () async {
      final process = await child('cat');
      final out = process.stdout.transform(utf8.decoder).join();
      Future<void> write(int i) async {
        process.stdin.add(utf8.encode('$i\n'));
        await process.stdin.flush();
        if (i < 99) await write(i + 1);
      }

      final writing = write(0);
      process.stdin.end();
      process.stdin.end();
      await writing;
      expect(await out, '${List.generate(100, (i) => '$i').join('\n')}\n');
      expect(await process.status, const Exit(0));
    });

    test(
      'malformed UTF-8 stderr is retained with replacement characters',
      () async {
        final process = await child(r"printf '\377' >&2; exit 2");
        expect(await process.status, const Exit(2));
        expect(await process.lastWords(), '\uFFFD');
        expect(process.stderrEnd(), const Tail(['\uFFFD'], 0));
      },
    );
  });
}
