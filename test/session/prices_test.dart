import 'dart:convert';
import 'dart:io';

import 'package:chord/session/prices.dart';
import 'package:clock/clock.dart';
import 'package:test/test.dart';

/// What the original's src/session/prices.ts computed for the same models
/// and tokens, probed with bun in ../chord (genai-prices 0.2.3) on the date
/// it records; see the CTUI-29 prices entry in docs/decisions.md.
final _probe =
    jsonDecode(
          File('test/fixtures/prices/original_probe.json').readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  final at = DateTime.parse(_probe['date'] as String);
  final tokens = [
    for (final t in _probe['tokens'] as List) (t as Map).cast<String, num>(),
  ];

  group('tester: CTUI-29 independent pinned pricing boundaries', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/prices/tester_boundaries.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final cases = (fixture['cases'] as List).cast<Map<String, Object?>>();
    for (final label in [
      'start_date',
      'time_of_day',
      'model_id_only',
      'tier',
    ]) {
      test(
        '$label matches the original package on both sides of each edge',
        () {
          final reached = cases.where((entry) => entry['label'] == label);
          expect(reached, isNotEmpty);
          for (final entry in reached) {
            final model = entry['model'] as String;
            final at = DateTime.parse(entry['date'] as String);
            final usage = (entry['usage'] as Map).cast<String, num>();
            final expected = entry['expected'] as Map?;
            final result = calcPrice(usage, model, at: at);
            final reason = '$model at $at with $usage';
            if (expected == null) {
              expect(result, isNull, reason: reason);
            } else {
              expect(result, isNotNull, reason: reason);
              expect(result!.model['id'], expected['model'], reason: reason);
              expect(
                result.model['context_window'],
                expected['window'],
                reason: reason,
              );
              expect(
                result.total,
                closeTo(expected['total'] as num, 1e-12),
                reason: reason,
              );
            }
          }
        },
      );
    }

    test(
      'turn lookup strips router and effort adornments without accepting bad counts',
      () {
        withClock(Clock.fixed(DateTime.utc(2026, 11, 18)), () {
          const tokens = {'inputTokens': 1000, 'outputTokens': 200};
          final plain = turnCost('gpt-4o', tokens);
          expect(plain, isNotNull);
          expect(turnCost('azure/gpt-4o', tokens), plain);
          expect(turnCost('gpt-4o/high', tokens), plain);
          expect(contextWindow('gpt-4o[1m]'), contextWindow('gpt-4o'));
          expect(
            turnCost('gpt-4o', {
              'inputTokens': 1,
              'cachedReadTokens': 2,
              'totalTokens': 1,
            }),
            isNull,
          );
          expect(turnCost('gpt-4o', {'inputTokens': double.infinity}), isNull);
        });
      },
    );
  });
  test('each model costs what the original priced, on the same date', () {
    withClock(Clock.fixed(at), () {
      for (final entry in _probe['out'] as List) {
        final model = (entry as Map)['m'] as String;
        final costs = entry['costs'] as List;
        for (final (i, expected) in costs.indexed) {
          final cost = turnCost(model, tokens[i]);
          if (expected == null) {
            expect(cost, isNull, reason: '$model ${tokens[i]}');
          } else {
            expect(
              cost,
              closeTo(expected as num, 1e-15),
              reason: '$model ${tokens[i]}',
            );
          }
        }
        expect(contextWindow(model), entry['window'], reason: model);
      }
    });
  });

  test('the context after a turn is what went in and came out, as priced', () {
    expect([for (final t in tokens) contextFrom(t)], _probe['contexts']);
  });
}
