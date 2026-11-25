// The original's tests/session/turn_costs_test.ts.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/cost_counts.dart';
import 'package:chord/session/prices.dart';
import 'package:chord/session/turn_costs.dart';
import 'package:test/test.dart';

CostReading _usd(num amount, [bool estimated = false]) =>
    CostReading(amount, 'USD', estimated: estimated);

OpeningCosts _opening({
  CostCount? counts,
  bool resumed = false,
  CostReading? past,
  CostReading? seen,
}) => OpeningCosts(counts: counts, resumed: resumed, past: past, seen: seen);

const _tokens = {'inputTokens': 1000, 'outputTokens': 200};

acp.SessionUpdate _update([num? amount, bool estimate = false]) =>
    acp.SessionUpdate.fromJson({
      'sessionUpdate': 'usage_update',
      'used': 1,
      'size': 2,
      if (amount != null) 'cost': {'amount': amount, 'currency': 'USD'},
      if (estimate)
        '_meta': {
          'chord/filled': ['cost'],
        },
    });

Matcher _costOf(num amount, {bool estimated = false}) => isA<TurnCost>()
    .having((c) => c.cost?.amount, 'amount', closeTo(amount, 1e-9))
    .having((c) => c.cost?.currency, 'currency', 'USD')
    .having((c) => c.estimated, 'estimated', estimated)
    .having((c) => c.uncounted, 'uncounted', isFalse);

void main() {
  group('tester: CTUI-29 cost reading ownership', () {
    test(
      'independent openings cannot share baselines or late-turn corrections',
      () {
        final first = TurnCosts(CostCount.session, true, [_update(10)]);
        final second = TurnCosts(CostCount.opening, false, const []);
        first.began('same-id');
        second.began('same-id');
        first.heardLast(_update(11));
        second.heardLast(_update(3));
        expect(first.ended('same-id', _tokens, 'm')!.cost, _costOf(1));
        expect(second.ended('same-id', _tokens, 'm')!.cost, _costOf(3));
        expect(first.heardLast(_update(12))!.cost, _costOf(2));
        expect(second.heardLast(_update(3)), isNull);
      },
    );

    test(
      'an authoritative equal amount replaces an estimate once without duplicating it',
      () {
        final costs = TurnCosts(CostCount.opening, false, const []);
        costs.began('one');
        costs.heardLast(_update(0.5, true));
        expect(
          costs.ended('one', _tokens, 'm')!.cost,
          _costOf(0.5, estimated: true),
        );
        expect(costs.heardLast(_update(0.5))!.cost, _costOf(0.5));
        expect(costs.heardLast(_update(0.5)), isNull);
        costs.began('two');
        costs.heardLast(_update(0.4));
        expect(costs.ended('two', _tokens, 'm')!.cost, _costOf(0));
      },
    );
  });
  test("a usage_update's cost is read with whether chord filled it in, and "
      "a session's last such is its cost so far", () {
    final agent = _update(0.5);
    final chord = _update(0.25, true);
    final read = costReading(agent)!;
    expect((read.amount, read.currency, read.estimated), (0.5, 'USD', false));
    expect(costReading(chord)!.estimated, isTrue);
    expect(costReading(_update()), isNull);
    final last = lastReading([
      agent,
      _update(),
      acp.SessionUpdate.fromJson({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'x'},
      }),
    ]);
    expect(last!.amount, 0.5);
    expect(lastReading(const []), isNull);
  });

  test('a cost that does not read as one, as an agent or a record may bend '
      'it, is none', () {
    for (final cost in [
      {'amount': -1, 'currency': 'USD'},
      {'amount': double.nan, 'currency': 'USD'},
      {'amount': double.infinity, 'currency': 'USD'},
      {'amount': 1, 'currency': ''},
      {'amount': '1', 'currency': 'USD'},
      null,
    ]) {
      expect(
        costReading(
          acp.SessionUpdate.fromJson({
            'sessionUpdate': 'usage_update',
            'used': 1,
            'size': 2,
            'cost': cost,
          }),
        ),
        isNull,
      );
    }
  });

  test("within an opening a turn's cost is what the session's cost moved by "
      "in it, chord's estimate marked", () {
    expect(
      costOfTurn(_opening(seen: _usd(0.0375)), _usd(0.025), _tokens, 'm'),
      _costOf(0.0125),
    );
    expect(
      costOfTurn(
        _opening(seen: _usd(0.3, true)),
        _usd(0.1, true),
        _tokens,
        'm',
      ),
      _costOf(0.2, estimated: true),
    );
    expect(
      costOfTurn(
        _opening(seen: const CostReading(3, 'EUR')),
        _usd(1),
        _tokens,
        'm',
      ),
      const TurnCost(),
    );
  });

  test('a turn the cost did not move in has none', () {
    final seen = _usd(0.5);
    expect(
      costOfTurn(_opening(seen: seen), seen, _tokens, 'm'),
      const TurnCost(),
    );
    expect(costOfTurn(_opening(), null, _tokens, 'm'), const TurnCost());
    // One that came in the turn and did not move says the turn cost nothing.
    expect(
      costOfTurn(_opening(seen: _usd(0.5)), seen, _tokens, 'm'),
      _costOf(0),
    );
  });

  test("a cost sent as the session opened is the opening's start, not a "
      "turn's", () {
    expect(
      costOfTurn(
        _opening(resumed: true, seen: _usd(0.45)),
        _usd(0.4),
        _tokens,
        'm',
      ),
      _costOf(0.05),
    );
  });

  test("an opening's first cost is the turn's for a new session and for an "
      'agent that counts from each opening', () {
    final seen = _usd(0.0125);
    expect(
      costOfTurn(_opening(seen: seen), null, _tokens, 'm'),
      _costOf(0.0125),
    );
    expect(
      costOfTurn(
        _opening(
          counts: CostCount.opening,
          resumed: true,
          past: _usd(0.4),
          seen: seen,
        ),
        null,
        _tokens,
        'm',
      ),
      _costOf(0.0125),
    );
  });

  test("after a resume, an agent that counts from the session's start has "
      "its first cost less the record's", () {
    expect(
      costOfTurn(
        _opening(
          counts: CostCount.session,
          resumed: true,
          past: _usd(0.025),
          seen: _usd(0.0375),
        ),
        null,
        _tokens,
        'm',
      ),
      _costOf(0.0125),
    );
    expect(
      costOfTurn(
        _opening(counts: CostCount.session, resumed: true, seen: _usd(0.0375)),
        null,
        _tokens,
        'm',
      ),
      _costOf(0.0375),
    );
  });

  test("chord's estimate after a resume goes on from the record's", () {
    expect(
      costOfTurn(
        _opening(resumed: true, past: _usd(0.1, true), seen: _usd(0.13, true)),
        null,
        _tokens,
        'm',
      ),
      _costOf(0.03, estimated: true),
    );
  });

  test('after a resume, an agent whose counting is not known has its first '
      'turn priced from its tokens, and with none it is not counted', () {
    final unknown = _opening(resumed: true, past: _usd(0.2), seen: _usd(0.25));
    const model = 'gpt-5.3-codex';
    final priced = turnCost(model, _tokens);
    expect(priced, isNotNull);
    expect(
      costOfTurn(unknown, null, _tokens, model),
      _costOf(priced!, estimated: true),
    );
    expect(
      costOfTurn(unknown, null, null, model),
      const TurnCost(uncounted: true),
    );
    expect(
      costOfTurn(unknown, null, _tokens, 'fake-large'),
      const TurnCost(uncounted: true),
    );
    expect(costOfTurn(unknown, _usd(0.2), _tokens, model), _costOf(0.05));
  });

  test("a turn's figures as it ends: its tokens, its own cost and the model "
      'it ended on', () {
    final costs = TurnCosts(CostCount.opening, false, const []);
    costs.began('t1');
    expect(costs.heard('t1', _update(0.01)), isNull);
    final figures = costs.ended('t1', {'totalTokens': 5}, 'm')!;
    expect((figures.turnId, figures.model, figures.total), ('t1', 'm', false));
    expect(figures.usage, {'totalTokens': 5});
    expect(figures.cost, _costOf(0.01));
    final alone = costs.ended('t0', {'totalTokens': 1}, 'm')!;
    expect(
      (alone.turnId, alone.model, alone.cost),
      ('t0', null, const TurnCost()),
    );
  });

  test("an agent whose answers give the session's running total has each "
      "turn's figures marked so; another's are not", () {
    final totals = TurnCosts(
      CostCount.session,
      false,
      const [],
      UsageCount.session,
    );
    totals.began('t1');
    totals.heard('t1', _update(0.01));
    expect(totals.ended('t1', {'totalTokens': 5}, 'm')!.total, isTrue);
    expect(totals.ended('t0', {'totalTokens': 1}, 'm')!.total, isTrue);
    final own = TurnCosts(CostCount.session, false, const []);
    own.began('t1');
    expect(own.ended('t1', {'totalTokens': 5}, 'm')!.total, isFalse);
  });

  test("a cost that comes after its turn's end is still that turn's, said "
      "again; after the next began, the next's", () {
    final costs = TurnCosts(CostCount.opening, false, const []);
    costs.began('t1');
    expect(costs.ended('t1', {'totalTokens': 5}, 'm')!.cost, const TurnCost());
    expect(costs.heard('t1', _update(0.01))!.cost, _costOf(0.01));
    expect(costs.heard('t1', _update(0.01)), isNull);
    costs.began('t2');
    expect(costs.ended('t2', null, 'm'), isNull);
    costs.began('t3');
    expect(costs.heard('t3', _update(0.03)), isNull);
    final t3 = costs.ended('t3', {'totalTokens': 7}, 'm')!;
    expect(t3.turnId, 't3');
    expect(t3.cost, _costOf(0.02));
  });

  test("an agent's own cycle is a turn of its own, by what its usage moved "
      'the cost by; one whose usage says no cost has none', () {
    final costs = TurnCosts(CostCount.opening, false, const []);
    costs.began('t1');
    costs.heard('t1', _update(0.01));
    costs.ended('t1', {'totalTokens': 5}, 'm');
    costs.began('c1');
    costs.heard('c1', _update(0.015));
    final cycle = costs.ended('c1', null, 'm')!;
    expect((cycle.turnId, cycle.model), ('c1', 'm'));
    expect(cycle.usage, isEmpty);
    expect(cycle.cost, _costOf(0.005));
    costs.began('c2');
    costs.heard('c2', _update());
    expect(costs.ended('c2', null, 'm'), isNull);
  });

  test("an opening resumed from a record counts from the record's last cost, "
      'as its agent counts', () {
    final past = [_update(0.025)];
    TurnCost first(TurnCosts costs) {
      costs.began('t');
      costs.heard('t', _update(0.0375));
      return costs.ended('t', {'totalTokens': 5}, 'fake-large')!.cost;
    }

    expect(first(TurnCosts(CostCount.session, true, past)), _costOf(0.0125));
    expect(first(TurnCosts(CostCount.opening, true, past)), _costOf(0.0375));
    expect(first(TurnCosts(null, true, past)), const TurnCost(uncounted: true));
  });

  test('a cost arriving after the answer adds its delta without turning '
      'total tokens into another turn', () {
    final costs = TurnCosts(
      CostCount.session,
      false,
      const [],
      UsageCount.session,
    );
    costs.began('a');
    final a = costs.ended('a', {'totalTokens': 100}, 'model')!;
    expect(a.total, isTrue);
    expect(a.usage, {'totalTokens': 100});
    final late = costs.heard('a', _update(0.02))!;
    expect(late.total, isTrue);
    expect(late.usage, {'totalTokens': 100});
    expect(late.cost, _costOf(0.02));
    expect(costs.heard('a', _update(0.02)), isNull);
    costs.began('b');
    costs.heard('b', _update(0.05));
    expect(
      costs.ended('b', {'totalTokens': 250}, 'model')!.cost,
      _costOf(0.03),
    );
  });

  test('a resumed total has only the cost added since the record; a fresh '
      'session has no earlier baseline', () {
    final resumed = TurnCosts(CostCount.session, true, [
      _update(0.5),
    ], UsageCount.session);
    resumed.began('a');
    resumed.heard('a', _update(0.5));
    expect(resumed.ended('a', {'totalTokens': 0}, 'model')!.cost, _costOf(0));
    final fresh = TurnCosts(
      CostCount.session,
      false,
      const [],
      UsageCount.session,
    );
    fresh.began('a');
    fresh.heard('a', _update(0.1));
    expect(fresh.ended('a', {'totalTokens': 50}, 'model')!.cost, _costOf(0.1));
  });

  test('on an agent that gives running totals and no cost, a turn on a model '
      "chord has no price for is not counted; another agent's is a turn of "
      'nothing', () {
    const tokens = {
      'inputTokens': 1000,
      'outputTokens': 200,
      'totalTokens': 1200,
    };
    final totals = TurnCosts(
      CostCount.session,
      false,
      const [],
      UsageCount.session,
    );
    totals.began('t1');
    totals.heard('t1', _update(0.004, true));
    expect(
      totals.ended('t1', tokens, 'gpt-5.3-codex')!.cost,
      _costOf(0.004, estimated: true),
    );
    totals.began('t2');
    final t2 = totals.ended('t2', tokens, 'fake-unpriced')!;
    expect(
      (t2.model, t2.total, t2.cost),
      ('fake-unpriced', true, const TurnCost(uncounted: true)),
    );
    final own = TurnCosts(CostCount.session, false, const []);
    own.began('t1');
    expect(own.ended('t1', tokens, 'fake-unpriced')!.cost, const TurnCost());
  });

  test('a costless update given the estimate so far again moves no cost, so '
      'a later turn on a model with no price is still not counted', () {
    const tokens = {'inputTokens': 1000, 'totalTokens': 1000};
    final totals = TurnCosts(
      CostCount.session,
      false,
      const [],
      UsageCount.session,
    );
    totals.began('t1');
    totals.heard('t1', _update(0.004, true));
    totals.ended('t1', tokens, 'gpt-5.3-codex');
    totals.began('t2');
    totals.heard('t2', _update(0.004, true));
    expect(
      totals.ended('t2', tokens, 'fake-unpriced')!.cost,
      const TurnCost(uncounted: true),
    );
  });
}
