import 'dart:convert';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

/// What fzf-for-js 0.5.2 answered, written by fzf_golden.mjs.
final List<Map<String, Object?>> golden = [
  for (final c
      in jsonDecode(File('test/text/fzf_golden.json').readAsStringSync())
          as List)
    (c as Map).cast<String, Object?>(),
];

FzfCasing casingOf(Object? name) => switch (name) {
  'case-insensitive' => FzfCasing.caseInsensitive,
  'case-sensitive' => FzfCasing.caseSensitive,
  _ => FzfCasing.smartCase,
};

void main() {
  testerEdges();
  group('matches fzf-for-js', () {
    for (final c in golden) {
      final items = (c['items'] as List).cast<String>();
      final options = (c['options'] as Map).cast<String, Object?>();
      final fzf = Fzf<String>(
        items,
        casing: casingOf(options['casing']),
        limit: options['limit'] as int?,
        tiebreakers: options['byLength'] == true
            ? [byLengthAsc<String>]
            : const [],
      );
      final results = (c['results'] as Map).cast<String, List>();
      for (final MapEntry(key: query, value: want) in results.entries) {
        test('${c['name']}: "$query"', () {
          final got = [
            for (final r in fzf.find(query))
              [r.index, r.score, r.start, r.end, r.positions],
          ];
          expect(got, want);
        });
      }
    }
  });

  test('items can be anything with a selector', () {
    final fzf = Fzf<(int, String)>(
      [(1, 'model'), (2, 'mcp'), (3, 'theme')],
      selector: (item) => item.$2,
      casing: FzfCasing.caseInsensitive,
    );
    expect([for (final r in fzf.find('m')) r.item.$1], [1, 2, 3]);
    expect([for (final r in fzf.find('mc')) r.item.$1], [2]);
  });

  test('an empty query gives the first items in order', () {
    final fzf = Fzf(['b', 'a', 'c'], limit: 2);
    final found = fzf.find('');
    expect([for (final r in found) r.item], ['b', 'a']);
    expect(found.first.positions, isEmpty);
  });

  test('without normalisation an accent must be typed', () {
    final fzf = Fzf(['café'], normalize: false);
    expect(fzf.find('cafe'), isEmpty);
    expect(fzf.find('café'), hasLength(1));
  });
}

void testerEdges() {
  group('tester: fzf independent boundary oracle', () {
    final cases =
        (jsonDecode(File('test/text/fzf_tester_golden.json').readAsStringSync())
                as List)
            .cast<Map>();
    for (final c in cases) {
      final items = (c['items'] as List).cast<String>();
      final queries = (c['queries'] as List).cast<String>();
      final expected = c['results'] as List;
      final fzf = Fzf<String>(
        items,
        casing: casingOf(c['casing']),
        normalize: c['normalize'] != false,
        limit: c['limit'] as int?,
        tiebreakers: c['byLength'] == true ? [byLengthAsc<String>] : const [],
      );
      for (var q = 0; q < queries.length; q++) {
        test('${c['name']}, query $q', () {
          expect([
            for (final r in fzf.find(queries[q]))
              [r.index, r.score, r.start, r.end, r.positions],
          ], expected[q]);
        });
      }
    }

    test('caller tie breakers apply in order and equal ties stay stable', () {
      final fzf = Fzf(
        ['ax', 'ay', 'az'],
        tiebreakers: [(a, b, _) => 0, (a, b, _) => b.index.compareTo(a.index)],
      );
      expect([for (final r in fzf.find('a')) r.index], [2, 1, 0]);
      final stable = Fzf(['ax', 'ay', 'az'], tiebreakers: [(a, b, _) => 0]);
      expect([for (final r in stable.find('a')) r.index], [0, 1, 2]);
    });

    test(
      'repeated queries do not mutate prior results or retain scratch positions',
      () {
        final items = ['ababa', 'aaab', '界a🙂b', 'AlphaBeta'];
        final finder = Fzf(items);
        final before = finder.find('ab');
        List<Object> describe(List<FzfResult<String>> results) => [
          for (final r in results)
            [
              r.index,
              r.score,
              r.start,
              r.end,
              [...r.positions],
            ],
        ];
        final snapshot = describe(before);
        for (var i = 0; i < 1000; i++) {
          finder.find(i.isEven ? 'aa' : '界b');
        }
        expect(describe(before), snapshot);
        expect(describe(finder.find('ab')), snapshot);
        expect(describe(Fzf(items).find('ab')), snapshot);
      },
    );
  });
}
