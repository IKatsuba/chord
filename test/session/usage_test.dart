import 'package:chord/session/turn_costs.dart';
import 'package:chord/session/usage.dart';
import 'package:chord/ui/transcript/reports.dart' show sessionTokens;
import 'package:test/test.dart';

TurnCost _usd(num amount, {bool estimated = false}) =>
    TurnCost(cost: (amount: amount, currency: 'USD'), estimated: estimated);

void main() {
  group('tester: CTUI-29 sparse usage reports', () {
    test(
      'zero and fractional counts remain reported while foreign fields do not',
      () {
        expect(
          tokensOf({
            'inputTokens': 0,
            'outputTokens': 0.5,
            'cachedReadTokens': '3',
            'thoughtTokens': false,
            'totalTokens': null,
            'foreign': 7,
          }),
          {'inputTokens': 0, 'outputTokens': 0.5},
        );
        expect(
          grownBy(
            {'inputTokens': 100, 'outputTokens': 10},
            {'inputTokens': 0, 'thoughtTokens': 0.25},
          ),
          {'inputTokens': 0, 'thoughtTokens': 0.25},
        );
      },
    );

    test(
      'a zero running total replaces the previous one without retaining per-turn tokens',
      () {
        final first = addTurn(
          null,
          'one',
          {'inputTokens': 5},
          const SpentTurn(TurnCost(), 'first'),
          true,
        );
        final reset = addTurn(
          first,
          'two',
          {'inputTokens': 0},
          const SpentTurn(TurnCost(), 'second'),
          true,
        );
        expect(first.total, {'inputTokens': 5});
        expect(reset.total, {'inputTokens': 0});
        expect(reset.totalModel, 'second');
        expect(reset.turns, isEmpty);
      },
    );
  });
  test("a turn's tokens are ACP's without its nulls", () {
    expect(
      tokensOf({
        'inputTokens': 10,
        'outputTokens': 2,
        'totalTokens': 12,
        'thoughtTokens': null,
        '_meta': {'model': 'large'},
      }),
      {'inputTokens': 10, 'outputTokens': 2, 'totalTokens': 12},
    );
  });

  test('a running total grows by each field, never less than none', () {
    expect(
      grownBy(
        {'inputTokens': 10, 'outputTokens': 5},
        {'inputTokens': 25, 'outputTokens': 3, 'totalTokens': 9},
      ),
      {'inputTokens': 15, 'outputTokens': 0, 'totalTokens': 9},
    );
    expect(grownBy(null, {'inputTokens': 4}), {'inputTokens': 4});
  });

  test("a turn's own cost is kept by its turn, replaced when said again, and "
      "a turn with no tokens, an agent's own cycle, adds none", () {
    var spent = addTurn(null, 'a', {'inputTokens': 5}, SpentTurn(_usd(0.01)));
    spent = addTurn(
      spent,
      'cycle',
      {},
      SpentTurn(_usd(0.002, estimated: true)),
    );
    spent = addTurn(spent, 'b', {
      'inputTokens': 1,
    }, const SpentTurn(TurnCost(uncounted: true)));
    spent = addTurn(spent, 'a', {'inputTokens': 5}, SpentTurn(_usd(0.015)));
    expect(spent.turns, {
      'a': {'inputTokens': 5},
      'b': {'inputTokens': 1},
    });
    expect(
      {for (final e in spent.costs!.entries) e.key: e.value.cost},
      {
        'cycle': _usd(0.002, estimated: true),
        'b': const TurnCost(uncounted: true),
        'a': _usd(0.015),
      },
    );
    expect(addTurn(spent, 'a', {'inputTokens': 5}).costs!.keys, ['cycle', 'b']);
    final none = addTurn(null, 'a', {'inputTokens': 5});
    expect(none.costs, isNull);
    expect(none.turns, {
      'a': {'inputTokens': 5},
    });
  });

  test("a running total replaces the session's total and keeps no turn of "
      "its own; the turn's cost is kept as any is", () {
    var spent = addTurn(
      null,
      't1',
      {'inputTokens': 10},
      SpentTurn(_usd(1)),
      true,
    );
    spent = addTurn(spent, 't2', {'inputTokens': 25}, SpentTurn(_usd(2)), true);
    spent = addTurn(spent, 't3', {}, const SpentTurn(), true);
    expect(spent.total, {'inputTokens': 25});
    expect(spent.turns, isEmpty);
    expect(spent.costs!.keys, ['t1', 't2']);
  });

  // CTUI-172: the original's tests/session/usage_test.ts cases the port
  // lacked.
  test('a turn reported again reads as it last did', () {
    final once = addTurn(null, 'a', {'inputTokens': 5});
    final twice = addTurn(addTurn(once, 'b', {'inputTokens': 1}), 'a', {
      'inputTokens': 7,
      'outputTokens': 3,
    });
    expect(sessionTokens(twice), {'inputTokens': 8, 'outputTokens': 3});
  });

  test('zero is a reported total, omitted fields are not retained, and empty '
      'usage preserves the last report', () {
    final first = addTurn(
      null,
      'first',
      {
        'inputTokens': 100,
        'outputTokens': 20,
        'cachedReadTokens': 50,
        'cachedWriteTokens': 4,
        'thoughtTokens': 7,
        'totalTokens': 120,
      },
      const SpentTurn(),
      true,
    );
    final zero = addTurn(
      first,
      'second',
      {'inputTokens': 0, 'totalTokens': 0},
      const SpentTurn(),
      true,
    );
    expect(sessionTokens(zero), {'inputTokens': 0, 'totalTokens': 0});
    expect(sessionTokens(addTurn(zero, 'third', {}, const SpentTurn(), true)), {
      'inputTokens': 0,
      'totalTokens': 0,
    });
    expect(first.total!['outputTokens'], 20);
    expect(zero.turns, isEmpty);
  });

  test('a later lower total is used as sent; replacing one cost never '
      'deletes another turn cost', () {
    final first = addTurn(
      null,
      'a',
      {'totalTokens': 100},
      SpentTurn(_usd(1)),
      true,
    );
    final second = addTurn(
      first,
      'b',
      {'totalTokens': 200},
      SpentTurn(_usd(2)),
      true,
    );
    final corrected = addTurn(
      second,
      'a',
      {'totalTokens': 40},
      SpentTurn(_usd(0.5)),
      true,
    );
    expect(sessionTokens(corrected), {'totalTokens': 40});
    expect(
      {for (final e in corrected.costs!.entries) e.key: e.value.cost},
      {'a': _usd(0.5), 'b': _usd(2)},
    );
    expect(sessionTokens(second), {'totalTokens': 200});
  });

  test('two sessions have independent totals and ordinary agents still sum '
      'partial token fields', () {
    final a = addTurn(
      null,
      'shared-id',
      {'inputTokens': 50},
      const SpentTurn(),
      true,
    );
    final b = addTurn(
      null,
      'shared-id',
      {'outputTokens': 7},
      const SpentTurn(),
      true,
    );
    expect(sessionTokens(a), {'inputTokens': 50});
    expect(sessionTokens(b), {'outputTokens': 7});
    final own = addTurn(addTurn(null, 'a', {'inputTokens': 2}), 'b', {
      'outputTokens': 3,
    });
    expect(sessionTokens(own), {'inputTokens': 2, 'outputTokens': 3});
  });

  test('cost-only corrections cannot rename the last token total, but a new '
      'total can', () {
    final first = addTurn(
      null,
      'one',
      {'totalTokens': 100},
      const SpentTurn(TurnCost(), 'old'),
      true,
    );
    final correction = addTurn(
      first,
      'cycle',
      {},
      SpentTurn(_usd(0.1), 'next'),
      true,
    );
    expect(correction.totalModel, 'old');
    expect(sessionTokens(correction), {'totalTokens': 100});
    final next = addTurn(
      correction,
      'next',
      {'totalTokens': 110},
      const SpentTurn(TurnCost(), 'next'),
      true,
    );
    expect(next.totalModel, 'next');
    expect(sessionTokens(next), {'totalTokens': 110});
  });
}
