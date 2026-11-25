/// Each turn's own cost, found from the session's cost so far as it moves,
/// for the record to keep beside the turn's tokens. An agent's cost is a sum
/// so far, counted from the opening or from the session's start
/// (cost_counts.dart), so a turn's is what the sum moved by in it, within
/// one opening of the session; only the first figure of an opening needs to
/// know which.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../acp/schema.dart' as acp;
import '../cost_counts.dart';
import 'enrich.dart' show filledIn;
import 'transcript/types.dart' show TranscriptAction, UsageAction;
import 'prices.dart';
import 'usage.dart';

/// A cost: an amount in a currency.
typedef Cost = ({num amount, String currency});

/// A session's cost so far, as one `usage_update` gave it.
class CostReading {
  const CostReading(this.amount, this.currency, {this.estimated = false});

  final num amount;
  final String currency;

  /// chord's estimate, from the turns' tokens, not the agent's figure.
  final bool estimated;
}

/// What a turn's record line carries of its cost.
class TurnCost {
  const TurnCost({
    this.cost,
    this.estimated = false,
    this.uncounted = false,
    this.before,
  });

  final Cost? cost;
  final bool estimated;

  /// The agent gave a cost in the turn that cannot be told apart from what
  /// came before it, and chord had no tokens to price it by: the turn is
  /// left out of the session's sum, and said to be.
  final bool uncounted;

  /// Not a turn's: what an older record spent before it kept each turn's
  /// cost, its last cost then, up to when it began to, where it says.
  final ({num? until})? before;

  /// As the record writes it.
  Map<String, Object?> toJson() => {
    if (cost case final cost?)
      'cost': {'amount': cost.amount, 'currency': cost.currency},
    if (estimated) 'estimated': true,
    if (uncounted) 'uncounted': true,
    if (before case final before?) 'before': {'until': ?before.until},
  };

  @override
  bool operator ==(Object other) =>
      other is TurnCost && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'TurnCost(${jsonEncode(toJson())})';
}

/// What one opening of a session knows of its cost.
class OpeningCosts {
  const OpeningCosts({
    required this.counts,
    required this.resumed,
    this.past,
    this.seen,
  });

  /// What the agent's cost counts from; none where it is not known.
  final CostCount? counts;

  /// The opening goes on in a record chord kept, from where [past] left it.
  final bool resumed;

  /// The last cost the record kept from before this opening.
  final CostReading? past;

  /// The last cost heard in this opening.
  final CostReading? seen;

  OpeningCosts _seeing(CostReading reading) =>
      OpeningCosts(counts: counts, resumed: resumed, past: past, seen: reading);
}

/// The cost a `usage_update` says the session has come to, if it says one.
CostReading? costReading(acp.SessionUpdate update) {
  if (update.kind != 'usage_update') return null;
  final json = update.toJson();
  // An agent or a record may have bent it: one that does not read as a cost
  // is none.
  if (json['cost'] case {
    'amount': final num amount,
    'currency': final String currency,
  } when amount >= 0 && amount.isFinite && currency.isNotEmpty) {
    return CostReading(
      amount,
      currency,
      estimated: filledIn(json).contains('cost'),
    );
  }
  return null;
}

bool _sameReading(CostReading? one, CostReading? other) =>
    one?.amount == other?.amount &&
    one?.currency == other?.currency &&
    one?.estimated == other?.estimated;

/// The last cost among a session's own updates, as its record replays them.
CostReading? lastReading(Iterable<acp.SessionUpdate> updates) {
  CostReading? last;
  for (final update in updates) {
    last = costReading(update) ?? last;
  }
  return last;
}

/// The cost of the turn that began when the opening's last cost was
/// [before] and has it at `opening.seen` now, the turn's [tokens] and
/// [model] to price it by where nothing else tells it.
TurnCost costOfTurn(
  OpeningCosts opening,
  CostReading? before,
  TokenUsage? tokens,
  String? model,
) {
  final after = opening.seen;

  // No cost came in the turn: it cost nothing anyone reported.
  if (after == null || identical(after, before)) return const TurnCost();

  TurnCost less(num amount) => TurnCost(
    cost: (
      amount: math.max(0, after.amount - amount),
      currency: after.currency,
    ),
    estimated: after.estimated,
  );

  if (before != null) {
    return before.currency == after.currency
        ? less(before.amount)
        : const TurnCost();
  }

  final past = opening.past;

  // chord's estimate goes on from the record's, which it was given back.
  if (after.estimated) {
    return less(
      past != null && past.estimated && past.currency == after.currency
          ? past.amount
          : 0,
    );
  }

  if (!opening.resumed || opening.counts == CostCount.opening) return less(0);

  if (opening.counts == CostCount.session) {
    return past == null || past.estimated
        ? less(0)
        : past.currency == after.currency
        ? less(past.amount)
        : const TurnCost();
  }

  // Whether this is the turn's or the session's is not known: the turn's
  // tokens priced, as for an agent that gives no cost.
  final priced = tokens == null || model == null
      ? null
      : turnCost(model, tokens);
  return priced == null
      ? const TurnCost(uncounted: true)
      : TurnCost(
          cost: (amount: priced, currency: priceCurrency),
          estimated: true,
        );
}

/// A turn's figures as the conversation reports them: its tokens and cost.
class TurnFigures {
  const TurnFigures({
    required this.turnId,
    required this.usage,
    this.total = false,
    this.model,
    this.cost = const TurnCost(),
  });

  final String turnId;
  final TokenUsage usage;

  /// [usage] is the session's running total, as its agent's answers give
  /// it, not the turn's own.
  final bool total;

  /// The model the turn ended on.
  final String? model;
  final TurnCost cost;

  /// As the record writes it, after its `type`.
  Map<String, Object?> toJson() => {
    'turnId': turnId,
    'usage': usage,
    if (total) 'total': true,
    'model': ?model,
    ...cost.toJson(),
  };

  /// A record line's figures, or null for one that does not read as any.
  static TurnFigures? fromJson(Map<String, Object?> json, String turnId) {
    final usage = json['usage'];
    if (usage is! Map<String, Object?>) return null;
    final cost = json['cost'];
    final before = json['before'];
    return TurnFigures(
      turnId: turnId,
      usage: tokensOf(usage),
      total: json['total'] == true,
      model: json['model'] is String ? json['model'] as String : null,
      cost: TurnCost(
        cost: switch (cost) {
          {'amount': final num amount, 'currency': final String currency}
              when amount >= 0 && amount.isFinite && currency.isNotEmpty =>
            (amount: amount, currency: currency),
          _ => null,
        },
        estimated: json['estimated'] == true,
        uncounted: json['uncounted'] == true,
        before: before is Map
            ? (until: before['until'] is num ? before['until'] as num : null)
            : null,
      ),
    );
  }
}

/// A turn or cycle as its cost is found, from its beginning to the next's.
class _CostTurn {
  _CostTurn(this.id, this.before);

  final String id;

  /// The opening's cost when it began.
  final CostReading? before;

  /// It has ended; what comes under it now is its tail.
  var over = false;
  TokenUsage? tokens;
  String? model;

  /// Its cost as it was last reported.
  String? reported;
}

/// A turn's figures as the session's running total.
TurnFigures _asTotal(TurnFigures f) => TurnFigures(
  turnId: f.turnId,
  usage: f.usage,
  total: true,
  model: f.model,
  cost: f.cost,
);

/// [past] as [agent]'s session shows it: a turn's tokens a record kept of an
/// agent whose answers give the session's running total are that total, a
/// record from before chord knew it too.
List<TranscriptAction> pastTotals(List<TranscriptAction> past, String agent) =>
    usageCountOf(agent) != UsageCount.session
    ? past
    : [
        for (final action in past)
          if (action case UsageAction(:final turnId, :final figures))
            UsageAction(turnId, _asTotal(figures))
          else
            action,
      ];

/// One opening of a session's turns and their costs: each turn's figures
/// as it ends, and again when its cost comes after its end, as Claude's can.
class TurnCosts {
  /// An opening of a session on an agent whose cost counts as [counts]
  /// says, going on in a record chord kept when [resumed], whose own
  /// updates are [past]; its answers' usage counts as [usage] says.
  TurnCosts(
    CostCount? counts,
    bool resumed,
    Iterable<acp.SessionUpdate> past, [
    UsageCount? usage,
  ]) : _opening = OpeningCosts(
         counts: counts,
         resumed: resumed,
         past: lastReading(past),
       ),
       _total = usage == UsageCount.session;

  OpeningCosts _opening;
  final bool _total;
  _CostTurn? _turn;

  /// A turn or the agent's own cycle began, from the cost there is now.
  void began(String turnId) => _turn = _CostTurn(turnId, _opening.seen);

  /// The turn or cycle that began last, by its id.
  String? get lastTurn => _turn?.id;

  /// One of the session's own updates, under [turnId]: the figures of the
  /// turn it came after the end of, when it moved that turn's cost.
  TurnFigures? heard(String turnId, acp.SessionUpdate update) {
    final reading = costReading(update);
    if (reading == null) return null;
    _opening = _opening._seeing(reading);
    final turn = _turn;
    return turn != null && turn.over && turn.id == turnId
        ? _figures(turn, false)
        : null;
  }

  /// As [heard], under the turn or cycle that began last.
  TurnFigures? heardLast(acp.SessionUpdate update) =>
      heard(_turn?.id ?? '', update);

  /// A turn or cycle ended, with the tokens its answer gave and the model it
  /// was on: its figures, always for one with tokens, else only when it has
  /// a cost to say.
  TurnFigures? ended(String turnId, TokenUsage? tokens, String? model) {
    final turn = _turn;
    if (turn?.id != turnId) {
      return tokens == null
          ? null
          : TurnFigures(turnId: turnId, usage: tokens, total: _total);
    }
    turn!
      ..over = true
      ..tokens = tokens
      ..model = model;
    return _figures(turn, tokens != null);
  }

  TurnFigures? _figures(_CostTurn turn, bool always) {
    final cost = _unpriced(turn)
        ? const TurnCost(uncounted: true)
        : costOfTurn(_opening, turn.before, turn.tokens, turn.model);
    final said = jsonEncode(cost.toJson());
    if (!always && said == (turn.reported ?? '{}')) return null;
    turn.reported = said;
    return TurnFigures(
      turnId: turn.id,
      usage: turn.tokens ?? const {},
      total: _total,
      model: turn.model,
      cost: cost,
    );
  }

  /// A turn of an agent that gives running totals and no cost of its own,
  /// on a model chord has no price for: chord's estimate leaves it out, so
  /// it is a turn not counted.
  bool _unpriced(_CostTurn turn) {
    final seen = _opening.seen;
    return _total &&
        turn.tokens != null &&
        turn.model != null &&
        (seen == null || seen.estimated) &&
        _sameReading(seen, turn.before) &&
        turnCost(turn.model!, turn.tokens!) == null;
  }
}
