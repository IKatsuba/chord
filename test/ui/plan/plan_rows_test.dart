import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/ui/plan/plan_rows.dart';
import 'package:test/test.dart';

List<acp.PlanEntry> plan(List<String> statuses) => [
  for (final (i, status) in statuses.indexed)
    acp.PlanEntry.fromJson({
      'content': 'Step ${i + 1}',
      'status': status,
      'priority': 'medium',
    }),
];

List<String> rows(List<String> statuses, int limit) =>
    planRows(plan(statuses), limit)
        .map(
          (row) => switch (row) {
            EntryPlanRow(:final entry) => entry.content,
            DonePlanRow(:final count) => '$count done',
            MorePlanRow(:final count) => '+$count more',
          },
        )
        .toList();

void main() {
  test('summary counts completed entries and row limit takes a quarter', () {
    expect(
      planSummary(plan(['completed', 'completed', 'in_progress'])),
      'Plan · 2 of 3 done',
    );
    expect(planSummary([]), 'Plan · 0 of 0 done');
    expect([planRowLimit(40), planRowLimit(24), planRowLimit(8)], [10, 6, 3]);
    expect(planMarks.values, ['☐', '◐', '☒']);
  });
  test('a fitting plan is whole', () {
    expect(rows(['completed', 'in_progress', 'pending'], 3), [
      'Step 1',
      'Step 2',
      'Step 3',
    ]);
    expect(planRows([], 3), isEmpty);
  });
  test('tall plans fold only enough completed prefix to fit', () {
    final statuses = [
      'completed',
      'completed',
      'completed',
      'completed',
      'in_progress',
      'pending',
    ];
    expect(rows(statuses, 4), ['3 done', 'Step 4', 'Step 5', 'Step 6']);
    expect(rows(statuses, 3), ['4 done', 'Step 5', 'Step 6']);
    expect(rows([...statuses, 'pending'], 3), ['4 done', 'Step 5', '+2 more']);
    expect(rows(['completed', 'completed', 'completed', 'completed'], 3), [
      '2 done',
      'Step 3',
      'Step 4',
    ]);
  });
  test('a single finished step stays, and unfinished plans fold the end', () {
    expect(rows(['completed', 'in_progress', 'pending', 'pending'], 3), [
      'Step 1',
      'Step 2',
      '+2 more',
    ]);
    expect(rows(['in_progress', 'pending', 'pending', 'pending'], 3), [
      'Step 1',
      'Step 2',
      '+2 more',
    ]);
    expect(rows(['pending', 'completed', 'completed', 'pending'], 3), [
      'Step 1',
      'Step 2',
      '+2 more',
    ]);
  });
  test(
    'entry keys count duplicate content, preserving others after removal',
    () {
      expect(entryKeys(['a', 'b', 'a']), ['0 a', '0 b', '1 a']);
      expect(entryKeys(['b', 'a']), ['0 b', '0 a']);
    },
  );
  group('tester U8 plan selection invariants', () {
    test('folding accounts for every entry exactly once in original order', () {
      for (var completed = 0; completed <= 8; completed++) {
        final entries = plan([
          ...List.filled(completed, 'completed'),
          'in_progress',
          'pending',
          'completed',
          'pending',
        ]);
        final original = entries.toList();
        for (var limit = 3; limit <= 12; limit++) {
          final selected = planRows(entries, limit);
          expect(selected.length, lessThanOrEqualTo(limit));
          var accounted = 0;
          for (final row in selected) {
            switch (row) {
              case DonePlanRow(:final count):
                expect(identical(row, selected.first), isTrue);
                expect(count, greaterThan(1));
                expect(
                  entries.take(count).every((e) => e.status == 'completed'),
                  isTrue,
                );
                accounted += count;
              case EntryPlanRow(:final entry):
                expect(identical(entry, original[accounted]), isTrue);
                accounted++;
              case MorePlanRow(:final count):
                expect(identical(row, selected.last), isTrue);
                expect(count, greaterThan(1));
                accounted += count;
            }
          }
          expect(accounted, entries.length);
          expect(entries, original);
        }
      }
    });

    test('all completed steps fold only the necessary prefix', () {
      expect(rows(List.filled(8, 'completed'), 6), [
        '3 done',
        'Step 4',
        'Step 5',
        'Step 6',
        'Step 7',
        'Step 8',
      ]);
      expect(rows(List.filled(8, 'completed'), 3), [
        '6 done',
        'Step 7',
        'Step 8',
      ]);
      expect(
        rows([
          'pending',
          'completed',
          'completed',
          'completed',
          'completed',
        ], 3),
        ['Step 1', 'Step 2', '+3 more'],
      );
    });

    test(
      'keys preserve exact Unicode whitespace and duplicate occurrences',
      () {
        final contents = [
          '界🙂e\u0301',
          '',
          'same',
          'same ',
          'same',
          '',
          '界🙂e\u0301',
        ];
        final keys = entryKeys(contents);
        expect(keys, [
          '0 界🙂e\u0301',
          '0 ',
          '0 same',
          '0 same ',
          '1 same',
          '1 ',
          '1 界🙂e\u0301',
        ]);
        expect(keys.toSet(), hasLength(contents.length));
        expect(entryKeys(['same', 'same ', 'same']), [
          '0 same',
          '0 same ',
          '1 same',
        ]);
        expect(keys.first, '0 界🙂e\u0301');
        expect(entryKeys([]), isEmpty);
      },
    );

    test('marks summary and quarter-window boundary wording stay exact', () {
      expect(planMarks, {'pending': '☐', 'in_progress': '◐', 'completed': '☒'});
      expect(planSummary(plan(['pending'])), 'Plan · 0 of 1 done');
      expect(planSummary(plan(['completed'])), 'Plan · 1 of 1 done');
      expect(
        planSummary(plan(['in_progress', 'completed', 'pending', 'completed'])),
        'Plan · 2 of 4 done',
      );
      for (final (height, expected) in [
        (0, 3),
        (1, 3),
        (11, 3),
        (12, 3),
        (15, 3),
        (16, 4),
        (23, 5),
        (24, 6),
        (39, 9),
        (40, 10),
      ]) {
        expect(planRowLimit(height), expected, reason: 'height $height');
      }
    });
  });
}
