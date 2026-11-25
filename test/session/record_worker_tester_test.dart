import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/record_worker.dart';
import 'package:test/test.dart';

import 'record_worker_test.dart' show ProbeEvents;

void projectionWorker(List<Object?> initial) =>
    serveRecordWorker(initial, 'projection', (io, path) async {
      await io.checkpoint(stage: 'projection');
      return {'at': 1.25, 'path': path};
    });

void main() {
  group('tester: owned record worker boundaries', () {
    test(
      'cancel joins an active consumer and discards its queued input',
      () async {
        final entered = Completer<void>(), consume = Completer<void>();
        final sourceClosed = Completer<void>();
        final source = StreamController<int>(onCancel: sourceClosed.complete);
        final io = RecordWorkerIO(), values = <int>[];
        final read = io.forEach(source.stream, (value) async {
          values.add(value);
          entered.complete();
          await consume.future;
        });
        final rejected = expectLater(read, throwsA(isA<Exception>()));
        for (var i = 0; i < 1000; i++) {
          source.add(i);
        }
        await entered.future;
        io.cancel();
        var finished = false;
        final closing = io.close().then((_) => finished = true);
        await sourceClosed.future;
        expect(finished, isFalse);
        expect(io.pendingTasks, 1);
        expect(values, [0]);
        consume.complete();
        await rejected;
        await closing;
        expect(values, [0]);
        expect(io.activeStreams, 0);
        expect(io.pendingTasks, 0);

        var listened = false;
        final lateSource = Stream<int>.multi((_) => listened = true);
        await expectLater(
          io.forEach(lateSource, (_) {}),
          throwsA(isA<Exception>()),
        );
        expect(listened, isFalse);
      },
    );

    test(
      'all eight asynchronous closes join despite one failed close',
      () async {
        final io = RecordWorkerIO();
        final started = [for (var i = 0; i < 8; i++) Completer<void>()];
        final release = [for (var i = 0; i < 8; i++) Completer<void>()];
        final failure = StateError('owned close failure');
        final attempts = <int>[];
        final sources = [
          for (var i = 0; i < 8; i++)
            StreamController<int>(
              onCancel: () async {
                attempts.add(i);
                started[i].complete();
                await release[i].future;
                if (i == 0) throw failure;
              },
            ),
        ];
        final reads = [
          for (final source in sources)
            expectLater(
              io.forEach(source.stream, (_) {}),
              throwsA(isA<Exception>()),
            ),
        ];
        io.cancel();
        io.cancel();
        final closing = io.close();
        expect(identical(io.close(), closing), isTrue);
        var finished = false;
        final rejected = expectLater(
          closing.whenComplete(() => finished = true),
          throwsA(same(failure)),
        );
        await Future.wait(started.map((gate) => gate.future));
        expect(attempts.toSet(), {0, 1, 2, 3, 4, 5, 6, 7});
        for (var i = 0; i < 7; i++) {
          release[i].complete();
        }
        await Future.wait(reads.take(7));
        expect(finished, isFalse);
        expect(io.pendingTasks, 1);
        release.last.complete();
        await Future.wait(reads);
        await rejected;
        expect(attempts, hasLength(8));
        expect(io.activeStreams, 0);
        expect(io.pendingTasks, 0);
      },
    );

    test(
      'CPU cancellation joins terminal and exit before publishing reason',
      () async {
        final probe = ProbeEvents();
        addTearDown(probe.close);
        final token = CancellationToken(),
            reason = Exception('projection stop');
        final seen = <Map<String, Object?>>[];
        final pending = runZoned(
          () => runRecordWorker(
            projectionWorker,
            'projection',
            'unchanged',
            cancellationToken: token,
          ),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              events: probe.port.sendPort,
              gates: ['projection'],
              observe: seen.add,
            ),
          },
        );
        final rejected = expectLater(pending, throwsA(same(reason)));
        await probe.next(
          (event) => event['type'] == 'gate' && event['stage'] == 'projection',
        );
        expect(seen.any((event) => event['type'] == 'closed'), isFalse);
        token.cancel(reason);
        await rejected;
        final closed = seen.singleWhere((event) => event['type'] == 'closed');
        expect(closed['outcome'], {'kind': 'cancelled'});
        expect(closed['streams'], 0);
        expect(closed['tasks'], 0);
        expect(seen.last['type'], 'exit');
        expect(token.hasCancellables, isFalse);
      },
    );
  });
}
