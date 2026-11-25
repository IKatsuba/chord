import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:chord/platform/process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('GroupHandshake', () {
    List<int> bytes(String text) => utf8.encode(text);
    String text(List<int> bytes) => utf8.decode(bytes);

    test('ok, then the program\'s own stderr passes through', () {
      final handshake = GroupHandshake('ab12');
      expect(handshake.add(bytes('chord-exec ab12 ok\nhello\n')), isNotEmpty);
      expect(handshake.state, HandshakeState.started);
      expect(handshake.settled, isTrue);
      expect(text(handshake.add(bytes('more'))), 'more');
    });

    test('ok alone keeps the exec window open until stderr says more', () {
      final handshake = GroupHandshake('ab12');
      expect(handshake.add(bytes('chord-exec ab12 ok\n')), isEmpty);
      expect(handshake.state, HandshakeState.started);
      expect(handshake.settled, isFalse);
      expect(text(handshake.add(bytes('warn'))), 'warn');
      expect(handshake.settled, isTrue);
    });

    test('ok, then fail exec, gives the errno', () {
      final handshake = GroupHandshake('ab12');
      final through = handshake.add(
        bytes('chord-exec ab12 ok\nchord-exec ab12 fail exec 2\n'),
      );
      expect(through, isEmpty);
      expect(handshake.state, HandshakeState.started);
      expect(handshake.execErrno, 2);
      expect(handshake.settled, isTrue);
    });

    test('fail setsid fails it with libc\'s words', () {
      final handshake = GroupHandshake('ab12');
      expect(handshake.add(bytes('chord-exec ab12 fail setsid 1\n')), isEmpty);
      expect(handshake.state, HandshakeState.failed);
      expect(handshake.failure, 'setsid: ${strerror(1)}');
    });

    test('stderr ending before ok fails it, and what came passes', () {
      final handshake = GroupHandshake('ab12');
      expect(handshake.add(bytes('chord-exec ab')), isEmpty);
      expect(text(handshake.close()), 'chord-exec ab');
      expect(handshake.state, HandshakeState.failed);
      expect(handshake.failure, 'it ended before it started');
    });

    test('a frame with the wrong nonce is the program\'s own and fails the '
        'start', () {
      final handshake = GroupHandshake('ab12');
      expect(
        text(handshake.add(bytes('chord-exec ffff ok\n'))),
        'chord-exec ffff ok\n',
      );
      expect(handshake.state, HandshakeState.failed);
    });

    test('a fail exec frame with the wrong nonce passes through', () {
      final handshake = GroupHandshake('ab12');
      handshake.add(bytes('chord-exec ab12 ok\n'));
      expect(
        text(handshake.add(bytes('chord-exec ffff fail exec 2\n'))),
        'chord-exec ffff fail exec 2\n',
      );
      expect(handshake.execErrno, isNull);
    });

    test('a frame after the program\'s first line is the program\'s own', () {
      final handshake = GroupHandshake('ab12');
      handshake.add(bytes('chord-exec ab12 ok\n'));
      expect(text(handshake.add(bytes('hello\n'))), 'hello\n');
      expect(
        text(handshake.add(bytes('chord-exec ab12 fail exec 2\n'))),
        'chord-exec ab12 fail exec 2\n',
      );
      expect(handshake.execErrno, isNull);
    });

    test('frames split across chunks, byte by byte', () {
      final handshake = GroupHandshake('ab12');
      final through = <int>[];
      for (final byte in bytes(
        'chord-exec ab12 ok\nchord-exec ab12 fail exec 13\n',
      )) {
        through.addAll(handshake.add([byte]));
      }
      expect(through, isEmpty);
      expect(handshake.state, HandshakeState.started);
      expect(handshake.execErrno, 13);
    });

    test('a line that starts like the exec frame and is not passes whole', () {
      final handshake = GroupHandshake('ab12');
      handshake.add(bytes('chord-exec ab12 ok\n'));
      expect(handshake.add(bytes('chord-exec ab12 fail exec')), isEmpty);
      expect(
        text(handshake.add(bytes(' x\n'))),
        'chord-exec ab12 fail exec x\n',
      );
      expect(handshake.execErrno, isNull);
    });
  });

  group('signalGroup', () {
    test('signals the group when it exists', () {
      final calls = <(int, int)>[];
      final took = signalGroup(
        (pid, signal) {
          calls.add((pid, signal));
          return 0;
        },
        42,
        15,
        exited: false,
      );
      expect(took, isTrue);
      expect(calls, [(-42, 15)]);
    });

    test('falls back to the pid alone on ESRCH before the exit', () {
      final calls = <(int, int)>[];
      final took = signalGroup(
        (pid, signal) {
          calls.add((pid, signal));
          return pid < 0 ? 3 : 0;
        },
        42,
        15,
        exited: false,
      );
      expect(took, isTrue);
      expect(calls, [(-42, 15), (42, 15)]);
    });

    test('never falls back once the exit is seen', () {
      final calls = <(int, int)>[];
      final took = signalGroup(
        (pid, signal) {
          calls.add((pid, signal));
          return 3;
        },
        42,
        9,
        exited: true,
      );
      expect(took, isFalse);
      expect(calls, [(-42, 9)]);
    });

    test('does not fall back on another error', () {
      final calls = <(int, int)>[];
      expect(
        signalGroup(
          (pid, signal) {
            calls.add((pid, signal));
            return 1;
          },
          42,
          15,
          exited: false,
        ),
        isFalse,
      );
      expect(calls, [(-42, 15)]);
    });
  });

  test('Exit reads a signal as 128 and its number', () {
    expect(Exit.fromExitCode(3), const Exit(3));
    expect(Exit.fromExitCode(-15), const Exit(143, 'SIGTERM'));
    expect(Exit.fromExitCode(-9), const Exit(137, 'SIGKILL'));
  });

  group('a real child', () {
    late Directory temp;
    late ProcessGroups groups;
    final started = <GroupProcess>[];

    setUp(() {
      temp = Directory.systemTemp.createTempSync('chord-group-');
      groups = ProcessGroups();
    });

    tearDown(() async {
      groups.killAll();
      for (final group in started) {
        await group.exit.then((_) {}, onError: (_) {});
      }
      started.clear();
      temp.deleteSync(recursive: true);
    });

    Future<GroupProcess> spawn(
      String program,
      List<String> args, {
      String? cwd,
      Map<String, String>? env,
      Launcher launcher = defaultLauncher,
    }) async {
      final group = await spawnGroup(
        program,
        args,
        cwd: cwd ?? temp.path,
        env: env,
        launcher: launcher,
        groups: groups,
      );
      started.add(group);
      return group;
    }

    Future<String> out(GroupProcess group) =>
        group.stdout.transform(utf8.decoder).join();

    Future<String> pgidOf(int pid) async =>
        ((await Process.run('ps', ['-o', 'pgid=', '-p', '$pid'])).stdout
                as String)
            .trim();

    bool running(int pid) =>
        Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

    test('leads its own group, with a grandchild in it that SIGTERM '
        'reaches, and nothing is left after', () async {
      final group = await spawn('sh', ['-c', r'sleep 30 & echo $!; wait']);
      await group.started;
      final lines = group.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final grandchild = int.parse(await lines.first);
      expect(await pgidOf(group.pid), '${group.pid}');
      expect(await pgidOf(grandchild), '${group.pid}');
      expect(group.alive(), isTrue);

      expect(group.signal(ProcessSignal.sigterm), isTrue);
      expect(await group.exit, const Exit(143, 'SIGTERM'));
      for (var i = 0; i < 100 && group.alive(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(group.alive(), isFalse);
      expect(running(grandchild), isFalse);
    });

    test('a missing program throws and starts nothing', () async {
      await expectLater(
        spawn('chord-no-such-agent', []),
        throwsA(
          isA<CannotStart>().having(
            (e) => e.toString(),
            'message',
            'cannot start chord-no-such-agent: ${strerror(2)}',
          ),
        ),
      );
      await expectLater(
        spawn('./nope', []),
        throwsA(
          isA<CannotStart>().having(
            (e) => e.toString(),
            'message',
            'cannot start ./nope: ${strerror(2)}',
          ),
        ),
      );
      expect(started, isEmpty);
    });

    test(
      'a program that is not executable throws and starts nothing',
      () async {
        File(p.join(temp.path, 'agent')).writeAsStringSync('#!/bin/sh\n');
        await expectLater(
          spawn('./agent', []),
          throwsA(
            isA<CannotStart>().having(
              (e) => e.toString(),
              'message',
              'cannot start ./agent: ${strerror(13)}',
            ),
          ),
        );
        await expectLater(spawn('.', []), throwsA(isA<CannotStart>()));
      },
    );

    // Holds the launcher until the gate file exists, so nothing of it has
    // run before then.
    Launcher gated(String gate) =>
        (nonce, path) => [
          '/bin/sh',
          '-c',
          r'while [ ! -e "$0" ]; do sleep 0.02; done; exec "$@"',
          gate,
          ...defaultLauncher(nonce, path),
        ];

    test('a program removed between resolution and exec fails the exit, '
        'after the group existed', () async {
      final agent = File(p.join(temp.path, 'agent'))
        ..writeAsStringSync('#!/bin/sh\n');
      Process.runSync('chmod', ['+x', agent.path]);
      final gate = p.join(temp.path, 'gate');
      final group = await spawn('./agent', [], launcher: gated(gate));
      agent.deleteSync();
      File(gate).writeAsStringSync('');
      await group.started;
      await expectLater(
        group.exit,
        throwsA(
          isA<CannotStart>().having(
            (e) => e.toString(),
            'message',
            'cannot start ./agent: ${strerror(2)}',
          ),
        ),
      );
      expect(await group.stderr.toList(), isEmpty);
    });

    test('an ok frame heard long after the exit still starts it', () async {
      final go = File(p.join(temp.path, 'go'));
      addTearDown(() {
        if (!go.existsSync()) go.createSync();
      });
      // The launcher exits at once; what it left holds its stderr and
      // writes `ok` only once the test says, as load can delay a frame
      // already written well past the exit. As a leak guard rather than a
      // test budget, what it left also leaves once this test process is
      // gone or a minute has passed, since no group of ours holds it.
      final group = await spawn(
        'sh',
        [],
        launcher: (nonce, _) => [
          '/bin/sh',
          '-c',
          r'(start=$(date +%s); while [ ! -e "$1" ] && kill -0 "$3" 2>/dev/null && '
              r'[ $(($(date +%s) - start)) -lt 60 ]; do sleep 0.01; done; '
              r'printf "chord-exec %s ok\\n" "$2" >&2) & exit 0',
          'launcher',
          go.path,
          nonce,
          '$pid',
        ],
      );
      while (running(group.pid)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // Its exit is reaped; well past the brief wait a frame once had.
      var settled = false;
      group.exit.then((_) => settled = true, onError: (_) => settled = true);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(settled, isFalse);
      go.createSync();
      await group.started;
      expect(await group.exit, const Exit(0));
    });

    test('a launcher stopped before its gate never starts, and leaves '
        'nothing', () async {
      final gate = p.join(temp.path, 'gate');
      final group = await spawn('sh', [
        '-c',
        'sleep 30',
      ], launcher: gated(gate));
      expect(group.signal(ProcessSignal.sigterm), isTrue);
      await expectLater(group.started, throwsA(isA<CannotStart>()));
      await expectLater(group.exit, throwsA(isA<CannotStart>()));
      expect(running(group.pid), isFalse);
      expect(group.alive(), isFalse);
    });

    test('a launcher stopped after its gate opened starts as usual', () async {
      final gate = p.join(temp.path, 'gate');
      final group = await spawn('sh', [
        '-c',
        'sleep 30',
      ], launcher: gated(gate));
      File(gate).writeAsStringSync('');
      await group.started;
      expect(await pgidOf(group.pid), '${group.pid}');
      expect(group.signal(ProcessSignal.sigterm), isTrue);
      expect(await group.exit, const Exit(143, 'SIGTERM'));
    });

    test('env is laid over chord\'s, PATH included, and the cwd is '
        'honoured', () async {
      final bin = Directory(p.join(temp.path, 'bin'))..createSync();
      final agent = File(
        p.join(bin.path, 'chord-test-agent'),
      )..writeAsStringSync('#!/bin/sh\necho "\$CHORD_TEST_X \$HOME"; pwd -P\n');
      Process.runSync('chmod', ['+x', agent.path]);
      final cwd = Directory(p.join(temp.path, 'elsewhere'))..createSync();
      final group = await spawn(
        'chord-test-agent',
        [],
        cwd: cwd.path,
        env: {
          'CHORD_TEST_X': 'laid',
          'PATH': '${bin.path}:${Platform.environment['PATH']}',
        },
      );
      expect(
        await out(group),
        '${'laid ${Platform.environment['HOME']}'}\n'
        '${cwd.resolveSymbolicLinksSync()}\n',
      );
      expect(await group.exit, const Exit(0));
    });

    test('relative and empty PATH entries are the agent\'s cwd\'s, not '
        'chord\'s', () async {
      File writeAgent(String dir, String says) {
        Directory(p.join(dir, 'bin')).createSync(recursive: true);
        final agent = File(p.join(dir, 'bin', 'chord-path-agent'))
          ..writeAsStringSync('#!/bin/sh\necho $says\n');
        Process.runSync('chmod', ['+x', agent.path]);
        return agent;
      }

      final chordDir = p.join(temp.path, 'chord');
      final agentDir = p.join(temp.path, 'agent');
      writeAgent(chordDir, 'chord');
      writeAgent(agentDir, 'agent');
      File(p.join(agentDir, 'chord-path-agent'))
        ..writeAsStringSync('#!/bin/sh\necho here\n')
        ..parent.createSync(recursive: true);
      Process.runSync('chmod', ['+x', p.join(agentDir, 'chord-path-agent')]);
      Directory(p.join(chordDir, 'chord-path-agent')).createSync();

      // In a process of its own whose current directory is chordDir: the
      // current directory is the whole test process's, other files' too.
      final fixture = Isolate.resolvePackageUriSync(
        Uri.parse('package:chord/platform/process.dart'),
      )!.resolve('../../test/fixtures/resolve_program.dart').toFilePath();
      Future<String> resolved(String path) async {
        final result = await Process.run(Platform.resolvedExecutable, [
          '--packages=${Isolate.packageConfigSync!.toFilePath()}',
          fixture,
          'chord-path-agent',
          agentDir,
          path,
        ], workingDirectory: chordDir).timeout(const Duration(seconds: 60));
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return (result.stdout as String).trim();
      }

      final inBin = p.join(agentDir, 'bin', 'chord-path-agent');
      final inCwd = p.join(agentDir, 'chord-path-agent');
      expect(await resolved('bin:/bin'), inBin);
      expect(await resolved('./bin:/bin'), inBin);
      expect(await resolved(':/bin'), inCwd);
      expect(await resolved('/bin::'), inCwd);

      final group = await spawn(
        'chord-path-agent',
        [],
        cwd: agentDir,
        env: {'PATH': 'bin:/bin'},
      );
      expect(await out(group), 'agent\n');

      File(inBin).deleteSync();
      expect(await resolved('bin'), 'cannot start');
    });

    test('argv reaches the program untouched', () async {
      final group = await spawn('sh', [
        '-c',
        r'printf "%s|" "$0" "$@"',
        '-dash-name',
        'a b',
        '',
        r'$HOME',
      ]);
      expect(await out(group), r'-dash-name|a b||$HOME|');
    });

    test('SIGPIPE is the default, as for node\'s children', () async {
      final group = await spawn('sh', ['-c', 'yes | head -n1']);
      final err = group.stderr.transform(utf8.decoder).join();
      expect(await out(group), 'y\n');
      expect(await err, isEmpty);
      expect(await group.exit, const Exit(0));
    });

    test(
      'killAll sends SIGKILL to every group still holding a process',
      () async {
        final group = await spawn('sh', ['-c', 'trap "" TERM; sleep 30']);
        await group.started;
        expect(groups.killAll(), [group.pid]);
        expect(await group.exit, const Exit(137, 'SIGKILL'));
        for (var i = 0; i < 100 && group.alive(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(groups.killAll(), isEmpty);
      },
    );

    test('an exit code is the program\'s own, 126 and 127 included', () async {
      for (final code in [0, 3, 126, 127]) {
        final group = await spawn('sh', ['-c', 'exit $code']);
        await group.started;
        expect(await group.exit, Exit(code));
      }
    });
  });

  group('the JIT launcher is found from', () {
    for (final (name, cwd, script) in [
      ('the repository root', '.', 'test/fixtures/group_child.dart'),
    ]) {
      test(name, () async {
        final result = await Process.run(Platform.resolvedExecutable, [
          'run',
          script,
        ], workingDirectory: cwd).timeout(const Duration(seconds: 60));
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final [pid, pgid] = (result.stdout as String).trim().split(
          RegExp(r'\s+'),
        );
        expect(pgid, pid);
      });
    }
  });

  group('tester: process group boundaries', () {
    test('handshake preserves payload at every byte split', () {
      for (final frame in [
        'chord-exec ab ok\n',
        'chord-exec ab fail setsid 1\n',
        'chord-exec ab ok\nchord-exec ab fail exec 13\n',
      ]) {
        final payload = utf8.encode('界👩‍💻e\u0301\n\u001b[31mwarning');
        final input = [...utf8.encode(frame), ...payload];
        for (var split = 0; split <= input.length; split++) {
          final handshake = GroupHandshake('ab');
          final through = [
            ...handshake.add(input.sublist(0, split)),
            ...handshake.add(input.sublist(split)),
            ...handshake.close(),
          ];
          expect(through, payload, reason: '$frame split $split');
          expect(handshake.settled, isTrue);
        }
      }
    });

    test('EOF releases an incomplete exec frame without reinterpreting it', () {
      final handshake = GroupHandshake('ab');
      handshake.add(utf8.encode('chord-exec ab ok\n'));
      final partial = utf8.encode('chord-exec ab fail exec 1');
      expect(handshake.add(partial), isEmpty);
      expect(handshake.close(), partial);
      expect(handshake.close(), isEmpty);
      expect(handshake.execErrno, isNull);
      expect(handshake.state, HandshakeState.started);
    });

    test('non-ASCII bytes in an apparent exec frame remain stderr', () {
      final handshake = GroupHandshake('ab');
      handshake.add(utf8.encode('chord-exec ab ok\n'));
      final payload = [...utf8.encode('chord-exec ab fail exec '), 255, 10];
      expect(handshake.add(payload), payload);
      expect(handshake.execErrno, isNull);
      expect(handshake.state, HandshakeState.started);
    });

    test('an errno larger than an integer remains program stderr', () {
      final handshake = GroupHandshake('ab');
      handshake.add(utf8.encode('chord-exec ab ok\n'));
      final payload = utf8.encode('chord-exec ab fail exec ${'9' * 100}\n');
      expect(handshake.add(payload), payload);
      expect(handshake.execErrno, isNull);
    });

    test('a failed ESRCH fallback reports failure and preserves signal', () {
      final calls = <(int, int)>[];
      expect(
        signalGroup(
          (pid, signal) {
            calls.add((pid, signal));
            return pid < 0 ? 3 : 1;
          },
          42,
          1,
          exited: false,
        ),
        isFalse,
      );
      expect(calls, [(-42, 1), (42, 1)]);
    });

    test('an unknown signal keeps its number', () {
      expect(Exit.fromExitCode(-99), const Exit(227, 'SIG99'));
      expect(Exit.fromExitCode(0), const Exit(0));
    });
  });
}
