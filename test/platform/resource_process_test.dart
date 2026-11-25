// The original's tests/platform/resource_process_test.ts: a reader's group
// closed on every way out, a cancel or the total past ahead of an answer
// revoking it, refusals in fixed words, a missing executable a startup
// failure. The provider is a shell script that waits on its stdin, which
// needs no bun.
@TestOn('posix')
library;

import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/platform/process.dart';
import 'package:chord/platform/resource_process.dart';
import 'package:path/path.dart' as p;
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;
import 'package:test/test.dart';

/// A process that ends once its stdin does, as the original's `normal`
/// provider does; [ignoreTerm] leaves it to SIGKILL.
List<String> _provider({bool ignoreTerm = false}) {
  final dir = Directory.systemTemp.createTempSync('chord-resource-process-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final script = File(p.join(dir.path, 'provider'))
    ..writeAsStringSync(
      '#!/bin/sh\n'
      '${ignoreTerm ? "trap '' TERM\nwhile :; do sleep 1; done\n" : 'exec cat > /dev/null\n'}',
    );
  Process.runSync('chmod', ['+x', script.path]);
  return [script.path];
}

bool _dead(int pid) => !Process.killPid(pid, ProcessSignal.sigcont);

/// [kind]'s [ResourceReadError].
Matcher _kind(String kind) =>
    throwsA(isA<ResourceReadError>().having((e) => e.kind, 'kind', kind));

final class _Status implements ResourceStatus {
  _Status(this.status);
  @override
  final int status;
  @override
  String toString() => 'excluded-provider-detail';
}

/// A monotonic clock a test steps: each look at it is [step] later, so a
/// rung's bound is reached in a known number of looks whatever the wall
/// clock does.
final class _SteppedWatch implements Stopwatch {
  _SteppedWatch(this.step);

  final Duration step;
  var looks = 0;

  @override
  Duration get elapsed => step * looks++;

  @override
  void start() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CTUI-37 tester: reader error and cleanup ownership', () {
    test(
      'a hanging library close cannot retain its failed read group',
      () async {
        late GroupProcess group;
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        var closes = 0;
        final result = withResourceProcess<String>(
          _provider(ignoreTerm: true),
          cwd: Directory.current.path,
          cancelled: CancellationToken(),
          bounds: (
            total: const Duration(seconds: 20),
            initialize: collectorBounds.initialize,
            request: collectorBounds.request,
            close: const Duration(milliseconds: 50),
            term: const Duration(milliseconds: 50),
            kill: const Duration(seconds: 2),
          ),
          read: (owned, _, onClose) {
            group = owned;
            onClose(() {
              closes++;
              return release.future;
            });
            return Future.error(_Status(401));
          },
        );
        await expectLater(result, _kind('authentication'));
        expect(closes, 1);
        expect(release.isCompleted, isFalse);
        expect(group.alive(), isFalse);
        expect(_dead(group.pid), isTrue);
        release.complete();
      },
    );

    test(
      'JSON-RPC numeric refusal codes retain fixed words after group cleanup',
      () async {
        for (final (code, kind) in [
          (401, 'authentication'),
          (429, 'rate-limit'),
        ]) {
          late GroupProcess group;
          final result = withResourceProcess<String>(
            _provider(),
            cwd: Directory.current.path,
            cancelled: CancellationToken(),
            read: (owned, _, _) {
              group = owned;
              return Future.error(RpcException(code, 'excluded-secret-detail'));
            },
          );
          await expectLater(
            result,
            throwsA(
              isA<ResourceReadError>()
                  .having((error) => error.kind, 'kind', kind)
                  .having(
                    (error) => error.message,
                    'message',
                    isNot(contains('excluded-secret-detail')),
                  ),
            ),
          );
          expect(group.alive(), isFalse);
          expect(_dead(group.pid), isTrue);
        }
      },
    );
  });

  test("a rung waits its bound on a monotonic clock, not the wall's", () async {
    final watch = _SteppedWatch(const Duration(milliseconds: 100));
    var asked = 0;
    final gone = await goneWithin(
      () {
        asked++;
        return true;
      },
      const Duration(milliseconds: 500),
      watch: () => watch,
    );
    expect(gone, isFalse);
    // Looks at 0, 100, …, 500 ms of the stepped clock: six, then done.
    expect(watch.looks, 6);
    expect(asked, 7);
    // Gone at once is gone, without waiting.
    expect(await goneWithin(() => false, const Duration(seconds: 5)), isTrue);
  });

  test('late read resolution after cancellation cannot publish and no group '
      'remains', () async {
    final cancelled = CancellationToken();
    final pending = Completer<String>();
    final entered = Completer<void>();
    var published = false;
    late GroupProcess group;
    final result =
        withResourceProcess(
          _provider(),
          cwd: Directory.current.path,
          cancelled: cancelled,
          read: (each, _, _) {
            group = each;
            entered.complete();
            return pending.future;
          },
        ).then((value) {
          published = true;
          return value;
        });
    await entered.future;
    cancelled.cancel();
    await expectLater(result, _kind('cancelled'));
    pending.complete('late observation');
    await pending.future;
    expect(published, isFalse);
    expect(group.alive(), isFalse);
  });

  test('cancellation while a successful read closes still revokes '
      'publication', () async {
    final cancelled = CancellationToken();
    final closing = Completer<void>();
    final release = Completer<void>();
    final result = withResourceProcess(
      _provider(),
      cwd: Directory.current.path,
      cancelled: cancelled,
      read: (_, _, onClose) async {
        onClose(() {
          closing.complete();
          return release.future;
        });
        return 'finished observation';
      },
    );
    await closing.future;
    cancelled.cancel();
    release.complete();
    await expectLater(result, _kind('cancelled'));
  });

  test('total deadline while a successful read closes revokes '
      'publication', () async {
    var enteredClose = false;
    late GroupProcess group;
    final result = withResourceProcess(
      _provider(),
      cwd: Directory.current.path,
      cancelled: CancellationToken(),
      // The close waits for the deadline itself, so the total only has to
      // outlast the spawn, which a loaded machine stretches past 250 ms.
      bounds: (
        total: const Duration(seconds: 2),
        initialize: collectorBounds.initialize,
        request: collectorBounds.request,
        close: const Duration(seconds: 30),
        term: collectorBounds.term,
        kill: collectorBounds.kill,
      ),
      read: (each, within, onClose) async {
        group = each;
        onClose(() async {
          enteredClose = true;
          while (!within.isCancelled) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        return 'observation before deadline';
      },
    );
    await expectLater(
      result,
      throwsA(
        isA<ResourceReadError>().having(
          (e) => e.message,
          'message',
          'Resource acquisition exceeded its deadline.',
        ),
      ),
    );
    expect(enteredClose, isTrue);
    expect(group.alive(), isFalse);
  });

  test('a group seen gone before its exit is heard still closes '
      'cleanly', () async {
    final dir = Directory.systemTemp.createTempSync('chord-resource-late-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final go = File(p.join(dir.path, 'go'));
    // It waits for `go`, and, as a leak guard rather than a test budget,
    // leaves by itself once the test process that started it is gone (its
    // parent changes, or was launchd from the start) or a minute has passed.
    final script = File(p.join(dir.path, 'provider'))
      ..writeAsStringSync(
        '#!/bin/sh\n'
        r'parent=$PPID start=$(date +%s)'
        '\n'
        r'while [ ! -e "$1" ] && [ "$parent" != 1 ] && '
        r'[ "$(ps -o ppid= -p $$ | tr -d " ")" = "$parent" ] && '
        r'[ $(($(date +%s) - start)) -lt 60 ]; do sleep 0.05; done'
        '\n',
      );
    Process.runSync('chmod', ['+x', script.path]);
    int? pid;
    // Best effort, the fixture guarding itself: released, given a moment,
    // and killed by its recorded pid only while that pid is still it.
    addTearDown(() async {
      if (!go.existsSync()) go.createSync();
      bool running() =>
          pid != null &&
          (Process.runSync('ps', ['-o', 'command=', '-p', '$pid']).stdout
                  as String)
              .contains(script.path);
      final until = DateTime.now().add(const Duration(seconds: 5));
      while (running() && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (running()) Process.killPid(pid!, ProcessSignal.sigkill);
    });
    var closing = false;
    var looks = 0;
    // Every look finds the group gone (ESRCH) while the process still runs,
    // as when the VM has reaped a group and not yet told of its exit. After
    // the library close, the zero-length wait looks twice and the third
    // look is the one cleanup makes as it judges the exit: the process is
    // released only there, so no exit can have been heard by then,
    // whatever the load.
    int kill(int pid, int signal) {
      if (closing && ++looks == 3) go.createSync();
      return 3;
    }

    final result = withResourceProcess(
      [script.path, go.path],
      cwd: Directory.current.path,
      cancelled: CancellationToken(),
      // The exit, released at that look, has this long to be heard.
      bounds: (
        total: const Duration(seconds: 30),
        initialize: collectorBounds.initialize,
        request: collectorBounds.request,
        close: collectorBounds.close,
        term: collectorBounds.term,
        kill: const Duration(seconds: 10),
      ),
      kill: kill,
      read: (group, _, onClose) async {
        pid = group.pid;
        onClose(() async => closing = true);
        return 'observation';
      },
    );
    expect(await result, 'observation');
    expect(go.existsSync(), isTrue);
  });

  test('provider refusals stay in fixed words and every failed read drains '
      'its group', () async {
    for (final (status, kind) in [
      (401, 'authentication'),
      (403, 'authentication'),
      (429, 'rate-limit'),
      (500, 'protocol'),
    ]) {
      late GroupProcess group;
      final result = withResourceProcess<String>(
        _provider(),
        cwd: Directory.current.path,
        cancelled: CancellationToken(),
        read: (each, _, _) {
          group = each;
          return Future.error(_Status(status));
        },
      );
      await expectLater(result, _kind(kind));
      await expectLater(
        result,
        throwsA(
          isA<ResourceReadError>().having(
            (e) => e.message,
            'message',
            isNot(contains('excluded-provider-detail')),
          ),
        ),
      );
      expect(group.alive(), isFalse, reason: '$status');
    }
  });

  test('a missing executable is a startup failure with no raw executable '
      'path', () async {
    await expectLater(
      withResourceProcess(
        ['/nonexistent-resource-fixture/executable'],
        cwd: Directory.current.path,
        cancelled: CancellationToken(),
        read: (_, _, _) async => 'must not run',
      ),
      throwsA(
        isA<ResourceReadError>()
            .having((e) => e.kind, 'kind', 'startup')
            .having(
              (e) => e.message,
              'message',
              'The collector process failed to start.',
            ),
      ),
    );
  });

  test('a cancel before the start starts nothing', () async {
    var read = false;
    await expectLater(
      withResourceProcess(
        _provider(),
        cwd: Directory.current.path,
        cancelled: CancellationToken()..cancel(),
        read: (_, _, _) async => read = true,
      ),
      throwsA(
        isA<ResourceReadError>().having(
          (e) => e.message,
          'message',
          'Resource read cancelled before startup.',
        ),
      ),
    );
    expect(read, isFalse);
  });

  test('a group that ignores SIGTERM is killed down the ladder, within its '
      'bounds', () async {
    late GroupProcess group;
    final started = DateTime.now();
    final answer = await withResourceProcess(
      _provider(ignoreTerm: true),
      cwd: Directory.current.path,
      cancelled: CancellationToken(),
      read: (each, _, _) async {
        group = each;
        return 'read';
      },
    );
    expect(answer, 'read');
    expect(group.alive(), isFalse);
    expect(_dead(group.pid), isTrue);
    // close, then SIGTERM's wait, then SIGKILL: about a second, never the
    // 20 s total.
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 5)),
    );
  });
}
