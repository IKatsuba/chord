// CTUI-110: an expect driver the test owns leaves nothing behind when its
// case gives up on it, as a timed-out case does: the case's teardown
// kills the driver and what it spawned.
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'fixtures/expect_driver.dart';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

// The command [pid] runs, as ps names it; empty once it is gone.
String _command(int pid) =>
    '${Process.runSync('ps', ['-p', '$pid', '-o', 'comm=']).stdout}'.trim();

void main() {
  final hasExpect =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  var started = <int>[];

  test('a driver given up on is still running when its case ends', () async {
    final run = runExpect(['-c', 'spawn -noecho sleep 600; expect eof']);
    run.ignore();
    // Until the spawned sleep is up, under the driver; a process the spawn
    // passes through on its way there is not one to keep.
    for (var i = 0; i < 250 && started.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final driver = lastExpectPid;
      if (driver == null) continue;
      final sleeps = [
        for (final pid in await descendantsOf(driver))
          if (_command(pid).endsWith('sleep')) pid,
      ];
      if (sleeps.isNotEmpty) started = [driver, ...sleeps];
    }
    expect(started.length, greaterThanOrEqualTo(2), reason: '$started');
    await expectLater(
      run.timeout(const Duration(milliseconds: 200)),
      throwsA(isA<TimeoutException>()),
    );
    expect(started.every(_alive), isTrue);
  }, skip: hasExpect ? false : 'POSIX and expect are required');

  test('its teardown killed the driver and its tree', () async {
    for (var i = 0; i < 100 && started.any(_alive); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(started.where(_alive), isEmpty);
  }, skip: hasExpect ? false : 'POSIX and expect are required');

  test('an ended driver is not killed again', () async {
    final result = await runExpect(['-c', 'exit 3']);
    expect(result.exitCode, 3);
  }, skip: hasExpect ? false : 'POSIX and expect are required');

  // CTUI-121: a spawned program has a session of its own, so when expect
  // itself dies abnormally it is left with PPID 1, out of the driver's
  // tree, holding expect's stderr; the case gives up on the run and the
  // teardown still reaps the program.
  test('a program outliving its driver\'s abnormal exit is reaped', () async {
    final dir = Directory.systemTemp.createTempSync('expect-orphan-');
    final said = File('${dir.path}/pid');
    int? orphan;
    // Registered before runExpect's, so it runs after the driver's.
    addTearDown(() async {
      final pid = orphan;
      dir.deleteSync(recursive: true);
      if (pid == null) return;
      for (var i = 0; i < 100 && _alive(pid); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final left = _alive(pid);
      if (left) Process.killPid(pid, ProcessSignal.sigkill);
      expect(left, isFalse, reason: 'spawned $pid outlived the teardown');
    });
    // The program ignores the hangup its pty sends when expect is gone,
    // and is up before expect kills itself.
    final run = runExpect(
      [
        '-c',
        r'''log_user 0; set pid [spawn -noecho sh -c "trap '' HUP; '''
            r'''echo up; exec sleep 600"]; expect up; '''
            r'set file [open $env(ORPHAN_PID) w]; puts $file $pid; '
            r'close $file; exec kill -KILL [pid]',
      ],
      environment: {'ORPHAN_PID': said.path},
    );
    run.ignore();
    for (var i = 0; i < 250; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final driver = lastExpectPid;
      if (driver != null && !_alive(driver) && said.existsSync()) break;
    }
    orphan = int.tryParse(said.readAsStringSync().trim());
    expect(orphan, isNotNull);
    expect(_alive(lastExpectPid!), isFalse, reason: 'expect killed itself');
    expect(_alive(orphan!), isTrue, reason: 'it outlives the driver');
  }, skip: hasExpect ? false : 'POSIX and expect are required');

  // CTUI-125: that orphan holding expect's output must not keep the run
  // waiting until the case times out: it returns on expect's exit, its
  // output drained for a bounded time, and the teardown still reaps it.
  test(
    'a driver\'s abnormal exit returns despite an orphan\'s output',
    () async {
      final dir = Directory.systemTemp.createTempSync('expect-drain-');
      final said = File('${dir.path}/pid');
      // Registered before runExpect's, so it runs after the driver's.
      addTearDown(() async {
        final pid = int.tryParse(
          said.existsSync() ? said.readAsStringSync().trim() : '',
        );
        dir.deleteSync(recursive: true);
        if (pid == null) return;
        for (var i = 0; i < 100 && _alive(pid); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        final left = _alive(pid);
        if (left) Process.killPid(pid, ProcessSignal.sigkill);
        expect(left, isFalse, reason: 'spawned $pid outlived the teardown');
      });
      final watch = Stopwatch()..start();
      final result = await runExpect(
        [
          '-c',
          r'''log_user 0; set pid [spawn -noecho sh -c "trap '' HUP; '''
              r'''echo up; exec sleep 600"]; expect up; '''
              r'set file [open $env(ORPHAN_PID) w]; puts $file $pid; '
              r'close $file; puts stdout said; flush stdout; '
              r'exec kill -KILL [pid]',
        ],
        environment: {'ORPHAN_PID': said.path},
      ).timeout(expectDrain + const Duration(seconds: 10));
      watch.stop();
      expect(result.exitCode, -ProcessSignal.sigkill.signalNumber);
      expect(result.stdout, contains('said'));
      expect(watch.elapsed, lessThan(expectDrain + const Duration(seconds: 5)));
      final orphan = int.parse(said.readAsStringSync().trim());
      expect(_alive(orphan), isTrue, reason: 'it outlives the driver');
    },
    skip: hasExpect ? false : 'POSIX and expect are required',
  );

  test('output that cannot be decoded fails the run', () async {
    final run = runExpect([
      '-c',
      'fconfigure stdout -translation binary; '
          'puts -nonewline stdout [binary format c2 {-1 -2}]; '
          'flush stdout; exit 0',
    ]);
    await expectLater(run, throwsA(isA<FormatException>()));
  }, skip: hasExpect ? false : 'POSIX and expect are required');

  // CTUI-126: a driver that never started leaves no directory behind.
  test('a driver that fails to start removes its record directory', () async {
    final missing = '${Directory.systemTemp.path}/expect-driver-missing-$pid';
    await expectLater(
      runExpect(['-c', 'exit 0'], workingDirectory: missing),
      throwsA(isA<ProcessException>()),
    );
    expect(lastExpectSpawns!.existsSync(), isFalse);
  }, skip: hasExpect ? false : 'POSIX and expect are required');

  // CTUI-126: the identity recorded at spawn names the spawn, and a
  // process started after the record is not taken for it.
  test('a spawn\'s recorded identity names it, not a later process', () async {
    final run = runExpect(['-c', 'spawn -noecho sleep 600; expect eof']);
    run.ignore();
    final spawned = File('${lastExpectSpawns!.path}/spawned');
    var record = '';
    for (var i = 0; i < 250 && record.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      record = spawned.readAsStringSync().trim();
    }
    final [child, recorded] = record.split(' ').map(int.parse).toList();
    final identity = spawnIdentity(child);
    expect(identity, isNotNull);
    expect(spawnedAs(identity!, recorded), isTrue);
    expect(spawnedAs(identity, identity), isTrue);
    expect(spawnedAs(identity, identity - 1), isFalse);
  }, skip: hasExpect ? false : 'POSIX and expect are required');

  test('on macOS a process\'s identity is its start in microseconds', () async {
    final before = DateTime.now().microsecondsSinceEpoch;
    final process = await Process.start('sleep', ['60']);
    final after = DateTime.now().microsecondsSinceEpoch;
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    expect(spawnIdentity(process.pid), inInclusiveRange(before, after));
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    expect(spawnIdentity(process.pid), isNull);
  }, skip: Platform.isMacOS ? false : 'the macOS start time is read here');

  // The command in /proc/<pid>/stat is in parentheses and may hold spaces
  // and parentheses, which both the hook and spawnIdentity skip.
  test(
    'on Linux the identity is the /proc start of a spawn of any name',
    () async {
      final dir = Directory.systemTemp.createTempSync('expect-identity-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final named = '${dir.path}/a) b (c';
      File(
        Process.runSync('sh', ['-c', 'command -v sleep']).stdout.trim(),
      ).copySync(named);
      Process.runSync('chmod', ['+x', named]);
      final run = runExpect(['-c', 'spawn -noecho {$named} 600; expect eof']);
      run.ignore();
      final spawned = File('${lastExpectSpawns!.path}/spawned');
      var record = '';
      for (var i = 0; i < 250 && record.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        record = spawned.readAsStringSync().trim();
      }
      final [child, recorded] = record.split(' ').map(int.parse).toList();
      expect(spawnIdentity(child), recorded);
    },
    skip: Platform.isLinux && hasExpect
        ? false
        : 'the Linux /proc start time is read here, with expect',
  );

  group('tester CTUI-121: orphaned spawn trees', () {
    test('reaps every spawn and its descendants after driver death', () async {
      final dir = Directory.systemTemp.createTempSync('expect-trees-tester-');
      final said = File('${dir.path}/pids');
      var owned = <int>[];
      addTearDown(() async {
        try {
          for (var i = 0; i < 100 && owned.any(_alive); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          expect(owned.where(_alive), isEmpty);
        } finally {
          for (final pid in owned.where(_alive)) {
            Process.killPid(pid, ProcessSignal.sigkill);
          }
          dir.deleteSync(recursive: true);
        }
      });
      final run = runExpect(
        [
          '-c',
          r'''log_user 0; spawn -noecho sh -c {trap '' HUP; sleep 600 & '''
              r'''echo "$$ $!" >> "$TESTER_EXPECT_PIDS"; echo up; wait}; '''
              r'''expect up; spawn -noecho sh -c {trap '' HUP; sleep 600 & '''
              r'''echo "$$ $!" >> "$TESTER_EXPECT_PIDS"; echo up; wait}; '''
              r'expect up; exec kill -KILL [pid]',
        ],
        environment: {'TESTER_EXPECT_PIDS': said.path},
      );
      run.ignore();
      for (var i = 0; i < 250; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (said.existsSync()) {
          owned = said
              .readAsStringSync()
              .trim()
              .split(RegExp(r'\s+'))
              .map(int.parse)
              .toList();
        }
        if (owned.length == 4 && !_alive(lastExpectPid!)) break;
      }
      expect(owned.toSet(), hasLength(4));
      expect(_alive(lastExpectPid!), isFalse);
      expect(owned.every(_alive), isTrue);
    }, skip: hasExpect ? false : 'POSIX and expect are required');
  });

  group('tester CTUI-110: expect result compatibility', () {
    test('keeps stdout, stderr, environment, cwd and nonzero status', () async {
      final dir = Directory.systemTemp.createTempSync('expect-result-tester-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final result = await runExpect(
        [
          '-c',
          r'puts [pwd]; puts -nonewline stdout $env(TESTER_EXPECT_VALUE); '
              'puts -nonewline stderr {separate error}; '
              'flush stdout; flush stderr; exit 7',
        ],
        workingDirectory: dir.path,
        environment: {'TESTER_EXPECT_VALUE': 'sentinel-value'},
      );
      expect(result.pid, greaterThan(0));
      expect(result.exitCode, 7);
      expect(
        result.stdout,
        '${dir.resolveSymbolicLinksSync()}\nsentinel-value',
      );
      expect(result.stderr, 'separate error');
    }, skip: hasExpect ? false : 'POSIX and expect are required');
  });
}
