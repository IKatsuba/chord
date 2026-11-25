import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/record_worker.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'record_worker_test.dart' show ProbeEvents;

void main() {
  group('tester: CTUI-176 direct record identity and ownership', () {
    late Directory state;
    late File target;
    setUp(() async {
      state = await Directory.systemTemp.createTemp('named-record-tester-');
      await Directory(recordsDir(state.path)).create();
      target = File(p.join(recordsDir(state.path), 'record-界🙂.jsonl'));
      await target.writeAsString(
        [
          encodeRecord({
            'type': 'session',
            'version': 1,
            'sessionId': 'agent/id',
            'agent': 'fake',
            'cwd': 'project',
            'at': 1,
          }),
          encodeRecord({
            'type': 'prompt',
            'turnId': 't',
            'prompt': 'first',
            'images': 0,
            'at': 2,
          }),
          '${'x' * 2000000}\n',
        ].join(),
      );
      await File(
        p.join(recordsDir(state.path), 'unrelated.jsonl'),
      ).writeAsString('unrelated bytes');
    });
    tearDown(() => state.delete(recursive: true));

    test(
      'direct read touches only its file and preserves machine session ids',
      () async {
        final probe = ProbeEvents();
        addTearDown(probe.close);
        final token = CancellationToken();
        addTearDown(token.cancel);
        final pending = runZoned(
          () => readNamedRecord(
            state.path,
            'record-界🙂',
            cancellationToken: token,
          ),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              events: probe.port.sendPort,
              gates: ['file', 'directory', 'header', 'tail'],
            ),
          },
        );
        final gate = await probe
            .next((e) => e['type'] == 'gate')
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw StateError('no gate: ${probe.values}'),
            );
        expect(gate['stage'], 'file');
        expect(gate['path'], target.path);
        final ready = await probe.next((e) => e['type'] == 'probe-ready');
        (ready['control'] as SendPort).send(gate['gate']);
        final record = (await pending.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError('held: ${probe.values}'),
        )).single;
        expect(probe.values.where((e) => e['type'] == 'gate'), hasLength(1));
        expect(record.sessionId, 'agent/id');
        expect(record.toJson()['sessionId'], 'agent/id');
        expect(record.resume.sessionId, 'agent/id');
        expect(
          namedSession(record, 'record-界🙂', agent: 'fake').sessionId,
          'agent/id',
        );
        expect(
          await quitRecordId(target.path, (
            agent: 'fake',
            sessionId: 'agent/id',
          )),
          'record-界🙂',
        );
        expect(await readRecordsWithId(state.path, 'record-界🙂'), isEmpty);
        expect(
          (await readRecordsWithId(state.path, 'agent/id')).single.sessionId,
          'agent/id',
        );
      },
    );

    test(
      'cancelling a direct byte scan joins cleanup without a fallback scan',
      () async {
        final probe = ProbeEvents(), trace = <Map<String, Object?>>[];
        final token = CancellationToken(),
            reason = Exception('cancel direct record');
        addTearDown(probe.close);
        addTearDown(() => token.cancel(reason));
        final pending = runZoned(
          () => readNamedRecord(
            state.path,
            'record-界🙂',
            cancellationToken: token,
          ),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              events: probe.port.sendPort,
              gates: ['scan', 'directory', 'header', 'tail'],
              observe: trace.add,
            ),
          },
        );
        final rejected = expectLater(pending, throwsA(same(reason)));
        final gate = await probe.next((e) => e['type'] == 'gate');
        expect(gate['stage'], 'scan');
        token.cancel(reason);
        await rejected;
        expect(probe.values.where((e) => e['type'] == 'gate'), hasLength(1));
        final closed = trace.singleWhere((e) => e['type'] == 'closed');
        expect(closed['outcome'], {'kind': 'cancelled'});
        expect(closed['streams'], 0);
        expect(closed['tasks'], 0);
        expect(trace.last['type'], 'exit');
        expect(token.hasCancellables, isFalse);
        expect(
          (await readNamedRecord(state.path, 'record-界🙂')).single.sessionId,
          'agent/id',
        );
      },
    );
  });
}
