/// The tools chord's MCP server offers, by the role of the session that
/// calls: every agent chord opens but a task lists the runtimes chord knows
/// and starts task agents of its own; a session the person opened also
/// lists the window's sessions, opens, messages, closes and clears
/// long-lived agents; a child, of either kind, sends messages to its parent
/// alone, and a long-lived child stops its own tasks. Each answer is worked
/// out here from what the window reads of itself, so it is tested without a
/// server. The person's sessions and long-lived children start, stop and
/// list monitors of their own, and main reads and, once the person agrees,
/// edits chord's settings. From the original's `server/tools.ts`; teams
/// and budgets come with their tasks.
library;

import 'dart:convert';
import 'dart:io' show FileSystemException;

import 'package:cancellation_token/cancellation_token.dart';
import 'package:clock/clock.dart';
import 'package:uuid/uuid.dart';

import '../acp/schema.dart' as acp;
import '../session/budgets.dart';
import '../session/elapsed.dart';
import '../session/monitors.dart';
import '../session/transcript/types.dart';
import '../settings.dart';
import '../settings_tool.dart';
import '../teams.dart';
import 'runtimes.dart';

/// Who a session is to chord, which says what it may call: one the person
/// opened, or a child one of those started, a task agent or a long-lived
/// one.
enum Role { person, child }

/// Which part of a team's run a long-lived child is.
enum TeamSide { lead, member }

/// What a session's token says of it.
final class Caller {
  const Caller({
    required this.role,
    required this.key,
    required this.window,
    this.task,
    this.agent,
    this.by,
    this.launch,
    this.fork = false,
    this.team,
  });

  final Role role;

  /// A long-lived child that is a team's lead or one of its members.
  final TeamSide? team;

  /// The main session's key; a child's parent's, which is the main
  /// session's.
  final int key;

  /// A child's task id, as `spawn_task` answered it.
  final String? task;

  /// A long-lived child's id, as `open_agent` answered it.
  final String? agent;

  /// The long-lived child that started a task, by its id; null for a task
  /// the main session started.
  final String? by;

  /// Whether the launch this caller was admitted for is still the one up:
  /// old tokens cannot borrow a replacement's state. Null for always.
  final bool Function()? launch;

  /// A fork's: the person's session beside main, under its own key, of no
  /// one, which opens no agents.
  final bool fork;

  final WindowView window;
}

/// What `spawn_task` was asked.
final class SpawnArgs {
  const SpawnArgs({
    required this.agent,
    required this.prompt,
    this.model,
    this.effort,
    this.name,
    this.mode,
  });

  /// [input], as the server checked it against the schema.
  factory SpawnArgs.of(Map<String, Object?> input) => SpawnArgs(
    agent: input['agent'] as String,
    prompt: input['prompt'] as String,
    model: input['model'] as String?,
    effort: input['effort'] as String?,
    name: input['name'] as String?,
  );

  final String agent;
  final String? model;

  /// Never refuses the start: a runtime that does not take it runs on its
  /// own.
  final String? effort;
  final String prompt;
  final String? name;

  /// The mode a team file set its agent on; none from `open_agent`.
  final String? mode;
}

/// What a lead's `open_agent` was asked: a member of its file, by name.
typedef MemberArgs = ({String member, String prompt});

/// What `run_team` was asked.
typedef RunTeamArgs = ({String team, String job});

/// The team files found, and each open run's lead, by its name, with its
/// team's, as `list_teams` reads them.
typedef TeamsFound = ({
  List<FoundTeam> found,
  List<({String team, String name, String? id})> runs,
});

/// An answer as the agent reads it.
abstract interface class Answer {
  /// The answer as JSON, its members in the original's order.
  Map<String, Object?> toJson();
}

/// Whether `close_agent` closes the caller's long-lived agents too: main's
/// and a lead's do; a long-lived child's and a member's stop only the tasks
/// they started.
bool closesAgents(Caller caller) =>
    caller.role == Role.person || caller.team == TeamSide.lead;

/// A task started, by chord's id for it, or why it was not.
sealed class SpawnAnswer implements Answer {}

/// A team's run started, by its lead's name and chord's id for it, or why
/// it was not.
sealed class RunTeamAnswer implements Answer {}

/// A long-lived agent opened, by chord's id for it, or why it was not.
sealed class OpenAnswer implements Answer {}

/// How a message went: straight to its recipient, queued, or refused.
sealed class MessageAnswer implements Answer {}

/// A long-lived agent or a task closed, a task that had ended, or why
/// neither.
sealed class CloseAnswer implements Answer {}

/// A child cleared, once its fresh session is up, or why it was not.
sealed class ClearAnswer implements Answer {}

/// A monitor started, by its id, or why it was not.
sealed class MonitorAnswer implements Answer {}

/// A monitor stopped, or why it was not.
sealed class StopMonitorAnswer implements Answer {}

/// chord's refusal, which the agent reads as the call's failure.
final class Refused
    implements
        SpawnAnswer,
        OpenAnswer,
        MessageAnswer,
        CloseAnswer,
        ClearAnswer,
        MonitorAnswer,
        StopMonitorAnswer,
        RunTeamAnswer {
  const Refused(this.error);

  final String error;

  @override
  Map<String, Object?> toJson() => {'error': error};
}

/// An agent started, task or long-lived, or a team's lead: on the effort
/// it is on, and, when that is not the one asked for, the refusal as the
/// transcript says it; a team agent's with the mode its file set, a lead's
/// with its team.
final class Started implements SpawnAnswer, OpenAnswer, RunTeamAnswer {
  const Started({
    required this.id,
    required this.name,
    required this.agent,
    this.model,
    this.mode,
    this.team,
    this.effort,
    this.note,
    this.receipt,
  });

  final String id;
  final String name;
  final String agent;
  final String? model;
  final String? mode;
  final String? team;
  final String? effort;
  final String? note;

  /// A selected run's receipt, as it stood when the lead started.
  final Map<String, Object?>? receipt;

  /// This, where its start left it: on [effort], with [note].
  Started withEffort(String? effort, String? note) => Started(
    id: id,
    name: name,
    agent: agent,
    model: model,
    mode: mode,
    team: team,
    effort: effort,
    note: note,
    receipt: receipt,
  );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'agent': agent,
    'model': ?model,
    'mode': ?mode,
    'team': ?team,
    'effort': ?effort,
    'note': ?note,
    'receipt': ?receipt,
  };
}

/// A selected run refused, by chord's id for its launch once it was
/// admitted, with its receipt as it stood.
final class RunRefused implements RunTeamAnswer {
  /// Refused for [error], the launch [id] with [receipt] once admitted.
  const RunRefused(this.error, {this.id, this.receipt});

  final String error;
  final String? id;
  final Map<String, Object?>? receipt;

  @override
  Map<String, Object?> toJson() => {
    'error': error,
    'id': ?id,
    'receipt': ?receipt,
  };
}

/// Whether a message went straight into its recipient or waits as its next
/// turn.
enum Delivery { sent, queued }

/// A message delivered; [to] is the recipient's name, for a message the
/// parent sent.
final class Delivered implements MessageAnswer {
  const Delivered(this.delivered, {this.to});

  final Delivery delivered;
  final String? to;

  @override
  Map<String, Object?> toJson() => {'delivered': delivered.name, 'to': ?to};
}

/// A long-lived agent or a task closed, by its name.
final class Closed implements CloseAnswer {
  const Closed(this.closed);

  final String closed;

  @override
  Map<String, Object?> toJson() => {'closed': closed};
}

/// A task of the caller's that had already ended.
final class Ended implements CloseAnswer {
  const Ended(this.ended);

  final String ended;

  @override
  Map<String, Object?> toJson() => {'ended': ended};
}

/// A child cleared: its name and id, and the messages queued to it that
/// were not delivered, said so.
final class Cleared implements ClearAnswer {
  const Cleared(this.cleared, this.id, {this.dropped});

  final String cleared;
  final String id;
  final String? dropped;

  @override
  Map<String, Object?> toJson() => {
    'cleared': cleared,
    'id': id,
    'dropped': ?dropped,
  };
}

/// A monitor started, as `monitor` answers it.
final class StartedMonitor implements MonitorAnswer {
  const StartedMonitor(this.id, this.description, this.timeoutMs);

  final String id;
  final String description;
  final int timeoutMs;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'timeout_ms': timeoutMs,
  };
}

/// A monitor the agent stopped, as `stop_monitor` answers it.
final class StoppedMonitor implements StopMonitorAnswer {
  const StoppedMonitor(this.id, this.description, this.events, this.ranMs);

  final String id;
  final String description;
  final int events;
  final int ranMs;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'events': events,
    'ran_ms': ranMs,
  };
}

/// A long-lived agent open in a session, as `list_sessions` gives it.
typedef ChildView = ({String id, String name, String runtime, String? model});

/// The window's session, as the tools read it.
typedef OpenSessionView = ({
  int key,
  String runtime,

  /// The agent's id for it; null while it still starts.
  String? id,

  /// The model it uses, by the agent's id; null until the agent names one.
  String? model,

  /// Its long-lived agents, in the order they opened.
  List<ChildView> children,
});

/// What the tools read of the window, and ask of it.
abstract interface class WindowView {
  /// The sessions open in the window.
  List<OpenSessionView> sessions();

  /// Every runtime chord can start, by the name a session is opened with.
  List<String> runtimes();

  /// A runtime's models and modes: from a session of it, open or read
  /// earlier, or, when [probe] is set, from one opened for the purpose and
  /// closed. Null when none is known and [probe] is not set. [key] is the
  /// session asking: the directory it works in decides how the runtime
  /// starts, or that it does not.
  Future<RuntimeOffer?> offer(String runtime, {required bool probe, int? key});

  /// Starts a task agent for the caller: the main session or its child.
  Future<SpawnAnswer> spawn(Caller caller, SpawnArgs args);

  /// Opens a long-lived agent for the main session [key]; [caller] is
  /// refused once its session has been let go.
  Future<OpenAnswer> open(int key, SpawnArgs args, Caller caller);

  /// A child's message to its parent; [queued] is called if one sent into
  /// its running turn goes as the next turn after all.
  MessageAnswer message(Caller caller, String text, void Function() queued);

  /// A parent's message to its child [to], by id or name; [queued] as for
  /// [message].
  MessageAnswer tell(
    Caller caller,
    String to,
    String text,
    void Function() queued,
  );

  /// Closes the caller's child or task [to], by id or name.
  CloseAnswer close(Caller caller, String to);

  /// `clear_agent`: a child of the caller's cleared.
  Future<ClearAnswer> clear(Caller caller, String to);

  /// Tells the caller's session a tool was served to it, as it answered.
  void served(Caller caller, ChordCall call);

  /// Where a call the caller is served again later goes, found now: a task
  /// may have ended by then, and its row is still to be told.
  void Function(ChordCall call) servedLater(Caller caller);

  /// Starts a monitor for the caller, as `monitor` asks.
  Future<MonitorAnswer> monitor(Caller caller, MonitorArgs args);

  /// Stops the caller's own monitor [id].
  StopMonitorAnswer stopMonitor(Caller caller, String id);

  /// The caller's own monitors still running.
  List<RunningMonitor> monitors(Caller caller);

  /// Asks the person a question of chord's own in the caller's session's
  /// permission box: the option picked, by its id, or null once the
  /// question is withdrawn.
  Future<String?> askPerson(
    Caller caller, {
    required String title,
    required String detail,
    required List<acp.PermissionOption> options,
    required SaveBox save,
    required CancellationToken signal,
  });

  /// Where the caller's settings files are and how the window shows them,
  /// and the runtime of the session that asks, which the box names.
  ({SettingsWhere where, String agent}) settingsWhere(Caller caller);

  /// Takes the one place for a `settings` change waiting on the person:
  /// how to give it back, or null while another holds it.
  void Function()? claimSettingsBox();

  /// A `settings` write was saved: the window takes up what it can at once.
  void settingSaved(List<String> path, SettingChange change);

  /// The teams saved for the caller's directory, and the leads of the runs
  /// open in its session, by team.
  Future<TeamsFound> teams(Caller caller);

  /// The providers' limits read now, for [agents] or claude and codex;
  /// null where the window reads none.
  Future<Budgets>? budgets(
    Caller caller,
    List<String>? agents,
    CancellationToken cancelled,
  );

  /// Hands a team a job: its lead opened as a child of the caller's.
  Future<RunTeamAnswer> runTeam(
    Caller caller,
    RunTeamArgs args, {
    Object? selection,
  });

  /// A lead opens a member its team's file has.
  Future<OpenAnswer> openMember(Caller caller, MemberArgs args);

  /// Where a team named [name] is saved for the caller's directory, and the
  /// team saved under that name now, which a proposal would replace.
  Future<TeamPlaces> teamPlaces(Caller caller, String name);
}

/// A team's lead or member as `list_teams` lists it.
Map<String, Object?> _agentRow(Map<String, String> agent) => {
  'agent': agent['agent'],
  'model': ?agent['model'],
  'effort': ?agent['effort'],
  'mode': ?agent['mode'],
  'instructions': ?agent['instructions'],
};

/// `list_teams`' answer: each team, or why its file cannot be run, and
/// the runs open.
Map<String, Object?> teamsAnswer(TeamsFound teams) => {
  'runs': [
    for (final run in teams.runs)
      {'team': run.team, 'name': run.name, 'id': ?run.id},
  ],
  'teams': [
    for (final one in teams.found)
      if (one.team case final team?)
        {
          'name': one.name,
          'description': team.description,
          'body': team.body,
          'lead': _agentRow(team.lead.toMap()),
          'members': [
            for (final member in team.members)
              {
                'name': member.name,
                ..._agentRow(member.toMap()),
                'role': member.role,
              },
          ],
          'runs': [
            for (final run in teams.runs)
              if (run.team == one.name) run.name,
          ],
        }
      else
        {
          'name': one.name,
          'problem': '${one.problem}; it cannot run until its file is fixed',
        },
  ],
};

/// What a tool call answers: the text the model reads, whether it is the
/// call's failure, and the value beside the words, when the words are not
/// it.
typedef ToolResult = ({
  String text,
  bool isError,
  Map<String, Object?>? structured,
});

/// One tool as a caller is given it.
final class ToolSpec {
  const ToolSpec(
    this.tool,
    this.description,
    this.inputSchema,
    this.call, {
    this.until,
  });

  final ChordTool tool;
  final String description;

  /// Its arguments' JSON Schema, as the original's SDK lists it; null for
  /// a tool that takes none.
  final Map<String, Object?>? inputSchema;

  /// Serves a call with [input], checked against [inputSchema].
  final Future<ToolResult> Function(Map<String, Object?> input) call;

  /// Serves a call that waits on the person until the request is
  /// cancelled; the server calls it in place of [call] where it is given.
  final Future<ToolResult> Function(
    Map<String, Object?> input,
    CancellationToken cancelled,
  )?
  until;

  /// The name an agent calls it by.
  String get name => tool.wire;
}

/// A row of `list_agents`: a runtime with what it offers, or a note on why
/// that is not given.
Map<String, Object?> _row(String name, RuntimeOffer? offer) => switch (offer) {
  null => {
    'name': name,
    'note':
        'models and modes not read yet; list_agents with agent "$name" '
        'reads them',
  },
  OfferError(:final error) => {
    'name': name,
    'note': 'models and modes could not be read: $error',
  },
  Offer() => {
    'name': name,
    'models': [
      for (final model in offer.models)
        {
          'id': model.id,
          'name': model.name,
          if (model.efforts case final efforts?)
            'efforts': [for (final e in efforts) _named(e.id, e.name)],
          'effort': ?model.effort,
        },
    ],
    'current': ?offer.current,
    if (offer.modes case final modes?)
      'modes': [for (final m in modes) _named(m.id, m.name)],
    'currentMode': ?offer.currentMode,
    if (offer.efforts case final efforts?)
      'efforts': [for (final e in efforts) _named(e.id, e.name)],
    'currentEffort': ?offer.currentEffort,
  },
};

Map<String, Object?> _named(String id, String name) => {'id': id, 'name': name};

/// Every runtime with the models and modes known without starting
/// anything, or, for [agent], that runtime's, a session started to read
/// them if need be. Probing every runtime unasked would install and start
/// each of the registry's agents on the person's machine.
Future<Map<String, Object?>> agentsAnswer(
  WindowView window, {
  String? agent,
  int? key,
}) async {
  final runtimes = window.runtimes();
  if (agent != null) {
    if (!runtimes.contains(agent)) {
      return {
        'agents': [
          {
            'name': agent,
            'note':
                'chord knows no runtime named $agent; list_agents without '
                'an agent names every one',
          },
        ],
      };
    }
    return {
      'agents': [_row(agent, await window.offer(agent, probe: true, key: key))],
    };
  }
  return {
    'agents': await Future.wait([
      for (final name in runtimes)
        window
            .offer(name, probe: false, key: key)
            .then((offer) => _row(name, offer)),
    ]),
  };
}

/// `list_sessions`'s answer: the window's session, the caller's marked.
Map<String, Object?> sessionsAnswer(Caller caller) => {
  'sessions': [
    for (final open in caller.window.sessions())
      {
        'id': open.id,
        'runtime': open.runtime,
        'model': open.model,
        if (open.key == caller.key && caller.role == Role.person) 'you': true,
        if (open.children.isNotEmpty)
          'agents': [
            for (final child in open.children)
              {
                'id': child.id,
                'name': child.name,
                'runtime': child.runtime,
                'model': child.model,
              },
          ],
      },
  ],
};

const _indented = JsonEncoder.withIndent('  ');

/// The answer, after the caller's session hears what was served: the value
/// as JSON, or, given [said], what it says for the model, with the value as
/// structured content.
ToolResult serve(
  Caller caller,
  ChordTool tool,
  Map<String, Object?> input,
  Object value, {
  String Function(Object value)? said,
  String? asked,
}) {
  final json = value is Answer ? value.toJson() : value;
  final error = value is Refused ? value.error : null;
  final task = tool == ChordTool.spawnTask && value is Started
      ? value.id
      : null;
  caller.window.served(
    caller,
    ChordCall(
      tool: tool,
      input: input,
      answer: error == null ? json : null,
      error: error,
      task: task,
      asked: asked,
      queued:
          tool == ChordTool.sendMessage &&
          value is Delivered &&
          value.delivered == Delivery.queued,
    ),
  );
  if (error != null) return (text: error, isError: true, structured: null);
  if (said == null) {
    return (text: _indented.convert(json), isError: false, structured: null);
  }
  return (
    text: said(value),
    isError: false,
    structured: json as Map<String, Object?>,
  );
}

/// `send_message` served. A message sent into its recipient's running turn
/// that goes as the next turn after all, as when the turn ended on the way,
/// is served again as queued in place of the first, so the sender's row
/// says it waited; the agent's answer, given already, stays as it was.
ToolResult _sendMessage(
  Caller caller,
  Map<String, Object?> input,
  MessageAnswer Function(void Function() queued) send,
) {
  final asked = const Uuid().v4();
  final later = caller.window.servedLater(caller);
  late final MessageAnswer value;
  value = send(
    () => later(
      ChordCall(
        tool: ChordTool.sendMessage,
        input: input,
        answer: value.toJson(),
        queued: true,
        asked: asked,
      ),
    ),
  );
  return serve(caller, ChordTool.sendMessage, input, value, asked: asked);
}

/// What a tool that opens, runs or closes agents answers a fork.
const forkRefused = Refused(
  'This tool works only from main and its agents, not from a fork.',
);

/// `close_agent`'s answer for the model.
String closedText(Object answer) => answer is Ended
    ? '${answer.ended} has already ended'
    : _indented.convert((answer as Answer).toJson());

/// `clear_agent`'s answer for the model.
String clearedText(Object answer) {
  final cleared = answer as Cleared;
  final dropped = cleared.dropped == null ? '' : ' ${cleared.dropped}';
  return '${cleared.cleared} (id ${cleared.id}) has a fresh session; it '
      'knows nothing of earlier turns.$dropped';
}

const _draft07 = 'http://json-schema.org/draft-07/schema#';

/// An object schema of string [properties], each with its description, as
/// the original's SDK lists it: `$schema` first, the required in order.
Map<String, Object?> _schema(
  Map<String, String> properties, {
  required List<String> required,
}) => {
  r'$schema': _draft07,
  'type': 'object',
  'properties': {
    for (final MapEntry(:key, :value) in properties.entries)
      key: {'type': 'string', 'description': value},
  },
  'required': required,
};

const _modelWords =
    "A model the runtime offers, by its id; the runtime's own if left out";
const _effortWords =
    'An effort the runtime offers for that model, by its id, as list_agents '
    "lists them (`efforts`); the runtime's own if left out. One it does not "
    'take starts it on its own, and the answer says so';
const _agentWords = 'The runtime, as list_agents names it';
const _toWords = 'The agent, by the id open_agent answered or by its name';

ToolSpec _listAgents(Caller caller) => ToolSpec(
  ChordTool.listAgents,
  'The agent runtimes chord can start, and the models and modes each '
  'offers, with the efforts of the model a session of it was read on '
  '(`efforts`, and `effort` for the one it is on), as agents offer '
  "each model's own. Without `agent`, they are given for runtimes "
  'already read; name one to read its models and modes, which may '
  'start it briefly.',
  _schema({
    'agent':
        'A runtime to read the models and modes of, as list_agents names it',
  }, required: const []),
  (input) async => serve(
    caller,
    ChordTool.listAgents,
    input,
    await agentsAnswer(
      caller.window,
      agent: input['agent'] as String?,
      key: caller.key,
    ),
  ),
);

/// `get_budgets`' arguments, as the original's SDK lists them.
const _budgetsSchema = {
  r'$schema': _draft07,
  'type': 'object',
  'properties': {
    'agents': {
      'description': 'Runtime IDs from list_agents to read only those',
      'maxItems': 128,
      'type': 'array',
      'items': {'type': 'string', 'minLength': 1, 'maxLength': 128},
    },
  },
};

/// The answer, or the call's failure where the window read nothing.
Future<ToolResult> _readBudgets(
  Caller caller,
  Map<String, Object?> input,
  CancellationToken cancelled,
) async {
  Budgets? budgets;
  try {
    budgets = await caller.window.budgets(
      caller,
      (input['agents'] as List?)?.cast<String>(),
      cancelled,
    );
  } on Object {
    budgets = null;
  }
  if (budgets == null) {
    return serve(
      caller,
      ChordTool.getBudgets,
      input,
      const Refused('The limits could not be read.'),
    );
  }
  return serve(
    caller,
    ChordTool.getBudgets,
    input,
    budgetsJson(budgets),
    said: (value) => _indented.convert(value),
  );
}

ToolSpec _getBudgets(Caller caller) => ToolSpec(
  ChordTool.getBudgets,
  "Reads each provider's usage limits now: per window, the percent used "
  'and when it resets, or why the provider could not be read. Providers '
  'are read in parallel, waiting up to 10 s each. Omit agents to read '
  'claude and codex; [] reads none.',
  _budgetsSchema,
  (input) => _readBudgets(caller, input, CancellationToken()),
  until: (input, cancelled) => _readBudgets(caller, input, cancelled),
);

ToolSpec _listSessions(Caller caller) => ToolSpec(
  ChordTool.listSessions,
  'The session chord runs: its id, runtime and model, and the '
  'long-lived agents open in it, by id and name; yours marked `you`.',
  null,
  (_) async =>
      serve(caller, ChordTool.listSessions, const {}, sessionsAnswer(caller)),
);

ToolSpec _spawnTask(Caller caller) => ToolSpec(
  ChordTool.spawnTask,
  'Starts a task agent: another agent, on any runtime '
  'list_agents names and any model it offers, does one job in this '
  'directory and reports. The answer is its id at once, or, given an '
  'effort, once it has started on it or been refused it; its report '
  'comes to you later as a message, <message from="…">…</message>, '
  'once its first turn ends.',
  _schema(
    {
      'agent': _agentWords,
      'model': _modelWords,
      'effort': _effortWords,
      'prompt': 'The job, in full',
      'name':
          "A short name for it on screen; the prompt's first line if left out",
    },
    required: const ['agent', 'prompt'],
  ),
  (input) async => serve(
    caller,
    ChordTool.spawnTask,
    input,
    await caller.window.spawn(caller, SpawnArgs.of(input)),
  ),
);

ToolSpec _openAgent(Caller caller) => ToolSpec(
  ChordTool.openAgent,
  'Opens a long-lived agent: another agent, on any runtime '
  'list_agents names and any model it offers, in this directory, with '
  'the prompt as its first turn. It stays open: you and the person can '
  'both talk to it, send_message reaches it and close_agent ends it. '
  'The answer is its id at once, or, given an effort, once it has '
  'started on it or been refused it; what it sends you comes later '
  'as a message, <message from="…">…</message>.',
  _schema(
    {
      'agent': _agentWords,
      'model': _modelWords,
      'effort': _effortWords,
      'prompt': 'Its first prompt, in full',
      'name':
          'A short name for it, which messages and the screen use; the '
          'runtime if left out',
    },
    required: const ['agent', 'prompt'],
  ),
  (input) async => serve(
    caller,
    ChordTool.openAgent,
    input,
    caller.fork
        ? forkRefused
        : await caller.window.open(caller.key, SpawnArgs.of(input), caller),
  ),
);

ToolSpec _tellAgent(Caller caller) => ToolSpec(
  ChordTool.sendMessage,
  'Sends a message to a long-lived agent you opened. While it '
  'works, the message goes into the turn it is in, where its runtime '
  'takes that, after any question it waits on is answered; otherwise '
  'it reaches it as a turn of its own, queued behind that turn. The '
  'answer says it was delivered, not what it replied, which comes to '
  'you as a message.',
  _schema(
    {'to': _toWords, 'text': 'What to tell it'},
    required: const ['to', 'text'],
  ),
  (input) async => _sendMessage(
    caller,
    input,
    (queued) => caller.window.tell(
      caller,
      input['to'] as String,
      input['text'] as String,
      queued,
    ),
  ),
);

ToolSpec _messageParent(Caller caller) => ToolSpec(
  ChordTool.sendMessage,
  'Sends a message to the agent that started you, while '
  'you work. It goes into the turn that agent is in, where its runtime '
  'takes that, or else reaches it as a turn of its own; your last '
  'message when you finish is your report and goes to it without this.',
  _schema({'text': 'What to tell it'}, required: const ['text']),
  (input) async => _sendMessage(
    caller,
    input,
    (queued) => caller.window.message(caller, input['text'] as String, queued),
  ),
);

ToolSpec _closeAgent(Caller caller) {
  final person = closesAgents(caller);
  return ToolSpec(
    ChordTool.closeAgent,
    person
        ? 'Closes a long-lived agent you opened, stopping what it is '
              'doing; it takes no more messages. Also stops a task you '
              'started with spawn_task, which then sends no report; one that '
              'has already ended is said to have.'
        : 'Stops a task you started with spawn_task, which then sends no '
              'report; one that has already ended is said to have. It closes '
              'no other agent.',
    _schema(
      {
        'to': person
            ? 'The agent, by the id open_agent answered or by its name; '
                  'or the task, by the id spawn_task answered or by its name'
            : 'The task, by the id spawn_task answered or by its name',
      },
      required: const ['to'],
    ),
    (input) async => serve(
      caller,
      ChordTool.closeAgent,
      input,
      caller.fork
          ? forkRefused
          : caller.window.close(caller, input['to'] as String),
      said: closedText,
    ),
  );
}

ToolSpec _clearAgent(Caller caller) => ToolSpec(
  ChordTool.clearAgent,
  'Clears a long-lived agent you opened: its turn stops and it gets a '
  'fresh session that knows nothing of earlier turns, with the same '
  "id and name. Your next message is its first; a team member's "
  "carries its instructions, as open_agent's first message does. The "
  'answer comes once the fresh session is up.',
  _schema({'to': _toWords}, required: const ['to']),
  (input) async => serve(
    caller,
    ChordTool.clearAgent,
    input,
    caller.fork
        ? forkRefused
        : await caller.window.clear(caller, input['to'] as String),
    said: clearedText,
  ),
);

ToolSpec _listTeams(Caller caller) => ToolSpec(
  ChordTool.listTeams,
  'The teams saved for this project and every project: '
  "each one's description, shared body, lead/member instructions, "
  'configuration including effort, roles, and open runs. Read these '
  'stored instructions before run_team. When the instructions or job '
  'make resources relevant, read get_budgets and list_agents before '
  'choosing per-run settings. Otherwise selection is not required.',
  null,
  (_) async => serve(
    caller,
    ChordTool.listTeams,
    const {},
    teamsAnswer(await caller.window.teams(caller)),
  ),
);

/// A file, whole and as the window shows it.
typedef PlacedFile = ({String file, String shown});

/// What `propose_team` reads of where a team goes: the runtime of the
/// session that proposes, which the box names; the project's file and the
/// user's, none for a person with no config home; and the team saved under
/// the name, project's over user's, its team none where the file fails its
/// check.
typedef TeamPlaces = ({
  String agent,
  PlacedFile project,
  PlacedFile? user,
  ({String file, String shown, Team? team})? saved,
});

/// What `propose_team` serves while the save box is open, and with the
/// person's answer: a new team or a change to one saved, the files each
/// choice writes, as shown, the team it changes, and once answered where it
/// was saved, or `false` when the person will say what to change.
final class ProposeAnswer implements Answer {
  const ProposeAnswer({
    required this.change,
    required this.files,
    this.before,
    this.saved,
  });

  /// A change to a team saved, not a new one.
  final bool change;
  final ({String? project, String? user}) files;
  final Team? before;

  /// Where it was saved, or false; null while the box is open.
  final Object? saved;

  /// This, as the person answered it.
  ProposeAnswer answered(Object saved) =>
      ProposeAnswer(change: change, files: files, before: before, saved: saved);

  @override
  Map<String, Object?> toJson() => {
    'proposal': change ? 'change' : 'new',
    'files': {'project': ?files.project, 'user': ?files.user},
    'before': ?before?.toJson(),
    'saved': ?saved,
  };
}

/// The save box's choices, by their ids.
const _saveProject = 'project',
    _saveUser = 'user',
    _saveReplace = 'replace',
    _saveChange = 'change';

/// `propose_team`: the proposal checked as a team file is, drawn as it
/// waits ([shown]), the save box's question asked, and the file chord
/// writes on a yes, the agent never writing it. A refusal is the check's
/// first problem, or a write that failed.
Future<Object> proposeTeam(
  Caller caller,
  Map<String, Object?> input,
  CancellationToken signal,
  void Function(ProposeAnswer shown) shown, [
  String? asked,
]) async {
  final checked = checkProposal(input, caller.window.runtimes());
  final team = checked.team;
  if (team == null) return Refused(checked.problem!);
  final name = checked.name!;
  final places = await caller.window.teamPlaces(caller, name);
  final (:agent, :project, :user, :saved) = places;
  final proposal = saved == null
      ? ProposeAnswer(
          change: false,
          files: (project: project.shown, user: user?.shown),
        )
      : ProposeAnswer(
          change: true,
          files: saved.file == project.file
              ? (project: saved.shown, user: null)
              : (project: null, user: saved.shown),
          before: saved.team,
        );
  final change = 'tell $agent what to change';
  acp.PermissionOption option(String id, String name, String kind) =>
      acp.PermissionOption.fromJson({
        'optionId': id,
        'name': name,
        'kind': kind,
      });
  shown(proposal);
  final picked = await caller.window.askPerson(
    caller,
    title: 'Team($name)',
    detail: teamText(team),
    options: saved == null
        ? [
            option(_saveProject, 'Yes, for this project', 'allow_once'),
            if (user != null)
              option(_saveUser, 'Yes, for every project', 'allow_always'),
            option(_saveChange, 'No, $change', 'reject_once'),
          ]
        : [
            option(_saveReplace, 'Yes, in ${saved.shown}', 'allow_once'),
            option(_saveChange, 'No, $change', 'reject_once'),
          ],
    save: SaveBox(
      question: '${saved == null ? 'Save' : 'Replace'} team $name?',
      files: saved == null
          ? {_saveProject: project.shown, _saveUser: ?user?.shown}
          : const {},
      escape: change,
      asked: asked,
    ),
    signal: signal,
  );
  if (picked == null) {
    return const Refused(
      'The person was not asked to the end; nothing was saved',
    );
  }
  if (picked == _saveChange) return proposal.answered(false);
  final PlacedFile? target = switch (picked) {
    _saveReplace =>
      saved == null ? null : (file: saved.file, shown: saved.shown),
    _saveUser => user,
    _ => project,
  };
  if (target == null) {
    return const Refused('Nowhere to save it; nothing was saved');
  }
  try {
    await saveTeam(target.file, team);
  } on Object catch (error) {
    return Refused('${target.shown} was not saved: ${_errorWords(error)}');
  }
  return proposal.answered(target.shown);
}

/// A failed write in words: the OS's, as a settings file's failure says it.
String _errorWords(Object error) => switch (error) {
  FileSystemException(:final osError?) when osError.message.isNotEmpty =>
    osError.message,
  FileSystemException(:final message) => message,
  _ => '$error',
};

/// What `propose_team` says to the agent, once the person answered.
String proposeText(Object answer) => (answer as ProposeAnswer).saved is String
    ? 'Saved to ${answer.saved}.'
    : 'The person did not save it; they will say what to change.';

/// `propose_team`'s arguments as the original's SDK lists them.
const _proposalSchema = {
  '\$schema': 'http://json-schema.org/draft-07/schema#',
  'type': 'object',
  'properties': {
    'name': {
      'type': 'string',
      'description':
          'The team\'s name and its file\'s: a lowercase letter, then up to 23 of a-z, 0-9 and -; not main or chord',
    },
    'description': {
      'type': 'string',
      'description': 'What the team is for, one line of at most 200 characters',
    },
    'lead': {
      'type': 'object',
      'properties': {
        'agent': {
          'type': 'string',
          'description': 'The runtime, as list_agents names it',
        },
        'model': {
          'description':
              'A model id list_agents gives for the runtime; the runtime\'s own if left out',
          'type': 'string',
        },
        'effort': {
          'description':
              'An effort the runtime offers for that model, by its id, as list_agents lists them (`efforts`); the runtime\'s own if left out. One it does not take starts the agent on its own',
          'type': 'string',
        },
        'mode': {
          'description':
              'A mode id list_agents gives for the runtime: the permissions it works under, which the person approves; the runtime\'s own if left out',
          'type': 'string',
        },
        'instructions': {
          'description':
              'How the lead works: when it opens which member, what it does itself',
          'type': 'string',
        },
      },
      'required': ['agent'],
      'description':
          'The lead, which opens the members, names who edits which files and reports to main',
    },
    'members': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description':
                'A lowercase letter, then up to 15 of a-z, 0-9 and -; unique, not main, chord or the team\'s name',
          },
          'role': {
            'type': 'string',
            'description': 'What it does, one line of at most 80',
          },
          'agent': {
            'type': 'string',
            'description': 'The runtime, as list_agents names it',
          },
          'model': {
            'description':
                'A model id list_agents gives for the runtime; the runtime\'s own if left out',
            'type': 'string',
          },
          'effort': {
            'description':
                'An effort the runtime offers for that model, by its id, as list_agents lists them (`efforts`); the runtime\'s own if left out. One it does not take starts the agent on its own',
            'type': 'string',
          },
          'mode': {
            'description':
                'A mode id list_agents gives for the runtime: the permissions it works under, which the person approves; the runtime\'s own if left out',
            'type': 'string',
          },
          'instructions': {
            'type': 'string',
            'description': 'How it does its part, in full',
          },
        },
        'required': ['name', 'role', 'agent', 'instructions'],
      },
      'description': '1 to 8 members',
    },
    'body': {
      'type': 'string',
      'description':
          'How the team works, in markdown, which every agent of it reads: the steps, a "Who edits what" section (one writer per file, how members agree on files, that other runs of a team may work here too) and a "Reporting" section (when the lead writes to main)',
    },
  },
  'required': ['name', 'description', 'lead', 'members', 'body'],
};

ToolSpec _proposeTeam(Caller caller) {
  Future<ToolResult> serveProposal(
    Map<String, Object?> input,
    CancellationToken cancelled,
  ) async {
    if (caller.fork) {
      return serve(caller, ChordTool.proposeTeam, input, forkRefused);
    }
    final asked = const Uuid().v4();
    final answer = await proposeTeam(
      caller,
      input,
      cancelled,
      (shown) => caller.window.served(
        caller,
        ChordCall(
          tool: ChordTool.proposeTeam,
          input: input,
          answer: shown.toJson(),
          pending: true,
          asked: asked,
        ),
      ),
      asked,
    );
    return serve(
      caller,
      ChordTool.proposeTeam,
      input,
      answer,
      said: proposeText,
      asked: asked,
    );
  }

  return ToolSpec(
    ChordTool.proposeTeam,
    'Proposes a team for the person to save: a lead and its '
    'members, each on a runtime, model, effort and mode list_agents '
    'gives, and how the team works. chord draws it and asks the person '
    'to save it for this project, for every project, or to tell you '
    'what to change; chord writes the file, not you. Proposing a team under '
    "a saved team's name proposes a change to it. The answer says where "
    'it was saved, or that the person will say what to change: then end '
    'your turn and wait for their words. A team that fails the check is '
    'refused with its first problem; correct it and call again.',
    _proposalSchema,
    (input) => serveProposal(input, CancellationToken()),
    until: serveProposal,
  );
}

ToolSpec _runTeam(Caller caller) => ToolSpec(
  ChordTool.runTeam,
  'Hands a saved team a job. chord opens its lead as a '
  'long-lived agent of yours, named after the team (a second run of '
  "a running team is `<team> 2`), with the team's instructions and "
  'the job as your message; the lead opens the members it needs. The '
  "answer is the lead's name at once, or, where the team gives the "
  'lead an effort, once it has started on it or been refused it; its '
  'reports come to you later as messages, send_message reaches it, and '
  'close_agent closes it with its members. Read list_teams instructions '
  'first. Omit selection to run saved composition. Optional selection '
  'changes this run only, preserving every saved role and instruction; '
  'provide a reason that preserves their requirements and explains '
  'uncertainty. Call get_budgets when instructions or the job make '
  'resources matter. There is no automatic retry, substitution or '
  'saved-team rewrite.',
  _runTeamSchema,
  (input) async {
    final args = (team: input['team'] as String, job: input['job'] as String);
    final selection = input['selection'];
    // Records keep our declared fields; the agent's input stays untouched.
    final recorded = {
      'team': args.team,
      'job': args.job,
      'selection': ?selection,
    };
    if (caller.fork) {
      return serve(caller, ChordTool.runTeam, recorded, forkRefused);
    }
    // With a selection the call is strict: no other field than these.
    if (input.containsKey('selection') &&
        input.keys.any(
          (key) => !const ['team', 'job', 'selection'].contains(key),
        )) {
      return serve(
        caller,
        ChordTool.runTeam,
        recorded,
        const Refused('Invalid run selection. No run started.'),
      );
    }
    final result = await caller.window.runTeam(
      caller,
      args,
      selection: selection,
    );
    final receipt = switch (result) {
      Started(:final receipt) => receipt,
      RunRefused(:final receipt) => receipt,
      _ => null,
    };
    if (receipt == null) {
      return serve(
        caller,
        ChordTool.runTeam,
        recorded,
        result is RunRefused ? Refused(result.error) : result,
      );
    }
    // A selected run's call is served under its run id, the receipt with it.
    final error = result is RunRefused ? result.error : null;
    final json = result.toJson();
    caller.window.served(
      caller,
      ChordCall(
        tool: ChordTool.runTeam,
        input: recorded,
        asked: receipt['runId'] as String,
        answer: json,
        error: error,
      ),
    );
    return (
      text: _indented.convert(json),
      isError: error != null,
      structured: json,
    );
  },
);

/// `run_team`'s arguments as the original's SDK lists them, `selection`
/// with them.
final Map<String, Object?> _runTeamSchema = () {
  final schema = (jsonDecode(_runTeamSchemaText) as Map)
      .cast<String, Object?>();
  // `$schema` first, as G2 lists every schema.
  return {r'$schema': schema[r'$schema'], ...schema..remove(r'$schema')};
}();

const _runTeamSchemaText =
    r'''{"type":"object","properties":{"team":{"type":"string","description":"The team, as list_teams names it"},"job":{"type":"string","description":"The job, in full: what to do, where, and when to report"},"selection":{"type":"object","properties":{"reason":{"type":"string","minLength":1,"maxLength":500,"description":"Explain the per-run choice, uncertainties and preservation of all saved role/instruction requirements."},"lead":{"description":"Overrides for the saved lead in this run only.","type":"object","properties":{"agent":{"description":"Runtime ID from list_agents; omitted fields inherit saved values only on the same runtime. A runtime change requires destination model and mode, plus effort when the saved role requests it.","type":"string","minLength":1,"maxLength":128},"model":{"description":"Supported destination model ID; no cross-runtime inheritance.","type":"string","minLength":1,"maxLength":128},"effort":{"description":"Supported soft effort request, never an exact-effort guarantee.","type":"string","minLength":1,"maxLength":128},"mode":{"description":"Supported exact destination mode ID; do not infer permission equivalence across runtimes.","type":"string","minLength":1,"maxLength":128}},"additionalProperties":false},"members":{"description":"Overrides keyed by existing saved member names; preserve every member and instruction.","type":"object","propertyNames":{"type":"string","minLength":1,"maxLength":128},"additionalProperties":{"type":"object","properties":{"agent":{"description":"Runtime ID from list_agents; omitted fields inherit saved values only on the same runtime. A runtime change requires destination model and mode, plus effort when the saved role requests it.","type":"string","minLength":1,"maxLength":128},"model":{"description":"Supported destination model ID; no cross-runtime inheritance.","type":"string","minLength":1,"maxLength":128},"effort":{"description":"Supported soft effort request, never an exact-effort guarantee.","type":"string","minLength":1,"maxLength":128},"mode":{"description":"Supported exact destination mode ID; do not infer permission equivalence across runtimes.","type":"string","minLength":1,"maxLength":128}},"additionalProperties":false}}},"required":["reason"],"additionalProperties":false,"description":"Optional frozen per-run configuration. Current hard constraints apply to every effective selected role, including inherited roles: omitted constraints add no restriction, an explicit empty allowlist denies. Omitted selection uses the unchanged direct saved path outside selection policy. Preferences are advisory, not permission or payment grants. Unknown fields or member names refuse before launch; no null/reset shorthand."}},"required":["team","job"],"$schema":"http://json-schema.org/draft-07/schema#","additionalProperties":{}}''';

ToolSpec _openMember(Caller caller) => ToolSpec(
  ChordTool.openAgent,
  "Opens one of your team's members, by its name in the team, on "
  'the runtime, model, effort and mode the team gives it, with the '
  "team's instructions and your prompt as its first message. It "
  'stays open: send_message reaches it, and close_agent closes it. '
  'The answer is its id at once, or, where the team gives it an '
  'effort, once it has started on it or been refused it; what it '
  'sends you comes later as a message.',
  _schema(
    {
      'member': 'The member, by its name in the team',
      'prompt': 'Its first message from you, in full',
    },
    required: const ['member', 'prompt'],
  ),
  (input) async => serve(
    caller,
    ChordTool.openAgent,
    input,
    await caller.window.openMember(caller, (
      member: input['member'] as String,
      prompt: input['prompt'] as String,
    )),
  ),
);

ToolSpec _tellTeam(Caller caller) {
  final lead = caller.team == TeamSide.lead;
  return ToolSpec(
    ChordTool.sendMessage,
    lead
        ? 'Sends a message to main, to one of your open members, or to the '
              "lead of another team's run open in this session, by name. It "
              'goes into the turn its recipient is in, where the runtime '
              'takes that, or else reaches it as a turn of its own; to an '
              "idle main, it starts main's turn. The answer says it was "
              'delivered, not what it replied, which comes to you as a '
              'message.'
        : 'Sends a message to your lead, or to another open member of your '
              'team, by name, directly: the lead does not see it. It goes '
              'into the turn its recipient is in, where the runtime takes '
              'that, or else reaches it as a turn of its own; the answer says '
              'it was delivered, not what it replied, which comes to you as a '
              'message.',
    _schema(
      {
        'to': lead
            ? "`main`, a member, or another run's lead, by name"
            : 'Your lead or another member, by name',
        'text': 'What to tell it',
      },
      required: const ['to', 'text'],
    ),
    (input) async => _sendMessage(
      caller,
      input,
      (queued) => caller.window.tell(
        caller,
        input['to'] as String,
        input['text'] as String,
        queued,
      ),
    ),
  );
}

/// `list_monitors`'s answer: the caller's own running monitors.
Map<String, Object?> monitorsAnswer(List<RunningMonitor> monitors) => {
  'monitors': [
    for (final RunningMonitor(:info, :events) in monitors)
      {
        'id': info.id,
        'description': info.description,
        'command': info.command,
        'started_at': DateTime.fromMillisecondsSinceEpoch(
          info.startedAt,
          isUtc: true,
        ).toIso8601String(),
        'events': events,
        'timeout_ms': info.timeoutMs,
      },
  ],
};

String _events(int count) =>
    count == 0 ? 'no events' : '$count ${count == 1 ? 'event' : 'events'}';

/// What the model reads of a monitor started.
String monitorText(Object answer) {
  final started = answer as StartedMonitor;
  return 'Started monitor ${started.id} (${started.description}); it times '
      'out in ${timeoutWords(started.timeoutMs)}. Its output does not come '
      'in this answer: each batch of lines (up to $eventLinesMax, gathered '
      'over $batchMs ms) reaches you later as a message from '
      '"${started.description} · monitor", and so does its end. Keep '
      'working. stop_monitor with id "${started.id}" stops it.';
}

/// What the model reads of a monitor it stopped.
String stopMonitorText(Object answer) {
  final stopped = answer as StoppedMonitor;
  return 'Stopped ${stopped.id} (${stopped.description}) after '
      '${formatElapsed(stopped.ranMs)} and ${_events(stopped.events)}.';
}

/// What the model reads of its running monitors, [now] epoch milliseconds.
String monitorsText(List<RunningMonitor> monitors, int now) => monitors.isEmpty
    ? 'No monitors running'
    : '${monitors.length} running: ${[for (final RunningMonitor(:info, :events) in monitors) '${info.id} ${info.description} '
            '(${formatElapsed(now - info.startedAt).split(' ').first}, '
            '${_events(events)})'].join(', ')}';

ToolSpec _startMonitor(Caller caller) => ToolSpec(
  ChordTool.monitor,
  'Run a shell command in the background and hear from it '
  'later. Each line it prints to stdout is an event; lines within '
  '$batchMs ms come together, up to $eventLinesMax, as one message '
  'from "<description> · monitor", which starts a new turn after the '
  "current one. This answer only gives the monitor's id. Use it to "
  'wait on something without polling: a log (`tail -n 0 -f app.log | '
  'grep --line-buffered ERROR`), a poll loop, a CI run. Print only '
  'what you need to hear: a monitor printing more than '
  '1,000 lines or ${floodBytes ~/ 1024} KiB within ${floodMs ~/ 1000} s is '
  'stopped. stderr is dropped unless you merge it (`2>&1`). It ends when '
  'the command exits, when timeout_ms passes, or with stop_monitor; you '
  'get a message when it ends on its own.',
  {
    r'$schema': _draft07,
    'type': 'object',
    'properties': {
      'command': {
        'type': 'string',
        'description':
            "Run through the person's shell in this session's "
            'directory',
      },
      'description': {
        'type': 'string',
        'description':
            'What it watches, at most 60 characters on one line; shown on '
            'every event',
      },
      'timeout_ms': {
        'type': 'number',
        // An agent once set it to a timer loop's length, so every
        // heartbeat was cut off as it came.
        'description':
            'A hard stop: chord stops the command when it passes, whatever '
            'it is doing, so make it longer than the command is meant to '
            "run (a loop's whole length and a margin). 1000 to 3600000; "
            '600000 (10 minutes) if left out',
      },
    },
    'required': const ['command', 'description'],
  },
  (input) async => serve(
    caller,
    ChordTool.monitor,
    input,
    await caller.window.monitor(caller, (
      command: input['command'] as String,
      description: input['description'] as String,
      timeoutMs: input['timeout_ms'] as num?,
    )),
    said: monitorText,
  ),
);

ToolSpec _stopMonitor(Caller caller) => ToolSpec(
  ChordTool.stopMonitor,
  'Stops a monitor you started, and what its command '
  'started; no message follows.',
  _schema(
    {'id': 'The id monitor answered, such as m1'},
    required: const ['id'],
  ),
  (input) async => serve(
    caller,
    ChordTool.stopMonitor,
    input,
    caller.window.stopMonitor(caller, input['id'] as String),
    said: stopMonitorText,
  ),
);

ToolSpec _listMonitors(Caller caller) => ToolSpec(
  ChordTool.listMonitors,
  "Your monitors still running: each one's id, "
  'description, command, when it started and how many events it sent.',
  null,
  (input) async {
    final monitors = caller.window.monitors(caller);
    return serve(
      caller,
      ChordTool.listMonitors,
      const {},
      monitorsAnswer(monitors),
      said: (_) => monitorsText(monitors, clock.now().millisecondsSinceEpoch),
    );
  },
);

/// The monitor tools, which a person's session and a long-lived child get,
/// last.
List<ToolSpec> _monitors(Caller caller) => [
  _startMonitor(caller),
  _stopMonitor(caller),
  _listMonitors(caller),
];

/// The monitor tools by name.
const monitorTools = [
  ChordTool.monitor,
  ChordTool.stopMonitor,
  ChordTool.listMonitors,
];

/// The tools [caller] is given, registered on the MCP server it talks to;
/// a new tool or role is a line here.
List<ToolSpec> toolsOf(Caller caller) => switch (caller.role) {
  Role.person => [
    _listAgents(caller),
    _getBudgets(caller),
    _listSessions(caller),
    _listTeams(caller),
    _spawnTask(caller),
    _openAgent(caller),
    _runTeam(caller),
    _proposeTeam(caller),
    _settings(caller),
    _tellAgent(caller),
    _closeAgent(caller),
    _clearAgent(caller),
    ..._monitors(caller),
  ],
  // A task ends with its first turn: a later event would reach nobody, and
  // a task of its own would outlive it.
  Role.child when caller.agent == null => [_messageParent(caller)],
  Role.child when caller.team == TeamSide.lead => [
    _listAgents(caller),
    _getBudgets(caller),
    _spawnTask(caller),
    _openMember(caller),
    _tellTeam(caller),
    _closeAgent(caller),
    _clearAgent(caller),
    ..._monitors(caller),
  ],
  Role.child when caller.team == TeamSide.member => [
    _listAgents(caller),
    _getBudgets(caller),
    _spawnTask(caller),
    _tellTeam(caller),
    _closeAgent(caller),
    ..._monitors(caller),
  ],
  Role.child => [
    _listAgents(caller),
    _getBudgets(caller),
    _spawnTask(caller),
    _messageParent(caller),
    _closeAgent(caller),
    ..._monitors(caller),
  ],
};

/// The tools a session of [role] is given, by name, as `/mcp` lists them;
/// a child's are a long-lived one's, as only those are picked in the
/// window.
List<ChordTool> toolNames(Role role) => switch (role) {
  Role.person => const [
    ChordTool.listAgents,
    ChordTool.getBudgets,
    ChordTool.listSessions,
    ChordTool.listTeams,
    ChordTool.spawnTask,
    ChordTool.openAgent,
    ChordTool.runTeam,
    ChordTool.proposeTeam,
    ChordTool.settings,
    ChordTool.sendMessage,
    ChordTool.closeAgent,
    ChordTool.clearAgent,
    ...monitorTools,
  ],
  Role.child => const [
    ChordTool.listAgents,
    ChordTool.getBudgets,
    ChordTool.spawnTask,
    ChordTool.sendMessage,
    ChordTool.closeAgent,
    ...monitorTools,
  ],
};

/// A window's one place for a `settings` change waiting on the person. A
/// box names only the path, so two at once could ask the same question over
/// each other's rows, and the box would not confirm the write it answers.
void Function()? Function() settingsBoxClaim() {
  var held = false;
  return () {
    if (held) return null;
    held = true;
    return () => held = false;
  };
}

/// The refusal of a change while another waits on the person.
const settingsBoxHeld =
    'Another settings change is waiting on the person; nothing was asked '
    'or saved. Ask again once they have answered';

/// A change in words: its file and its values, as the answer gives them.
String _settingDetail(SettingsChanged answer) {
  String value(Object? held) =>
      identical(held, absent) ? 'not set' : jsonEncode(held);
  return 'In ${answer.file}: ${value(answer.before)} becomes '
      '${value(answer.after)}.';
}

/// The settings box's choices, by their ids.
const _settingYes = 'yes', _settingNo = 'no';

/// A `settings` `set` or `remove`: checked, drawn as it waits ([shown]),
/// asked in chord's box whatever mode the runtime is in, and written on a
/// yes by chord, the agent never writing it. A [SettingsChanged], or a
/// [Refused].
Future<Object> changeSetting(
  Caller caller,
  List<String> path,
  SettingChange change,
  CancellationToken signal,
  void Function(SettingsChanged answer) shown,
  String asked,
) async {
  final (:where, :agent) = caller.window.settingsWhere(caller);
  final planned = await plannedSetting(
    where,
    path,
    change,
    caller.window.runtimes(),
  );
  if (planned is SettingsToolRefused) return Refused(planned.error);
  final PlannedSetting(:answer, :file) = planned as PlannedSetting;
  if (answer.unchanged) return answer;
  // No wait between the check and the claim, so two calls cannot both pass.
  final release = caller.window.claimSettingsBox();
  if (release == null) return const Refused(settingsBoxHeld);
  final shownKey = shownSettingPath(path);
  final word = changeWord(answer);
  final escape = 'tell $agent what to change';
  try {
    shown(answer);
    final picked = await caller.window.askPerson(
      caller,
      title: 'Settings($shownKey)',
      detail: _settingDetail(answer),
      options: [
        acp.PermissionOption.fromJson({
          'optionId': _settingYes,
          'name': 'Yes, in ${answer.file}',
          'kind': acp.PermissionOptionKind.allowOnce,
        }),
        acp.PermissionOption.fromJson({
          'optionId': _settingNo,
          'name': 'No, $escape',
          'kind': acp.PermissionOptionKind.rejectOnce,
        }),
      ],
      save: SaveBox(
        question: '${word[0].toUpperCase()}${word.substring(1)} $shownKey?',
        escape: escape,
        asked: asked,
      ),
      signal: signal,
    );
    if (picked == null) {
      return const Refused(
        'The person was not asked to the end; nothing was saved',
      );
    }
    if (picked == _settingNo) return answer.answered(saved: false);
    try {
      await saveSettingAt(file, path, change);
    } on Object catch (error) {
      return Refused(saveFailure(answer.file, error, shownHome(where)));
    }
    caller.window.settingSaved(path, change);
    return answer.answered(saved: true);
  } finally {
    release();
  }
}

/// What a `settings` call answers, as the agent reads it.
final class _SettingsAnswer implements Answer {
  const _SettingsAnswer(this.json);
  final Map<String, Object?> json;

  @override
  Map<String, Object?> toJson() => json;
}

ToolSpec _settings(Caller caller) {
  Future<ToolResult> serveSettings(
    Map<String, Object?> input,
    CancellationToken cancelled,
  ) async {
    if (caller.fork) {
      return serve(caller, ChordTool.settings, input, forkRefused);
    }
    final path = [
      for (final key in (input['path'] as List<Object?>?) ?? const [])
        key as String,
    ];
    if (input['action'] != 'read') {
      final asked = const Uuid().v4();
      final changed = await changeSetting(
        caller,
        path,
        input['action'] == 'set'
            ? SetSetting(input.containsKey('value') ? input['value'] : absent)
            : const RemoveSetting(),
        cancelled,
        (shown) => caller.window.served(
          caller,
          ChordCall(
            tool: ChordTool.settings,
            input: input,
            answer: shown.toJson(),
            pending: true,
            asked: asked,
          ),
        ),
        asked,
      );
      return serve(
        caller,
        ChordTool.settings,
        input,
        changed is SettingsChanged
            ? _SettingsAnswer(changed.toJson())
            : changed,
        asked: asked,
      );
    }
    final read = await readSettingsTool(
      caller.window.settingsWhere(caller).where,
      path,
    );
    if (read is SettingsToolRefused) {
      return serve(caller, ChordTool.settings, input, Refused(read.error));
    }
    final SettingsReadAnswer(:answer, :user, :project) =
        read as SettingsReadAnswer;
    final json = answer.toJson();
    caller.window.served(
      caller,
      ChordCall(
        tool: ChordTool.settings,
        input: input,
        answer: json,
        settingsFiles: (user: user, project: project),
      ),
    );
    return (text: _indented.convert(json), isError: false, structured: null);
  }

  return ToolSpec(
    ChordTool.settings,
    "Reads and edits chord's settings. `read` gives the user's file and "
    "the project's as written, and the merged, checked settings that "
    "take effect, with any problems; values under an MCP server's env "
    'and headers read "***". `set` and `remove` change one key in the '
    "user's file, after chord asks the person, whatever mode you run "
    'in; chord writes the file, not you. A path is a list of keys, as '
    "an agent's name may hold a dot. The keys chord writes are theme, "
    'editorMode, mouse, copyOnSelect, offeredAgents, '
    'preferredNotifChannel, agent, agents.<name>.model and .effort, '
    'teamSelection.intent and teamSelection.prefer.agent and .model; '
    'the person edits any other by hand. The answer says what changed '
    'and when it takes effect. When `saved` is false and `unchanged` '
    'is not set, the person will say what to change: end your turn and '
    'wait for their words.',
    {
      r'$schema': _draft07,
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['read', 'set', 'remove'],
          'description': 'What to do',
        },
        'path': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'The key, as a list of keys; for a read, every key if left out',
        },
        'value': {'description': 'What `set` sets it to'},
      },
      'required': ['action'],
    },
    (input) => serveSettings(input, CancellationToken()),
    until: serveSettings,
  );
}
