import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/record_worker.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'record_worker_test.dart' show ProbeEvents;

void main() {
  group('tester: CTUI-176 byte scan boundaries', () {
    late Directory state;
    setUp(() async {
      state = await Directory.systemTemp.createTemp('scan-byte-tester-');
      await Directory(recordsDir(state.path)).create();
    });
    tearDown(() => state.delete(recursive: true));

    String header(String id) => encodeRecord({
      'type': 'session',
      'version': 1,
      'sessionId': id,
      'agent': 'fake',
      'cwd': 'fixture-project',
      'at': 1,
    });
    String prompt(String text, int at) => encodeRecord({
      'type': 'prompt',
      'turnId': 'turn',
      'prompt': text,
      'images': 0,
      'at': at,
    });
    File record(String name) =>
        File(p.join(recordsDir(state.path), '$name.jsonl'));

    test('seeded chunks including empty chunks equal SDK line splitting', () {
      final random = Random(176);
      final bytes = <int>[
        ...utf8.encode('界👩‍💻e\u0301\u001b[31m\r\n\n\r\r\n'),
        for (var i = 0; i < 3000; i++) random.nextInt(256),
        ...utf8.encode('\r\nlast🙂'),
      ];
      final expected = const LineSplitter().convert(
        const Utf8Decoder(allowMalformed: true).convert(bytes),
      );
      for (var trial = 0; trial < 100; trial++) {
        final actual = <String>[];
        final splitter = RecordByteLines(
          (b, s, e) => actual.add(
            const Utf8Decoder(allowMalformed: true).convert(b, s, e),
          ),
        );
        var at = 0;
        while (at < bytes.length) {
          splitter.add(Uint8List(0));
          final end = min(bytes.length, at + 1 + random.nextInt(71));
          splitter.add(Uint8List.fromList(bytes.sublist(at, end)));
          at = end;
        }
        splitter.close();
        expect(actual, expected, reason: 'seed 176 trial $trial');
      }
    });

    test(
      'huge retained and ignored lines preserve later summary fields',
      () async {
        final file = record('huge');
        final text =
            '${header('huge')}${prompt('界🙂e\u0301' * 300000, 2)}'
            '${encodeRecord({
              'type': 'update',
              'turnId': 'turn',
              'update': {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': '\u001b[31m🙂' * 300000},
              },
            })}'
            '${encodeRecord({'type': 'renamed', 'title': 'after huge 界🙂', 'at': 3})}'
            '${prompt('last', 999)}';
        await file.writeAsString(text.replaceAll('\n', '\r\n'));
        final bytes = await file.readAsBytes();
        final actual = (await readRecords(state.path)).single;
        expect(
          actual.toJson(),
          (await scanRecords(state.path)).single.toJson(),
        );
        expect(actual.lastUsedAt, 999);
        expect(actual.title, 'after huge 界🙂');
        expect(await file.readAsBytes(), bytes);
      },
    );

    test('empty and header-only stores offer no resumable records', () async {
      expect(await readRecords(state.path), isEmpty);
      await record('empty').writeAsString('');
      await record('header').writeAsString(header('header').trimRight());
      await record('opened').writeAsString(
        '${header('opened')}'
        '${encodeRecord({'type': 'opened', 'at': 5})}',
      );
      expect(await readRecords(state.path), isEmpty);
    });

    test(
      'a file vanished after listing is skipped and fresh reads recover',
      () async {
        final file = record('vanished');
        await file.writeAsString('${header('vanished')}${prompt('first', 2)}');
        final probe = ProbeEvents();
        addTearDown(probe.close);
        final pending = runZoned(
          () => readRecords(state.path),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              events: probe.port.sendPort,
              gates: ['directory'],
            ),
          },
        );
        final gate = await probe.next((e) => e['type'] == 'gate');
        final ready = await probe.next((e) => e['type'] == 'probe-ready');
        await file.delete();
        (ready['control'] as SendPort).send(gate['gate']);
        expect(await pending, isEmpty);
        await file.writeAsString('${header('fresh')}${prompt('new', 3)}');
        expect((await readRecords(state.path)).single.sessionId, 'fresh');
      },
    );

    test(
      'cancellation after first byte chunk joins worker and closes streams',
      () async {
        await record('cancel').writeAsString(
          '${header('cancel')}'
          '${prompt('first', 2)}${'x' * 2000000}\n',
        );
        final probe = ProbeEvents(), trace = <Map<String, Object?>>[];
        final token = CancellationToken(),
            reason = Exception('cancel byte scan');
        addTearDown(probe.close);
        final pending = runZoned(
          () => readRecords(state.path, cancellationToken: token),
          zoneValues: {
            recordWorkerTestKey: RecordWorkerTestHooks(
              events: probe.port.sendPort,
              gates: ['scan'],
              observe: trace.add,
            ),
          },
        );
        final rejected = expectLater(pending, throwsA(same(reason)));
        await probe.next((e) => e['type'] == 'gate' && e['stage'] == 'scan');
        token.cancel(reason);
        await rejected;
        final closed = trace.singleWhere((e) => e['type'] == 'closed');
        expect(closed['outcome'], {'kind': 'cancelled'});
        expect(closed['streams'], 0);
        expect(closed['tasks'], 0);
        expect(trace.last['type'], 'exit');
        expect(token.hasCancellables, isFalse);
        expect((await readRecords(state.path)).single.sessionId, 'cancel');
      },
    );
  });
}
