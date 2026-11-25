import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/record_worker.dart';

import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'record_worker_test.dart' show ProbeEvents;

String _line(Map<String, Object?> json) => encodeRecord(json).trimRight();

String _header(
  String id,
  String agent,
  String cwd, {
  String? parent,
  String? task,
}) => _line({
  'type': 'session',
  'version': 1,
  'sessionId': id,
  'agent': agent,
  'cwd': cwd,
  'at': 1,
  'parent': ?parent,
  'task': ?task,
});

String _prompt(num at, [String text = 'hello']) => _line({
  'type': 'prompt',
  'turnId': 't$at',
  'prompt': text,
  'at': at,
  'images': 0,
});

String _update(String text) => _line({
  'type': 'update',
  'turnId': 't',
  'update': {
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  },
});

final _opened = _line({'type': 'opened', 'at': 3});

String _record(String header, List<num> prompts, {String end = '\n'}) => [
  header,
  _opened,
  for (final at in prompts) ...[_prompt(at), _update('x')],
].join(end);

typedef _Shown = (String, String, String?, num?, String?, String?);

Object? _outcome(Resume Function() pick) {
  try {
    final r = pick();
    final _Shown shown = (
      r.sessionId,
      r.cwd,
      r.record,
      r.lastUsedAt,
      r.prompt,
      r.title,
    );
    return shown;
  } on ResumeError catch (error) {
    return 'refused: ${error.message}';
  }
}

void main() {
  late Directory state;
  late String records;
  setUpAll(() async {
    state = await Directory.systemTemp.createTemp('chord-targeted-');
    records = (await Directory(recordsDir(state.path)).create()).path;
    var n = 0;
    Future<void> write(String text, [String? name]) => File(
      p.join(records, '${name ?? (n++).toString().padLeft(3, '0')}.jsonl'),
    ).writeAsString(text);

    // Several records per session id, newest not listed last.
    await write(_record(_header('s1', 'claude', '/a'), [10]));
    await write(_record(_header('s1', 'claude', '/a'), [5, 30]));
    await write(_record(_header('s1', 'claude', '/a'), [20]));
    // Another agent's record with the same id, and an id only it has.
    await write(_record(_header('s1', 'codex', '/a'), [90]));
    await write(_record(_header('s2', 'codex', '/a'), [15]));
    // Records with no prompt are not offered, however late they open.
    await write([_header('s3', 'claude', '/a'), _opened].join('\n'));
    await write(_header('s4', 'claude', '/a'));
    // A task record has no parent and is a candidate; a child is not.
    await write(_record(_header('task', 'claude', '/a', task: 'a task'), [25]));
    await write(_record(_header('child', 'claude', '/a', parent: 'p'), [99]));
    // Another directory.
    await write(_record(_header('b1', 'claude', '/b'), [500]));
    // Equal times: the earlier listed wins.
    await write(_record(_header('tie1', 'claude', '/c'), [50]));
    await write(_record(_header('tie2', 'claude', '/c'), [50]));
    // CRLF, then an invalid prompt (no images) and a torn last line: the
    // last valid prompt is the one at 40.
    await write(
      '${_record(_header('crlf', 'claude', '/a'), [12, 29.5], end: '\r\n')}'
      '\r\n{"type":"prompt","turnId":"t","prompt":"bad","at":999}'
      '\r\n{"type":"prompt","turnId":"t","prompt":"torn","at":9',
    );
    // A last prompt of multi-byte text longer than a backward chunk, after
    // a large tail of updates, so chunk edges fall inside both.
    await write(
      [
        _header('big', 'claude', '/d'),
        _prompt(60),
        _prompt(70, 'é🙂界' * 30000),
        for (var i = 0; i < 40; i++) _update('κόσμε🙂' * 900),
      ].join('\n'),
    );
    await write(_record(_header('small', 'claude', '/d'), [65]));
    // An unreadable candidate is dropped by both reads.
    await write(_record(_header('e1', 'claude', '/e'), [5]));
    await write(_record(_header('e2', 'claude', '/e'), [1000]), 'zz_locked');
    await Process.run('chmod', ['000', p.join(records, 'zz_locked.jsonl')]);
    // A candidate with no prompt whose opening is the latest time.
    await write([_header('e3', 'claude', '/e'), _opened].join('\n'));
  });
  tearDownAll(() async {
    await Process.run('chmod', ['600', p.join(records, 'zz_locked.jsonl')]);
    await state.delete(recursive: true);
  });

  test('by id: records with the id give what the full scan gives to '
      'sessionById and recordedAgent', () async {
    final full = await readRecords(state.path);
    for (final id in [
      's1',
      's2',
      's3',
      's4',
      'task',
      'child',
      'crlf',
      'big',
      'e2',
      'unknown',
    ]) {
      final named = await readRecordsWithId(state.path, id);
      expect(named.every((r) => r.sessionId == id), isTrue);
      expect(recordedAgent(named, id), recordedAgent(full, id), reason: id);
      for (final agent in ['claude', 'codex']) {
        expect(
          _outcome(() => sessionById(named, id, agent: agent, cwd: '/x')),
          _outcome(() => sessionById(full, id, agent: agent, cwd: '/x')),
          reason: '$id $agent',
        );
      }
    }
    // An id only another agent recorded is refused.
    final s2 = await readRecordsWithId(state.path, 's2');
    expect(
      _outcome(() => sessionById(s2, 's2', agent: 'claude', cwd: '/a')),
      'refused: Session s2 belongs to another agent (codex).',
    );
    // The CRLF record's time is its last valid prompt's, past the invalid
    // and torn lines after it.
    expect(
      (await readRecordsWithId(state.path, 'crlf')).single.lastUsedAt,
      29.5,
    );
  });

  test('--continue: the latest record gives what the full scan gives to '
      'latestSession, across ties, CRLF, torn and invalid last lines, '
      'multi-byte text over backward chunk edges, no-prompt and '
      'unreadable candidates', () async {
    final full = await readRecords(state.path);
    final seen = <Object?>[];
    for (final agent in ['claude', 'codex', 'gemini']) {
      for (final cwd in ['/a', '/b', '/c', '/d', '/e', '/z']) {
        final latest = await readLatestRecord(
          state.path,
          agent: agent,
          cwd: cwd,
        );
        expect(latest.length, lessThanOrEqualTo(1));
        final outcome = _outcome(
          () => latestSession(latest, agent: agent, cwd: cwd),
        );
        expect(
          outcome,
          _outcome(() => latestSession(full, agent: agent, cwd: cwd)),
          reason: '$agent $cwd',
        );
        seen.add(outcome);
      }
    }
    String? id(Object? outcome) => outcome is _Shown ? outcome.$1 : null;
    // The cases this set exists for, as both reads see them.
    num? at(Object? outcome) => outcome is _Shown ? outcome.$4 : null;
    expect((id(seen[0]), at(seen[0])), ('s1', 30)); // claude /a
    expect(id(seen[1]), 'b1');
    expect(id(seen[2]), 'tie1'); // equal times: the earlier listed
    expect((id(seen[3]), at(seen[3])), ('big', 70));
    expect(id(seen[4]), 'e1'); // e2 unreadable, e3 has no prompt
    expect(seen[5], startsWith('refused: No earlier claude session'));
    expect((id(seen[6]), at(seen[6])), ('s1', 90)); // codex /a
  });

  for (final (stage, read) in [
    (
      'header',
      (CancellationToken token) =>
          readRecordsWithId(state.path, 's1', cancellationToken: token),
    ),
    (
      'tail',
      (CancellationToken token) => readLatestRecord(
        state.path,
        agent: 'claude',
        cwd: '/a',
        cancellationToken: token,
      ),
    ),
  ]) {
    test('a cancel while a $stage read holds its file open ends the '
        'worker, its reads joined', () async {
      final token = CancellationToken(),
          probe = ProbeEvents(),
          trace = <Map<String, Object?>>[];
      addTearDown(probe.close);
      final pending = runZoned(
        () => read(token),
        zoneValues: {
          recordWorkerTestKey: RecordWorkerTestHooks(
            events: probe.port.sendPort,
            gates: [stage],
            observe: trace.add,
          ),
        },
      );
      final rejected = expectLater(pending, throwsA(isA<CancelledException>()));
      await probe.next((e) => e['type'] == 'gate' && e['stage'] == stage);
      token.cancel();
      await rejected;
      final closed = trace.singleWhere((e) => e['type'] == 'closed');
      expect(closed['streams'], 0);
      expect(closed['tasks'], 0);
      expect((closed['outcome'] as Map)['kind'], 'cancelled');
      expect(trace.last['type'], 'exit');
    });
  }
}
