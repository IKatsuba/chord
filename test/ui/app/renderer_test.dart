import 'dart:async';
import 'dart:io';

import 'package:chord/platform/signals.dart';
import 'package:test/test.dart';

import '../../fixtures/fake.dart';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  group('tester first signal boundaries', () {
    for (final first in leaveSignals) {
      test('$first wins while all later signals are held', () async {
        final streams = {
          for (final signal in leaveSignals)
            signal: StreamController<ProcessSignal>.broadcast(),
        };
        final gate = Completer<void>();
        final raised = Completer<ProcessSignal>();
        var closes = 0;
        final off = dieBySignal(
          () {
            closes++;
            return gate.future;
          },
          watch: (signal) => streams[signal]!.stream,
          raise: raised.complete,
        );
        addTearDown(() async {
          off();
          for (final stream in streams.values) {
            await stream.close();
          }
        });
        streams[first]!.add(first);
        await Future<void>.delayed(Duration.zero);
        for (final signal in [...leaveSignals, first]) {
          streams[signal]!.add(signal);
        }
        await Future<void>.delayed(Duration.zero);
        expect(closes, 1);
        expect(raised.isCompleted, isFalse);
        gate.complete();
        expect(await raised.future, first);
        expect(streams.values.every((s) => !s.hasListener), isTrue);
      });
    }
  });

  group('the way out, in a child that owns agents', () {
    // Started with `dart run`, each child compiled the app again, which
    // under load took most of a case's budget; it is compiled once, and
    // kept, in setUpAll, which is bounded by the test runner's own setUpAll limit, not by a case's.
    late List<String> wayOut;
    setUpAll(() {
      wayOut = fixtureCommand('test/fixtures/way_out_child.dart');
    });

    /// The child, its output so far, and when it said ready and when its
    /// output ended; cleaned up however the test ends.
    Future<
      (Process, StringBuffer, StringBuffer, Future<List<int>>, Future<void>)
    >
    launch(String how) async {
      final child = await Process.start(wayOut.first, [...wayOut.skip(1), how]);
      final out = StringBuffer();
      final err = StringBuffer();
      final ready = Completer<List<int>>();
      final outDone = Completer<void>();
      child.stdout.transform(const SystemEncoding().decoder).listen((text) {
        out.write(text);
        final line = RegExp(r'ready (\d+) (\d+)').firstMatch('$out');
        if (line != null && !ready.isCompleted) {
          ready.complete([int.parse(line[1]!), int.parse(line[2]!)]);
        }
      }, onDone: outDone.complete);
      child.stderr.transform(const SystemEncoding().decoder).listen(err.write);
      // The agents ignore SIGTERM in groups of their own, so a child
      // SIGKILLed before it says ready (a slow start under load) left them
      // running with no parent (CTUI-90). SIGTERM has the child kill every
      // group it started; should it not end, it is SIGKILLed, and every
      // group it named in its output is killed here.
      addTearDown(() async {
        child.kill(ProcessSignal.sigterm);
        await child.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            child.kill(ProcessSignal.sigkill);
            return child.exitCode;
          },
        );
        await outDone.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
        for (final agent in RegExp(r'agent (\d+)').allMatches('$out')) {
          Process.killPid(-int.parse(agent[1]!), ProcessSignal.sigkill);
        }
      });
      return (child, out, err, ready.future, outDone.future);
    }

    Future<(Process, List<int>, StringBuffer, StringBuffer)> start(
      String how,
    ) async {
      final (child, out, err, ready, _) = await launch(how);
      final pids = await ready.timeout(const Duration(seconds: 30));
      return (child, pids, out, err);
    }

    for (final signal in leaveSignals) {
      test('$signal closes what it owns, kills what is left, gives the '
          'terminal back, and dies by it', () async {
        final (child, pids, out, _) = await start('signal');
        expect(pids.every(_alive), isTrue);
        child.kill(signal);
        expect(
          await child.exitCode.timeout(const Duration(seconds: 10)),
          -signal.signalNumber,
        );
        expect('$out', contains('closed'));
        expect('$out', contains('gave back'));
        expect(pids.where(_alive), isEmpty);
      });
    }

    test(
      'an uncaught error closes and kills them, says it, and exits 1',
      () async {
        final (child, pids, out, err) = await start('crash');
        expect(await child.exitCode.timeout(const Duration(seconds: 10)), 1);
        expect('$out', contains('closed'));
        expect('$err', startsWith('Bad state: chord failed'));
        expect(pids.where(_alive), isEmpty);
      },
    );

    test('a SIGTERM while an agent is starting waits for it, kills it, '
        'and dies by the signal', () async {
      final (child, out, _, _, outDone) = await launch('term-starting');
      expect(
        await child.exitCode.timeout(const Duration(seconds: 30)),
        -ProcessSignal.sigterm.signalNumber,
      );
      await outDone.timeout(const Duration(seconds: 3));
      final pids = [
        for (final agent in RegExp(r'agent (\d+)').allMatches('$out'))
          int.parse(agent[1]!),
      ];
      expect(pids, hasLength(1), reason: '$out');
      expect('$out', isNot(contains('ready')));
      expect(pids.where(_alive), isEmpty);
    });
  }, timeout: const Timeout(Duration(minutes: 1)));
}
