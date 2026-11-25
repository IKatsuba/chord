/// What a session has spent: each turn's tokens, as the agent's answer to
/// its prompt gives them, and its own cost, as chord found it.
library;

import 'turn_costs.dart';

/// A turn's tokens. A field the agent did not report is absent, never zero,
/// so a report can say what it was not told: a map from [tokenFields] to
/// counts.
typedef TokenUsage = Map<String, num>;

/// ACP's `Usage` fields, in order.
const tokenFields = [
  'inputTokens',
  'outputTokens',
  'cachedReadTokens',
  'cachedWriteTokens',
  'thoughtTokens',
  'totalTokens',
];

/// ACP's `Usage` without its nulls and `_meta`.
TokenUsage tokensOf(Map<String, Object?> usage) => {
  for (final field in tokenFields)
    if (usage[field] case final num count) field: count,
};

/// What a running total grew by since [last]: each field's increase, never
/// less than none, as a total that fell, as after a reset, adds nothing.
TokenUsage grownBy(TokenUsage? last, TokenUsage now) => {
  for (final field in tokenFields)
    if (now[field] case final count?)
      field: count - (last?[field] ?? 0) < 0 ? 0 : count - (last?[field] ?? 0),
};

/// A turn's own cost as a session keeps it, with the model it ended on.
class SpentTurn {
  const SpentTurn([this.cost = const TurnCost(), this.model]);

  final TurnCost cost;
  final String? model;
}

/// What a session has spent.
class Spent {
  const Spent({this.turns = const {}, this.total, this.totalModel, this.costs});

  /// Each turn's tokens by the turn's id, every one the agent reported.
  final Map<String, TokenUsage> turns;

  /// The session's tokens as an agent whose answers give its running total
  /// last gave them, in place of each turn's.
  final TokenUsage? total;

  /// The model the session's last running total came on.
  final String? totalModel;

  /// Each turn's own cost by the turn's id, where it had one or was left
  /// uncounted.
  final Map<String, SpentTurn>? costs;
}

/// [spent] with a turn's tokens, where it has any, and its cost; a turn
/// reported again replaces its own. Tokens that are the session's running
/// [total] replace the total it had, and no turn keeps them.
Spent addTurn(
  Spent? spent,
  String turnId,
  TokenUsage tokens, [
  SpentTurn cost = const SpentTurn(),
  bool total = false,
]) {
  final costs = {...?spent?.costs}..remove(turnId);
  final counted = cost.cost.cost != null || cost.cost.uncounted;
  final some = tokens.isNotEmpty;
  return Spent(
    total: total && some ? tokens : spent?.total,
    totalModel: total && some && cost.model != null
        ? cost.model
        : spent?.totalModel,
    turns: !some || total
        ? spent?.turns ?? const {}
        : {...?spent?.turns, turnId: tokens},
    costs: counted || spent?.costs != null
        ? (counted ? {...costs, turnId: cost} : costs)
        : null,
  );
}
