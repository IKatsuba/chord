import 'package:chord_tui/chord_tui.dart' show stripAnsi;
import 'package:intl/intl.dart';

import '../../js_trim.dart';

import '../../session/agent_state.dart';
import '../../session/auth_status.dart';
import '../../session/elapsed.dart';
import '../../session/turn_costs.dart' show Cost;
import '../../session/usage.dart';
import '../status/status.dart' show contextEstimated, contextUsed;
import 'currency_symbols.dart';
import 'spend.dart';
import 'spend_table.dart';
import '../../session/models.dart';
import '../../session/modes.dart';

import '../../session/transcript/types.dart'
    show
        AwaitingPermission,
        Cancelling,
        Idle,
        ReportRow,
        TurnState,
        Usage,
        Working;

/// `/status`: who and where the session is, its [title] the agent's or a
/// rename's, and its [account] as the agent says it.
List<ReportRow> statusReport(
  AgentState state, {
  required String agent,
  required String cwd,
  String? sessionId,
  String? fallbackMode,
  String? title,
  AccountState account = noAccount,
}) {
  final modes = modesFrom(state.configOptions, state.modes);
  final current = modes?.current ?? fallbackMode;
  final mode =
      modes?.available.where((m) => m.id == current).firstOrNull?.name ??
      current;
  final accounts = accountRows(account, agent);
  return [
    (label: 'Agent:', text: agent),
    if (accounts.isNotEmpty) (label: 'Account:', text: accounts.first),
    // Later accounts go under the first, their label left blank, each after
    // an empty line so a wrapped one reads apart from the next.
    for (final text in accounts.skip(1)) ...[
      (label: '', text: ''),
      (label: ' ', text: text),
    ],
    (label: 'Title:', text: title == null ? 'not given' : _clean(title)),
    (
      label: 'Model:',
      text:
          modelName(modelsFrom(state.configOptions, state.models)) ??
          'not reported by $agent',
    ),
    (label: 'Mode:', text: mode ?? 'not reported by $agent'),
    (label: 'Session:', text: sessionId ?? 'starting…'),
    (label: 'Directory:', text: cwd),
  ];
}

/// The `Account` row's values, one per row: none where the agent does not
/// advertise `auth.status`, the active accounts, or all of them when none
/// is marked, and otherwise the state in words.
List<String> accountRows(AccountState account, String agent) {
  switch (account) {
    case AccountNone():
      return const [];
    case AccountPending():
      return const ['checking…'];
    case AccountFailed():
      return ['not reported by $agent'];
    case AccountHeard(:final status):
      switch (status['state']) {
        case 'authenticated':
          final shown = shownAccounts(status['accounts']);
          return shown.isEmpty
              ? const ['signed in']
              : [for (final each in shown) accountLine(each)];
        case 'unauthenticated':
          return const ['not signed in'];
        case 'not_required':
          return const ['none needed'];
        default:
          return ['not reported by $agent'];
      }
  }
}

/// An agent's string as a row draws it: its escapes gone, on one line.
String _clean(String text) =>
    jsTrim(stripAnsi(text).replaceAll(RegExp(r'\s+'), ' '));

/// Said after a figure chord worked out itself, never the agent's.
const estimateNote = "(chord's estimate)";

/// Said after a cost chord worked out only some of.
const partEstimateNote = "(part chord's estimate)";

/// What `/cost` says of the turn running, none of whose spend has come yet:
/// an agent reports a turn's spend when it ends, and chord guesses nothing.
const ReportRow _runningTurn = (
  label: 'This turn:',
  text: 'counted when it ends',
);

// As Intl.NumberFormat('en-US') writes a count: grouped, up to three
// fraction digits.
final _tokens = NumberFormat('#,##0.###', 'en_US');
final _day = DateFormat('MMM d', 'en_US');

/// The session's tokens, each turn's added up, or the running total its
/// agent last gave. A field no turn reported stays out rather than reading
/// as zero.
TokenUsage? sessionTokens(Spent? spent) {
  final each = spent?.total == null
      ? [...?spent?.turns.values]
      : [spent!.total!];
  final sum = <String, num>{
    for (final field in tokenFields)
      if (each.any((turn) => turn[field] != null))
        field: each.fold<num>(0, (sum, turn) => sum + (turn[field] ?? 0)),
  };
  return sum.isEmpty ? null : sum;
}

/// A cost as Claude Code writes one: dollars to the cent above half a
/// dollar, to a hundredth of a cent below; another currency by its own
/// sign, as JS Intl writes it in en-US (currency_symbols.dart), grouped in
/// thousands; a code CLDR does not know by its code and a no-break space; a
/// currency that is not a code by the agent's own word after the amount.
String formatCost(Cost cost) {
  final (:amount, :currency) = cost;
  final digits = amount > 0.5 ? 2 : 4;
  if (currency == 'USD') return '\$${amount.toStringAsFixed(digits)}';
  if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(currency)) {
    return '${amount.toStringAsFixed(digits)} $currency';
  }
  final code = currency.toUpperCase();
  final number = NumberFormat.decimalPatternDigits(
    locale: 'en_US',
    decimalDigits: digits,
  ).format(amount);
  return '${currencySigns[code] ?? '$code\u00a0'}$number';
}

/// What `/cost` is made from.
class CostFacts {
  const CostFacts({
    required this.agent,
    this.spent,
    this.running,
    this.since,
    required this.now,
    this.models,
    this.window,
  });

  final String agent;

  /// Each turn's tokens and own cost.
  final Spent? spent;

  /// The turn running now, by its id; none between turns.
  final String? running;

  /// When the session came up, and now, epoch milliseconds.
  final num? since;
  final num now;
  final AgentModels? models;

  /// What the whole window has spent, its closed agents and sessions too,
  /// and the columns its table is laid out in.
  final ({List<SpendPart> spend, int width})? window;
}

/// A model by the name its agent gives it, else by its id.
String _modelNamed(CostFacts facts, String? id) => id == null
    ? 'its model'
    : facts.models?.available.where((m) => m.id == id).firstOrNull?.name ?? id;

/// A count as `Intl.NumberFormat('en-US')` writes it, as the window's spend
/// table does too.
String formatTokens(num count) => _tokens.format(count);

/// A day as `Oct 12`, in local time, as the original's Intl writes one.
String formatDay(num until) =>
    _day.format(DateTime.fromMillisecondsSinceEpoch(until.toInt()));

/// `/cost`: the session's whole cost, each of its turns' added up, from
/// before a resume too, and its marks, its tokens in and out, and how long
/// it ran; then, once the window holds more than one session, what the
/// whole window has spent.
List<ReportRow> costReport(CostFacts facts) {
  final own = _sessionReport(facts);
  final window = facts.window;
  return window == null || !manySessions(window.spend)
      ? own
      : [
          ...own,
          (label: '', text: ''),
          ...spendTable(window.spend, window.width),
        ];
}

/// The session's own rows of `/cost`.
List<ReportRow> _sessionReport(CostFacts facts) {
  final agent = facts.agent;
  final spent = sessionTokens(facts.spent);
  final figure = sessionFigure(facts.spent);
  final totals = figure?.totals;
  // An agent that gives running totals and no cost, whose model chord has
  // no price for: both reasons, in the cost's cell.
  final unpricedModels = totals == null
      ? const <String?>[]
      : totals.unpriced.isEmpty
      ? [totals.model ?? facts.models?.current]
      : totals.unpriced;
  final unpriced = totals != null && figure!.cost == null
      ? "not reported: $agent's provider reports none, and chord has no "
            'price for '
            '${unpricedModels.map((each) => _modelNamed(facts, each)).join(' and ')}'
      : null;
  final cost = figure?.cost == null
      ? null
      : switch (figure!.estimated) {
          Estimated.all => '${formatCost(figure.cost!)} $estimateNote',
          Estimated.part => '${formatCost(figure.cost!)} $partEstimateNote',
          Estimated.none => formatCost(figure.cost!),
        };
  final marks = <ReportRow>[
    if (figure?.before case final before?)
      (
        label: before.until == null
            ? 'Before:'
            : 'Before ${formatDay(before.until!)}:',
        text: '${formatCost(before.cost)} as last reported',
      ),
    if (figure != null && figure.uncounted > 0 && unpriced == null)
      (
        label: 'Not counted:',
        text: '${figure.uncounted} ${figure.uncounted == 1 ? 'turn' : 'turns'}',
      ),
  ];
  final time = <ReportRow>[
    if (facts.since case final since?)
      (label: 'Session time:', text: formatElapsed(facts.now - since)),
  ];
  final running = <ReportRow>[
    if (facts.running case final turn? when facts.spent?.turns[turn] == null)
      _runningTurn,
  ];

  if (spent == null && cost == null && marks.isEmpty) {
    return [
      (label: '', text: '$agent has not reported what this session has used.'),
      ...running,
      ...time,
    ];
  }

  final counts = <ReportRow>[
    for (final (label, field) in [
      ('Tokens in:', 'inputTokens'),
      ('Tokens out:', 'outputTokens'),
      ('Cache read:', 'cachedReadTokens'),
      ('Cache written:', 'cachedWriteTokens'),
      ('Thinking:', 'thoughtTokens'),
    ])
      if (spent?[field] case final count?)
        (label: label, text: _tokens.format(count)),
  ];
  // An agent that gives only a total still said how many.
  if (counts.isEmpty) {
    if (spent?['totalTokens'] case final total?) {
      counts.add((label: 'Tokens:', text: _tokens.format(total)));
    }
  }

  return [
    (label: 'Total cost:', text: unpriced ?? cost ?? 'not reported by $agent'),
    ...marks,
    ...running,
    if (spent == null)
      (label: 'Tokens:', text: 'not reported by $agent')
    else
      ...counts,
    ...time,
    ..._totalsLines(facts, figure),
  ];
}

/// What `/cost` says after the rows of an agent that gives running totals:
/// how its figures were read, and, where it gave no cost and chord priced
/// its tokens, why.
List<ReportRow> _totalsLines(CostFacts facts, Figure? figure) {
  final totals = figure?.totals;
  if (totals == null) return const [];
  final agent = facts.agent;
  final model = figure!.models.firstOrNull;
  final one =
      model != null && figure.models.length == 1 && totals.unpriced.isEmpty;
  final unpriced = totals.unpriced
      .map((each) => _modelNamed(facts, each))
      .join(' and ');
  final price = one
      ? "these tokens at ${_modelNamed(facts, model)}'s price"
      : "each answer's tokens at the price of the model that gave it"
            '${totals.unpriced.isEmpty ? '' : '; it has no price for $unpriced'}';
  return [
    (
      label: '',
      text:
          "$agent reports these as the session's running total; chord shows "
          'the last it sent.',
    ),
    if (figure.estimated == Estimated.all)
      (
        label: '',
        text: "$agent's provider reports no cost, so chord priced $price.",
      ),
  ];
}

/// `/context`: how much of the window is used and how much is free, the
/// used share as the status line draws it, so the two never disagree.
List<ReportRow> contextReport(String agent, Usage? context) {
  if (context == null || context.size <= 0) {
    return [
      (
        label: '',
        text: '$agent has not reported how full its context window is.',
      ),
    ];
  }
  final used = contextUsed(context);
  final left = context.size - context.used;
  final free = left < 0 ? 0 : left;
  final note = contextEstimated(context) ? ' $estimateNote' : '';
  return [
    (
      label: 'Used:',
      text:
          '${_tokens.format(context.used)} of ${_tokens.format(context.size)} '
          'tokens ($used%)$note',
    ),
    (
      label: 'Free:',
      text: '${_tokens.format(free)} tokens (${100 - used}%)$note',
    ),
  ];
}

/// The turn of the session running now: one the person or the agent
/// started, not a request held between turns with none running. A request
/// held inside an agent's own cycle leaves the cycle running: its spend,
/// too, comes when it ends.
String? runningTurn(TurnState turn) => switch (turn) {
  Idle() => null,
  AwaitingPermission(between: true, cycle: false) => null,
  Working(:final turnId) ||
  AwaitingPermission(:final turnId) ||
  Cancelling(:final turnId) => turnId,
};
