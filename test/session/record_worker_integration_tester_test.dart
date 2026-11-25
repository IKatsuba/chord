import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/record.dart' show recordsDir;
import 'package:chord/session/record_worker.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sessions.dart';
import 'package:test/test.dart';

import 'record_worker_integration_test.dart' show history, records, root;
import 'record_worker_test.dart' show ProbeEvents;

void main() {
  group('tester: public record worker boundaries', () {
    test('scan serialization cancellation publishes no partial list', () async {
      final directory = await root();
      await records(directory, 128);
      final token = CancellationToken(), reason = Exception('stop summaries');
      final probe = ProbeEvents(), trace = <Map<String, Object?>>[];
      addTearDown(probe.close);
      final pending = runZoned(
        () => readRecords(directory.path, cancellationToken: token),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            events: probe.port.sendPort,
            gates: ['scan-projection'],
            observe: trace.add,
          ),
        },
      );
      final rejected = expectLater(pending, throwsA(same(reason)));
      await probe.next(
        (event) =>
            event['type'] == 'gate' && event['stage'] == 'scan-projection',
      );
      expect(trace.any((event) => event['type'] == 'closed'), isFalse);
      token.cancel(reason);
      await rejected;
      final closed = trace.singleWhere((event) => event['type'] == 'closed');
      expect(closed['outcome'], {'kind': 'cancelled'});
      expect(closed['streams'], 0);
      expect(closed['tasks'], 0);
      expect(trace.last['type'], 'exit');
      expect(token.hasCancellables, isFalse);
      await Directory(recordsDir(directory.path)).delete(recursive: true);
    });

    test(
      'held scan cancellation leaves selected and fresh scan independent',
      () async {
        final directory = await root();
        await records(directory, 17);
        final file = await history(directory, turns: 70);
        final token = CancellationToken(),
            reason = Exception('retire old scan');
        final probe = ProbeEvents(), trace = <Map<String, Object?>>[];
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
        final rejected = expectLater(pending, throwsA(same(reason)));
        final held = <Object?>{};
        for (var i = 0; i < 8; i++) {
          final event = await probe.next(
            (event) =>
                event['type'] == 'gate' &&
                event['stage'] == 'file' &&
                !held.contains(event['path']),
          );
          held.add(event['path']);
        }
        final selected = await readRecordedHistory(file.path);
        expect(selected.rawHasPast, isTrue);
        expect(selected.omitted, isFalse);
        expect(selected.actions, hasLength(140));
        token.cancel(reason);
        final fresh = readRecords(directory.path);
        await rejected;
        final summaries = await fresh;
        expect(summaries, hasLength(17));
        expect(summaries.map((summary) => summary.sessionId).toSet(), {
          for (var i = 0; i < 17; i++) 'id-$i',
        });
        expect(summaries.map((summary) => summary.lastUsedAt).toSet(), {2.75});
        expect(
          probe.values.where(
            (event) => event['type'] == 'gate' && event['stage'] == 'file',
          ),
          hasLength(8),
        );
        final closed = trace.singleWhere((event) => event['type'] == 'closed');
        expect(closed['streams'], 0);
        expect(closed['tasks'], 0);
        expect(trace.last['type'], 'exit');
        expect(token.hasCancellables, isFalse);
        expect(
          (await readRecordedHistory(file.path)).toJson(),
          selected.toJson(),
        );
      },
    );
  });
}
