import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

void main() {
  group('tester compaction history codec', () {
    for (final mark in <Object?>[true, false, null, 'true', 1]) {
      test(
        'only literal true survives history preparation: $mark (${mark.runtimeType})',
        () {
          final read = recordActions([
            {
              'type': 'update',
              'turnId': 'first',
              'unasked': mark,
              'update': {
                'sessionUpdate': 'compaction_update',
                'compactionId': 'compact',
                'status': 'in_progress',
              },
            },
            {
              'type': 'update',
              'turnId': 'later',
              'update': {
                'sessionUpdate': 'compaction_summary_chunk',
                'compactionId': 'compact',
                'content': {'type': 'text', 'text': '界🙂e\u0301\x1b[31m'},
              },
            },
            {
              'type': 'update',
              'turnId': 'later',
              'update': {
                'sessionUpdate': 'compaction_update',
                'compactionId': 'compact',
                'status': 'failed',
                'error': 'failure',
              },
            },
          ]);
          final history = PreparedHistory.fromJson(read.toJson());
          expect(history.omitted, isFalse);
          final entry =
              history.actions
                      .fold(Transcript.empty, reduceTranscript)
                      .entries
                      .single
                  as CompactionEntry;
          expect(entry.turnId, 'history-first');
          expect(entry.compaction.unasked, mark == true);
          expect(entry.compaction.summary, '界🙂e\u0301\x1b[31m');
          expect(entry.compaction.error, 'failure');
        },
      );
    }
  });
}
