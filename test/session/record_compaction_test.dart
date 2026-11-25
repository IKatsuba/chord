// The original's record.ts for an idle compaction (CHD-624): its opening
// update carries the unasked mark into the record, and a replay of the
// record draws the compaction unasked again.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'recording_test.dart' show lines, opening;

Transcribed compaction(String status, {bool unasked = false}) => Transcribed(
  UpdateAction(
    'c1',
    acp.SessionUpdate.fromJson({
      'sessionUpdate': 'compaction_update',
      'compactionId': 'k1',
      'status': status,
    }),
    unasked: unasked,
  ),
);

void main() {
  test(
    'only the opening update is written unasked, and replay keeps it',
    () async {
      final writes = <String>[];
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'fixture',
        now: () => 1,
        append: (path, text) async => writes.add(text),
      );
      recording.opened(opening('id'));
      recording.heard(const Transcribed(CycleStartedAction('c1', 5)));
      recording.heard(compaction('in_progress', unasked: true));
      recording.heard(
        Transcribed(
          UpdateAction(
            'c1',
            acp.SessionUpdate.fromJson({
              'sessionUpdate': 'compaction_summary_chunk',
              'compactionId': 'k1',
              'content': {'type': 'text', 'text': 'Kept.'},
            }),
          ),
        ),
      );
      recording.heard(compaction('completed'));
      await recording.flushed();

      final updates = [
        for (final line in lines(writes.join()))
          if (line['type'] == 'update') line,
      ];
      expect([for (final line in updates) line['unasked']], [true, null, null]);

      final read = recordActions(lines(writes.join()));
      expect(read.omitted, isFalse);
      // As the preparation isolate hands it back.
      final past = PreparedHistory.fromJson(read.toJson());
      final drawn = past.actions
          .fold(Transcript.empty, reduceTranscript)
          .entries
          .whereType<CompactionEntry>()
          .single
          .compaction;
      expect(
        (drawn.id, drawn.status, drawn.summary, drawn.unasked),
        ('k1', 'completed', 'Kept.', true),
      );
    },
  );

  test('a compaction asked in a turn replays plain', () {
    final past = recordActions([
      {
        'type': 'update',
        'turnId': 't',
        'update': {
          'sessionUpdate': 'compaction_update',
          'compactionId': 'k1',
          'status': 'completed',
        },
      },
    ]);
    final entry = past.actions
        .fold(Transcript.empty, reduceTranscript)
        .entries
        .whereType<CompactionEntry>()
        .single;
    expect(entry.compaction.unasked, isFalse);
    expect(past.omitted, isFalse);
  });
}
