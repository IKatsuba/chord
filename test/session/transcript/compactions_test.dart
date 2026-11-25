import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

UpdateAction compactionUpdate(
  String id,
  String status, {
  Object? summary = _absent,
  Object? error = _absent,
  bool unasked = false,
}) => UpdateAction(
  't1',
  update('t1', {
    'sessionUpdate': 'compaction_update',
    'compactionId': id,
    'status': status,
    if (!identical(summary, _absent)) 'summary': summary,
    if (!identical(error, _absent)) 'error': error,
  }).update,
  unasked: unasked,
);

const _absent = Object();

UpdateAction summaryChunk(String id, String text) => update('t1', {
  'sessionUpdate': 'compaction_summary_chunk',
  'compactionId': id,
  'content': {'type': 'text', 'text': text},
});

List<Map<String, Object?>> compactionsOf(Transcript state) => [
  for (final entry in state.entries)
    if (entry is CompactionEntry) describedCompaction(entry.compaction),
];

void main() {
  test(
    "a compaction is one entry by its id, its summary built from chunks, as Claude's adapter sends it",
    () {
      final actions = <TranscriptAction>[
        const PromptAction('t1', '/compact', 0),
        compactionUpdate('k1', 'in_progress'),
        summaryChunk('k1', 'Read the '),
        summaryChunk('k1', 'README.'),
        compactionUpdate('k1', 'completed'),
      ];
      final seen = states(actions);

      expect(compactionsOf(seen[1]), [
        {'id': 'k1', 'status': 'in_progress', 'summary': ''},
      ]);
      expect(compactionsOf(seen[3]), [
        {'id': 'k1', 'status': 'in_progress', 'summary': 'Read the README.'},
      ]);
      expect(fold(actions).entries.map(describedEntry), [
        {'turnId': 't1', 'kind': 'user', 'text': '/compact'},
        {
          'turnId': 't1',
          'kind': 'compaction',
          'compaction': {
            'id': 'k1',
            'status': 'completed',
            'summary': 'Read the README.',
          },
        },
      ]);
    },
  );

  test(
    'a summary sent whole replaces the chunks, and null or [] clears it',
    () {
      final start = [
        compactionUpdate('k1', 'in_progress'),
        summaryChunk('k1', 'raw <summary>'),
      ];

      expect(
        compactionsOf(
          fold([
            ...start,
            compactionUpdate(
              'k1',
              'completed',
              summary: [
                {'type': 'text', 'text': 'Clean'},
                {'type': 'text', 'text': ' summary.'},
              ],
            ),
          ]),
        ).first['summary'],
        'Clean summary.',
      );

      for (final summary in [null, <Object?>[]]) {
        expect(
          compactionsOf(
            fold([
              ...start,
              compactionUpdate('k1', 'completed', summary: summary),
            ]),
          ).first['summary'],
          '',
        );
      }
    },
  );

  test(
    'a failed compaction keeps its error, and a later update without one leaves it',
    () {
      final failed = fold([
        compactionUpdate('k1', 'in_progress'),
        compactionUpdate(
          'k1',
          'failed',
          error: 'Not enough messages to compact.',
        ),
        // A duplicate of the terminal update, as Claude's adapter can send.
        compactionUpdate('k1', 'failed'),
      ]);

      expect(compactionsOf(failed), [
        {
          'id': 'k1',
          'status': 'failed',
          'summary': '',
          'error': 'Not enough messages to compact.',
        },
      ]);
      expect(
        compactionsOf(
          fold([compactionUpdate('k1', 'failed', error: null)], failed),
        ).first.containsKey('error'),
        isFalse,
      );
    },
  );

  test(
    'a compaction whose first update is its last, as one replayed, still gets its entry',
    () {
      expect(
        fold([
          compactionUpdate(
            'k1',
            'completed',
            summary: [
              {'type': 'text', 'text': 'Done.'},
            ],
          ),
        ]).entries.map(describedEntry),
        [
          {
            'turnId': 't1',
            'kind': 'compaction',
            'compaction': {
              'id': 'k1',
              'status': 'completed',
              'summary': 'Done.',
            },
          },
        ],
      );
    },
  );

  test(
    'a chunk for no compaction is dropped, and two compactions keep apart',
    () {
      final state = fold([
        summaryChunk('k0', 'stray'),
        compactionUpdate('k1', 'in_progress'),
        compactionUpdate('k2', 'in_progress'),
        summaryChunk('k1', 'one'),
        summaryChunk('k2', 'two'),
        compactionUpdate('k1', 'cancelled'),
      ]);

      expect(compactionsOf(state), [
        {'id': 'k1', 'status': 'cancelled', 'summary': 'one'},
        {'id': 'k2', 'status': 'in_progress', 'summary': 'two'},
      ]);
    },
  );

  test('unasked is said by the opening update and kept by every later one', () {
    final state = fold([
      compactionUpdate('k1', 'in_progress', unasked: true),
      summaryChunk('k1', 'kept'),
      compactionUpdate('k1', 'completed'),
      compactionUpdate('k2', 'in_progress'),
      compactionUpdate('k2', 'completed', unasked: true),
    ]);

    expect(compactionsOf(state), [
      {'id': 'k1', 'status': 'completed', 'summary': 'kept', 'unasked': true},
      {'id': 'k2', 'status': 'completed', 'summary': ''},
    ]);
  });

  test(
    'a malformed compaction update draws nothing, and the next still draws',
    () {
      final state = fold([
        update('t1', {'sessionUpdate': 'compaction_update', 'status': 'x'}),
        update('t1', {
          'sessionUpdate': 'compaction_summary_chunk',
          'compactionId': 'k1',
        }),
        compactionUpdate('k1', 'in_progress'),
      ]);

      expect(compactionsOf(state), [
        {'id': 'k1', 'status': 'in_progress', 'summary': ''},
      ]);
    },
  );
}
