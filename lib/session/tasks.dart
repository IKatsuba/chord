/// Task agents and messages between agents. A task agent is a session chord
/// opens on any runtime for one job a parent asked for with `spawn_task`.
/// It has no row of its own: its work is relayed into its parent's stream
/// as a subagent's, under the task's id, so it draws in the parent's turn,
/// and its requests reach the person in the parent's session. It ends with
/// its first turn, whose last message is the report, delivered to the
/// parent as a message; then chord closes it. From the original's
/// `session/tasks.ts`.
library;

import '../acp/schema.dart' as acp;
import '../js_trim.dart';
import 'conversation.dart';
import 'elicitations.dart' show ElicitationReply, PendingElicitation;
import 'monitors.dart' show endWord;
import 'permissions.dart' show PendingPermission;
import 'transcript/reducer.dart';
import 'transcript/subagents.dart'
    show taskMetaKey, taskSpentMetaKey, taskStoppedMetaKey;
import 'transcript/types.dart';
import 'turn_costs.dart' show CostReading, costReading;

/// [from] as a message's row and its wrapper name it.
String fromLine(MessageFrom from) => switch (from.monitor) {
  null => [from.name, ?from.runtime, ?from.note?.name],
  (:final end, id: _) => [from.name, 'monitor', if (end != null) endWord(end)],
}.join(' · ');

/// The sender as a row after `←` names it: `@parser` for a name
/// `send_message` reaches, bare for a task and chord. The wrapper the agent
/// reads keeps the bare name, which is what `send_message` takes.
String senderName(MessageFrom from) =>
    from.reachable ? '@${from.name}' : from.name;

/// A message as its recipient gets it, so the agent knows who speaks: never
/// as the person's own words.
String wrapMessage(MessageFrom from, String text) =>
    '<message from="${fromLine(from).replaceAll('"', '&quot;')}"'
    '${from.monitor == null ? '' : ' monitor="${from.monitor!.id}"'}>\n'
    '$text\n</message>';

/// A team agent's first prompt: the team part in `<team>`, so the agent
/// tells the team's words from the job, then the message that opened it.
String wrapTeamMessage(TeamPart part, MessageFrom from, String text) =>
    '${teamBlock(part)}\n${wrapMessage(from, text)}';

/// The team part alone, in `<team>`, as a first prompt opens with it.
String teamBlock(TeamPart part) {
  final member = part.member == null ? '' : ' member="${part.member}"';
  return '<team name="${part.team}" '
      'role="${part.member == null ? 'lead' : 'member'}"$member>\n'
      '${part.text}\n</team>';
}

/// A task's name: the one asked for, or its prompt's first line.
String taskName(String? name, String prompt) {
  final named = name == null ? '' : jsTrim(name);
  if (named.isNotEmpty) return named;
  final first = jsTrim(jsTrim(prompt).split('\n').first);
  return first.isEmpty ? 'task' : first;
}

/// The last message the agent sent in turn [turnId], which is its report.
String reportOf(Transcript transcript, String turnId) {
  for (final entry in transcript.entries.reversed) {
    if (entry is AssistantEntry && entry.turnId == turnId) {
      return jsTrim(entry.text.text);
    }
  }
  return '';
}

/// What starts a task: who it is, and what it was asked.
final class TaskStart {
  const TaskStart({
    required this.id,
    required this.name,
    required this.runtime,
    required this.prompt,
    this.model,
    this.effort,
  });

  /// chord's id for it, which `spawn_task` answers.
  final String id;
  final String name;
  final String runtime;
  final String prompt;
  final String? model;
  final String? effort;
}

/// A `subagent_update` for task [id], as an adapter's would describe it:
/// [task] said on its start, and on its end what it [spent] and who
/// [stoppedWith].
acp.SessionUpdate taskUpdate(
  String id,
  SubagentState state, {
  TaskStart? task,
  TaskSpent? spent,
  TaskStop? stoppedWith,
}) => acp.SessionUpdate.fromJson({
  'sessionUpdate': 'subagent_update',
  'sessionId': id,
  'state': {'state': state.name},
  if (task != null) ...{'title': task.name, 'description': task.prompt},
  if (task != null || spent != null || stoppedWith != null)
    '_meta': {
      if (task != null)
        taskMetaKey: {
          'name': task.name,
          'runtime': task.runtime,
          'model': ?task.model,
          'effort': ?task.effort,
        },
      // What it spent, on its ending update.
      if (spent != null) taskSpentMetaKey: spent.toJson(),
      // Who stopped it, which its end line says.
      if (stoppedWith != null) taskStoppedMetaKey: stoppedWith.toJson(),
    },
});

/// What a task spent: the tokens its turn's answer gave, and the cost its
/// last `usage_update` did, marked when chord worked it out; none when its
/// agent reported neither.
TaskSpent? taskSpent(Map<String, num>? tokens, CostReading? cost) =>
    tokens == null && cost == null
    ? null
    : TaskSpent(
        tokens: tokens,
        cost: cost == null
            ? null
            : (amount: cost.amount, currency: cost.currency),
        estimated: cost?.estimated ?? false,
      );

/// What a task does to its parent, which the parent's [Conversation] gives
/// it.
abstract interface class TaskParent {
  /// An event of the task's, into the parent's stream: its work as a
  /// subagent's, its requests as the parent's to answer.
  void relay(ConversationEvent event);

  /// The task's report, or its failure, to the parent: a turn, or queued
  /// behind the one running.
  void deliver(MessageFrom from, String text);

  /// A line to go ahead of the person's next prompt, as a task the person
  /// stopped sends no report: a turn right after Esc would undo the Esc.
  void ahead(MessageFrom from, String text);

  /// The task ended and its agent is closing.
  void ended();
}

/// What a task drives: its own [Conversation], or a stand-in in a test.
abstract interface class TaskSession {
  /// Opens its session.
  void start();

  /// Sends its job as its first turn.
  bool send(String text);

  /// Stops its turn.
  void interrupt();

  /// Answers its permission [id] with [optionId].
  void choose(String id, String optionId);

  /// Rejects its permission [id].
  void reject(String id);

  /// Answers its form or link [id].
  void answer(String id, ElicitationReply reply);

  /// Closes its session.
  Future<void> close();

  /// A permission of its own, as its agent asked it, for one who passes it
  /// on.
  PendingPermission? permissionRequest(String id);

  /// A form or link of its own, as its agent asked it.
  PendingElicitation? elicitationRequest(String id);
}

/// One task agent, from its start to its report. Its session is made with
/// the task's own listener, so every event it reports is heard here first.
final class TaskAgent {
  /// Task [start], reporting to [parent], timed by [now] in epoch
  /// milliseconds.
  TaskAgent(this.start, TaskParent parent, num Function() now)
    : _parent = parent,
      _now = now;

  /// Who it is and what it was asked.
  final TaskStart start;
  final TaskParent _parent;
  final num Function() _now;
  TaskSession? _session;

  // The task's own transcript, folded here to read its report from.
  var _transcript = const Transcript();
  String? _turnId;

  // The job went to the agent: a cancel stops its turn from here on.
  var _sent = false;
  var _ended = false;

  // The parent cancelled it: it ends cancelled and sends no report.
  var _stopped = false;

  // The person's key that stopped it, or the agent that did, if either did.
  TaskStop? _stoppedWith;

  // Its turn's tokens, as the answer to its prompt gave them, and the cost
  // its last usage_update said.
  Map<String, num>? _tokens;
  CostReading? _cost;

  /// chord's id for it.
  String get id => start.id;

  /// Until it has ended.
  bool get running => !_ended;

  /// How the task reads, as a message's sender.
  MessageFrom get from => MessageFrom(start.name, runtime: start.runtime);

  void _relayUpdate(acp.SessionUpdate update) =>
      _parent.relay(Transcribed(UpdateAction('', update, at: _now())));

  /// The effort the task is on once it is up, for its block to say after
  /// its model; the window says it only for a task asked for one.
  void startedOn(String effort) {
    if (_ended) return;
    _relayUpdate(
      taskUpdate(
        id,
        SubagentState.running,
        task: TaskStart(
          id: id,
          name: start.name,
          runtime: start.runtime,
          prompt: start.prompt,
          model: start.model,
          effort: effort,
        ),
      ),
    );
  }

  /// Puts the task in the parent's transcript and starts its agent.
  void begin(TaskSession session) {
    _session = session;
    _relayUpdate(taskUpdate(id, SubagentState.running, task: start));
    session.start();
  }

  /// Every event the task's conversation reports.
  void heard(ConversationEvent event) {
    if (_ended) return;
    switch (event) {
      case Connected():
        _sent = true;
        _session?.send(start.prompt);
      // A model the runtime refused fails the start, as the task's session
      // requires the one asked for.
      case ConnectFailed(:final message):
        _end(SubagentState.failed, message);
      case Transcribed(:final action):
        _heardAction(action);
      default:
    }
  }

  void _heardAction(TranscriptAction action) {
    // Only what the report is read from: its own turn and messages.
    if (action is PromptAction ||
        action is ResultAction ||
        (action is UpdateAction && action.subagentId == null)) {
      _transcript = reduceTranscript(_transcript, action);
    }
    switch (action) {
      // A starting effort or mode it was refused, before it is up: the task
      // runs on the agent's own, and the person is told which task it was.
      case FailedAction(:final turnId, :final message):
        if (!_sent) {
          _parent.relay(
            Transcribed(FailedAction(turnId, '${start.name}: $message')),
          );
        }
      // The servers its agent was not given, in its parent's turn, named as
      // the task.
      case WarnedAction(:final turnId, :final message):
        _parent.relay(
          Transcribed(WarnedAction(turnId, '${start.name}: $message')),
        );
      case PromptAction(:final turnId):
        _turnId = turnId;
      case UpdateAction(:final update, :final subagentId):
        if (subagentId == null && update.kind == 'usage_update') {
          _cost = costReading(update);
        }
        _parent.relay(
          Transcribed(
            UpdateAction(
              action.turnId,
              update,
              at: action.at,
              unasked: action.unasked,
              subagentId: subagentId ?? id,
            ),
          ),
        );
      case ServedAction(:final turnId, :final call, :final subagentId):
        _parent.relay(
          Transcribed(ServedAction(turnId, call, subagentId: subagentId ?? id)),
        );
      case PermissionRequestedAction(:final turnId, :final wait):
        _parent.relay(
          Transcribed(
            PermissionRequestedAction(
              turnId,
              wait.askedBy(wait.subagentId ?? id),
              at: _now(),
              between: action.between,
            ),
          ),
        );
      case ElicitationRequestedAction(:final turnId, :final elicitation):
        _parent.relay(
          Transcribed(
            ElicitationRequestedAction(turnId, elicitation.askedBy(id)),
          ),
        );
      case PermissionSettledAction() || ElicitationSettledAction():
        _parent.relay(Transcribed(action));
      case DisconnectedAction():
        _end(SubagentState.disconnected, '${start.runtime} exited');
      case ResultAction(:final turnId, :final result):
        if (turnId != _turnId) return;
        _tokens = result is TurnAnswered ? result.usage : null;
        switch (result) {
          case TurnFailed(:final message):
            _end(SubagentState.failed, message);
          case TurnAnswered(cancelled: true):
            _end(SubagentState.cancelled, '');
          case TurnAnswered():
            _end(SubagentState.completed, reportOf(_transcript, turnId));
        }
      default:
    }
  }

  /// Stops the task's turn, as the parent's Esc does; it sends no report.
  /// One still starting has no turn to stop: it ends here, so its job is
  /// never sent. [by] is the person's key that stopped it, or the agent
  /// that started it, which its end says.
  void cancel([TaskStop? by]) {
    if (_ended) return;
    // The first stop counts, a stop with no key among them.
    if (!_stopped) _stoppedWith = by;
    _stopped = true;
    if (!_sent) return _end(SubagentState.cancelled, '');
    _session?.interrupt();
  }

  /// Answers the task's permission [id] with [optionId].
  void choose(String id, String optionId) => _session?.choose(id, optionId);

  /// Rejects the task's permission [id].
  void reject(String id) => _session?.reject(id);

  /// Answers the task's form or link [id].
  void answer(String id, ElicitationReply reply) => _session?.answer(id, reply);

  /// The task's permission [id], as its agent asked it.
  PendingPermission? permissionRequest(String id) =>
      _session?.permissionRequest(id);

  /// The task's form or link [id], as its agent asked it.
  PendingElicitation? elicitationRequest(String id) =>
      _session?.elicitationRequest(id);

  /// Closes the task's agent; one still running ends cancelled first, as
  /// the parent closing takes it with it.
  Future<void> close() {
    if (!_ended) {
      _stopped = true;
      _end(SubagentState.cancelled, '');
    }
    return _session?.close() ?? Future.value();
  }

  void _end(SubagentState how, String text) {
    if (_ended) return;
    // Its agent's close stands however it ended after it, its turn's result
    // or its agent's exit, so its line names who stopped it; the person's
    // keys keep how it ended.
    final byAgent = _stoppedWith?.agent != null;
    final state = byAgent ? SubagentState.cancelled : how;
    _ended = true;
    _relayUpdate(
      taskUpdate(
        id,
        state,
        spent: taskSpent(_tokens, _cost),
        stoppedWith: state == SubagentState.cancelled ? _stoppedWith : null,
      ),
    );
    if (state == SubagentState.cancelled || _stopped) {
      // The agent that stopped it was told so by its own call's answer.
      if (!byAgent) {
        _parent.ahead(from, 'The person stopped this task before it reported.');
      }
    } else {
      _parent.deliver(
        MessageFrom(
          start.name,
          runtime: start.runtime,
          note: state == SubagentState.completed
              ? MessageNote.report
              : MessageNote.failed,
        ),
        text.isEmpty ? '(no report)' : text,
      );
    }
    _parent.ended();
  }
}
