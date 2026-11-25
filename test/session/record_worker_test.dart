import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/record_worker.dart';
import 'package:test/test.dart';

void echoWorker(List<Object?> initial) => serveRecordWorker(initial, 'echo', (
  io,
  path,
) async {
  await io.checkpoint();
  if (path == 'filesystem') {
    throw const FileSystemException('fixture', 'record', OSError('denied', 13));
  }
  if (path == 'error') {
    throw StateError('fixture job');
  }
  return {'path': path, 'at': 4.25};
});

void readWorker(List<Object?> initial) =>
    serveRecordWorker(initial, 'read', (io, path) async {
      var bytes = 0;
      await io.forEach(
        File(path).openRead(),
        (chunk) => bytes += chunk.length,
        stage: 'selected',
        path: path,
      );
      return bytes;
    });

void failingCloseWorker(List<Object?> initial) =>
    serveRecordWorker(initial, 'fail-close', (io, path) async {
      late StreamController<int> source;
      source = StreamController<int>(
        onListen: () => source.add(1),
        onCancel: () => throw StateError('actual close failure'),
      );
      await io.forEach(source.stream, (_) {}, stage: 'close');
      return 1;
    });

// These protocol fixtures own no IO; synthetic messages never credit FD cleanup.
void lateWorker(List<Object?> initial) {
  final id = initial[0], events = initial[1] as SendPort;
  events.send({'type': 'test-port', 'id': id, 'control': events});
  Isolate.exit(events, {
    'type': 'closed',
    'id': id,
    'outcome': {'kind': 'success', 'value': 7.5},
  });
}

void noAckWorker(List<Object?> initial) => Isolate.exit();
void fatalWorker(List<Object?> initial) => throw StateError('fixture uncaught');
void cleanupFailureWorker(List<Object?> initial) =>
    Isolate.exit(initial[1] as SendPort, {
      'type': 'cleanup-failed',
      'id': initial[0],
      'cause': 'fixture close',
      'stack': 'fixture remote stack',
    });
void duplicateWorker(List<Object?> initial) {
  final id = initial[0], events = initial[1] as SendPort;
  events.send({
    'type': 'closed',
    'id': id,
    'outcome': {'kind': 'success', 'value': 1.25},
  });
  events.send({
    'type': 'closed',
    'id': id,
    'outcome': {'kind': 'success', 'value': 99},
  });
  Isolate.exit(events, {
    'type': 'closed',
    'id': id,
    'outcome': {'kind': 'success', 'value': 100},
  });
}

class ProbeEvents {
  ProbeEvents() {
    subscription = port.listen((dynamic event) {
      final value = Map<String, Object?>.from(event as Map);
      values.add(value);
      for (final (matches, ready) in List.of(waiting)) {
        if (matches(value)) {
          waiting.remove((matches, ready));
          ready.complete(value);
        }
      }
    });
  }
  final port = ReceivePort();
  late final StreamSubscription<dynamic> subscription;
  final values = <Map<String, Object?>>[];
  final waiting =
      <
        (bool Function(Map<String, Object?>), Completer<Map<String, Object?>>)
      >[];
  Future<Map<String, Object?>> next(
    bool Function(Map<String, Object?>) matches,
  ) {
    for (final value in values) {
      if (matches(value)) return Future.value(value);
    }
    final ready = Completer<Map<String, Object?>>();
    waiting.add((matches, ready));
    return ready.future;
  }

  Future<void> close() async {
    await subscription.cancel();
    port.close();
  }
}

void main() {
  test(
    'normal no-hook operation joins Closed then SDK exit and detaches token',
    () async {
      final token = CancellationToken();
      expect(
        await runRecordWorker(
          echoWorker,
          'echo',
          'hello',
          cancellationToken: token,
        ),
        {'path': 'hello', 'at': 4.25},
      );
      expect(token.hasCancellables, isFalse);
      token.cancelWithReason('late');
    },
  );
  test(
    'terminal and exit events are observed before the Future completes',
    () async {
      final seen = <String>[];
      final value = await runZoned(
        () => runRecordWorker(echoWorker, 'echo', 'ordered'),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            observe: (event) => seen.add(event['type'] as String),
          ),
        },
      );
      seen.add('published');
      expect(value, {'path': 'ordered', 'at': 4.25});
      expect(seen, ['spawned', 'ready', 'closed', 'exit', 'published']);
    },
  );
  test(
    'pre-cancelled operation preserves exception identity and spawns nothing',
    () async {
      final reason = Exception('original reason'), token = CancellationToken();
      token.cancel(reason);
      final seen = <Object?>[];
      await expectLater(
        runZoned(
          () => runRecordWorker(
            echoWorker,
            'echo',
            'none',
            cancellationToken: token,
          ),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(observe: seen.add),
          },
        ),
        throwsA(same(reason)),
      );
      expect(seen, isEmpty);
      expect(token.hasCancellables, isFalse);
    },
  );
  for (final cancelAt in ['spawned', 'ready', 'closed', 'exit']) {
    test(
      'cancellation at $cancelAt joins cleanup/exit and keeps custom reason',
      () async {
        final token = CancellationToken(), reason = Exception(cancelAt);
        final seen = <Map<String, Object?>>[];
        final pending = runZoned(
          () => runRecordWorker(
            echoWorker,
            'echo',
            'held',
            cancellationToken: token,
          ),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              observe: (event) {
                seen.add(event);
                if (event['type'] == cancelAt) token.cancel(reason);
              },
            ),
          },
        );
        await expectLater(pending, throwsA(same(reason)));
        expect(seen.last['type'], 'exit');
        expect(seen.where((e) => e['type'] == 'closed').single['streams'], 0);
        expect(seen.where((e) => e['type'] == 'closed').single['tasks'], 0);
        expect(token.hasCancellables, isFalse);
      },
    );
  }
  test(
    'cancelled file read releases a real gated stream before public completion',
    () async {
      final root = await Directory.systemTemp.createTemp('record-worker-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/record');
      await file.writeAsBytes(List.filled(256 * 1024, 120));
      final probe = ProbeEvents();
      addTearDown(probe.close);
      final token = CancellationToken();
      final seen = <Map<String, Object?>>[];
      final pending = runZoned(
        () => runRecordWorker(
          readWorker,
          'read',
          file.path,
          cancellationToken: token,
        ),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            events: probe.port.sendPort,
            gates: ['selected'],
            observe: seen.add,
          ),
        },
      );
      final canceled = expectLater(pending, throwsA(isA<CancelledException>()));
      await probe.next(
        (event) => event['type'] == 'gate' && event['stage'] == 'selected',
      );
      token.cancelWithReason('stop read');
      await canceled;
      final closed = seen.singleWhere((event) => event['type'] == 'closed');
      expect(closed['streams'], 0);
      expect(closed['tasks'], 0);
      expect(seen.last['type'], 'exit');
      await file.delete();
      expect(await file.exists(), isFalse);
    },
  );
  test(
    'caught filesystem error keeps category/message/path/OS error fields',
    () async {
      await expectLater(
        runRecordWorker(echoWorker, 'echo', 'filesystem'),
        throwsA(
          isA<FileSystemException>()
              .having((e) => e.message, 'message', 'fixture')
              .having((e) => e.path, 'path', 'record')
              .having((e) => e.osError?.errorCode, 'code', 13)
              .having((e) => e.osError?.message, 'OS message', 'denied'),
        ),
      );
    },
  );
  test(
    'caught other job error has the fixed wording and remote stack',
    () async {
      try {
        await runRecordWorker(echoWorker, 'echo', 'error');
        fail('expected job error');
      } catch (error, stack) {
        expect(
          error,
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Record worker failed: Bad state: fixture job',
          ),
        );
        expect(stack.toString(), contains('echoWorker'));
      }
    },
  );
  test(
    'exit without terminal is a protocol failure even when cancelled',
    () async {
      final token = CancellationToken();
      await expectLater(
        runZoned(
          () => runRecordWorker(
            noAckWorker,
            'echo',
            'none',
            cancellationToken: token,
          ),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              observe: (event) {
                if (event['type'] == 'spawned') token.cancel();
              },
            ),
          },
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Record worker exited without acknowledging IO cleanup.',
          ),
        ),
      );
      expect(token.hasCancellables, isFalse);
    },
  );
  test(
    'SDK error list then exit is never a cleanup ACK and retains details',
    () async {
      try {
        await runRecordWorker(fatalWorker, 'echo', 'none');
        fail('expected no ACK');
      } catch (error, stack) {
        expect(
          error,
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Record worker exited without acknowledging IO cleanup.',
          ),
        );
        expect(stack.toString(), contains('fixture uncaught'));
      }
    },
  );
  test(
    'CleanupFailed outranks cancellation and preserves remote cause',
    () async {
      final token = CancellationToken();
      await expectLater(
        runZoned(
          () => runRecordWorker(
            cleanupFailureWorker,
            'echo',
            'none',
            cancellationToken: token,
          ),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              observe: (event) {
                if (event['type'] == 'spawned') token.cancel();
              },
            ),
          },
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Record worker IO cleanup failed: fixture close',
          ),
        ),
      );
    },
  );
  test('duplicate terminal maps do not replace the first outcome', () async {
    expect(await runRecordWorker(duplicateWorker, 'echo', 'none'), 1.25);
  });
  test(
    'server emits CleanupFailed after actual source cancellation failure',
    () async {
      final probe = ProbeEvents();
      addTearDown(probe.close);
      final token = CancellationToken(), seen = <String>[];
      final pending = runZoned(
        () => runRecordWorker(
          failingCloseWorker,
          'fail-close',
          '',
          cancellationToken: token,
        ),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            events: probe.port.sendPort,
            gates: ['close'],
            observe: (event) => seen.add(event['type'] as String),
          ),
        },
      );
      final failure = expectLater(
        pending,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Record worker IO cleanup failed: Bad state: actual close failure',
          ),
        ),
      );
      await probe.next(
        (event) => event['type'] == 'gate' && event['stage'] == 'close',
      );
      token.cancel();
      await failure;
      expect(seen, contains('cleanup-failed'));
      expect(seen, isNot(contains('closed')));
      expect(seen.last, 'exit');
      expect(token.hasCancellables, isFalse);
    },
  );
  test(
    'cancellation before publication outranks an unpublished caught job error',
    () async {
      final reason = Exception('keep custom object'),
          token = CancellationToken();
      await expectLater(
        runZoned(
          () => runRecordWorker(
            echoWorker,
            'echo',
            'filesystem',
            cancellationToken: token,
          ),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              observe: (event) {
                if (event['type'] == 'closed') token.cancel(reason);
              },
            ),
          },
        ),
        throwsA(same(reason)),
      );
    },
  );
  test(
    'late messages on a settled port cannot affect a later operation',
    () async {
      SendPort? old;
      expect(
        await runZoned(
          () => runRecordWorker(lateWorker, 'echo', ''),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              observe: (event) {
                if (event['type'] == 'test-port') {
                  old = event['control'] as SendPort;
                }
              },
            ),
          },
        ),
        7.5,
      );
      final second = runRecordWorker(echoWorker, 'echo', 'new');
      old!.send({'type': 'cleanup-failed', 'id': 0, 'cause': 'old'});
      old!.send(['old error', 'old stack']);
      old!.send(null);
      expect(await second, {'path': 'new', 'at': 4.25});
    },
  );
  test('spawn failure closes local ports and detaches its token', () async {
    final port = ReceivePort(), token = CancellationToken();
    addTearDown(port.close);
    void invalid(List<Object?> initial) {
      port.toString();
    }

    await expectLater(
      runRecordWorker(invalid, 'echo', '', cancellationToken: token),
      throwsA(isA<ArgumentError>()),
    );
    expect(token.hasCancellables, isFalse);
  });
  test(
    'concurrent operations retain independent ids, tokens and completions',
    () async {
      final token = CancellationToken(), ids = <Object?>{};
      final first = runZoned(
        () => runRecordWorker(
          echoWorker,
          'echo',
          'first',
          cancellationToken: token,
        ),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            observe: (event) {
              ids.add(event['id']);
              if (event['type'] == 'ready') token.cancel();
            },
          ),
        },
      );
      final rejected = expectLater(first, throwsA(isA<CancelledException>()));
      final second = runZoned(
        () => runRecordWorker(echoWorker, 'echo', 'second'),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            observe: (event) => ids.add(event['id']),
          ),
        },
      );
      expect(await second, {'path': 'second', 'at': 4.25});
      await rejected;
      expect(ids, hasLength(2));
    },
  );
  test(
    'IO scope natural EOF and asynchronous consumers preserve order',
    () async {
      final io = RecordWorkerIO(), values = <num>[];
      await io.forEach(Stream<num>.fromIterable([1.25, 2.5, 3.75]), (
        value,
      ) async {
        values.add(value);
        await io.checkpoint();
      });
      await io.close();
      expect(values, [1.25, 2.5, 3.75]);
      expect(io.activeStreams, 0);
      expect(io.pendingTasks, 0);
    },
  );
  test(
    'scope cancellation awaits async source close without waiting on onDone',
    () async {
      final closeStarted = Completer<void>(), release = Completer<void>();
      final source = StreamController<int>(
        onCancel: () {
          closeStarted.complete();
          return release.future;
        },
      );
      final io = RecordWorkerIO();
      var settled = false;
      final read = io
          .forEach(source.stream, (_) {})
          .whenComplete(() => settled = true);
      final rejected = expectLater(read, throwsA(isA<Exception>()));
      io.cancel();
      final closing = io.close();
      await closeStarted.future;
      expect(settled, isFalse);
      expect(io.pendingTasks, 1);
      release.complete();
      await rejected;
      await closing;
      expect(io.activeStreams, 0);
      expect(io.pendingTasks, 0);
    },
  );
  test(
    'error delivery cannot discard the real subscription close Future',
    () async {
      final closeStarted = Completer<void>(), release = Completer<void>();
      final source = StreamController<int>(
        onCancel: () {
          closeStarted.complete();
          return release.future;
        },
      );
      final io = RecordWorkerIO();
      var settled = false;
      final read = io
          .forEach(source.stream, (_) {})
          .whenComplete(() => settled = true);
      final rejected = expectLater(read, throwsA(isA<FormatException>()));
      source.addError(const FormatException('bad line'));
      await closeStarted.future;
      expect(settled, isFalse);
      release.complete();
      await rejected;
      await io.close();
      expect(io.activeStreams, 0);
      expect(io.pendingTasks, 0);
    },
  );
  test('one failed close never prevents other active close attempts', () async {
    final attempts = <int>[], io = RecordWorkerIO();
    final sources = [
      for (var i = 0; i < 8; i++)
        StreamController<int>(
          onCancel: () {
            attempts.add(i);
            if (i == 0) throw const FileSystemException('close failed');
          },
        ),
    ];
    final reads = [
      for (final source in sources)
        io.forEach(source.stream, (_) {}).catchError((Object _) {}),
    ];
    io.cancel();
    await expectLater(io.close(), throwsA(isA<FileSystemException>()));
    await Future.wait(reads);
    expect(attempts.toSet(), {0, 1, 2, 3, 4, 5, 6, 7});
    expect(io.activeStreams, 0);
    expect(io.pendingTasks, 0);
  });
}
