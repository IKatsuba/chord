import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/record_worker.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/team_selection.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'record_worker_test.dart' show ProbeEvents;

String _line(Map<String, Object?> value) => encodeRecord(value).trimRight();
String _header(
  String id,
  String agent,
  String cwd, {
  String? parent,
  String? task,
  String? name,
}) => _line({
  'type': 'session',
  'version': 1,
  'sessionId': id,
  'agent': agent,
  'cwd': cwd,
  'at': 1,
  'parent': ?parent,
  'task': ?task,
  'name': ?name,
});
String _prompt(num at, String text) => _line({
  'type': 'prompt',
  'turnId': 't',
  'prompt': text,
  'at': at,
  'images': 0,
});
Map<String, Object?> _receipt(String id) => {
  'schemaVersion': 1,
  'runId': id,
  'saved': {'name': 'fixture', 'place': 'project'},
  'reason': 'Keep the saved roles and their permissions.',
  'policy': <String, Object?>{},
  'roles': [
    {
      'role': 'lead',
      'name': 'lead',
      'saved': {'agent': 'fake'},
      'planned': {'agent': 'fake'},
      'state': 'refused',
      'actual': null,
      'note': 'Fixture refusal before a prompt.',
    },
  ],
  'decisionRead': null,
  'warnings': <String>[],
};
String _served(String id) => _line({
  'type': 'served',
  'call': {
    'tool': 'run_team',
    'input': <String, Object?>{},
    'asked': id,
    'answer': {'id': id, 'receipt': _receipt(id)},
  },
});
Object _outcome(Resume Function() pick) {
  try {
    final r = pick();
    return [
      r.sessionId,
      r.cwd,
      r.record,
      r.lastUsedAt,
      r.prompt,
      r.name,
      r.title,
      r.task,
    ];
  } on ResumeError catch (e) {
    return e.message;
  }
}

void main() {
  group('tester: CTUI-176 targeted discovery equality', () {
    late Directory state;
    setUp(() {
      final temp = Directory.systemTemp.createTempSync('targeted-tester-');
      state = Directory(temp.resolveSymbolicLinksSync());
      Directory(recordsDir(state.path)).createSync();
    });
    tearDown(() => state.deleteSync(recursive: true));
    File file(String name) =>
        File(p.join(recordsDir(state.path), '$name.jsonl'));

    test(
      'seeded sets preserve by-id, agent, and latest choices in every field',
      () async {
        for (var seed = 0; seed < 8; seed++) {
          final random = Random(17600 + seed);
          for (var index = 0; index < 40; index++) {
            final id = 'id-${random.nextInt(7)}';
            final lines = <String>[
              _header(
                id,
                'agent-${random.nextInt(3)}',
                'project-${random.nextInt(3)}',
                parent: random.nextInt(5) == 0 ? 'parent' : null,
                task: random.nextInt(5) == 0 ? 'task' : null,
                name: random.nextBool() ? 'named 界🙂' : null,
              ),
              _line({'type': 'opened', 'at': random.nextInt(10) + 100}),
              if (index % 7 == 0) _served('run-$index'),
              for (var j = 0, n = random.nextInt(4); j < n; j++) ...[
                _prompt(
                  random.nextInt(6) + .5,
                  'prompt $j 界👩‍💻e\u0301\u001b[31m',
                ),
                _line({'type': 'renamed', 'title': 'title $j', 'at': j}),
                _line({
                  'type': 'update',
                  'turnId': 't',
                  'update': {
                    'sessionUpdate': 'agent_message_chunk',
                    'content': {
                      'type': 'text',
                      'text': 'ignored🙂' * random.nextInt(200),
                    },
                  },
                }),
              ],
              if (random.nextBool()) '{"type":"prompt","at":999}',
              if (random.nextBool()) '{"type":"prompt",',
            ];
            var text = lines.join(['\n', '\r', '\r\n'][random.nextInt(3)]);
            if (index % 13 == 0) text = '\n$text';
            if (index == 39) text = '';
            await file('$index').writeAsString(text);
          }
          final full = await readRecords(state.path);
          for (final id in [...List.generate(7, (i) => 'id-$i'), 'unknown']) {
            final named = await readRecordsWithId(state.path, id);
            expect(
              named.map((r) => r.toJson()).toList(),
              full
                  .where((r) => r.sessionId == id)
                  .map((r) => r.toJson())
                  .toList(),
              reason: 'seed $seed id $id',
            );
            expect(recordedAgent(named, id), recordedAgent(full, id));
            for (var agent = 0; agent < 4; agent++) {
              expect(
                _outcome(
                  () => sessionById(
                    named,
                    id,
                    agent: 'agent-$agent',
                    cwd: 'fallback',
                  ),
                ),
                _outcome(
                  () => sessionById(
                    full,
                    id,
                    agent: 'agent-$agent',
                    cwd: 'fallback',
                  ),
                ),
                reason: 'seed $seed id $id agent $agent',
              );
            }
          }
          for (var agent = 0; agent < 4; agent++) {
            for (var cwd = 0; cwd < 4; cwd++) {
              final latest = await readLatestRecord(
                state.path,
                agent: 'agent-$agent',
                cwd: 'project-$cwd',
              );
              expect(
                _outcome(
                  () => latestSession(
                    latest,
                    agent: 'agent-$agent',
                    cwd: 'project-$cwd',
                  ),
                ),
                _outcome(
                  () => latestSession(
                    full,
                    agent: 'agent-$agent',
                    cwd: 'project-$cwd',
                  ),
                ),
                reason: 'seed $seed agent $agent cwd $cwd',
              );
            }
          }
        }
      },
    );

    test(
      'a receipt-only record competes using its last opening time',
      () async {
        expect(isSelectionReceipt(_receipt('run')), isTrue);
        await file('receipt').writeAsString(
          [
            _header('receipt', 'fake', 'project'),
            _served('run'),
            _line({'type': 'opened', 'at': 900}),
          ].join('\r\n'),
        );
        await file('prompt').writeAsString(
          [
            _header('prompt', 'fake', 'project'),
            _prompt(899, 'normal'),
          ].join('\n'),
        );
        final full = await readRecords(state.path);
        expect(
          full.singleWhere((r) => r.sessionId == 'receipt').prompt,
          'Team attempt: fixture',
        );
        final targeted = await readLatestRecord(
          state.path,
          agent: 'fake',
          cwd: 'project',
        );
        expect(
          targeted.single.toJson(),
          full.singleWhere((r) => r.sessionId == 'receipt').toJson(),
        );
        expect(
          (await readRecordsWithId(state.path, 'receipt')).single.toJson(),
          targeted.single.toJson(),
        );
      },
    );

    final supportsHandleProof =
        Platform.isMacOS && File('/usr/sbin/lsof').existsSync();
    for (final stage in ['header', 'tail']) {
      test(
        'cancel at $stage closes the observed random-access handle before exit',
        () async {
          final record = file('handle-$stage');
          await record.writeAsString(
            '${_header('handle', 'fake', 'project')}\n'
            '${_prompt(2, 'first')}\n${'x' * 140000}\n',
          );
          Future<String> handles() async {
            final result = await Process.run('/usr/sbin/lsof', [
              '-a',
              '-p',
              '$pid',
              '-Fn',
            ]);
            if (result.exitCode != 0) {
              throw StateError('lsof failed: ${result.stderr}');
            }
            return result.stdout as String;
          }

          final probe = ProbeEvents(), trace = <Map<String, Object?>>[];
          final token = CancellationToken(),
              reason = Exception('cancel $stage');
          addTearDown(probe.close);
          addTearDown(() => token.cancel(reason));
          final pending = runZoned(
            () => stage == 'header'
                ? readRecordsWithId(
                    state.path,
                    'handle',
                    cancellationToken: token,
                  )
                : readLatestRecord(
                    state.path,
                    agent: 'fake',
                    cwd: 'project',
                    cancellationToken: token,
                  ),
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
          expect(await handles(), contains(record.path));
          token.cancel(reason);
          await rejected;
          expect(await handles(), isNot(contains(record.path)));
          expect(trace.last['type'], 'exit');
          final closed = trace.singleWhere((e) => e['type'] == 'closed');
          expect(closed['outcome'], {'kind': 'cancelled'});
          expect(token.hasCancellables, isFalse);
          expect(
            (await readRecordsWithId(state.path, 'handle')).single.sessionId,
            'handle',
          );
        },
        skip: supportsHandleProof
            ? false
            : 'Own descriptor proof requires macOS lsof.',
      );
    }
  });
}
