// chord acp's session/load and session/resume read only the records that
// name the id, and answer as the full scan would; session/list still reads
// every record.
import 'dart:convert';
import 'dart:io';

import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:fake_async/fake_async.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'acp_rig.dart';

String _record(String id, String agent, String cwd, List<num> prompts) => [
  encodeRecord({
    'type': 'session',
    'version': 1,
    'sessionId': id,
    'agent': agent,
    'cwd': cwd,
    'at': 1,
  }),
  for (final at in prompts)
    encodeRecord({
      'type': 'prompt',
      'turnId': 't$at',
      'prompt': 'p$at',
      'at': at,
      'images': 0,
    }),
].join();

Map<String, Object?> _reopen(String id) => {
  'sessionId': id,
  'cwd': '/w',
  'mcpServers': <Object?>[],
};

const _ids = ['s1', 's2', 's3', 's4', 'unknown'];

void main() {
  late Directory state;
  late List<SessionRecord> full;
  late Map<String, List<SessionRecord>> named;
  setUpAll(() async {
    state = await Directory.systemTemp.createTemp('chord-acp-targeted-');
    final dir = await Directory(recordsDir(state.path)).create();
    var n = 0;
    for (final text in [
      // Several of this agent's records with one id, and another agent's.
      _record('s1', 'memory', '/w', [10]),
      _record('s1', 'memory', '/w', [30]),
      _record('s1', 'other', '/w', [90]),
      // An id only another agent has.
      _record('s2', 'other', '/w', [5]),
      // An id recorded in another directory.
      _record('s3', 'memory', '/elsewhere', [7]),
      // An id with no prompt: not offered, so a bare resume.
      _record('s4', 'memory', '/w', []),
    ]) {
      await File(p.join(dir.path, '${n++}.jsonl')).writeAsString(text);
    }
    full = await readRecords(state.path);
    named = {
      for (final id in _ids) id: await readRecordsWithId(state.path, id),
    };
  });
  tearDownAll(() => state.delete(recursive: true));

  List<Object?> outcomes(Rig rig) {
    rig.init = {
      'protocolVersion': 1,
      'agentCapabilities': {'loadSession': true},
    };
    rig.initialize();
    final answers = <Object?>[];
    for (final method in ['session/load', 'session/resume']) {
      for (final id in _ids) {
        final asked = rig.request(method, _reopen(id));
        rig.settle();
        answers.add(jsonEncode([method, id, rig.answer(asked)]));
      }
    }
    // What each started agent was asked to reopen.
    answers.add(
      jsonEncode([
        for (final agent in rig.agents)
          for (final message in agent.stdin.messages)
            if (message['method'] case 'session/load' || 'session/resume')
              (message['params'] as Map)['sessionId'],
      ]),
    );
    return answers;
  }

  test('by-id loads answer as on the full scan, without reading it', () {
    late List<Object?> scanned, targeted;
    var scans = 0;
    fakeAsync((async) {
      final rig = Rig(async, records: () async => full);
      scanned = outcomes(rig);
      rig.eof();
    });
    fakeAsync((async) {
      final rig = Rig(
        async,
        records: () async {
          scans++;
          throw StateError('the full scan is not read for an id');
        },
        recordsWithId: (id) async => named[id]!,
      );
      targeted = outcomes(rig);
      rig.eof();
    });
    expect(targeted, scanned);
    expect(scans, 0);
    // The cases are what they are on the full scan.
    final errors = [
      for (final answer
          in scanned.take(10).map((a) => jsonDecode(a as String) as List))
        (answer[1], ((answer[2] as Map?)?['error'] as Map?)?['message']),
    ];
    printOnFailure(scanned.join("\n"));
    // s1 resolves to its record, whose past is then read off the fake
    // clock, so its load waits in both; s4 and unknown are bare resumes.
    expect(jsonDecode(scanned.first as String), ['session/load', 's1', null]);
    expect(jsonDecode(scanned.last as String), ['s4', 'unknown']);
    expect(errors.take(5), [
      ('s1', null),
      ('s2', 'Invalid params: Session s2 belongs to another agent (other).'),
      ('s3', 'Invalid params: Session s3 is in /elsewhere.'),
      ('s4', null),
      ('unknown', null),
    ]);
  });

  test('with records alone given, an id is taken from them; session/list '
      'still reads every record', () {
    fakeAsync((async) {
      var scans = 0;
      final rig = Rig(
        async,
        records: () async {
          scans++;
          return full;
        },
      );
      rig.initialize();
      final load = rig.request('session/load', _reopen('s2'));
      rig.settle();
      expect((rig.answer(load)!['error'] as Map)['message'], contains('other'));
      expect(scans, 1);
      final list = rig.request('session/list', {'cwd': '/w'});
      rig.settle();
      final sessions = (rig.answer(list)!['result'] as Map)['sessions'] as List;
      expect([for (final s in sessions) (s as Map)['sessionId']], ['s1']);
      expect(scans, 2);
      rig.eof();
    });
  });
}
