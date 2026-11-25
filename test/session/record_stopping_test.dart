// The original's record.ts for the person's stop of a subagent alone
// (CHD-479, Q118): a line of its own, taken back as one too, so a resumed
// transcript says who ended it as the live one did.
import 'dart:convert';
import 'dart:io';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'recording_test.dart' show lines, opening;

const _started = <Map<String, Object?>>[
  {'type': 'prompt', 'turnId': 't1', 'prompt': 'work', 'images': 0, 'at': 1},
  {
    'type': 'update',
    'turnId': 't1',
    'at': 2,
    'update': {
      'sessionUpdate': 'subagent_update',
      'sessionId': 'worker',
      'description': 'Run the test suite',
      'state': {'state': 'running'},
      'capabilities': {'cancel': <String, Object?>{}},
    },
  },
  {
    'type': 'result',
    'turnId': 't1',
    'result': {'status': 'completed', 'stopReason': 'end_turn'},
  },
];

const _cancelled = <String, Object?>{
  'type': 'update',
  'turnId': 't1',
  'at': 43002,
  'update': {
    'sessionUpdate': 'subagent_update',
    'sessionId': 'worker',
    'state': {'state': 'idle', 'stopReason': 'cancelled'},
  },
};

Map<String, Object?> _stop(bool stopping) => {
  'type': 'stopping',
  'subagentId': 'worker',
  'stopping': stopping,
};

/// The end lines a record's past draws.
List<ItemEndedEntry> _ends(List<Map<String, Object?>> entries) =>
    recordActions(entries).actions
        .fold(Transcript.empty, reduceTranscript)
        .entries
        .whereType<ItemEndedEntry>()
        .toList();

void main() {
  testerStoppingWorker();
  test('the stop goes into the record as its own line, and taken back as '
      'one too', () async {
    final writes = <String>[];
    final recording = FileRecording(
      'state',
      failed: fail,
      uuid: () => 'fixture',
      now: () => 1,
      append: (path, text) async => writes.add(text),
    );
    recording.opened(opening('id'));
    recording.sent('t1', 'work', 0, const [], 1);
    recording.heard(
      const Transcribed(SubagentStoppingAction('stop', 'worker', true)),
    );
    recording.heard(
      const Transcribed(SubagentStoppingAction('stop', 'worker', false)),
    );
    await recording.flushed();
    expect(
      [
        for (final line in lines(writes.join()))
          if (line['type'] == 'stopping') line,
      ],
      [_stop(true), _stop(false)],
    );
    expect(RecordEntry.view(_stop(true)), isNotNull);
    expect(
      RecordEntry.view({'type': 'stopping', 'subagentId': 'worker'}),
      isNull,
    );
  });

  test('a record with the stop says the person ended it; one written before '
      'these, or with the stop taken back, says only how it ended', () {
    final [stopped] = _ends([..._started, _stop(true), _cancelled]);
    expect(
      (stopped.end, stopped.byPerson, stopped.startedAt, stopped.endedAt),
      (ItemEnd.stopped, true, 2, 43002),
    );
    expect(_ends([..._started, _cancelled]).single.byPerson, isFalse);
    expect(
      _ends([
        ..._started,
        _stop(true),
        _stop(false),
        _cancelled,
      ]).single.byPerson,
      isFalse,
    );
  });
}

void testerStoppingWorker() {
  group('CTUI-83 tester: stopping history worker', () {
    for (final rollback in [false, true]) {
      test(
        'actual worker keeps stop attribution, rollback $rollback',
        () async {
          final dir = await Directory.systemTemp.createTemp('stopping-worker-');
          addTearDown(() => dir.delete(recursive: true));
          final file = File('${dir.path}/history.jsonl');
          final entries = [
            ..._started,
            _stop(true),
            if (rollback) _stop(false),
            _cancelled,
          ];
          await file.writeAsString(entries.map(jsonEncode).join('\n'));
          final past = await readRecordedHistory(file.path);
          expect(past.omitted, isFalse);
          final actions = past.actions
              .whereType<SubagentStoppingAction>()
              .toList();
          expect(actions.map((a) => (a.subagentId, a.stopping)), [
            ('worker', true),
            if (rollback) ('worker', false),
          ]);
          final copied = PreparedHistory.fromJson(
            jsonDecode(jsonEncode(past.toJson())) as Map<String, Object?>,
          );
          final end = copied.actions
              .fold(Transcript.empty, reduceTranscript)
              .entries
              .whereType<ItemEndedEntry>()
              .single;
          expect(
            (end.end, end.byPerson, end.endedAt),
            (ItemEnd.stopped, !rollback, 43002),
          );
        },
      );
    }

    test(
      'malformed stopping entries are omitted without losing a later valid stop',
      () {
        for (final bad in [
          {'type': 'stopping', 'subagentId': 1, 'stopping': true},
          {'type': 'stopping', 'subagentId': 'worker', 'stopping': 'true'},
          {'type': 'stopping', 'stopping': false},
        ]) {
          expect(RecordEntry.view(bad), isNull);
          final past = recordActions([
            ..._started,
            bad,
            _stop(true),
            _cancelled,
          ]);
          expect(past.omitted, isTrue);
          final end = past.actions
              .fold(Transcript.empty, reduceTranscript)
              .entries
              .whereType<ItemEndedEntry>()
              .single;
          expect(end.byPerson, isTrue);
        }
      },
    );
  });
}
