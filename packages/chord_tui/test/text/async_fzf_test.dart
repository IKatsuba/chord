import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

FzfCasing casing(Object? value) => switch (value) {
  'case-insensitive' => FzfCasing.caseInsensitive,
  'case-sensitive' => FzfCasing.caseSensitive,
  _ => FzfCasing.smartCase,
};
List<Object?> fields<T>(FzfResult<T> r) => [
  r.item,
  r.index,
  r.score,
  r.start,
  r.end,
  r.positions,
];
void main() {
  for (final fixture in ['fzf_golden.json', 'fzf_tester_golden.json']) {
    final cases =
        (jsonDecode(File('test/text/$fixture').readAsStringSync()) as List)
            .cast<Map>();
    for (final c in cases) {
      test(
        'async equals sync all result fields: $fixture ${c['name']}',
        () async {
          final options = (c['options'] as Map?) ?? c;
          final items = (c['items'] as List).cast<String>();
          final ties = options['byLength'] == true
              ? [byLengthAsc<String>]
              : <FzfTiebreaker<String>>[];
          final sync = Fzf(
            items,
            casing: casing(options['casing']),
            normalize: options['normalize'] != false,
            limit: options['limit'] as int?,
            tiebreakers: ties,
          );
          final async = AsyncFzf(
            items,
            casing: casing(options['casing']),
            normalize: options['normalize'] != false,
            limit: options['limit'] as int?,
            tiebreakers: ties,
          );
          addTearDown(async.dispose);
          final queries =
              (c['queries'] as List?)?.cast<String>() ??
              (c['results'] as Map).keys.cast<String>();
          for (final query in ['', ...queries]) {
            final actual = (await async.find(query))!;
            expect(
              actual.map(fields),
              sync.find(query).map(fields),
              reason: query,
            );
            expect(() => actual.clear(), throwsUnsupportedError);
            if (actual.isNotEmpty) {
              expect(
                () => actual.first.positions.add(0),
                throwsUnsupportedError,
              );
            }
          }
        },
      );
    }
  }
  test(
    'snapshot candidate and tiebreaker order, selectors and duplicate indexes',
    () async {
      final items = [(1, 'café'), (2, 'cafe\u0301'), (3, 'Cafe'), (4, 'café')];
      final ties = <FzfTiebreaker<(int, String)>>[
        (a, b, _) => b.item.$1.compareTo(a.item.$1),
      ];
      final sync = Fzf(
        [...items],
        selector: (x) => x.$2,
        normalize: false,
        casing: FzfCasing.caseInsensitive,
        tiebreakers: [...ties],
      );
      final async = AsyncFzf(
        items,
        selector: (x) => x.$2,
        normalize: false,
        casing: FzfCasing.caseInsensitive,
        tiebreakers: ties,
      );
      addTearDown(async.dispose);
      items.clear();
      ties.clear();
      expect(() => async.items.clear(), throwsUnsupportedError);
      expect(() => async.tiebreakers.clear(), throwsUnsupportedError);
      for (final query in ['', 'café', 'cafe', 'CAFÉ', 'none']) {
        expect(
          (await async.find(query))!.map(fields),
          sync.find(query).map(fields),
        );
      }
    },
  );
  test(
    'preprocessing scan yields and superseded equal queries return null',
    () async {
      var selected = 0, ticked = false, done = false;
      final finder = AsyncFzf(
        List.generate(5000, (i) => 'src/file$i.ts'),
        selector: (String item) {
          selected++;
          return item;
        },
        limit: 100,
      );
      addTearDown(finder.dispose);
      final old = finder.find('file42').then((x) {
        done = true;
        return x;
      });
      expect(selected, 0);
      final atYield = Completer<void>();
      Timer.run(() {
        ticked = true;
        expect(done, isFalse);
        expect(selected, lessThan(5000));
        atYield.complete();
      });
      await atYield.future;
      final current = finder.find('file42');
      expect(await old, isNull);
      expect((await current)!.first.item, 'src/file42.ts');
      expect(ticked, isTrue);
    },
  );
  test(
    'final equal-score merge yields and supersession cancels before publication',
    () async {
      final items = List.generate(4096, (_) => 'same');
      late AsyncFzf<String> finder;
      Future<List<FzfResult<String>>?>? latest;
      var comparisons = 0;
      final timerRan = Completer<void>();
      finder = AsyncFzf(
        items,
        limit: 100,
        tiebreakers: [
          (a, b, _) {
            if (++comparisons == 1) {
              Timer.run(() {
                latest = finder.find('absent');
                timerRan.complete();
              });
            }
            return 0;
          },
        ],
      );
      addTearDown(finder.dispose);
      final old = finder.find('same');
      await timerRan.future;
      expect(comparisons, greaterThan(0));
      expect(comparisons, lessThan(items.length * 12));
      expect(await old, isNull);
      expect(await latest!, isEmpty);
    },
  );
  test(
    'large empty and equal-score results yield while stable order stays exact',
    () async {
      final items = List.generate(2048, (i) => 'same');
      final finder = AsyncFzf(items);
      addTearDown(finder.dispose);
      for (final query in ['', 'same']) {
        var ticked = false;
        final pending = finder.find(query);
        Timer.run(() => ticked = true);
        final results = (await pending)!;
        expect(ticked, isTrue);
        expect(
          results.map((x) => x.index),
          List.generate(items.length, (i) => i),
        );
      }
    },
  );
  test('dispose during scan or merge, idempotent and post-dispose', () async {
    for (final duringMerge in [false, true]) {
      late AsyncFzf<String> finder;
      var scheduled = false;
      void disposeLater() {
        if (scheduled) return;
        scheduled = true;
        Timer.run(finder.dispose);
      }

      finder = AsyncFzf(
        List.filled(2048, 'same'),
        selector: (String item) {
          if (!duringMerge) disposeLater();
          return item;
        },
        tiebreakers: [
          (a, b, _) {
            if (duringMerge) disposeLater();
            return 0;
          },
        ],
      );
      expect(await finder.find('same'), isNull);
      finder.dispose();
      expect(await finder.find('same'), isNull);
      expect(await finder.find(''), isNull);
    }
  });
}
