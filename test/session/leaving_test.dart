import 'dart:async';
import 'dart:io';

import 'package:chord/platform/process.dart';
import 'package:chord/session/leaving.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('Owned', () {
    test('closes all it owns once, then owns nothing', () async {
      final o = Owned();
      final closed = <String>[];
      o.closeOnForcedExit(() async => closed.add('a'));
      o.closeOnForcedExit(() async => closed.add('b'));
      await Future.wait(o.closeOwned());
      expect(closed, ['a', 'b']);
      expect(o.closeOwned(), isEmpty);
    });

    test('a close forgotten is not run', () async {
      final o = Owned();
      var ran = false;
      final forget = o.closeOnForcedExit(() async => ran = true);
      forget();
      await Future.wait(o.closeOwned());
      expect(ran, isFalse);
    });

    test('one close given twice is owned twice', () async {
      final o = Owned();
      var runs = 0;
      Future<void> close() async => runs++;
      final forget = o.closeOnForcedExit(close);
      o.closeOnForcedExit(close);
      forget();
      await Future.wait(o.closeOwned());
      expect(runs, 1);
    });

    test('a close that forgets itself or another still lets every close '
        'run, and leave reach the kill', () async {
      final o = Owned();
      final ran = <String>[];
      late void Function() forgetSelf;
      late void Function() forgetOther;
      forgetSelf = o.closeOnForcedExit(() async {
        forgetSelf();
        forgetOther();
        ran.add('first');
      });
      forgetOther = o.closeOnForcedExit(() async => ran.add('second'));
      final groups = _Groups([]);
      await leave(from: o, groups: groups);
      expect(ran, ['first', 'second']);
      expect(groups.kills, 1);
    });

    test('a close that throws at once still gives a future', () async {
      final o = Owned();
      o.closeOnForcedExit(() => throw StateError('no'));
      final closing = o.closeOwned();
      expect(closing, hasLength(1));
      await expectLater(closing.single, throwsStateError);
    });
  });

  group('leave', () {
    test('waits for every close and the terminal, however they go, then '
        'kills what groups are left', () async {
      final o = Owned();
      final done = <String>[];
      final slow = Completer<void>();
      o.closeOnForcedExit(() => slow.future.then((_) => done.add('slow')));
      o.closeOnForcedExit(() async => throw StateError('failed close'));
      final groups = _Groups(done);
      final leaving = leave(
        from: o,
        groups: groups,
        giveBack: () async => done.add('gave back'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(done, ['gave back']);
      slow.complete();
      await leaving;
      expect(done, ['gave back', 'slow', 'killed']);
    });

    test('a leave under way is joined, not started again', () async {
      final o = Owned();
      final slow = Completer<void>();
      var closes = 0;
      o.closeOnForcedExit(() {
        closes++;
        return slow.future;
      });
      final groups = _Groups([]);
      final first = leave(from: o, groups: groups);
      final second = leave(from: o, groups: groups);
      expect(identical(first, second), isTrue);
      slow.complete();
      await Future.wait([first, second]);
      expect(closes, 1);
      expect(groups.kills, 1);
    });

    test(
      'a failing terminal is waited for and does not stop the kill',
      () async {
        final groups = _Groups([]);
        await leave(
          from: Owned(),
          groups: groups,
          giveBack: () => throw StateError('no terminal'),
        );
        expect(groups.kills, 1);
      },
    );
  });
  group('tester ownership lifecycle', () {
    test('ownership added during close belongs to the next leave', () async {
      final owners = Owned();
      final events = <String>[];
      final groups = _Groups(events);
      owners.closeOnForcedExit(() async {
        events.add('first');
        owners.closeOnForcedExit(() async => events.add('later'));
      });
      await leave(from: owners, groups: groups);
      expect(events, ['first', 'killed']);
      await leave(from: owners, groups: groups);
      expect(events, ['first', 'killed', 'later', 'killed']);
      expect(groups.kills, 2);
    });

    test(
      'all failures settle before the sweep and a later leave still works',
      () async {
        final owners = Owned();
        final events = <String>[];
        final gate = Completer<void>();
        owners.closeOnForcedExit(() => throw StateError('synchronous close'));
        owners.closeOnForcedExit(() => gate.future);
        final groups = _Groups(events);
        final first = leave(
          from: owners,
          groups: groups,
          giveBack: () async => throw StateError('restore'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(groups.kills, 0);
        gate.completeError(StateError('asynchronous close'));
        await first;
        expect(groups.kills, 1);
        owners.closeOnForcedExit(() async => events.add('next'));
        await leave(from: owners, groups: groups);
        expect(events, ['killed', 'next', 'killed']);
      },
    );
  });

  group('Leaving', () {
    final never = Completer<void>().future;

    ({
      Leaving leaving,
      List<String> lines,
      List<LeaveExit> exits,
      List<String> calls,
      _Groups groups,
    })
    setUpLeaving({
      void Function()? answer,
      Future<void> Function()? drained,
      FutureOr<void> Function()? closeConnection,
      List<LeaveStep> steps = const [],
      void Function(String line)? stderr,
      List<int> left = const [],
      Duration leaveTime = leaveTime,
      Duration drainTime = drainTime,
    }) {
      final lines = <String>[];
      final exits = <LeaveExit>[];
      final calls = <String>[];
      final groups = _Groups(calls, left);
      final leaving = Leaving(
        answer: answer ?? () => calls.add('answer'),
        drained: drained ?? () async {},
        closeConnection: closeConnection ?? () => calls.add('close'),
        steps: () => steps,
        stderr: stderr ?? lines.add,
        exit: exits.add,
        groups: groups,
        leaveTime: leaveTime,
        drainTime: drainTime,
      );
      return (
        leaving: leaving,
        lines: lines,
        exits: exits,
        calls: calls,
        groups: groups,
      );
    }

    test('EOF sends no answers and exits 0 when clean', () async {
      final (:leaving, :exits, :calls, :lines, groups: _) = setUpLeaving();
      await leaving.leave(const LeaveEof());
      expect(calls, ['close', 'killed']);
      expect(exits, [const LeaveExit.code(0)]);
      expect(lines, isEmpty);
    });

    test('a signal answers first, then dies by that signal', () async {
      final (:leaving, :exits, :calls, lines: _, groups: _) = setUpLeaving();
      await leaving.leave(const LeaveSignal(ProcessSignal.sigterm));
      expect(calls, ['answer', 'close', 'killed']);
      expect(exits, [const LeaveExit.signal(ProcessSignal.sigterm)]);
    });

    test('a crash answers and exits 1; a broken connection does not '
        'answer', () async {
      final crash = setUpLeaving();
      final broken = setUpLeaving();
      await crash.leaving.leave(const LeaveCrash());
      await broken.leaving.leave(const LeaveBroken());
      expect(crash.calls, ['answer', 'close', 'killed']);
      expect(crash.exits, [const LeaveExit.code(1)]);
      expect(broken.calls, ['close', 'killed']);
      expect(broken.exits, [const LeaveExit.code(1)]);
    });

    test('runs once, whatever asks again', () async {
      final (:leaving, :exits, :calls, lines: _, groups: _) = setUpLeaving();
      final first = leaving.leave(const LeaveEof());
      expect(
        identical(
          leaving.leave(const LeaveSignal(ProcessSignal.sigint)),
          first,
        ),
        isTrue,
      );
      await first;
      expect(calls, ['close', 'killed']);
      expect(exits, [const LeaveExit.code(0)]);
    });

    test('new work is refused from before the answers go', () async {
      var seen = false;
      late Leaving holder;
      final (:leaving, exits: _, calls: _, lines: _, groups: _) = setUpLeaving(
        answer: () => seen = holder.started,
      );
      holder = leaving;
      expect(leaving.started, isFalse);
      await leaving.leave(const LeaveSignal(ProcessSignal.sigint));
      expect(seen, isTrue);
    });

    test('a drain that never ends waits only its bound, 500 ms', () {
      fakeAsync((async) {
        final (:leaving, :exits, :calls, lines: _, groups: _) = setUpLeaving(
          drained: () => never,
        );
        leaving.leave(const LeaveSignal(ProcessSignal.sighup));
        async.elapse(const Duration(milliseconds: 499));
        expect(calls, ['answer']);
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, ['answer', 'close', 'killed']);
        expect(exits, [const LeaveExit.signal(ProcessSignal.sighup)]);
      });
    });

    test('a drain that fails is kept, and the connection still '
        'closes', () async {
      final (:leaving, :exits, :calls, :lines, groups: _) = setUpLeaving(
        drained: () async => throw StateError('EPIPE'),
      );
      await leaving.leave(const LeaveEof());
      expect(calls, ['close', 'killed']);
      expect(lines, ['chord: drain: EPIPE']);
      expect(exits, [const LeaveExit.code(1)]);
    });

    test('a synchronous drain failure still closes and keeps the '
        'failure', () async {
      final (:leaving, :exits, :calls, :lines, groups: _) = setUpLeaving(
        drained: () => throw StateError('drain threw'),
      );
      await leaving.leave(const LeaveEof());
      expect(calls, ['close', 'killed']);
      expect(lines, ['chord: drain: drain threw']);
      expect(exits, [const LeaveExit.code(1)]);
    });

    test('a stderr that throws does not stop the way out', () async {
      final (:leaving, :exits, calls: _, lines: _, groups: _) = setUpLeaving(
        stderr: (_) => throw StateError('EPIPE'),
        steps: [LeaveStep('host', () => throw StateError('no'))],
      );
      await leaving.leave(const LeaveEof());
      expect(exits, [const LeaveExit.code(1)]);
    });

    test('each failure on stderr, the rest run, exit 1 on EOF', () async {
      var ran = false;
      final (:leaving, :exits, calls: _, :lines, groups: _) = setUpLeaving(
        steps: [
          LeaveStep('host', () => throw StateError('flush failed')),
          LeaveStep('probes', () => Future.error(Exception('stuck'))),
          LeaveStep('readers', () => ran = true),
        ],
      );
      await leaving.leave(const LeaveEof());
      expect(ran, isTrue);
      expect(lines, ['chord: host: flush failed', 'chord: probes: stuck']);
      expect(exits, [const LeaveExit.code(1)]);
    });

    test('a failure under a signal still dies by the signal', () async {
      final (:leaving, :exits, calls: _, :lines, groups: _) = setUpLeaving(
        answer: () => throw StateError('no connection'),
      );
      await leaving.leave(const LeaveSignal(ProcessSignal.sigterm));
      expect(lines, ['chord: answers: no connection']);
      expect(exits, [const LeaveExit.signal(ProcessSignal.sigterm)]);
    });

    test('an answer can reenter leave without starting another', () async {
      Future<void>? nested;
      late Leaving holder;
      final (:leaving, :exits, :calls, lines: _, groups: _) = setUpLeaving(
        answer: () => nested = holder.leave(const LeaveEof()),
      );
      holder = leaving;
      final first = leaving.leave(const LeaveSignal(ProcessSignal.sigint));
      expect(identical(nested, first), isTrue);
      await first;
      expect(calls, ['close', 'killed']);
      expect(exits, [const LeaveExit.signal(ProcessSignal.sigint)]);
    });

    test('steps are taken when it starts, so what opened before is '
        'closed', () async {
      final steps = <LeaveStep>[];
      final calls = <String>[];
      final leaving = Leaving(
        answer: () {},
        drained: () async {},
        closeConnection: () {},
        steps: () => steps,
        stderr: (_) {},
        exit: (_) {},
        groups: _Groups(calls, const []),
      );
      steps.add(LeaveStep('s1', () => calls.add('s1')));
      await leaving.leave(const LeaveEof());
      expect(calls, ['s1', 'killed']);
    });

    test('the deadline names each step not settled and the groups it '
        'kills, after 15 s', () {
      fakeAsync((async) {
        final (:leaving, :exits, :calls, :lines, groups: _) = setUpLeaving(
          drained: () => never,
          drainTime: const Duration(seconds: 1),
          steps: [
            LeaveStep('first host', () => never),
            LeaveStep('second host', () => never),
            LeaveStep('collector', () {}),
          ],
          left: [4242, 4343],
        );
        leaving.leave(const LeaveEof());
        async.elapse(const Duration(milliseconds: 14999));
        expect(exits, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(lines, [
          'chord: not settled at the deadline: first host, second host',
          'chord: killed process group 4242',
          'chord: killed process group 4343',
        ]);
        expect(calls, ['close', 'killed']);
        expect(exits, [const LeaveExit.code(1)]);
      });
    });

    test('a hung connection close is named at the deadline', () {
      fakeAsync((async) {
        var closed = false;
        final (:leaving, exits: _, :calls, :lines, groups: _) = setUpLeaving(
          drained: () => never,
          closeConnection: () {
            closed = true;
            return never;
          },
        );
        leaving.leave(const LeaveEof());
        async.elapse(leaveTime);
        expect(closed, isTrue);
        expect(calls, ['killed']);
        expect(lines, ['chord: not settled at the deadline: connection']);
      });
    });

    test('a signal at the deadline still dies by it', () {
      fakeAsync((async) {
        final (:leaving, :exits, calls: _, lines: _, groups: _) = setUpLeaving(
          steps: [LeaveStep('host', () => never)],
        );
        leaving.leave(const LeaveSignal(ProcessSignal.sigterm));
        async.elapse(leaveTime);
        expect(exits, [const LeaveExit.signal(ProcessSignal.sigterm)]);
      });
    });

    test('a late settle after the deadline exits nothing more', () {
      fakeAsync((async) {
        final late = Completer<void>();
        final (:leaving, :exits, :calls, lines: _, groups: _) = setUpLeaving(
          steps: [LeaveStep('host', () => late.future)],
        );
        leaving.leave(const LeaveEof());
        async.elapse(leaveTime);
        late.complete();
        async.flushMicrotasks();
        expect(exits, [const LeaveExit.code(1)]);
        expect(calls, ['close', 'killed']);
      });
    });

    test('all settled: what the registry still holds has SIGKILL', () async {
      final groups = ProcessGroups();
      final left = await spawnGroup(
        'sh',
        ['-c', 'sleep 60'],
        cwd: Directory.systemTemp.path,
        groups: groups,
      );
      addTearDown(() => left.signal(ProcessSignal.sigkill));
      await left.started;
      final exits = <LeaveExit>[];
      await Leaving(
        answer: () {},
        drained: () async {},
        closeConnection: () {},
        steps: () => const [],
        stderr: (_) {},
        exit: exits.add,
        groups: groups,
      ).leave(const LeaveEof());
      expect(exits, [const LeaveExit.code(0)]);
      await left.exit.timeout(const Duration(seconds: 5));
      expect(left.alive(), isFalse);
    });
  });

  group('tester U1 shutdown boundaries', () {
    test('hosts start together while the connection drain is held', () {
      fakeAsync((async) {
        final drain = Completer<void>();
        final first = Completer<void>();
        final second = Completer<void>();
        final calls = <String>[];
        final exits = <LeaveExit>[];
        final groups = _Groups(calls);
        final leaving = Leaving(
          answer: () => calls.add('answer'),
          drained: () => drain.future,
          closeConnection: () => calls.add('connection'),
          steps: () => [
            LeaveStep('first', () {
              calls.add('first');
              return first.future;
            }),
            LeaveStep('second', () {
              calls.add('second');
              return second.future;
            }),
            LeaveStep('collector', () => calls.add('collector')),
          ],
          stderr: (_) {},
          exit: exits.add,
          groups: groups,
        );
        leaving.leave(const LeaveEof());
        expect(calls, ['first', 'second', 'collector']);
        second.complete();
        first.complete();
        async.flushMicrotasks();
        expect(groups.kills, 0);
        expect(exits, isEmpty);
        drain.complete();
        async.flushMicrotasks();
        expect(calls, ['first', 'second', 'collector', 'connection', 'killed']);
        expect(exits, [const LeaveExit.code(0)]);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('the deadline bounds the drain and every host independently', () {
      fakeAsync((async) {
        final drain = Completer<void>();
        final host = Completer<void>();
        final lines = <String>[];
        final exits = <LeaveExit>[];
        final calls = <String>[];
        final leaving = Leaving(
          answer: () {},
          drained: () => drain.future,
          closeConnection: () => calls.add('connection'),
          steps: () => [
            LeaveStep('first host', () => host.future),
            LeaveStep('second host', () => host.future),
            LeaveStep('collector', () => calls.add('collector')),
          ],
          stderr: lines.add,
          exit: exits.add,
          groups: _Groups(calls, [4242]),
          leaveTime: const Duration(milliseconds: 20),
          drainTime: const Duration(seconds: 1),
        );
        final first = leaving.leave(const LeaveEof());
        async.elapse(const Duration(milliseconds: 20));
        expect(lines, [
          'chord: not settled at the deadline: connection, first host, second host',
          'chord: killed process group 4242',
        ]);
        expect(calls, ['collector', 'killed']);
        expect(exits, [const LeaveExit.code(1)]);
        host.completeError(StateError('late host'));
        drain.completeError(StateError('late drain'));
        async.flushMicrotasks();
        expect(calls, ['collector', 'killed', 'connection']);
        expect(exits, [const LeaveExit.code(1)]);
        expect(leaving.started, isTrue);
        expect(identical(leaving.leave(const LeaveCrash()), first), isTrue);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('a timed out drain on EOF remains a clean best effort', () {
      fakeAsync((async) {
        final calls = <String>[];
        final exits = <LeaveExit>[];
        final lines = <String>[];
        final leaving = Leaving(
          answer: () => calls.add('answer'),
          drained: () => Completer<void>().future,
          closeConnection: () => calls.add('connection'),
          steps: () => [],
          stderr: lines.add,
          exit: exits.add,
          groups: _Groups(calls),
        );
        final first = leaving.leave(const LeaveEof());
        async.elapse(drainTime);
        expect(calls, ['connection', 'killed']);
        expect(lines, isEmpty);
        expect(exits, [const LeaveExit.code(0)]);
        expect(identical(leaving.leave(const LeaveBroken()), first), isTrue);
        async.elapse(leaveTime);
        expect(exits, [const LeaveExit.code(0)]);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('a failed connection close leaves other closes running', () async {
      final host = Completer<void>();
      final calls = <String>[];
      final lines = <String>[];
      final exits = <LeaveExit>[];
      final groups = _Groups(calls);
      final leaving = Leaving(
        answer: () {},
        drained: () async {},
        closeConnection: () => throw StateError('close failed'),
        steps: () => [LeaveStep('host', () => host.future)],
        stderr: lines.add,
        exit: exits.add,
        groups: groups,
      );
      final done = leaving.leave(const LeaveEof());
      await Future<void>.delayed(Duration.zero);
      expect(lines, ['chord: connection: close failed']);
      expect(exits, isEmpty);
      expect(groups.kills, 0);
      host.complete();
      await done;
      expect(groups.kills, 1);
      expect(exits, [const LeaveExit.code(1)]);
    });

    for (final name in ['task', 'monitor', 'collector', 'record']) {
      test(
        'expiry names $name and kills its registered process group',
        () async {
          final groups = ProcessGroups();
          final process = await spawnGroup(
            'sh',
            ['-c', 'exec sleep 60'],
            cwd: Directory.systemTemp.path,
            groups: groups,
          );
          addTearDown(() async {
            process.signal(ProcessSignal.sigkill);
            await process.exit.timeout(const Duration(seconds: 5));
          });
          await process.started;
          final lines = <String>[];
          final exits = <LeaveExit>[];
          final leaving = Leaving(
            answer: () {},
            drained: () async {},
            closeConnection: () {},
            steps: () => [LeaveStep(name, () => Completer<void>().future)],
            stderr: lines.add,
            exit: exits.add,
            groups: groups,
            leaveTime: const Duration(milliseconds: 50),
          );
          await leaving.leave(const LeaveEof());
          expect(lines, [
            'chord: not settled at the deadline: $name',
            'chord: killed process group ${process.pid}',
          ]);
          expect(exits, [const LeaveExit.code(1)]);
          await process.exit.timeout(const Duration(seconds: 5));
          expect(process.alive(), isFalse);
          expect(groups.killAll(), isEmpty);
        },
      );
    }
  });
}

class _Groups implements ProcessGroups {
  _Groups(this.done, [this.left = const []]);

  final List<String> done;
  final List<int> left;
  var kills = 0;

  @override
  List<int> killAll() {
    kills++;
    done.add('killed');
    return left;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
