import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

List<Object?> _fields(FzfResult<String> result) => [
  result.item,
  result.index,
  result.score,
  result.start,
  result.end,
  result.positions,
];

void main() {
  group('tester: asynchronous fuzzy ownership and option boundaries', () {
    test(
      'negative limits preserve synchronous errors even without matches',
      () async {
        for (final items in [
          <String>[],
          ['same'],
        ]) {
          for (final query in ['', 'same', 'missing']) {
            for (final limit in [-2, -1, 0, 1, 99]) {
              List<FzfResult<String>>? expected;
              Object? error;
              try {
                expected = Fzf(items, limit: limit).find(query);
              } catch (caught) {
                error = caught;
              }
              final finder = AsyncFzf(items, limit: limit);
              try {
                if (error == null) {
                  expect(
                    (await finder.find(query))!.map(_fields),
                    expected!.map(_fields),
                    reason: '$items / $query / $limit',
                  );
                } else {
                  await expectLater(
                    finder.find(query),
                    throwsA(isA<RangeError>()),
                    reason: '$items / $query / $limit',
                  );
                }
              } finally {
                finder.dispose();
              }
            }
          }
        }
      },
    );

    test(
      'completed results survive finder replacement without sharing mutable lists',
      () async {
        final old = AsyncFzf(['café', 'cafe\u0301', '界same']);
        final complete = (await old.find('cafe'))!;
        old.dispose();
        final replacement = AsyncFzf(['same', 'new café']);
        addTearDown(replacement.dispose);
        final next = (await replacement.find('cafe'))!;
        expect(complete.map((r) => r.item), ['café', 'cafe\u0301']);
        expect(next.single.item, 'new café');
        expect(() => complete.removeLast(), throwsUnsupportedError);
        expect(() => complete.first.positions[0] = 99, throwsUnsupportedError);
        expect(await old.find(''), isNull);
      },
    );

    test(
      'candidate cache keeps all-field parity across option combinations',
      () async {
        final items = List.generate(
          300,
          (i) => [
            'café',
            'cafe\u0301',
            '界same',
            'Same',
            'src/same.dart',
            'é👩‍💻',
          ][i % 6],
        );
        final ties = <FzfTiebreaker<String>>[
          (a, b, _) => (b.index % 7).compareTo(a.index % 7),
          byLengthAsc,
        ];
        for (final casing in FzfCasing.values) {
          for (final normalize in [false, true]) {
            for (final limit in [0, 1, 17, 999]) {
              final sync = Fzf(
                items,
                casing: casing,
                normalize: normalize,
                limit: limit,
                tiebreakers: ties,
              );
              final async = AsyncFzf(
                items,
                casing: casing,
                normalize: normalize,
                limit: limit,
                tiebreakers: ties,
              );
              try {
                for (final query in ['', 'cafe', 'É', '界', 'same', 'missing']) {
                  expect(
                    (await async.find(query))!.map(_fields),
                    sync.find(query).map(_fields),
                    reason: '$casing / $normalize / $limit / $query',
                  );
                }
              } finally {
                async.dispose();
              }
            }
          }
        }
      },
    );

    test(
      'large empty publication yields repeatedly and loses old generation',
      () async {
        final finder = AsyncFzf(List.generate(4096, (i) => 'item$i'));
        addTearDown(finder.dispose);
        var ticks = 0;
        Future<List<FzfResult<String>>?>? current;
        final timer = Timer.periodic(Duration.zero, (_) {
          if (++ticks == 6) current = finder.find('item4095');
        });
        try {
          expect(await finder.find(''), isNull);
          expect(ticks, greaterThanOrEqualTo(6));
          expect((await current!)!.first.item, 'item4095');
        } finally {
          timer.cancel();
        }
      },
    );
  });
}
