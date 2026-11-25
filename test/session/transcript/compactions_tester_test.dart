import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

UpdateAction _status(String turn, String id, String status) => update(turn, {
  'sessionUpdate': 'compaction_update',
  'compactionId': id,
  'status': status,
});

UpdateAction _chunk(String turn, String id, String text) => update(turn, {
  'sessionUpdate': 'compaction_summary_chunk',
  'compactionId': id,
  'content': {'type': 'text', 'text': text},
});

void main() {
  group('tester compaction fold boundaries', () {
    test('later turns retain the opening position and logical identity', () {
      final before = fold([
        const PromptAction('first', '/compact', 0),
        _status('first', 'compact', 'in_progress'),
        const PromptAction('second', 'next', 1),
        _status('second', 'other', 'in_progress'),
      ]);
      final opening = before.entries[1] as CompactionEntry;
      final identity = opening.identity;
      final after = fold([
        _chunk('second', 'compact', 'summary'),
        _status('third', 'compact', 'completed'),
      ], before);
      final patched = after.entries[1] as CompactionEntry;
      expect(patched.turnId, 'first');
      expect(patched.identity, same(identity));
      expect(patched.compaction.summary, 'summary');
      expect(patched.compaction.status, 'completed');
      expect(after.entries.length, 4);
      expect(after.entries[0], same(before.entries[0]));
      expect(after.entries[2], same(before.entries[2]));
      expect(after.entries[3], same(before.entries[3]));
    });

    test('a thousand chunks preserve Unicode and escape bytes verbatim', () {
      const text = '界🙂e\u0301\x1b[31m';
      final state = fold([
        _status('first', 'compact', 'in_progress'),
        for (var i = 0; i < 1000; i++) _chunk('first', 'compact', text),
        _status('first', 'compact', 'completed'),
      ]);
      expect(state.entries, hasLength(1));
      expect(
        (state.entries.single as CompactionEntry).compaction.summary,
        List.filled(1000, text).join(),
      );
    });

    test('empty and stray chunks retain identical state', () {
      final state = fold([_status('first', 'compact', 'in_progress')]);
      expect(
        reduceTranscript(state, _chunk('first', 'compact', '')),
        same(state),
      );
      expect(
        reduceTranscript(state, _chunk('first', 'missing', 'x')),
        same(state),
      );
    });

    test('malformed patches are atomic and valid late updates still apply', () {
      final state = fold([
        _status('first', 'compact', 'in_progress'),
        _chunk('first', 'compact', 'kept'),
      ]);
      for (final patch in <Map<String, Object?>>[
        {'status': 3},
        {'status': 'failed', 'error': 3},
        {
          'status': 'completed',
          'summary': [
            {'type': 'text', 'text': 'partial'},
            3,
          ],
        },
      ]) {
        expect(
          reduceTranscript(
            state,
            update('first', {
              'sessionUpdate': 'compaction_update',
              'compactionId': 'compact',
              ...patch,
            }),
          ),
          same(state),
        );
      }
      final after = fold([_status('late', 'compact', 'cancelled')], state);
      final compaction = (after.entries.single as CompactionEntry).compaction;
      expect(compaction.summary, 'kept');
      expect(compaction.status, 'cancelled');
    });

    test('separate transcripts isolate identical compaction ids', () {
      final first = fold([
        _status('first', 'same', 'in_progress'),
        _chunk('first', 'same', 'one'),
      ]);
      final second = fold([
        _status('second', 'same', 'failed'),
        _chunk('second', 'same', 'two'),
      ]);
      expect(
        (first.entries.single as CompactionEntry).compaction.summary,
        'one',
      );
      expect(
        (second.entries.single as CompactionEntry).compaction.summary,
        'two',
      );
    });
  });
}
