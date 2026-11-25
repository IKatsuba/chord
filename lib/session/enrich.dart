/// The enricher chain: what one agent leaves out of an ACP message, chord
/// fills in before anything reads it. Each enricher is pure, from one
/// message the agent sent and what the chain knows of its sessions to the
/// messages chord reads in its place, ACP's shape on both sides. What the
/// chain knows is folded from the traffic both ways, after each message has
/// been enriched.
library;

import 'dart:collection';

import '../acp/connection.dart' show Relay;
import '../acp/schema.dart' as acp;
import 'agent_state.dart';
import 'modes.dart';
import 'usage.dart';

/// A message as decoded from the wire.
typedef Message = Map<String, Object?>;

/// The `_meta` key on what chord filled in, naming the fields it filled.
const filledKey = 'chord/filled';

/// The name Claude's adapter gives itself in `initialize`'s `agentInfo`.
const claudeAdapter = '@agentclientprotocol/claude-agent-acp';

/// The `_meta` key on a `subagent_update` of Claude's adapter, whose title
/// is the subagent's name and whose description only its role, where every
/// other agent's description is its task. The wire cannot tell them apart,
/// so chord says so from who the adapter is, and a record keeps it.
const namedByTitleKey = 'chord/named_by_title';

/// The `_meta` key on a `subagent_update` made from the adapters' draft
/// shape, holding what that shape said that ACP's has no field for: its own
/// kind, and the rest, such as `prompt`, so nothing the agent sent is lost.
const subagentDraftKey = 'chord/subagent_draft';

/// What the chain knows of one tool call.
final class ToolFacts {
  const ToolFacts({this.title, this.kind, this.ownContent});

  /// The call's title, as its `tool_call` or an update gave it.
  final String? title;

  /// The call's kind, as its `tool_call` or an update gave it.
  final String? kind;

  /// The agent sent content of its own for the call, not chord's filled
  /// in, which an update that leaves content out keeps.
  final bool? ownContent;
}

/// A persistent stack of early resume state reports, appended in constant time.
final class EarlySessionReport {
  const EarlySessionReport(this.update, this.previous);
  final Message update;
  final EarlySessionReport? previous;
}

/// A request chord sent and the agent has not answered yet.
final class Asked {
  const Asked(
    this.method,
    this.params, {
    this.modeReported = false,
    this.resumeReport,
  });

  /// A mode report arrived while this request was open.
  final bool modeReported;

  /// Resume reports before its answer are live and follow answer seeding.
  final EarlySessionReport? resumeReport;

  Iterable<Message> get earlyStates {
    final reversed = <Message>[];
    for (var report = resumeReport; report != null; report = report.previous) {
      reversed.add(report.update);
    }
    return reversed.reversed;
  }

  /// The request's method.
  final String method;

  /// The request's params, as an object.
  final Map<String, Object?> params;
}

/// What the chain knows of one session's spend.
final class SessionCosts {
  const SessionCosts({
    this.usage,
    this.agentCost = false,
    this.estimate,
    this.total,
  });

  /// The context as the agent's own last `usage_update` gave it.
  final ({num used, num size})? usage;

  /// Whether the agent has given a cost of its own; then chord gives none.
  final bool agentCost;

  /// chord's estimate of what the session has cost, once there is one.
  final num? estimate;

  /// The running total of tokens the agent's last answer gave, on an agent
  /// whose answers give one.
  final TokenUsage? total;

  static const none = SessionCosts();

  SessionCosts _withTotal(TokenUsage total) => SessionCosts(
    usage: usage,
    agentCost: agentCost,
    estimate: estimate,
    total: total,
  );

  /// These costs after a `usage_update` [update].
  SessionCosts heard(Message update) {
    final filled = filledIn(update);
    final cost = recordOf(update['cost'])['amount'];
    final amount = cost is num ? cost : null;
    final used = update['used'], size = update['size'];
    return SessionCosts(
      // A size chord filled in is still none the agent gave.
      usage: filled.contains('used') || used is! num
          ? usage
          : (
              used: used,
              size: filled.contains('size') || size is! num ? 0 : size,
            ),
      agentCost: agentCost || (amount != null && !filled.contains('cost')),
      estimate: amount != null && filled.contains('cost') ? amount : estimate,
      total: total,
    );
  }
}

/// What the chain knows: chord's open requests by id, and each session's
/// tool calls by id.
final class Wire {
  const Wire({
    this.asked = const {},
    this.tools = const {},
    this.sessions = const {},
    this.costs = const {},
    this.totals = false,
    this.adapter,
  });

  /// The name the agent gave itself in `initialize`'s `agentInfo`, which
  /// says whose adapter it is.
  final String? adapter;

  /// Each session's spend, as the chain has heard it.
  final Map<String, SessionCosts> costs;

  /// The agent's answers give each session's running total as their usage,
  /// not the turn's: a fact of the agent, not of what it sent.
  final bool totals;

  /// Each session's latest reported settings.
  final Map<String, AgentState> sessions;

  /// Nothing known yet.
  static const empty = Wire();

  /// chord's requests the agent has not answered, by their id as a string.
  final Map<String, Asked> asked;

  /// Each session's tool calls, by session id, then by call id.
  final Map<String, Map<String, ToolFacts>> tools;
}

/// Turns one message the agent sent into the messages chord reads in its
/// place: itself, filled in, perhaps with others before or after it. It
/// builds new maps and never writes the one it was handed.
typedef Enricher = List<Message> Function(Message message, Wire wire);

/// Each enricher in turn over what the one before it made.
List<Message> enrich(List<Enricher> chain, Message message, Wire wire) =>
    chain.fold(
      [message],
      (messages, enricher) => [
        for (final each in messages) ...enricher(each, wire),
      ],
    );

/// [wire] after a message chord sent.
Wire heardFromChord(Wire wire, Message message) {
  final method = message['method'];
  final id = message['id'];

  if (method is! String || id == null) {
    return wire;
  }

  return Wire(
    asked: {...wire.asked, '$id': Asked(method, recordOf(message['params']))},
    tools: wire.tools,
    sessions: wire.sessions,
    costs: wire.costs,
    totals: wire.totals,
    adapter: wire.adapter,
  );
}

/// [wire] after a message the agent sent, as the chain left it.
Wire heardFromAgent(Wire wire, Message message) {
  final notification = notificationOf(message);

  if (notification != null) {
    final (sessionId, update) = notification;

    final before = wire.sessions[sessionId] ?? AgentState.empty;
    final after = foldUpdate(before, acp.SessionUpdate.fromJson(update));
    final reported =
        update['sessionUpdate'] == 'current_mode_update' ||
        (update['sessionUpdate'] == 'config_option_update' &&
            modesFrom(before.configOptions, before.modes)?.current !=
                modesFrom(after.configOptions, after.modes)?.current);
    wire = Wire(
      tools: wire.tools,
      totals: wire.totals,
      adapter: wire.adapter,
      costs: update['sessionUpdate'] == 'usage_update'
          ? {
              ...wire.costs,
              sessionId: (wire.costs[sessionId] ?? SessionCosts.none).heard(
                update,
              ),
            }
          : wire.costs,
      sessions: identical(before, after)
          ? wire.sessions
          : {...wire.sessions, sessionId: after},
      asked:
          !reported &&
              !const {
                'current_mode_update',
                'config_option_update',
                'available_commands_update',
              }.contains(update['sessionUpdate'])
          ? wire.asked
          : {
              for (final entry in wire.asked.entries)
                entry.key:
                    entry.value.params['sessionId'] == sessionId &&
                        (reported || entry.value.method == 'session/resume')
                    ? Asked(
                        entry.value.method,
                        entry.value.params,
                        modeReported: entry.value.modeReported || reported,
                        resumeReport: entry.value.method == 'session/resume'
                            ? EarlySessionReport(
                                update,
                                entry.value.resumeReport,
                              )
                            : entry.value.resumeReport,
                      )
                    : entry.value,
            },
    );
    if (!_isToolUpdate(update)) return wire;

    final callId = update['toolCallId'];

    if (callId is! String) {
      return wire;
    }

    final session = wire.tools[sessionId] ?? const {};

    return Wire(
      asked: wire.asked,
      sessions: wire.sessions,
      costs: wire.costs,
      totals: wire.totals,
      adapter: wire.adapter,
      tools: {
        ...wire.tools,
        sessionId: {...session, callId: _toolFacts(session[callId], update)},
      },
    );
  }

  final id = message['id'];

  if (message.containsKey('method') ||
      id == null ||
      !wire.asked.containsKey('$id')) {
    return wire;
  }

  final asked = wire.asked['$id']!;
  final result = recordOf(message['result']);
  var sessions = wire.sessions;
  var costs = wire.costs;
  if (asked.method == 'session/prompt' &&
      wire.totals &&
      !message.containsKey('error')) {
    final sessionId = asked.params['sessionId'];
    final usage = result['usage'];
    if (sessionId is String && usage is Map<String, Object?>) {
      costs = {
        ...costs,
        sessionId: (costs[sessionId] ?? SessionCosts.none)._withTotal(
          tokensOf(usage),
        ),
      };
    }
  }
  if (!message.containsKey('error')) {
    final sessionId = asked.method == 'session/new'
        ? result['sessionId']
        : asked.params['sessionId'];
    if (sessionId is String) {
      final before = sessions[sessionId] ?? AgentState.empty;
      var after =
          const {
            'session/new',
            'session/load',
            'session/resume',
          }.contains(asked.method)
          ? stateOf(acp.SessionResponse.fromJson(result))
          : withOptions(before, result['configOptions']);
      if (asked.method == 'session/resume') {
        for (final update in asked.earlyStates) {
          after = foldUpdate(after, acp.SessionUpdate.fromJson(update));
        }
      }
      sessions = {...sessions, sessionId: after};
    }
  }
  final name = recordOf(result['agentInfo'])['name'];
  return Wire(
    asked: {...wire.asked}..remove('$id'),
    tools: wire.tools,
    sessions: sessions,
    costs: costs,
    totals: wire.totals,
    adapter:
        asked.method == 'initialize' &&
            !message.containsKey('error') &&
            name is String
        ? name
        : wire.adapter,
  );
}

/// Work at the detached recall writer, for long-history validation.
final class RecallWork {
  int reports = 0;
  int copiedToolEntries = 0;
  int toolWrites = 0;
}

/// Recalls one session in linear tool-map work, with one final publication.
Wire recalled(
  Wire wire,
  String sessionId,
  Iterable<acp.SessionUpdate> updates, {
  RecallWork? work,
  TokenUsage? total,
}) {
  var costs = wire.costs[sessionId] ?? SessionCosts.none;
  final tools = <String, ToolFacts>{};
  for (final entry
      in (wire.tools[sessionId] ?? const <String, ToolFacts>{}).entries) {
    tools[entry.key] = entry.value;
    if (work != null) work.copiedToolEntries++;
  }
  var state = wire.sessions[sessionId] ?? AgentState.empty;
  for (final update in updates) {
    if (work != null) work.reports++;
    final json = update.toJson();
    state = foldUpdate(state, update);
    if (json['sessionUpdate'] == 'usage_update') costs = costs.heard(json);
    final id = json['toolCallId'];
    if (_isToolUpdate(json) && id is String) {
      tools[id] = _toolFacts(tools[id], json);
      if (work != null) work.toolWrites++;
    }
  }
  // Only this detached writer saw the backing map; the published view is frozen.
  return Wire(
    asked: wire.asked,
    tools: Map.unmodifiable({
      ...wire.tools,
      sessionId: UnmodifiableMapView(tools),
    }),
    sessions: Map.unmodifiable({...wire.sessions, sessionId: state}),
    costs: {
      ...wire.costs,
      sessionId: total == null ? costs : costs._withTotal(total),
    },
    totals: wire.totals,
    adapter: wire.adapter,
  );
}

/// A relay that runs [chain] over everything the agent sends, with one
/// [Wire] for its connection.
/// A relay that runs [chain] over everything the agent sends, on an agent
/// whose answers give the session's running total as their usage when
/// [totals].
EnricherRelay enricherRelay(List<Enricher> chain, {bool totals = false}) =>
    EnricherRelay(chain, totals: totals);

final class EnricherRelay implements Relay {
  EnricherRelay(this._chain, {bool totals = false})
    : _wire = Wire(totals: totals);

  /// Recalls semantic saved reports directly, never running the chain
  /// twice, with the running total its agent last gave, where it gives one.
  void recall(
    String sessionId,
    Iterable<acp.SessionUpdate> updates, {
    TokenUsage? total,
  }) {
    _wire = recalled(_wire, sessionId, updates, total: total);
  }

  final List<Enricher> _chain;
  Wire _wire;

  @override
  List<Message> fromChord(Message message) {
    _wire = heardFromChord(_wire, message);
    return [message];
  }

  @override
  List<Message> fromAgent(Message message) {
    final out = enrich(_chain, message, _wire);

    for (final each in out) {
      _wire = heardFromAgent(_wire, each);
    }

    return out;
  }
}

bool _isToolUpdate(Message update) =>
    update['sessionUpdate'] == 'tool_call' ||
    update['sessionUpdate'] == 'tool_call_update';

/// What a tool call's [update] leaves known of it, [known] before.
ToolFacts _toolFacts(ToolFacts? known, Message update) {
  final title = update['title'];
  final kind = update['kind'];
  final content = update['content'];

  return ToolFacts(
    title: title is String ? title : known?.title,
    kind: kind is String ? kind : known?.kind,
    // Content chord filled in is none of the agent's: what it sent there
    // was none, or an empty list that cleared its own.
    ownContent: content is List
        ? content.isNotEmpty && !filledIn(update).contains('content')
        : known?.ownContent,
  );
}

/// The fields chord filled in, named on [value]'s `_meta`.
List<String> filledIn(Message value) {
  final filled = recordOf(value['_meta'])[filledKey];

  return filled is List ? filled.whereType<String>().toList() : const [];
}

/// [meta] with [fields] named as chord's, beside what it already said.
Message markFilled(Object? meta, List<String> fields) {
  final record = recordOf(meta);
  final already = filledIn({'_meta': record});

  return {
    ...record,
    filledKey: [...already, ...fields.where((each) => !already.contains(each))],
  };
}

/// The session id and update of a `session/update` the agent sent, when
/// the message is one; taken by its shape alone.
(String, Message)? notificationOf(Message message) {
  if (message.containsKey('id') || message['method'] != 'session/update') {
    return null;
  }

  final params = recordOf(message['params']);
  final sessionId = params['sessionId'];
  final update = recordOf(params['update']);

  return sessionId is String && update['sessionUpdate'] is String
      ? (sessionId, update)
      : null;
}

/// [message] carrying [update] in place of its own.
Message withUpdate(Message message, Message update) => {
  ...message,
  'params': {...recordOf(message['params']), 'update': update},
};

/// [message], a request, with [params] in place of its own.
Message withParams(Message message, Message params) => {
  ...message,
  'params': params,
};

/// [value] when it is an object, else an empty one.
Map<String, Object?> recordOf(Object? value) =>
    value is Map<String, Object?> ? value : const {};
