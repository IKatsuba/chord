import 'dart:async';
import 'dart:convert';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

RecordingSession _opening(String id) => RecordingSession(
  sessionId: id,
  agent: 'fake',
  cwd: 'fixture-project',
  record: '$id.jsonl',
  state: AgentState.empty,
);

Transcribed _update(String text, [num? value]) => Transcribed(
  UpdateAction(
    'turn',
    acp.SessionUpdate.fromJson({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': text},
      if (value != null) '_meta': {'value': value},
    }),
  ),
);

List<Map<String, Object?>> _lines(String text) =>
    parseRecord(text).cast<Map<String, Object?>>();

void main() {
  group('CTUI-26 U2 tester: drain pressure and reentrant ownership', () {
    test(
      'a thousand updates remain ordered across close and a stalled append',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final writes = <String>[];
        final recording = FileRecording(
          'state',
          failed: fail,
          append: (_, text) async {
            writes.add(text);
            if (writes.length == 1) {
              entered.complete();
              await release.future;
            }
          },
        );
        recording.opened(_opening('first'));
        recording.sent('turn', 'submitted', 0, [], 1);
        await entered.future;
        for (var i = 0; i < 1000; i++) {
          recording.heard(_update('界👩‍💻é $i', i + 0.25));
        }
        final queued = recording.queuedBytes;
        expect(queued, greaterThan(1000));
        recording.heard(
          const Transcribed(ResultAction('turn', TurnAnswered('end_turn'))),
        );
        recording.heard(const Closing());
        recording.heard(_update('after close'));
        recording.sent('late', 'after close', 0, [], 2);
        var joined = false;
        final flushed = recording.flushed().then((_) => joined = true);
        await Future<void>.delayed(Duration.zero);
        expect(joined, isFalse);
        release.complete();
        await flushed;
        final kept = _lines(writes.join());
        final updates = kept.where((line) => line['type'] == 'update').toList();
        expect(updates, hasLength(1000));
        for (var i = 0; i < updates.length; i++) {
          final update = updates[i]['update'] as Map;
          expect((update['content'] as Map)['text'], '界👩‍💻é $i');
          expect((update['_meta'] as Map)['value'], i + 0.25);
        }
        expect(kept.last['type'], 'result');
        expect(writes.join(), isNot(contains('after close')));
        expect(recording.queuedBytes, 0);
        expect(recording.heldBytes, 0);
        expect(recording.queuedBytesHighWater, greaterThanOrEqualTo(queued));
        expect(utf8.encode(writes.join()).length, greaterThan(queued));
      },
    );

    test(
      'a failed captured path drops the rest of its batch before a fresh retry',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final attempts = <String>[], warnings = <String>[];
        final saved = <String, StringBuffer>{};
        final recording = FileRecording(
          'state',
          failed: warnings.add,
          append: (path, text) async {
            attempts.add(path);
            if (attempts.length == 1) {
              entered.complete();
              await release.future;
            }
            if (path == 'second.jsonl') {
              throw StateError('fixture uncertain write');
            }
            (saved[path] ??= StringBuffer()).write(text);
          },
        );
        recording.opened(_opening('first'));
        recording.sent('turn', 'first admitted', 0, [], 1);
        await entered.future;
        recording.heard(const Cleared());
        recording.opened(_opening('second'));
        recording.sent('turn', 'uncertain second', 0, [], 2);
        recording.heard(const Cleared());
        recording.opened(_opening('third'));
        recording.sent('turn', 'dropped third', 0, [], 3);
        release.complete();
        await recording.flushed();
        expect(attempts, ['first.jsonl', 'second.jsonl']);
        expect(saved.keys, ['first.jsonl']);
        expect(recording.queuedBytes, 0);
        expect(warnings, hasLength(1));
        recording.heard(_update('fresh third'));
        await recording.flushed();
        expect(attempts, ['first.jsonl', 'second.jsonl', 'third.jsonl']);
        final third = _lines(saved['third.jsonl'].toString());
        expect(third.map((line) => line['type']), ['update']);
        expect(saved['third.jsonl'].toString(), contains('fresh third'));
        expect(
          saved['third.jsonl'].toString(),
          isNot(contains('dropped third')),
        );
        expect(warnings, hasLength(1));
      },
    );

    test(
      'append observer may close synchronously without admitting replacement work',
      () async {
        final writes = <String>[];
        late FileRecording recording;
        recording = FileRecording(
          'state',
          failed: fail,
          append: (_, text) async {
            writes.add(text);
            recording.heard(const Closing());
            recording.opened(_opening('replacement'));
            recording.sent('late', 'replacement prompt', 0, [], 9);
            recording.heard(_update('replacement update'));
          },
        );
        recording.opened(_opening('first'));
        recording.sent('turn', 'admitted first', 0, [], 1);
        await Future.wait([recording.flushed(), recording.flushed()]);
        expect(writes, hasLength(1));
        expect(writes.single, contains('admitted first'));
        expect(writes.single, isNot(contains('replacement')));
        expect(recording.path, isNull);
        expect(recording.queuedBytes, 0);
        expect(recording.heldBytes, 0);
      },
    );
  });
}
