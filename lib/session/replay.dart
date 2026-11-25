import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:path/path.dart' as p;

import '../acp/schema.dart' as acp;
import 'context.dart';
import 'enrichers.dart' show guardianReview;
import 'record.dart';
import 'record_worker.dart';
import 'sign_in.dart' show recordSignIn;
import 'subagents.dart' show Heard;
import 'transcript/reducer.dart' show applyUpdate;
import 'transcript/types.dart';
import 'turn_costs.dart';
import 'monitors.dart' show monitorsPast;

/// A selected file whose declared format is outside the interchange boundary.
final class UnsupportedRecordVersion implements Exception {
  const UnsupportedRecordVersion(this.version);
  final Object? version;
  @override
  String toString() => 'Unsupported session record version: $version.';
}

/// Detached supported actions and omission facts, never a live transcript.
/// One event of a session's past as ACP carries it, for `chord acp` to
/// relay on a load ahead of its answer: what the window's projection
/// merges or omits is kept whole.
sealed class PastEvent {
  const PastEvent();

  /// The event as JSON, which crosses the record worker.
  Map<String, Object?> toJson();

  /// [json] as the event it carries; none for one it does not know.
  static PastEvent? fromJson(Map<String, Object?> json) => switch (json) {
    {'type': 'prompt', 'text': final String text} => PastPrompt(
      text,
      from: json['from'] as Map<String, Object?>?,
    ),
    {'type': 'update', 'update': final Map<String, Object?> update} =>
      PastUpdate(update, subagentId: json['subagentId'] as String?),
    {'type': 'renamed', 'title': final String title} => PastRenamed(title),
    {'type': 'left_open', 'agents': final List<Object?> agents} => PastLeftOpen(
      agents,
    ),
    _ => null,
  };
}

/// A prompt, as the person or a message's sender said it.
final class PastPrompt extends PastEvent {
  /// [text], sent by [from] when it was a message.
  const PastPrompt(this.text, {this.from});

  /// Its words, chord's asides omitted.
  final String text;

  /// Who sent it, when it was a message, as the record keeps it.
  final Map<String, Object?>? from;

  @override
  Map<String, Object?> toJson() => {
    'type': 'prompt',
    'text': text,
    'from': ?from,
  };
}

/// One of the agent's updates, whole.
final class PastUpdate extends PastEvent {
  /// [update], of the subagent [subagentId] when it was one's.
  const PastUpdate(this.update, {this.subagentId});

  /// The update as the agent sent it.
  final Map<String, Object?> update;

  /// The subagent it came from, if any.
  final String? subagentId;

  @override
  Map<String, Object?> toJson() => {
    'type': 'update',
    'update': update,
    'subagentId': ?subagentId,
  };
}

/// A rename the session took.
final class PastRenamed extends PastEvent {
  /// A rename to [title].
  const PastRenamed(this.title);

  /// The title kept.
  final String title;

  @override
  Map<String, Object?> toJson() => {'type': 'renamed', 'title': title};
}

/// The children a session left open when it was let go.
final class PastLeftOpen extends PastEvent {
  /// The [agents] left open, as the record keeps them.
  const PastLeftOpen(this.agents);

  /// Each child left open.
  final List<Object?> agents;

  @override
  Map<String, Object?> toJson() => {'type': 'left_open', 'agents': agents};
}

final class PreparedHistory {
  PreparedHistory({
    required this.rawHasPast,
    required this.omitted,
    required Iterable<TranscriptAction> actions,
    Iterable<acp.SessionUpdate> recalled = const [],
    this.pendingRename,
    this.title,
    this.past,
  }) : actions = List.unmodifiable(actions),
       recalled = List.unmodifiable(recalled);
  static final empty = PreparedHistory(
    rawHasPast: false,
    omitted: false,
    actions: const [],
  );
  final bool rawHasPast, omitted;
  final List<TranscriptAction> actions;

  /// Supported main reports in original order, recalled without enriching again.
  final List<acp.SessionUpdate> recalled;

  /// The raw ACP past, when it was asked for: the record's, or what the
  /// agent replayed of a session chord never recorded.
  final List<PastEvent>? past;

  /// The title of the record's last rename when `chord acp` recorded it
  /// for a session not loaded, so its agent has not taken it yet.
  final String? pendingRename;

  /// The session's title as its past left it: the last rename, or the last
  /// title its agent gave it; none while it has none.
  final String? title;

  /// JSON alone crosses the preparation isolate boundary.
  Map<String, Object?> toJson() => {
    'pendingRename': ?pendingRename,
    'title': ?title,
    if (past case final past?)
      'past': [for (final event in past) event.toJson()],
    'rawHasPast': rawHasPast,
    'omitted': omitted,
    'actions': [for (final action in actions) _actionJson(action)],
    'recalled': [for (final update in recalled) update.toJson()],
  };
  factory PreparedHistory.fromJson(Map<String, Object?> json) =>
      PreparedHistory(
        rawHasPast: json['rawHasPast'] == true,
        omitted: json['omitted'] == true,
        pendingRename: json['pendingRename'] as String?,
        title: json['title'] as String?,
        past: switch (json['past']) {
          final List<Object?> past => [
            for (final event in past)
              ?PastEvent.fromJson(event as Map<String, Object?>),
          ],
          _ => null,
        },
        recalled: [
          for (final update in json['recalled'] as List)
            acp.SessionUpdate.fromJson(update as Map<String, Object?>),
        ],
        actions: [
          for (final action in json['actions'] as List)
            _actionFromJson(action as Map<String, Object?>),
        ],
      );
}

/// Prepares the selected local history before any agent process starts.
Future<PreparedHistory> readRecordedHistory(
  String? path, {
  CancellationToken? cancellationToken,
  bool past = false,
}) async {
  if (path == null) return PreparedHistory.empty;
  final Map<String, Object?> json;
  try {
    json =
        await runRecordWorker(
              past ? _preparePastWorker : _prepareWorker,
              'prepare',
              path,
              cancellationToken: cancellationToken,
              decodeError: (error) => error['kind'] == 'unsupported-version'
                  ? UnsupportedRecordVersion(error['version'])
                  : decodeRecordWorkerError(error),
            )
            as Map<String, Object?>;
  } catch (error, stack) {
    Error.throwWithStackTrace(
      recordWorkerPublicationError(error, cancellationToken),
      stack,
    );
  }
  if (cancellationToken?.exception case final exception?) throw exception;
  return PreparedHistory.fromJson(json);
}

void _prepareWorker(List<Object?> initial) => _prepare(initial, past: false);

void _preparePastWorker(List<Object?> initial) => _prepare(initial, past: true);

void _prepare(List<Object?> initial, {required bool past}) => serveRecordWorker(
  initial,
  'prepare',
  (io, path) async {
    final text = StringBuffer();
    try {
      await io.forEach(
        File(
          path,
        ).openRead().transform(const Utf8Decoder(allowMalformed: true)),
        text.write,
        stage: 'selected',
        path: path,
      );
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 2) return PreparedHistory.empty.toJson();
      rethrow;
    }
    io.throwIfCancelled();
    var raw = <Object?>[];
    final lines = text.toString().split('\n');
    var count = 0;
    for (final (index, line) in lines.indexed) {
      io.throwIfCancelled();
      if (line.trim().isNotEmpty) count++;
      raw.addAll(parseRecord(line));
      io.throwIfCancelled();
      if (index % 64 == 63) await io.checkpoint(stage: 'parse');
    }
    final malformed = count != raw.length;
    // A task's work is in its own record, beside its parent's, as are a
    // team run's lead's.
    var runs = const <String, List<Object?>>{};
    if (raw.firstOrNull case {
      'type': 'session',
      'sessionId': final String sessionId,
    }) {
      final children = await childPasts(p.dirname(path), sessionId);
      io.throwIfCancelled();
      raw = withTaskWork(raw, taskPasts(children));
      runs = runPasts(children);
    }
    await io.checkpoint(stage: 'projection');
    final projection = _RecordProjection(
      malformed,
      past: past,
      raw: raw,
      runs: runs,
    );
    for (final (index, value) in raw.indexed) {
      io.throwIfCancelled();
      projection.add(value);
      io.throwIfCancelled();
      if (index % 64 == 63) await io.checkpoint(stage: 'projection');
    }
    return _projectionJson(projection, io);
  },
  encodeError: (error) => error is UnsupportedRecordVersion
      ? {'kind': 'unsupported-version', 'version': error.version}
      : encodeRecordWorkerError(error),
);

Future<Map<String, Object?>> _projectionJson(
  _RecordProjection projection,
  RecordWorkerIO io,
) async {
  projection._settleUnanswered();
  projection._end();
  projection._leftOpen();
  final actions = <Map<String, Object?>>[], recalled = <Map<String, Object?>>[];
  await io.checkpoint(stage: 'serialization');
  for (final (index, action) in projection.actions.indexed) {
    io.throwIfCancelled();
    actions.add(_actionJson(action));
    if (index % 64 == 63) await io.checkpoint(stage: 'serialization');
  }
  for (final (index, update) in projection.recalled.indexed) {
    io.throwIfCancelled();
    recalled.add(update.toJson());
    if (index % 64 == 63) await io.checkpoint(stage: 'serialization');
  }
  return {
    if (projection.past case final past?)
      'past': [for (final event in past) event.toJson()],
    'pendingRename': ?projection.pendingRename,
    'title': ?projection.title,
    'rawHasPast': projection.hasPast,
    'omitted': projection.omitted,
    'actions': actions,
    'recalled': recalled,
  };
}

/// Supported version-1 record projection; raw parsed presence drives ACP choice.
/// [raw] is the record as read, with its tasks' work spliced in already
/// where [withTaskWork] put it.
PreparedHistory recordActions(
  List<Object?> raw, {
  bool malformed = false,
  bool past = false,
  Map<String, List<Object?>> runs = const {},
}) {
  final projection = _RecordProjection(
    malformed,
    past: past,
    raw: raw,
    runs: runs,
  );
  for (final value in raw) {
    projection.add(value);
  }
  return projection.finish();
}

final class _RecordProjection {
  _RecordProjection(
    this.omitted, {
    bool past = false,
    List<Object?> raw = const [],
    this._runs = const {},
  }) : past = past ? <PastEvent>[] : null,
       _reachable = _answeredReachable(raw);

  /// The records of the team runs' leads, by chord's id for each lead.
  final Map<String, List<Object?>> _runs;

  /// The names `send_message` reached by, as the record's own answers tell
  /// it, for a message whose line has no `from`.
  final Set<String> _reachable;

  /// The long-lived agents open so far, by chord's id for each.
  final _open = <String, LeftOpen>{};

  /// The raw ACP past, when it is asked for.
  final List<PastEvent>? past;
  final actions = <TranscriptAction>[];
  final recalled = <acp.SessionUpdate>[];
  bool omitted, hasPast = false;
  String? open;

  /// The last rename's title while it is a pending one.
  String? pendingRename;

  /// The plans asked and not yet answered, by id, with their turns and
  /// where their ask stands in [actions].
  final _unanswered = <String, ({String turn, int at, bool form})>{};

  /// The session's title so far.
  String? title;

  /// When the record's first `opened` line came, once it has.
  num? _openedAt;
  var _opened = false;

  /// The session's own updates before its first `opened` line, or in all
  /// of a record written before those lines were.
  final _beforeOpened = <acp.SessionUpdate>[];

  /// The plans never answered, settled withdrawn, each where its ask is.
  void _settleUnanswered() {
    // A plan the record never saw answered, as chord was stopped while it
    // waited, comes back withdrawn: never waiting, never taken.
    // Each straight after its ask, as the original's replay puts it: a later
    // plan under the same call stays the call's.
    final unanswered = _unanswered.entries.toList()
      ..sort((a, b) => b.value.at.compareTo(a.value.at));
    for (final MapEntry(key: id, value: (:turn, :at, :form)) in unanswered) {
      actions.insert(
        at,
        form
            ? ElicitationSettledAction(turn, id, const ElicitationWithdrawn())
            : PlanSettledAction(turn, id, const PlanWithdrawn()),
      );
    }
    _unanswered.clear();
  }

  void _end() {
    if (open != null) {
      actions.add(
        ResultAction(
          open!,
          const TurnAnswered('end_turn', recordedStatus: 'completed'),
        ),
      );
    }
    open = null;
  }

  void add(Object? value) {
    if (!hasPast) {
      if (value case final Map<String, Object?> header
          when header['type'] == 'session' &&
              header.containsKey('version') &&
              header['version'] != 1) {
        throw UnsupportedRecordVersion(header['version']);
      }
    }
    hasPast = true;
    final entry = RecordEntry.view(value);
    if (entry == null) {
      omitted = true;
      return;
    }
    final json = entry.json;
    if (past case final past?) {
      if (_pastOf(json) case final event?) past.add(event);
    }
    final turn = json['turnId'] is String
        ? 'history-${json['turnId']}'
        : 'history';
    switch (entry.type) {
      // An agent another started draws as any session, a team's lead too.
      case 'session' || 'state':
        break;
      case 'renamed':
        title = json['title'] as String;
        pendingRename = json['pending'] == true
            ? json['title'] as String
            : null;
      case 'opened':
        if (!_opened) _openedAt = json['at'] as num;
        _opened = true;
        _end();
        actions.add(const DisconnectedAction('history'));
      case 'prompt':
        final prompt = json['prompt'] as String;
        final into = json['into'] as String?;
        if (wrappedPromptText(prompt) case final text?) {
          final from = _fromOf(json['from'], prompt);
          // A monitor's, which a later task draws.
          if (from == null) {
            if (into == null) _end();
            omitted = true;
            return;
          }
          // It went into the turn running then, which goes on past it.
          if (into != null) {
            actions.add(
              PromptAction(
                turn,
                text,
                json['at'] as num,
                from: from,
                into: 'history-$into',
                team: wrappedPromptTeam(prompt),
              ),
            );
            return;
          }
          _end();
          actions.add(
            PromptAction(
              turn,
              text,
              json['at'] as num,
              from: from,
              team: wrappedPromptTeam(prompt),
            ),
          );
          open = turn;
          return;
        }
        if (json['from'] != null) {
          if (into == null) _end();
          omitted = true;
          return;
        }
        if (into == null) _end();
        final split = splitContext(withoutChordAsides(prompt));
        for (final (index, run) in split.runs.indexed) {
          actions.add(ShellReplayedAction('$turn-shell-${index + 1}', run));
        }
        actions.add(
          PromptAction(
            turn,
            withImages(split.text, json['images'] as num),
            json['at'] as num,
            into: into == null ? null : 'history-$into',
          ),
        );
        if (into == null) open = turn;
      case 'forked':
        actions.add(
          ForkedAction(turn, json['from'] as String, json['at'] as num),
        );
      case 'self_started':
        final from = MessageFrom.fromJson(json['from']);
        if (json['from'] != null && from == null) {
          omitted = true;
          return;
        }
        actions.add(SelfStartedAction(turn, from: from));
      case 'served':
        final call = ChordCall.fromJson(json['call'])!;
        _openedBy(call);
        actions.add(
          ServedAction(turn, call, subagentId: json['subagentId'] as String?),
        );
      // The person's command drew its call; the record keeps it for what
      // it opened.
      case 'ran':
        _openedBy(ChordCall.fromJson(json['call'])!);
      case 'closed':
        _open.remove(json['agent']);
      case 'update':
        // A subagent's id of another type could name no session.
        final subagentId = json['subagentId'];
        if (subagentId != null && subagentId is! String) {
          omitted = true;
          return;
        }
        final update = guardianReview(json['update'] as Map<String, Object?>);
        final projection = _updateProjection(update);
        if (!projection.supported) {
          omitted = true;
          return;
        }
        omitted |= projection.omitted;
        // A subagent's title, settings and calls are not the session's.
        if (subagentId == null) {
          title = titled(title, update);
          recalled.add(acp.SessionUpdate.fromJson(update));
          if (!_opened) _beforeOpened.add(acp.SessionUpdate.fromJson(update));
        }
        if (projection.action) {
          actions.add(
            UpdateAction(
              turn,
              acp.SessionUpdate.fromJson(update),
              at: json['at'] is num ? json['at'] as num : null,
              unasked: json['unasked'] == true,
              subagentId: subagentId as String?,
            ),
          );
        }
      case 'cancel':
        actions.add(CancelAction(turn, json['at'] as num));
      case 'stopping':
        actions.add(
          SubagentStoppingAction(
            'stop',
            json['subagentId'] as String,
            json['stopping'] as bool,
          ),
        );
      case 'disconnected':
        actions.add(
          DisconnectedAction(open ?? 'history', at: json['at'] as num),
        );
      case 'result':
        final result = RecordedResult.view(json['result'])!;
        omitted |= result.omittedDetail;
        actions.add(ResultAction(turn, _result(result)));
        if (open == turn) open = null;
      case 'usage':
        final figures = TurnFigures.fromJson(json, turn);
        if (figures != null) actions.add(UsageAction(turn, figures));
      case 'plan_asked':
        final wait = PlanWait.fromJson(json['wait'])!;
        actions.add(PlanRequestedAction(turn, wait));
        _unanswered[wait.id] = (turn: turn, at: actions.length, form: false);
      // A form or link the record never saw answered, as chord was stopped
      // while it waited, is not drawn again as waiting.
      case 'asked':
        final wait = elicitationWaitFrom(json['wait'])!;
        actions.add(ElicitationRequestedAction(turn, wait));
        _unanswered[wait.id] = (turn: turn, at: actions.length, form: true);
      case 'answered':
        final id = json['id'] as String;
        actions.add(
          ElicitationSettledAction(
            turn,
            id,
            elicitationAnswerFrom(json['answer'])!,
          ),
        );
        _unanswered.remove(id);
      case 'plan_answered':
        final id = json['id'] as String;
        actions.add(
          PlanSettledAction(turn, id, PlanAnswer.fromJson(json['answer'])!),
        );
        _unanswered.remove(id);
      default:
        omitted = true;
    }
  }

  /// [json]'s event of the raw past, if it is one: a prompt, its words as
  /// the original reads them, a message's with its sender; an update whole;
  /// a rename; the children left open.
  static PastEvent? _pastOf(Map<String, Object?> json) {
    switch (json['type']) {
      case 'prompt':
        final prompt = json['prompt'] as String;
        if (wrappedPromptText(prompt) case final message?) {
          // The record's own sender wins; one written before it was kept
          // has it read from the wrapper, as the original's legacyFrom
          // reads it. Whom send_message reaches is M4's to know.
          return PastPrompt(
            message,
            from: switch (json['from']) {
              final Map<String, Object?> from => from,
              _ => wrappedPromptFrom(prompt),
            },
          );
        }
        return PastPrompt(
          withImages(
            splitContext(withoutChordAsides(prompt)).text,
            json['images'] as num,
          ),
        );
      // A subagent's id of another type could name no session: the
      // update is left out, as the window leaves it out.
      case 'update' when json['subagentId'] is String?:
        return PastUpdate(
          guardianReview(json['update'] as Map<String, Object?>),
          subagentId: json['subagentId'] as String?,
        );
      case 'renamed':
        return PastRenamed(json['title'] as String);
      case 'left_open' when json['agents'] is List<Object?>:
        return PastLeftOpen(json['agents'] as List<Object?>);
      default:
        return null;
    }
  }

  /// A long-lived agent [call] opened, as its answer names it: a team's
  /// run counts its lead and the members its lead's record in [_runs] had
  /// open, or its lead alone once that record has gone.
  void _openedBy(ChordCall call) {
    if (call.tool != ChordTool.openAgent && call.tool != ChordTool.runTeam) {
      return;
    }
    if (call.answer case {
      'id': final String id,
      'name': final String name,
      'agent': final String runtime,
    }) {
      final team = call.tool == ChordTool.runTeam ? call.answer : null;
      _open[id] = team is Map && team['team'] is String
          ? (
              name: name,
              runtime: runtime,
              team: team['team'] as String,
              agents: 1 + leftOpenIn(_runs[id] ?? const []).length,
            )
          : (name: name, runtime: runtime, team: null, agents: null);
    }
  }

  /// The long-lived agents open when the session was left, named last, as
  /// they are not reopened with it; then its monitors running then, which
  /// nothing restarts.
  void _leftOpen() {
    _leftOpenAgents();
    final running = monitorsPast(actions).left;
    if (running.isNotEmpty) {
      actions.add(MonitorsLeftAction('history-monitors', running));
    }
  }

  void _leftOpenAgents() {
    if (_open.isEmpty) return;
    final agents = [..._open.values];
    actions.add(LeftOpenAction('history-left', agents));
    past?.add(PastLeftOpen([for (final agent in agents) leftOpenJson(agent)]));
    _open.clear();
  }

  /// Who sent a message: the record's own sender, or, for a line written
  /// before it was kept, the wrapper's, reachable by its name when the
  /// record's answers say so; none for a sender this version does not draw.
  MessageFrom? _fromOf(Object? kept, String prompt) {
    if (kept != null) return MessageFrom.fromJson(kept);
    final from = MessageFrom.fromJson(wrappedPromptFrom(prompt));
    if (from == null) return null;
    return from.note == null && _reachable.contains(from.name)
        ? MessageFrom(
            from.name,
            runtime: from.runtime,
            monitor: from.monitor,
            reachable: true,
          )
        : from;
  }

  PreparedHistory finish() {
    _settleUnanswered();
    _end();
    // What a record spent before it kept each turn's cost, as one figure:
    // the last cost its session's own updates gave before its first
    // `opened` line, or in all of one written before those lines were.
    if (lastReading(_beforeOpened) case final last?) {
      actions.add(
        UsageAction(
          'history-before',
          TurnFigures(
            turnId: 'history-before',
            usage: const {},
            cost: TurnCost(
              cost: (amount: last.amount, currency: last.currency),
              estimated: last.estimated,
              before: (until: _openedAt),
            ),
          ),
        ),
      );
    }
    _leftOpen();
    return PreparedHistory(
      rawHasPast: hasPast,
      omitted: omitted,
      actions: actions,
      recalled: recalled,
      pendingRename: pendingRename,
      title: title,
      past: past,
    );
  }
}

({bool supported, bool action, bool omitted}) _updateProjection(
  Map<String, Object?> update,
) {
  final kind = update['sessionUpdate'];
  if (const {
    'user_message_chunk',
    'config_option_update',
    'available_commands_update',
    'session_info_update',
  }.contains(kind)) {
    return (supported: true, action: false, omitted: false);
  }
  if (!const {
    'agent_message_chunk',
    'agent_thought_chunk',
    'tool_call',
    'tool_call_update',
    'plan',
    'plan_update',
    'plan_removed',
    'usage_update',
    'current_mode_update',
    'notice',
    'subagent_update',
    'session_message',
    'compaction_update',
    'compaction_summary_chunk',
  }.contains(kind)) {
    return (supported: false, action: false, omitted: true);
  }
  if (kind == 'agent_message_chunk' || kind == 'agent_thought_chunk') {
    final content = update['content'];
    if (content is! Map ||
        content['type'] != 'text' ||
        content['text'] is! String) {
      return (supported: false, action: false, omitted: true);
    }
  }
  try {
    applyUpdate(
      Transcript.empty,
      'history',
      acp.SessionUpdate.fromJson(update),
    );
    return (
      supported: true,
      action: true,
      omitted:
          (kind == 'tool_call' || kind == 'tool_call_update') &&
          _toolContentOmitted(update),
    );
  } catch (_) {
    return (supported: false, action: false, omitted: true);
  }
}

bool _toolContentOmitted(Map<String, Object?> update) {
  final content = update['content'];
  if (content is! List) return false;
  for (final item in content) {
    if (item is! Map) return true;
    switch (item['type']) {
      case 'diff':
      case 'terminal':
        break;
      case 'content':
        final block = item['content'];
        if (block is! Map ||
            !const {
              'text',
              'image',
              'audio',
              'resource',
              'resource_link',
            }.contains(block['type'])) {
          return true;
        }
      default:
        return true;
    }
  }
  return false;
}

TurnResult _result(RecordedResult result) => result.status == 'failed'
    ? TurnFailed(
        result.message!,
        code: result.code == null ? null : int.tryParse(result.code!),
        recordedCode: result.code,
        signIn: recordSignIn(result.signIn),
      )
    : TurnAnswered(result.stopReason!, recordedStatus: result.status);

/// Existing placeholders count as images already shown, including repeated ids.
String withImages(String text, num images) {
  final shown = RegExp(r'\[Image #\d+\]').allMatches(text).length;
  final missing = (images - shown).truncate();
  return [
    if (text.isNotEmpty) text,
    for (var i = 0; i < missing; i++) '[Image #${shown + i + 1}]',
  ].join(' ');
}

/// [title] after [update], if it is a `session_info_update`: a title left
/// out or blank is kept, and null takes it back.
String? titled(String? title, Map<String, Object?> update) {
  if (update['sessionUpdate'] != 'session_info_update') return title;
  return switch (update['title']) {
    null when update.containsKey('title') => null,
    final String given when given.trim().isNotEmpty => given,
    _ => title,
  };
}

/// Contiguous main user chunks form one prompt when ACP load supplies history.
PreparedHistory pastActions(List<Heard> updates, num at) {
  final actions = <TranscriptAction>[];
  final typed = <Map<String, Object?>>[];
  String? turn, title;
  var turns = 0, omitted = false;
  void end() {
    if (turn != null) {
      actions.add(
        ResultAction(
          turn!,
          const TurnAnswered('end_turn', recordedStatus: 'completed'),
        ),
      );
    }
  }

  void prompt() {
    if (typed.isEmpty) return;
    end();
    turn = 'history-${++turns}';
    final text = StringBuffer();
    var images = 0;
    for (final block in typed) {
      switch (block['type']) {
        case 'text':
          if (block['text'] is String) {
            text.write(block['text']);
          } else {
            omitted = true;
          }
        case 'resource':
          final resource = block['resource'];
          if (resource is Map && resource['uri'] is String) {
            text.write(resource['uri']);
          } else {
            omitted = true;
          }
        case 'audio':
          text.write('[audio]');
        case 'image':
          images++;
        case 'resource_link':
          break;
        default:
          omitted = true;
      }
    }
    final split = splitContext(withImages(text.toString(), images));
    for (final (index, run) in split.runs.indexed) {
      actions.add(ShellReplayedAction('$turn-shell-${index + 1}', run));
    }
    actions.add(PromptAction(turn!, split.text, at));
    typed.clear();
  }

  for (final (:update, :subagentId) in updates) {
    final json = update.toJson();
    // A subagent's prompt is its work, not one the person typed.
    if (update.kind == 'user_message_chunk' && subagentId == null) {
      final content = json['content'];
      if (content is Map<String, Object?>) {
        typed.add(content);
      } else {
        omitted = true;
      }
      continue;
    }
    prompt();
    turn ??= 'history-${++turns}';
    final projection = _updateProjection(json);
    if (!projection.supported) {
      omitted = true;
      continue;
    }
    omitted |= projection.omitted;
    // A subagent's title is its own, never the session's.
    if (subagentId == null) title = titled(title, json);
    if (projection.action) {
      actions.add(UpdateAction(turn!, update, subagentId: subagentId));
    }
  }
  prompt();
  end();
  // The subagents it replayed are no longer running in this opening.
  if (updates.any((heard) => heard.update.kind == 'subagent_update')) {
    actions.add(DisconnectedAction(turn ?? 'history'));
  }
  return PreparedHistory(
    rawHasPast: false,
    omitted: omitted,
    actions: actions,
    title: title,
  );
}

/// Agent-loaded supported past becomes a held prefix with images already in text.
List<Map<String, Object?>> historyEntries(List<TranscriptAction> actions) {
  final entries = <Map<String, Object?>>[];
  final runs = <ShellRun>[];
  for (final action in actions) {
    switch (action) {
      case ShellReplayedAction(:final run):
        runs.add(run);
      case PromptAction(:final turnId, :final text, :final at, :final into):
        entries.add({
          'type': 'prompt',
          'turnId': turnId,
          'at': at,
          'prompt': withContext(shellContext(runs), text),
          'into': ?into,
          'images': 0,
        });
        runs.clear();
      case UpdateAction(
        :final turnId,
        :final update,
        :final at,
        :final unasked,
        :final subagentId,
      ):
        entries.add({
          'type': 'update',
          'turnId': turnId,
          'update': update.toJson(),
          'subagentId': ?subagentId,
          'at': ?at,
          if (unasked) 'unasked': true,
        });
      case SelfStartedAction(:final turnId):
        entries.add({'type': 'self_started', 'turnId': turnId});
      case ResultAction(:final turnId, :final result):
        entries.add({
          'type': 'result',
          'turnId': turnId,
          'result': recordResult(result),
        });
      case UsageAction(:final figures):
        entries.add({'type': 'usage', ...figures.toJson()});
      default:
        break;
    }
  }
  return List.unmodifiable(entries);
}

Map<String, Object?> _actionJson(TranscriptAction action) => switch (action) {
  PromptAction(
    :final turnId,
    :final text,
    :final at,
    :final into,
    :final from,
    :final team,
  ) =>
    {
      'type': 'prompt',
      'turnId': turnId,
      'text': text,
      'at': at,
      'into': ?into,
      'from': ?from?.toJson(),
      if (team != null)
        'team': {'team': team.team, 'member': ?team.member, 'text': team.text},
    },
  SelfStartedAction(:final turnId, :final from) => {
    'type': 'self_started',
    'turnId': turnId,
    'from': ?from?.toJson(),
  },
  ServedAction(:final turnId, :final call, :final subagentId) => {
    'type': 'served',
    'turnId': turnId,
    'call': call.toJson(),
    'subagentId': ?subagentId,
  },
  ForkedAction(:final turnId, :final from, :final at) => {
    'type': 'forked',
    'turnId': turnId,
    'from': from,
    'at': at,
  },
  MonitorsLeftAction(:final turnId, :final monitors) => {
    'type': 'monitors_left',
    'turnId': turnId,
    'monitors': [
      for (final m in monitors) {'id': m.id, 'description': m.description},
    ],
  },
  LeftOpenAction(:final turnId, :final agents) => {
    'type': 'left_open',
    'turnId': turnId,
    'agents': [for (final agent in agents) leftOpenJson(agent)],
  },
  UpdateAction(
    :final turnId,
    :final update,
    :final at,
    :final unasked,
    :final subagentId,
  ) =>
    {
      'type': 'update',
      'turnId': turnId,
      'update': update.toJson(),
      'subagentId': ?subagentId,
      'at': ?at,
      if (unasked) 'unasked': true,
    },
  CancelAction(:final turnId, :final at) => {
    'type': 'cancel',
    'turnId': turnId,
    'at': at,
  },
  SubagentStoppingAction(:final turnId, :final subagentId, :final stopping) => {
    'type': 'subagent_stopping',
    'turnId': turnId,
    'subagentId': subagentId,
    'stopping': stopping,
  },
  DisconnectedAction(:final turnId, :final at) => {
    'type': 'disconnected',
    'turnId': turnId,
    'at': ?at,
  },
  ResultAction(:final turnId, :final result) => {
    'type': 'result',
    'turnId': turnId,
    'result': recordResult(result),
  },
  // A turn's figures, as the record line that kept them says them.
  UsageAction(:final turnId, :final figures) => {
    'type': 'usage',
    'turnId': turnId,
    'figures': figures.toJson(),
  },
  ShellReplayedAction(:final turnId, :final run) => {
    'type': 'shell_replayed',
    'turnId': turnId,
    'run': {
      'command': run.command,
      'stdout': run.stdout,
      'stderr': run.stderr,
      'code': run.code,
      'stopped': run.stopped,
      'error': run.error,
      'truncated': run.truncated,
    },
  },
  ElicitationRequestedAction(:final turnId, :final elicitation) => {
    'type': 'elicitation_requested',
    'turnId': turnId,
    'wait': elicitationWaitJson(elicitation),
  },
  ElicitationSettledAction(:final turnId, :final id, :final answer) => {
    'type': 'elicitation_settled',
    'turnId': turnId,
    'id': id,
    'answer': elicitationAnswerJson(answer),
  },
  PlanRequestedAction(:final turnId, :final plan) => {
    'type': 'plan_requested',
    'turnId': turnId,
    'plan': plan.toJson(),
  },
  PlanSettledAction(:final turnId, :final id, :final answer) => {
    'type': 'plan_settled',
    'turnId': turnId,
    'id': id,
    'answer': answer.toJson(),
  },
  _ => throw StateError('Not a supported historical action.'),
};
TranscriptAction _actionFromJson(Map<String, Object?> json) {
  final turn = json['turnId'] as String;
  return switch (json['type']) {
    'prompt' => PromptAction(
      turn,
      json['text'] as String,
      json['at'] as num,
      into: json['into'] as String?,
      from: MessageFrom.fromJson(json['from']),
      team: switch (json['team']) {
        {'team': final String team, 'text': final String text} && final part =>
          (team: team, member: part['member'] as String?, text: text),
        _ => null,
      },
    ),
    'self_started' => SelfStartedAction(
      turn,
      from: MessageFrom.fromJson(json['from']),
    ),
    'served' => ServedAction(
      turn,
      ChordCall.fromJson(json['call'])!,
      subagentId: json['subagentId'] as String?,
    ),
    'forked' => ForkedAction(turn, json['from'] as String, json['at'] as num),
    'monitors_left' => MonitorsLeftAction(turn, [
      for (final monitor in json['monitors'] as List)
        (
          id: (monitor as Map)['id'] as String,
          description: monitor['description'] as String,
        ),
    ]),
    'left_open' => LeftOpenAction(turn, [
      for (final agent in json['agents'] as List)
        (
          name: (agent as Map)['name'] as String,
          runtime: agent['runtime'] as String,
          team: agent['team'] as String?,
          agents: agent['agents'] as int?,
        ),
    ]),
    'update' => UpdateAction(
      turn,
      acp.SessionUpdate.fromJson(json['update'] as Map<String, Object?>),
      at: json['at'] as num?,
      unasked: json['unasked'] == true,
      subagentId: json['subagentId'] as String?,
    ),
    'cancel' => CancelAction(turn, json['at'] as num),
    'subagent_stopping' => SubagentStoppingAction(
      turn,
      json['subagentId'] as String,
      json['stopping'] as bool,
    ),
    'disconnected' => DisconnectedAction(turn, at: json['at'] as num?),
    'result' => ResultAction(
      turn,
      _result(RecordedResult.view(json['result'])!),
    ),
    'shell_replayed' => ShellReplayedAction(
      turn,
      _shell(json['run'] as Map<String, Object?>),
    ),
    'usage' => UsageAction(
      turn,
      TurnFigures.fromJson(
        json['figures'] as Map<String, Object?>,
        (json['figures'] as Map<String, Object?>)['turnId'] as String,
      )!,
    ),
    'elicitation_requested' => ElicitationRequestedAction(
      turn,
      elicitationWaitFrom(json['wait'])!,
    ),
    'elicitation_settled' => ElicitationSettledAction(
      turn,
      json['id'] as String,
      elicitationAnswerFrom(json['answer'])!,
    ),
    'plan_requested' => PlanRequestedAction(
      turn,
      PlanWait.fromJson(json['plan'])!,
    ),
    'plan_settled' => PlanSettledAction(
      turn,
      json['id'] as String,
      PlanAnswer.fromJson(json['answer'])!,
    ),
    _ => throw StateError('Not a supported historical action.'),
  };
}

ShellRun _shell(Map<String, Object?> json) => ShellRun(
  command: json['command'] as String,
  running: false,
  stdout: json['stdout'] as String,
  stderr: json['stderr'] as String,
  code: json['code'] as num?,
  stopped: json['stopped'] == true,
  error: json['error'] as String?,
  truncated: json['truncated'] == true,
);

/// The names `send_message` reached by, as a record's own answers tell it:
/// `main`, and each child `open_agent` opened, but none a `spawn_task` in
/// it named, as a message from that name could be the task's.
Set<String> _answeredReachable(List<Object?> raw) {
  final opened = {'main'}, tasks = <String>{};
  for (final value in raw) {
    if (value case {
      'type': 'served',
      'call': {
        'tool': final String tool,
        'answer': {'name': final String name},
      },
    }) {
      if (tool == ChordTool.openAgent.wire) opened.add(name);
      if (tool == ChordTool.spawnTask.wire) tasks.add(name);
    }
  }
  return opened.difference(tasks);
}

/// [agent] as a record's past keeps it: a team's run with its team and how
/// many agents it had open.
Map<String, Object?> leftOpenJson(LeftOpen agent) => {
  'name': agent.name,
  'runtime': agent.runtime,
  'team': ?agent.team,
  'agents': ?agent.agents,
};

/// The long-lived agents a record's session had open when it was left:
/// each `open_agent` or `run_team` answered, `served` or `ran`, but not one
/// closed while it went on, by chord's id for each.
List<String> leftOpenIn(List<Object?> raw) {
  final open = <String>{};
  for (final line in raw) {
    switch (line) {
      case {'type': 'closed', 'agent': final String agent}:
        open.remove(agent);
      case {'type': 'served' || 'ran', 'call': final Object? json}:
        final call = ChordCall.fromJson(json);
        if (call == null ||
            (call.tool != ChordTool.openAgent &&
                call.tool != ChordTool.runTeam)) {
          continue;
        }
        if (call.answer case {
          'id': final String id,
          'name': String _,
          'agent': String _,
        }) {
          open.add(id);
        }
    }
  }
  return [...open];
}
