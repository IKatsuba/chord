import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/record_worker.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sessions.dart';
import 'package:test/test.dart';

import 'record_worker_test.dart'
    show ProbeEvents, cleanupFailureWorker, noAckWorker;

Map<String, Object?> header(String id) => {
  'type': 'session',
  'version': 1,
  'sessionId': id,
  'agent': 'fake',
  'cwd': '.',
  'at': 1.25,
};
Map<String, Object?> prompt(String id) => {
  'type': 'prompt',
  'turnId': id,
  'prompt': 'Saved request $id 界😀',
  'images': 0,
  'at': 2.75,
};

Future<Directory> root() async {
  final directory = await Directory.systemTemp.createTemp(
    'record-io-integration-',
  );
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

Future<File> history(
  Directory root, {
  int turns = 1,
  bool large = false,
}) async {
  final file = File('${root.path}/past.jsonl');
  await file.writeAsString(
    [
      header('selected'),
      for (var i = 0; i < turns; i++) prompt('turn-$i'),
      if (large) {'type': 'future_history', 'payload': 'x' * (256 * 1024)},
    ].map(encodeRecord).join(),
  );
  return file;
}

Future<void> records(Directory root, int count, {bool large = false}) async {
  final directory = Directory(recordsDir(root.path));
  await directory.create();
  for (var i = 0; i < count; i++) {
    await File('${directory.path}/$i.jsonl').writeAsString(
      [
        header('id-$i'),
        prompt('turn-$i'),
        if (large) {'type': 'update', 'ignored': 'x' * (128 * 1024)},
      ].map(encodeRecord).join(),
    );
  }
}

void main() {
  for (final worker in [cleanupFailureWorker, noAckWorker]) {
    test(
      'publication keeps ${worker == noAckWorker ? 'protocol' : 'cleanup'} failure above exit-microtask cancellation',
      () async {
        final token = CancellationToken(),
            reason = Exception('late cancellation');
        try {
          await runZoned(
            () => runRecordWorker(
              worker,
              'echo',
              'none',
              cancellationToken: token,
            ),
            zoneValues: {
              recordWorkerTestKey: RecordWorkerTestHooks(
                observe: (event) {
                  if (event['type'] == 'exit') {
                    scheduleMicrotask(() => token.cancel(reason));
                  }
                },
              ),
            },
          );
          fail('Expected cleanup/protocol failure.');
        } catch (error) {
          expect(token.exception, same(reason));
          expect(error, isA<StateError>());
          expect(recordWorkerPublicationError(error, token), same(error));
        }
      },
    );
  }
  for (final kind in ['scan', 'selected']) {
    for (final failure in [false, true]) {
      test(
        '$kind exit-microtask cancellation beats unpublished ${failure ? 'error' : 'success'}',
        () async {
          final directory = await root();
          await records(directory, 1);
          final file = await history(directory);
          if (failure) {
            if (kind == 'scan') {
              await Directory(
                recordsDir(directory.path),
              ).delete(recursive: true);
              await File(
                recordsDir(directory.path),
              ).writeAsString('not a directory');
            } else {
              await file.writeAsString(
                encodeRecord({...header('future'), 'version': 2.75}),
              );
            }
          }
          final reason = Exception('exit microtask $kind'),
              token = CancellationToken();
          final pending = runZoned(
            () => kind == 'scan'
                ? readRecords(directory.path, cancellationToken: token)
                : readRecordedHistory(file.path, cancellationToken: token),
            zoneValues: {
              recordWorkerTestKey: RecordWorkerTestHooks(
                observe: (event) {
                  if (event['type'] == 'exit') {
                    scheduleMicrotask(() => token.cancel(reason));
                  }
                },
              ),
            },
          );
          await expectLater(pending, throwsA(same(reason)));
          expect(token.hasCancellables, isFalse);
        },
      );
    }
  }
  test(
    'public pre-cancel starts no operation and keeps the original exception',
    () async {
      final directory = await root(),
          reason = Exception('caller object'),
          token = CancellationToken();
      token.cancel(reason);
      final events = <Object?>[];
      await expectLater(
        runZoned(
          () => readRecords(directory.path, cancellationToken: token),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(observe: events.add),
          },
        ),
        throwsA(same(reason)),
      );
      await expectLater(
        runZoned(
          () => readRecordedHistory(
            '${directory.path}/past',
            cancellationToken: token,
          ),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(observe: events.add),
          },
        ),
        throwsA(same(reason)),
      );
      expect(events, isEmpty);
      expect(token.hasCancellables, isFalse);
    },
  );
  test(
    'null selected path stays empty and never observes a cancelled token',
    () async {
      final token = CancellationToken()..cancel(), events = <Object?>[];
      final result = await runZoned(
        () => readRecordedHistory(null, cancellationToken: token),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(observe: events.add),
        },
      );
      expect(result, same(PreparedHistory.empty));
      expect(events, isEmpty);
    },
  );
  test(
    'missing directory and selected file keep their ordinary empty results',
    () async {
      final directory = await root();
      expect(await readRecords(directory.path), isEmpty);
      expect(
        (await readRecordedHistory('${directory.path}/absent')).toJson(),
        PreparedHistory.empty.toJson(),
      );
    },
  );
  test(
    'cancel during directory enumeration closes before any file admission',
    () async {
      final directory = await root();
      await records(directory, 200);
      final token = CancellationToken(),
          probe = ProbeEvents(),
          trace = <Map<String, Object?>>[];
      addTearDown(probe.close);
      final pending = runZoned(
        () => readRecords(directory.path, cancellationToken: token),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            events: probe.port.sendPort,
            gates: ['directory', 'file'],
            observe: trace.add,
          ),
        },
      );
      final rejected = expectLater(pending, throwsA(isA<CancelledException>()));
      await probe.next(
        (event) => event['type'] == 'gate' && event['stage'] == 'directory',
      );
      token.cancel();
      await rejected;
      expect(
        probe.values.where((e) => e['type'] == 'gate' && e['stage'] == 'file'),
        isEmpty,
      );
      final closed = trace.singleWhere((e) => e['type'] == 'closed');
      expect(closed['streams'], 0);
      expect(closed['tasks'], 0);
      expect(trace.last['type'], 'exit');
      await Directory(recordsDir(directory.path)).delete(recursive: true);
    },
  );
  test(
    'cancel joins all eight admitted file readers without partial summaries',
    () async {
      final directory = await root();
      await records(directory, 16, large: true);
      final token = CancellationToken(),
          probe = ProbeEvents(),
          trace = <Map<String, Object?>>[];
      addTearDown(probe.close);
      final pending = runZoned(
        () => readRecords(directory.path, cancellationToken: token),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            events: probe.port.sendPort,
            gates: ['file'],
            observe: trace.add,
          ),
        },
      );
      final rejected = expectLater(pending, throwsA(isA<CancelledException>()));
      final paths = <Object?>{};
      for (var i = 0; i < 8; i++) {
        final gate = await probe.next(
          (e) =>
              e['type'] == 'gate' &&
              e['stage'] == 'file' &&
              !paths.contains(e['path']),
        );
        paths.add(gate['path']);
      }
      expect(paths, hasLength(8));
      token.cancelWithReason('eight files');
      await rejected;
      final closed = trace.singleWhere((e) => e['type'] == 'closed');
      expect(closed['streams'], 0);
      expect(closed['tasks'], 0);
      expect(trace.last['type'], 'exit');
      expect(
        probe.values.where((e) => e['type'] == 'gate' && e['stage'] == 'file'),
        hasLength(8),
      );
      expect(token.hasCancellables, isFalse);
      await Directory(recordsDir(directory.path)).delete(recursive: true);
    },
  );
  for (final stage in ['selected', 'parse', 'projection', 'serialization']) {
    test(
      'selected $stage cancellation joins cleanup and preserves custom reason',
      () async {
        final directory = await root(),
            file = await history(directory, turns: 160, large: true);
        final reason = Exception('stop $stage'),
            token = CancellationToken(),
            probe = ProbeEvents(),
            trace = <Map<String, Object?>>[];
        addTearDown(probe.close);
        final pending = runZoned(
          () => readRecordedHistory(file.path, cancellationToken: token),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              events: probe.port.sendPort,
              gates: [stage],
              observe: trace.add,
            ),
          },
        );
        final rejected = expectLater(pending, throwsA(same(reason)));
        await probe.next((e) => e['type'] == 'gate' && e['stage'] == stage);
        token.cancel(reason);
        await rejected;
        final closed = trace.singleWhere((e) => e['type'] == 'closed');
        expect(closed['streams'], 0);
        expect(closed['tasks'], 0);
        expect(trace.last['type'], 'exit');
        await file.delete();
        expect(await file.exists(), isFalse);
      },
    );
  }
  for (final at in ['spawned', 'ready']) {
    test('public scan cancellation at $at admits no IO', () async {
      final directory = await root();
      await records(directory, 8, large: true);
      final token = CancellationToken(), probe = ProbeEvents();
      addTearDown(probe.close);
      final pending = runZoned(
        () => readRecords(directory.path, cancellationToken: token),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            events: probe.port.sendPort,
            gates: ['directory', 'file'],
            observe: (e) {
              if (e['type'] == at) token.cancel();
            },
          ),
        },
      );
      await expectLater(pending, throwsA(isA<CancelledException>()));
      expect(probe.values.where((e) => e['type'] == 'gate'), isEmpty);
    });
  }
  test(
    'other directory errors keep FileSystemException fields after the barrier',
    () async {
      final directory = await root(), file = File(recordsDir(directory.path));
      await file.writeAsString('not a directory');
      late FileSystemException original;
      try {
        await Directory(file.path).list().toList();
        fail('expected directory failure');
      } on FileSystemException catch (error) {
        original = error;
      }
      await expectLater(
        readRecords(directory.path),
        throwsA(
          isA<FileSystemException>()
              .having((e) => e.message, 'message', original.message)
              .having((e) => e.path, 'path', original.path)
              .having(
                (e) => e.osError?.errorCode,
                'code',
                original.osError?.errorCode,
              ),
        ),
      );
    },
  );
  test(
    'unsupported version keeps its exact JSON value and typed refusal',
    () async {
      final directory = await root(),
          file = File('${directory.path}/future.jsonl');
      final version = {
        'future': [2.75, 'v2'],
      };
      await file.writeAsString(
        encodeRecord({...header('future'), 'version': version}),
      );
      final bytes = await file.readAsBytes();
      await expectLater(
        readRecordedHistory(file.path),
        throwsA(
          isA<UnsupportedRecordVersion>().having(
            (e) => e.version,
            'value',
            version,
          ),
        ),
      );
      expect(await file.readAsBytes(), bytes);
    },
  );
  test(
    'selected UTF8 replacement/newline parsing matches the synchronous projection',
    () async {
      final directory = await root(),
          file = File('${directory.path}/encoded.jsonl');
      final base = [
        header('saved'),
        prompt('first'),
        {'type': 'future_history', 'text': 'omitted'},
      ].map(encodeRecord).join();
      final samples = <List<int>>[
        utf8.encode(base),
        utf8.encode(base.replaceAll('\n', '\r\n')),
        utf8.encode(
          '${encodeRecord(header('cr')).trim()}\r${encodeRecord(prompt('cr')).trim()}',
        ),
        utf8.encode(encodeRecord(prompt('unterminated')).trimRight()),
        [0xef, 0xbb, 0xbf, ...utf8.encode(base)],
        [...utf8.encode(base), ...utf8.encode('not-json '), 0xff],
        utf8.encode('\n \r\n'),
      ];
      for (final bytes in samples) {
        await file.writeAsBytes(bytes);
        final text = const Utf8Codec(allowMalformed: true).decode(bytes),
            raw = parseRecord(
              const Utf8Codec(allowMalformed: true).decode(bytes),
            );
        final count = text.split('\n').where((l) => l.trim().isNotEmpty).length;
        final expected = recordActions(raw, malformed: count != raw.length);
        expect(
          (await readRecordedHistory(file.path)).toJson(),
          expected.toJson(),
        );
      }
    },
  );
  test(
    'cancelled selected operation cannot contaminate a simultaneous scan',
    () async {
      final directory = await root();
      await records(directory, 8);
      final file = await history(directory, large: true),
          token = CancellationToken(),
          probe = ProbeEvents();
      addTearDown(probe.close);
      final first = runZoned(
        () => readRecordedHistory(file.path, cancellationToken: token),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            events: probe.port.sendPort,
            gates: ['selected'],
          ),
        },
      );
      final rejected = expectLater(first, throwsA(isA<CancelledException>()));
      await probe.next((e) => e['type'] == 'gate' && e['stage'] == 'selected');
      final summaries = await readRecords(directory.path);
      expect(summaries, hasLength(8));
      expect(summaries.map((s) => s.lastUsedAt).toSet(), {2.75});
      token.cancel();
      await rejected;
    },
  );
}
