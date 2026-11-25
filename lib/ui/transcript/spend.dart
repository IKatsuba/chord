/// What the window's sessions have spent, kept out of `/cost`'s drawing: a
/// figure for each session, its whole life as its record and this window
/// found it turn by turn, and for each task agent, and the sums of them,
/// with what was chord's estimate and what was never reported said rather
/// than guessed. Team runs' parts are not here yet.
library;

import '../../session/transcript/types.dart'
    show Subagent, SubagentEntry, SubagentState, TaskSpent, Transcript;
import '../../session/turn_costs.dart' show Cost;
import '../../session/usage.dart';
import '../../session/window_agents.dart';

/// The one currency costs are added up in; any other is not counted.
const _summed = 'USD';

/// How much of a cost is chord's estimate rather than the agent's figure.
enum Estimated { none, part, all }

/// One session's spend: its cost, and its tokens in all.
class Figure {
  const Figure({
    this.cost,
    this.estimated = Estimated.none,
    this.tokens,
    this.uncounted = 0,
    this.before,
    this.models = const [],
    this.totals,
  });

  final Cost? cost;

  /// None, part or all of the cost is chord's estimate.
  final Estimated estimated;
  final num? tokens;

  /// Turns whose cost could not be told, or came in another currency: left
  /// out of the cost, and said to be.
  final int uncounted;

  /// Of the cost, what an older record spent before it kept each turn's, as
  /// last reported, and up to when.
  final ({Cost cost, num? until})? before;

  /// The models whose prices chord's estimate came from, where it says.
  final List<String> models;

  /// Its figures are the running totals its agent last gave, not turns
  /// added up: the model the last came on, and the models chord had no
  /// price for, in the order they first answered.
  final ({String? model, List<String> unpriced})? totals;
}

/// A turn's tokens, or a session's, in all: the total, else each kind.
num? tokensIn(TokenUsage? tokens) {
  if (tokens == null) return null;
  final total = tokens['totalTokens'];
  if (total != null) return total;
  final each = [
    for (final field in tokenFields)
      if (field != 'totalTokens') ?tokens[field],
  ];
  return each.isEmpty ? null : each.reduce((a, b) => a + b);
}

Estimated _share(int some, int of) => some == 0
    ? Estimated.none
    : some == of
    ? Estimated.all
    : Estimated.part;

/// A session's figure, its whole life: its turns' own costs added up, each
/// once by its turn, the record's before it kept them among them, and its
/// turns' tokens; null when it reported neither.
Figure? sessionFigure(Spent? spent) {
  final costs = [...?spent?.costs?.values];
  final added = [
    for (final each in costs)
      if (each.cost.cost?.currency == _summed) each,
  ];
  final estimated = _share(
    added.where((each) => each.cost.estimated).length,
    added.length,
  );
  final uncounted = costs.length - added.length;
  final before = costs.where((each) => each.cost.before != null).firstOrNull;
  final models = {
    for (final each in added)
      if (each.cost.estimated && each.model != null) each.model!,
  }.toList();
  final each = [
    for (final turn
        in spent?.total == null ? [...?spent?.turns.values] : [spent!.total!])
      ?tokensIn(turn),
  ];
  final tokens = each.isEmpty ? null : each.reduce((a, b) => a + b);
  final cost = added.isEmpty
      ? null
      : (
          amount: added.fold<num>(
            0,
            (sum, each) => sum + each.cost.cost!.amount,
          ),
          currency: _summed,
        );
  final totals = spent?.total == null
      ? null
      : (
          model: spent!.totalModel,
          unpriced: {
            for (final each in costs)
              if (each.cost.uncounted && each.model != null) each.model!,
          }.toList(),
        );
  final beforeCost = before?.cost.cost;
  if (cost == null &&
      estimated == Estimated.none &&
      tokens == null &&
      uncounted == 0 &&
      models.isEmpty &&
      totals == null &&
      beforeCost == null) {
    return null;
  }
  return Figure(
    cost: cost,
    estimated: estimated,
    tokens: tokens,
    uncounted: uncounted,
    models: models,
    totals: totals,
    before: beforeCost == null
        ? null
        : (cost: beforeCost, until: before!.cost.before?.until),
  );
}

/// A task agent's figure, from what its block keeps; null when its agent
/// reported nothing.
Figure? taskFigure(TaskSpent? spent) {
  if (spent == null) return null;
  final tokens = tokensIn(spent.tokens);
  if (spent.cost == null && !spent.estimated && tokens == null) return null;
  return Figure(
    cost: spent.cost,
    estimated: spent.estimated ? Estimated.all : Estimated.none,
    tokens: tokens,
  );
}

/// What a part of the window's spend is: the main session, a long-lived
/// agent, a team run, one of its lead and members, or a task agent one of
/// them started.
enum SpendKind { main, agent, team, member, task }

/// A part of the window's spend: a session or task with its own figure,
/// and the tasks it started under it; or a team run, whose figure is only
/// what is under it.
class SpendPart {
  const SpendPart({
    required this.name,
    required this.kind,
    this.agent,
    this.runtime,
    this.figure,
    this.parts = const [],
    this.running = false,
    this.ended = false,
  });

  final String name;
  final SpendKind kind;

  /// The agent the main session is, which says what reported nothing.
  final String? agent;

  /// The agent a long-lived agent runs on, as chord starts it, which its
  /// notes name, as [agent] is main's.
  final String? runtime;

  /// Its own figure; null when it reported nothing.
  final Figure? figure;

  /// The task agents it started, each with its own figure.
  final List<SpendPart> parts;

  /// A task still at work, whose figure comes when it ends: not counted yet.
  final bool running;

  /// A task that has ended, an agent that has closed, or a main session
  /// `/clear` let go.
  final bool ended;

  /// This part with [parts] under it, as a closed one's is kept.
  SpendPart withParts(List<SpendPart> parts) => SpendPart(
    name: name,
    kind: kind,
    agent: agent,
    runtime: runtime,
    figure: figure,
    parts: parts,
    running: running,
    ended: ended,
  );

  /// This part alone, without the tasks under it, as a group's sum takes it.
  SpendPart get alone => parts.isEmpty ? this : withParts(const []);
}

/// The figures of a part and those under it, added up.
class Summed {
  const Summed({
    this.cost,
    required this.estimated,
    this.tokens,
    required this.missing,
    required this.providers,
    required this.uncounted,
  });

  /// In USD, the only currency added up; null when no part had a cost.
  final num? cost;

  /// How much of the cost is chord's estimate.
  final Estimated estimated;
  final num? tokens;

  /// The parts that reported no cost, or one in another currency: by name,
  /// the main session by its agent.
  final List<String> missing;

  /// The agents, each once, whose running totals came with no cost, as
  /// their provider gives none: said apart from [missing].
  final List<String> providers;

  /// Turns left out of the cost of the parts that had one.
  final int uncounted;
}

/// [parts] and all under them added up: costs in USD only, a part with no
/// cost, or another currency, named as missing rather than read as zero; a
/// task still at work is not counted until its figure comes.
Summed sum(List<SpendPart> parts) {
  num? cost;
  num? tokens;
  var costed = 0;
  var estimated = 0;
  var partly = false;
  var uncounted = 0;
  final missing = <String>[];
  final providers = <String>{};

  void add(SpendPart part) {
    final own = part.figure;
    // A team run is only what is under it.
    if (part.kind != SpendKind.team && !part.running) {
      if (own?.cost case final Cost counted when counted.currency == _summed) {
        cost = (cost ?? 0) + counted.amount;
        costed += 1;
        if (own!.estimated == Estimated.all) estimated += 1;
        if (own.estimated == Estimated.part) partly = true;
      } else if (own?.totals != null) {
        providers.add(part.runtime ?? part.agent ?? part.name);
      } else {
        missing.add(part.agent ?? part.name);
      }
      if (own?.tokens case final counted?) tokens = (tokens ?? 0) + counted;
      uncounted += own?.uncounted ?? 0;
    }
    part.parts.forEach(add);
  }

  parts.forEach(add);

  return Summed(
    cost: cost,
    estimated: partly && estimated < costed
        ? Estimated.part
        : _share(estimated, costed),
    tokens: tokens,
    missing: missing,
    providers: providers.toList(),
    uncounted: uncounted,
  );
}

/// A session as the window holds it, as much of it as its spend needs.
class SpendSession {
  const SpendSession({
    this.sessionId,
    this.spent,
    this.transcript = const Transcript(),
  });

  /// The agent's id for it, once it is up.
  final String? sessionId;
  final Spent? spent;

  /// Where its task agents' figures are read from.
  final Transcript transcript;
}

/// A closed agent's spend, kept for the window's total, as closed agents
/// count: the team lead it worked for, by chord's id, and its part as it
/// was when it closed.
class KeptSpend {
  const KeptSpend({this.sessionId, this.lead, this.team, required this.part});

  /// The agent's id for its session: a session resumed since counts its
  /// whole spend where it is open, and one closed again where it closed
  /// last.
  final String? sessionId;

  /// The lead of the team run it was of, by chord's id, itself for a lead.
  final String? lead;

  /// That team's name, for a run whose lead has closed.
  final String? team;
  final SpendPart part;
}

/// Kept parts grouped as they were: each closed team run's, whose lead is
/// not in [open], as one team part; the rest as they are.
List<SpendPart> _regrouped(List<KeptSpend> kept, Set<String> open) {
  final runs = <String, List<SpendPart>>{};
  final loose = <SpendPart>[];
  final names = <String, String>{};
  for (final each in kept) {
    final lead = each.lead;
    if (lead == null || open.contains(lead)) {
      loose.add(each.part);
      continue;
    }
    (runs[lead] ??= []).add(each.part);
    if (each.team case final team?) names[lead] = team;
  }
  return [
    ...loose,
    for (final MapEntry(key: lead, value: parts) in runs.entries)
      SpendPart(
        name: names[lead] ?? lead,
        kind: SpendKind.team,
        ended: true,
        parts: parts,
      ),
  ];
}

/// The task agents among [tasks], each a part with its own figure: one at
/// work as running, its figure to come, one done as ended. A subagent that
/// is no task of chord's is left out.
List<SpendPart> taskParts(Iterable<Subagent> tasks) => [
  for (final subagent in tasks)
    if (subagent.task case final task?)
      SpendPart(
        name: task.name,
        kind: SpendKind.task,
        figure: taskFigure(task.spent),
        running: subagent.state == SubagentState.running,
        ended: subagent.state != SubagentState.running,
      ),
];

/// The task agents a session started, as its transcript draws them.
Iterable<Subagent> tasksOf(Transcript transcript) => [
  for (final entry in transcript.entries)
    if (entry is SubagentEntry && entry.subagent.task != null) entry.subagent,
];

/// A session's own part and its task agents'.
List<SpendPart> sessionParts(
  String name,
  SpendKind kind,
  SpendSession? session, {
  String? agent,
  String? runtime,
}) => [
  SpendPart(
    name: name,
    kind: kind,
    agent: agent,
    runtime: runtime,
    figure: sessionFigure(session?.spent),
  ),
  ...taskParts(tasksOf(session?.transcript ?? const Transcript())),
];

/// A session's part, main's, a long-lived agent's or a team member's, its
/// task agents under it, as a closed one's is kept.
SpendPart _ownPart(
  String name,
  SpendKind kind,
  SpendSession? session, {
  String? agent,
  String? runtime,
}) {
  final [own, ...tasks] = sessionParts(
    name,
    kind,
    session,
    agent: agent,
    runtime: runtime,
  );
  return tasks.isEmpty ? own : own.withParts(tasks);
}

/// The window's spend: the main session and its task agents, then each
/// long-lived agent with its own, a team run as one part with its lead and
/// members under it; then the agents closed since the window opened, each
/// under its team while that runs; with main gone, what was kept, as it
/// was. [sessions] are by the agents' keys.
List<SpendPart> windowSpend<C>(
  WindowAgents<C> agents,
  Map<int, SpendSession?> sessions,
  List<KeptSpend> everKept,
) {
  final live = {for (final each in sessions.values) ?each?.sessionId};
  // Each session once, its whole spend: where it is open, else where it
  // closed last.
  final kept = [
    for (final (index, each) in everKept.indexed)
      if (each.sessionId == null ||
          (!live.contains(each.sessionId) &&
              !everKept
                  .skip(index + 1)
                  .any((later) => later.sessionId == each.sessionId)))
        each,
  ];

  final main = agents.main;
  // With main gone, what was kept, as it was.
  if (main == null) return _regrouped(kept, const {});

  final leads = [
    for (final child in agents.children)
      if (isLead(child.info)) child,
  ];
  final running = {for (final lead in leads) lead.id};
  return [
    _ownPart('main', SpendKind.main, sessions[main.key], agent: main.agent),
    for (final child in agents.children)
      if (child.info.team == null)
        _ownPart(
          child.name,
          SpendKind.agent,
          sessions[child.key],
          runtime: child.runtime,
        ),
    for (final lead in leads)
      SpendPart(
        name: lead.team ?? lead.name,
        kind: SpendKind.team,
        parts: [
          // Its row is named by the team; its lead is `lead` under it.
          _ownPart(
            'lead',
            SpendKind.member,
            sessions[lead.key],
            runtime: lead.runtime,
          ),
          for (final member in membersOf(agents, lead.id))
            _ownPart(
              member.name,
              SpendKind.member,
              sessions[member.key],
              runtime: member.runtime,
            ),
          for (final each in kept)
            if (each.lead == lead.id) each.part,
        ],
      ),
    // What closed under a team still running is in its part above.
    ..._regrouped([
      for (final each in kept)
        if (each.lead == null || !running.contains(each.lead)) each,
    ], running),
  ];
}
