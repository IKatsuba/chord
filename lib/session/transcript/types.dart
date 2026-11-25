/// The transcript: everything a session's turns have produced, as plain
/// state the screens draw, and the actions the reducer folds into it.
///
/// State is sealed classes with no `==`: a reducer hands back the identical
/// object for whatever it did not change, and that identity is the change
/// signal everything downstream reads. ACP's data inside is kept as the
/// wire's read-only views, `_meta` included.
library;

import '../../acp/schema.dart' as acp;
import '../../teams.dart' show Team, TeamPart;

export '../../teams.dart' show TeamPart;
import '../../acp/plans.dart';

export '../../acp/plans.dart' show PlanAgent, PlanTodo, PlanPhase;
import '../permission_review.dart';
import '../questions.dart' show Questions;
import '../sign_in.dart' show SignIn;
import '../terminal_text.dart';
import 'text_run.dart';
import '../turn_costs.dart' show TurnFigures;

/// A label and value in a client report.
typedef ReportRow = ({String label, String text});

/// An opaque logical occurrence token, with no reference to an entry revision.
final class EntryIdentity {
  EntryIdentity();
}

/// One line of the transcript, owned by the turn that drew it.
sealed class Entry {
  const Entry(String turnId, {EntryIdentity? identity})
    : this._(turnId, identity);

  const Entry._(this.turnId, this._identity);

  final EntryIdentity? _identity;
  static final _fallback = Expando<EntryIdentity>();

  /// Stable logical identity; transcript writers issue independent occurrences.
  EntryIdentity get identity =>
      _identity ?? (_fallback[this] ??= EntryIdentity());

  /// The turn the entry belongs to.
  final String turnId;
}

/// A command run locally, whose finished output can precede the next prompt.
final class ShellRun {
  const ShellRun({
    required this.command,
    required this.running,
    this.stdout = '',
    this.stderr = '',
    this.code,
    this.stopped = false,
    this.error,
    this.truncated = false,
  });
  final String command, stdout, stderr;
  final bool running, stopped, truncated;
  final num? code;
  final String? error;
}

/// A local command, independent of the agent's turn state.
final class ShellEntry extends Entry {
  const ShellEntry(super.turnId, this.run, {super.identity});
  final ShellRun run;
}

/// The person's prompt, as it was sent.
final class UserEntry extends Entry {
  const UserEntry(super.turnId, this.text, {this.from, super.identity});

  /// The prompt's text.
  final String text;

  /// Who sent it, when another agent or chord did: a message, not the
  /// person's words.
  final MessageFrom? from;
}

/// The close of an unwanted turn the adapter started itself.
final class SelfStartedEntry extends Entry {
  const SelfStartedEntry(
    super.turnId, {
    this.alone = true,
    this.from,
    super.identity,
  });

  /// Whether the turn drew nothing before its close line.
  final bool alone;

  /// Who sent the message the turn was started with, when not the person.
  final MessageFrom? from;

  /// The original personal steering interruption notice.
  static const message =
      'Interrupted · the agent started this on its own; your message goes as the next turn';
}

/// Chunks of one message run on into one block.
sealed class ChunkEntry extends Entry {
  const ChunkEntry(super.turnId, this.text, {this.messageId, super.identity});

  /// The block's text so far.
  final TextRun text;

  /// The agent's id for the message, when it sent one.
  final String? messageId;
}

/// A block of the agent's reply.
final class AssistantEntry extends ChunkEntry {
  const AssistantEntry(
    super.turnId,
    super.text, {
    super.messageId,
    super.identity,
    this.planId,
  });

  /// The plan a `plan_update` wrote as this reply; each update to it
  /// rewrites it, so no chunk runs on into it.
  final String? planId;
}

/// A block of the agent's thought, kept apart from its reply.
final class ThoughtEntry extends ChunkEntry {
  const ThoughtEntry(
    super.turnId,
    super.text, {
    super.messageId,
    super.identity,
  });
}

/// One tool call, merged from its `tool_call` and every update to it.
final class ToolEntry extends Entry {
  const ToolEntry(super.turnId, this.call, {super.identity});

  /// The call as merged so far.
  final ToolCall call;
}

/// A window-only plain line at the boundary between saved and live history.
final class HistoryOmittedEntry extends Entry {
  const HistoryOmittedEntry({super.identity}) : super('history-omitted');
  static const message = 'Some saved history is not shown in this version.';
}

/// A local slash command and its replaceable pending or outcome note.
final class NotedEntry extends Entry {
  const NotedEntry(
    super.turnId,
    this.command,
    this.text, {
    this.failed = false,
    super.identity,
  });
  final String command;
  final String text;
  final bool failed;
}

/// A call of chord's the person made with one of chord's commands, as
/// `/new` opens an agent: the command as typed, then the call drawn as the
/// agent's own call of that tool is.
final class TypedCallEntry extends Entry {
  const TypedCallEntry(super.turnId, this.command, this.call, {super.identity});

  /// The command as typed, without its slash.
  final String command;
  final ChordCall call;
}

/// What `/team` showed under the command as typed: the team `/team show`
/// found, or, while its picker is open, the command alone.
final class TeamShownEntry extends Entry {
  const TeamShownEntry(
    super.turnId,
    this.command,
    this.shown, {
    super.identity,
  });

  /// The command as typed, without its slash.
  final String command;
  final TeamShown shown;
}

/// What one `/team` command shows besides a line or a run's call.
sealed class TeamShown {
  const TeamShown();
}

/// `/team`: the command as typed, while its picker is open.
final class TeamListed extends TeamShown {
  const TeamListed();
}

/// A line under the command: what it did, or why it did not.
final class TeamSaid extends TeamShown {
  const TeamSaid(this.text, {required this.failed});

  final String text;
  final bool failed;
}

/// `/team show`: the team as its file has it, and its run, if open.
final class ShownTeam extends TeamShown {
  const ShownTeam({
    required this.name,
    required this.file,
    required this.team,
    this.running,
  });

  final String name;

  /// Its file, as the window shows paths.
  final String file;
  final Team team;
  final TeamRunShown? running;
}

/// `/team show <run ID>`: a selected run's receipt as main's record keeps
/// it, the run no longer open.
final class TeamReceiptShown extends TeamShown {
  const TeamReceiptShown(this.call);

  /// The `run_team` call the run was admitted as, its receipt in its answer.
  final ChordCall call;
}

/// A state or mark as the agent list words it, its tone by name:
/// `warning`, `error`, `success`, `dim` or `working`.
typedef ShownState = ({String glyph, String words, String tone});

/// A team's run as `/team show` caught it.
final class TeamRunShown {
  const TeamRunShown({
    required this.name,
    required this.since,
    required this.at,
    required this.job,
    required this.agents,
  });

  /// The run's name: `bugfix`, `bugfix 2`.
  final String name;

  /// When its lead opened, on chord's clock.
  final num since;

  /// When `/team show` caught it, which its times are counted to.
  final num at;
  final String job;

  /// The lead, then each of the file's members, in the file's order.
  final List<TeamAgentShown> agents;
}

/// One agent of a running team, as `/team show` caught it.
final class TeamAgentShown {
  const TeamAgentShown({
    required this.name,
    required this.open,
    this.lead = false,
    this.state,
    this.mark,
    this.latest,
  });

  /// `lead`, or the member's name.
  final String name;

  /// The team's lead: a member may be named `lead` too.
  final bool lead;

  /// Not opened yet, or closed again: it has no state.
  final bool open;

  /// Its state as the agent list words it.
  final ShownState? state;

  /// What of it is not yet seen, as the agent list marks it beside its
  /// state; showing it here does not clear it.
  final ShownState? mark;

  /// Its latest call's or incoming message's headline, as its transcript
  /// draws it: `Edit(src/a.ts)`, `→ to @coder`, `← from @tester · claude`.
  final String? latest;
}

/// A resumed session's long-lived agents that were open when it was left,
/// which are not reopened with it; drawn as one dim line.
final class LeftOpenEntry extends Entry {
  const LeftOpenEntry(super.turnId, this.agents, {super.identity});

  /// Each agent left open, by its name and runtime, a team's run as one.
  final List<LeftOpen> agents;
}

/// A team's instructions, which went to a lead or member ahead of its first
/// message; drawn as one line, its text under ctrl+o.
final class TeamPartEntry extends Entry {
  const TeamPartEntry(super.turnId, this.part, {super.identity});

  /// The team, the member it is for (none for a lead), and the text.
  final TeamPart part;
}

/// A long-lived agent a session left open, as its record names it: a team
/// run's lead with its team's name, by its file, and the agents of the run,
/// its lead and the members it had open.
typedef LeftOpen = ({String name, String runtime, String? team, int? agents});

/// Where a fork parted from [from], at [at]: drawn as a dim divider.
final class ForkedEntry extends Entry {
  const ForkedEntry(super.turnId, this.from, this.at, {super.identity});

  final String from;
  final num at;
}

/// A resumed session's monitors that were running when it was left, which
/// nothing restarts; drawn as one dim line.
final class MonitorsLeftEntry extends Entry {
  const MonitorsLeftEntry(super.turnId, this.monitors, {super.identity});

  final List<PastMonitor> monitors;
}

/// A local status report, with aligned original labels and values.
final class ReportEntry extends Entry {
  const ReportEntry(super.turnId, this.command, this.rows, {super.identity});
  final String command;
  final List<ReportRow> rows;
}

/// How a permission was answered; a withdrawn one leaves none.
final class PermissionEntry extends Entry {
  const PermissionEntry(
    super.turnId, {
    this.title,
    this.option,
    this.review,
    super.identity,
  });

  /// The tool call's title, as the request named it.
  final String? title;

  /// The agent's option the person chose; none when Esc rejected it.
  final acp.PermissionOption? option;

  /// The safety review the request carried.
  final PermissionReview? review;
}

/// A turn the agent ended `cancelled`.
final class CancelledEntry extends Entry {
  const CancelledEntry(super.turnId, {super.identity});
}

/// A turn that ended with a stop reason other than `end_turn`.
final class StoppedEntry extends Entry {
  const StoppedEntry(super.turnId, this.reason, {super.identity});

  /// The agent's stop reason, as it sent it.
  final String reason;
}

/// A turn that failed, or a failure chord tells.
final class ErrorEntry extends Entry {
  const ErrorEntry(
    super.turnId,
    this.message, {
    this.code,
    this.signIn,
    super.identity,
  });

  /// What went wrong, in the agent's or chord's words.
  final String message;

  /// The JSON-RPC error's code, when there was one.
  final int? code;

  /// The sign-in a prompt refused for want of a login needs, drawn as its
  /// block.
  final SignIn? signIn;
}

/// A warning chord tells.
final class WarningEntry extends Entry {
  const WarningEntry(super.turnId, this.message, {super.identity});

  /// The warning's words.
  final String message;
}

/// The severities a notice draws by; any other word reads [info].
enum NoticeSeverity { info, warning, error }

/// An agent's notice: its severity, its title and what it adds.
final class NoticeEntry extends Entry {
  const NoticeEntry(
    super.turnId,
    this.severity,
    this.title, {
    this.description,
    super.identity,
  });

  final NoticeSeverity severity;
  final String title;

  /// What it adds under the title; none when the agent gave none.
  final String? description;
}

/// A compaction of the session's context the agent ran, folded from its
/// `compaction_update`s and `compaction_summary_chunk`s by its id.
final class Compaction {
  const Compaction(
    this.id,
    this.status, {
    this.summary = '',
    this.error,
    this.unasked = false,
  });

  /// The agent's id for it.
  final String id;

  /// ACP's `in_progress`, `completed`, `failed` or `cancelled`.
  final String status;

  /// The summary the agent kept of what it dropped, as text; streamed
  /// chunks build it, an update's `summary` replaces it. Empty when it sent
  /// none, as Codex's adapter never does.
  final String summary;

  /// Why it failed, in the agent's words.
  final String? error;

  /// The agent ran it on its own, with nothing of the person's or chord's
  /// under way, as Claude does to an idle session.
  final bool unasked;
}

/// A compaction, where its first update put it.
final class CompactionEntry extends Entry {
  const CompactionEntry(super.turnId, this.compaction, {super.identity});

  /// The compaction as merged so far.
  final Compaction compaction;
}

/// Where a subagent stands, from its `subagent_update`s: at work, or ended
/// by its stop reason (`end_turn` completed, `error` failed, `cancelled`
/// cancelled, any other or none [ended]); [untracked] is ACP's `unknown`:
/// the agent lost sight of it, and a later state takes it back.
enum SubagentState {
  running,
  completed,
  failed,
  cancelled,
  disconnected,
  ended,
  untracked,
}

/// A subagent: a session of its own the agent started for part of a turn,
/// as its `subagent_update`s describe it, with the work it did held apart
/// from its parent's. Times are when the updates that carried them reached
/// chord, epoch milliseconds.
final class Subagent {
  const Subagent(
    this.id, {
    this.state = SubagentState.running,
    this.title,
    this.description,
    this.prompt,
    this.promptId,
    this.addressed = false,
    this.namedByTitle = false,
    this.cancellable = false,
    this.offeredCancel = false,
    this.stopping = false,
    this.waiting,
    this.error,
    this.startedAt,
    this.endedAt,
    this.entries = const [],
    this.plan = const [],
    this.planId,
    this.planAt,
    this.task,
    this.callId,
  });

  /// Its session's id, which its own updates and requests carry.
  final String id;

  /// Set on a task agent chord started, which the agent's runtime did not.
  final TaskInfo? task;

  /// The `spawn_task` call it stands in place of, whose own updates it
  /// takes from then on.
  final String? callId;

  /// The parent's short name for it.
  final String? title;

  /// What it was asked to do, as the parent described it.
  final String? description;

  /// Its whole task, from the first `session_message` it got, and that
  /// message's id, which a later upsert of it names.
  final String? prompt, promptId;

  /// Its parent's session said what it sent it, so a row above it says
  /// what it was asked.
  final bool addressed;

  /// Its adapter is Claude's: its title is its name, its description a role.
  final bool namedByTitle;
  final SubagentState state;

  /// It announced it can be cancelled alone: its agent reports its end
  /// itself, so a cancel of its parent's turn does not end it on chord's
  /// word.
  final bool cancellable;

  /// It announced `capabilities.cancel` at some point, if not now.
  final bool offeredCancel;

  /// The person stopped it alone, and its agent has not yet said it ended;
  /// it still stands running.
  final bool stopping;

  /// Its agent says it waits on the person, since when that came, where it
  /// was timed; it still stands running.
  final ({num? since})? waiting;

  /// What the agent said went wrong, while it stands failed.
  final String? error;

  /// When its first update came, and when it ended, once it has.
  final num? startedAt, endedAt;

  /// Its own messages, thoughts, tool calls and subagents.
  final List<Entry> entries;

  /// Its latest plan, which never stands for its parent's.
  final List<acp.PlanEntry> plan;

  /// The id a `plan_update` gave that plan.
  final String? planId;

  /// Where its plan first came: how many of [entries] were there then.
  final int? planAt;

  /// This subagent with what is given changed; [clear] names the nullable
  /// fields set to none.
  Subagent copyWith({
    String? title,
    String? description,
    String? prompt,
    String? promptId,
    bool? addressed,
    bool? namedByTitle,
    SubagentState? state,
    bool? cancellable,
    bool? offeredCancel,
    bool? stopping,
    ({num? since})? waiting,
    String? error,
    num? startedAt,
    num? endedAt,
    List<Entry>? entries,
    List<acp.PlanEntry>? plan,
    String? planId,
    int? planAt,
    TaskInfo? task,
    String? callId,
    Set<String> clear = const {},
  }) => Subagent(
    id,
    title: clear.contains('title') ? null : title ?? this.title,
    description: clear.contains('description')
        ? null
        : description ?? this.description,
    prompt: clear.contains('prompt') ? null : prompt ?? this.prompt,
    promptId: promptId ?? this.promptId,
    addressed: addressed ?? this.addressed,
    namedByTitle: namedByTitle ?? this.namedByTitle,
    state: state ?? this.state,
    cancellable: cancellable ?? this.cancellable,
    offeredCancel: offeredCancel ?? this.offeredCancel,
    stopping: stopping ?? this.stopping,
    waiting: clear.contains('waiting') ? null : waiting ?? this.waiting,
    error: clear.contains('error') ? null : error ?? this.error,
    startedAt: startedAt ?? this.startedAt,
    endedAt: clear.contains('endedAt') ? null : endedAt ?? this.endedAt,
    entries: entries ?? this.entries,
    plan: plan ?? this.plan,
    planId: clear.contains('planId') ? null : planId ?? this.planId,
    planAt: clear.contains('planAt') ? null : planAt ?? this.planAt,
    task: task ?? this.task,
    callId: callId ?? this.callId,
  );
}

/// Who stopped a task: the person's key, [x] or [esc], or the agent that
/// started it, by its name, with `close_agent`.
final class TaskStop {
  const TaskStop._(this.key, this.agent);

  /// Stopped by the agent named [agent], which started it.
  const TaskStop.agent(String agent) : this._(null, agent);

  /// The person's `x` in the background view.
  static const x = TaskStop._('x', null);

  /// The person's Esc on its parent's turn.
  static const esc = TaskStop._('esc', null);

  /// The person's key, `x` or `esc`; null when an agent stopped it.
  final String? key;

  /// The agent that stopped it, by name; null when the person did.
  final String? agent;

  /// As its ending update carries it: the key, or `{agent}`.
  Object toJson() => key ?? {'agent': agent};

  @override
  bool operator ==(Object other) =>
      other is TaskStop && other.key == key && other.agent == agent;

  @override
  int get hashCode => Object.hash(key, agent);

  @override
  String toString() => 'TaskStop(${key ?? agent})';
}

/// How a monitor ended, where it tells its agent: its command exited, a
/// signal chord did not send killed it, its `timeout_ms` passed, the person
/// stopped it, or it printed too much.
sealed class MonitorEnd {
  const MonitorEnd();

  /// As a record keeps it, the original's shape.
  Map<String, Object?> toJson() => switch (this) {
    MonitorExited(:final code) => {'kind': 'exit', 'code': code},
    MonitorKilled(:final signal) => {'kind': 'signal', 'signal': signal},
    MonitorTimedOut(:final timeoutMs) => {
      'kind': 'timed_out',
      'timeoutMs': timeoutMs,
    },
    MonitorStopped() => {'kind': 'stopped'},
    MonitorFlooded(:final by) => {'kind': 'flooded', 'by': by.name},
  };

  /// [json] as a record keeps an end; none for a shape it does not know.
  static MonitorEnd? fromJson(Object? json) => switch (json) {
    {'kind': 'exit', 'code': final int code} => MonitorExited(code),
    {'kind': 'signal', 'signal': final String signal} => MonitorKilled(signal),
    {'kind': 'timed_out', 'timeoutMs': final int timeoutMs} => MonitorTimedOut(
      timeoutMs,
    ),
    {'kind': 'stopped'} => const MonitorStopped(),
    {'kind': 'flooded', 'by': 'lines'} => const MonitorFlooded(FloodBy.lines),
    {'kind': 'flooded', 'by': 'bytes'} => const MonitorFlooded(FloodBy.bytes),
    _ => null,
  };
}

/// Its command exited with [code].
final class MonitorExited extends MonitorEnd {
  const MonitorExited(this.code);
  final int code;

  @override
  bool operator ==(Object other) =>
      other is MonitorExited && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'MonitorExited($code)';
}

/// A signal chord did not send, by its name, killed it.
final class MonitorKilled extends MonitorEnd {
  const MonitorKilled(this.signal);
  final String signal;

  @override
  bool operator ==(Object other) =>
      other is MonitorKilled && other.signal == signal;

  @override
  int get hashCode => signal.hashCode;

  @override
  String toString() => 'MonitorKilled($signal)';
}

/// Its [timeoutMs] passed and chord stopped it.
final class MonitorTimedOut extends MonitorEnd {
  const MonitorTimedOut(this.timeoutMs);
  final int timeoutMs;

  @override
  bool operator ==(Object other) =>
      other is MonitorTimedOut && other.timeoutMs == timeoutMs;

  @override
  int get hashCode => timeoutMs.hashCode;

  @override
  String toString() => 'MonitorTimedOut($timeoutMs)';
}

/// The person stopped it.
final class MonitorStopped extends MonitorEnd {
  const MonitorStopped();

  @override
  bool operator ==(Object other) => other is MonitorStopped;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'MonitorStopped()';
}

/// What a flood was more of: lines or bytes.
enum FloodBy { lines, bytes }

/// It printed more [by] than a monitor may, and chord stopped it.
final class MonitorFlooded extends MonitorEnd {
  const MonitorFlooded(this.by);
  final FloodBy by;

  @override
  bool operator ==(Object other) => other is MonitorFlooded && other.by == by;

  @override
  int get hashCode => by.hashCode;

  @override
  String toString() => 'MonitorFlooded(${by.name})';
}

/// A monitor a session's past started, by its id and description.
typedef PastMonitor = ({String id, String description});

/// A task agent's spend: its turn's tokens as the answer to its prompt gave
/// them, and its cost as its last `usage_update` did, [estimated] when chord
/// worked that cost out. What its agent did not report is left out.
final class TaskSpent {
  const TaskSpent({this.tokens, this.cost, this.estimated = false});

  /// ACP's `Usage` fields it gave, without its nulls.
  final Map<String, num>? tokens;
  final ({num amount, String currency})? cost;
  final bool estimated;

  /// As its ending update carries it.
  Map<String, Object?> toJson() => {
    'tokens': ?tokens,
    if (cost case final cost?)
      'cost': {'amount': cost.amount, 'currency': cost.currency},
    if (estimated) 'estimated': true,
  };
}

/// A task agent chord started for the session, as `spawn_task` asked.
final class TaskInfo {
  const TaskInfo({
    required this.name,
    required this.runtime,
    this.model,
    this.effort,
    this.workLost = false,
    this.spent,
    this.stoppedWith,
  });

  /// Its `name`, or failing that its prompt's first line.
  final String name;
  final String runtime;

  /// The model asked for; none when the runtime's own was left.
  final String? model;

  /// The effort it started on, when one was asked for; said once it is up,
  /// as a refused one leaves it on the runtime's own.
  final String? effort;

  /// Its own record, which keeps its work, had gone when its parent was
  /// resumed: how much it did is not known.
  final bool workLost;

  /// What it spent, as its agent reported it, once it has ended.
  final TaskSpent? spent;

  /// Who stopped it: the person, with `x` or with Esc on its parent's turn,
  /// or the agent that started it, with `close_agent`.
  final TaskStop? stoppedWith;

  /// This task as [told] says it now: what [told] says replaces what this
  /// said, and what it leaves out is kept.
  TaskInfo told(TaskInfo told) => TaskInfo(
    name: told.name,
    runtime: told.runtime,
    model: told.model ?? model,
    effort: told.effort ?? effort,
    workLost: told.workLost || workLost,
    spent: spent,
    stoppedWith: stoppedWith,
  );

  /// This task with what its ending update says, where it says it.
  TaskInfo ended({TaskSpent? spent, TaskStop? stoppedWith}) =>
      spent == null && stoppedWith == null
      ? this
      : TaskInfo(
          name: name,
          runtime: runtime,
          model: model,
          effort: effort,
          workLost: workLost,
          spent: spent ?? this.spent,
          stoppedWith: stoppedWith ?? this.stoppedWith,
        );
}

/// A subagent, where its first update came among its parent's entries;
/// each later update changes it here.
final class SubagentEntry extends Entry {
  const SubagentEntry(super.turnId, this.subagent, {super.identity});
  final Subagent subagent;
}

/// A `session_message` between the transcript's agent and a subagent of
/// its: a launch's prompt, a message sent, a reply or a report.
final class AgentMessageEntry extends Entry {
  const AgentMessageEntry(
    super.turnId,
    this.messageId, {
    required this.toSubagent,
    required this.agentId,
    this.title,
    required this.text,
    this.launch = false,
    super.identity,
  });
  final String messageId;

  /// Sent to the subagent; else from it.
  final bool toSubagent;

  /// The subagent's id, and its title as its updates last said it.
  final String agentId;
  final String? title;
  final String text;

  /// The first sent to it: its task.
  final bool launch;
}

/// A message a subagent was sent after its task, among its work, by its
/// parent's agent ([byAgent]) or by another subagent named [from].
final class ChildMessageEntry extends Entry {
  const ChildMessageEntry(
    super.turnId,
    this.from,
    this.text, {
    this.messageId,
    this.byAgent = false,
    super.identity,
  });
  final String from;
  final String text;
  final String? messageId;
  final bool byAgent;
}

/// How an agent item ended, as its end line says it.
enum ItemEnd { done, failed, stopped, ended, disconnected }

/// What ended, as its end line names its kind: an agent item, or a task
/// agent chord started.
enum ItemKind { agent, task }

/// A subagent that ended after the turn that started it, said once in the
/// transcript; one that ends while that turn runs is said by its own block.
/// A task's is said only when it was stopped, with who stopped it.
final class ItemEndedEntry extends Entry {
  const ItemEndedEntry(
    super.turnId,
    this.name,
    this.end, {
    this.item = ItemKind.agent,
    this.byPerson = false,
    this.byEsc = false,
    this.byAgent,
    this.startedAt,
    this.endedAt,
    this.error,
    super.identity,
  });
  final String name;
  final ItemEnd end;
  final ItemKind item;

  /// The person's `x` stopped it.
  final bool byPerson;

  /// The person's Esc on its parent's turn stopped it.
  final bool byEsc;

  /// The agent that started the task stopped it, by its name.
  final String? byAgent;
  final num? startedAt, endedAt;
  final String? error;
}

/// How a form or link the agent asked for was answered. A request that
/// stopped mattering, as when its turn was cancelled, reads cancelled.
final class ElicitationEntry extends Entry {
  const ElicitationEntry(
    super.turnId,
    this.wait,
    this.outcome, {
    this.content,
    super.identity,
  });

  /// What was asked.
  final ElicitationWait wait;

  /// How it ended.
  final ElicitationOutcome outcome;

  /// What an accepted form sent, by field.
  final Map<String, Object?>? content;
}

/// How an elicitation ended, as its record says it.
enum ElicitationOutcome { accepted, declined, cancelled, timedOut }

/// A form or link the agent asks the person for, through ACP's
/// `elicitation/create`, with what the window draws to ask it.
sealed class ElicitationWait {
  const ElicitationWait(
    this.id,
    this.message, {
    this.toolCallId,
    this.at,
    this.between = false,
    this.asker,
    this.subagentId,
  });

  /// The bridge's id for the request.
  final String id;

  /// The task agent that asks, when the session's own agent does not.
  final String? subagentId;

  /// The agent's message.
  final String message;

  /// The tool call the request came out of, when the agent names one.
  final String? toolCallId;

  /// When chord got the request, epoch milliseconds.
  final num? at;

  /// Asked with no turn of chord's running.
  final bool between;

  /// The agent's own subagent that asks, by its session id, when the
  /// session's agent does not: who a form between turns names.
  final String? asker;

  /// This wait asked at [at], [between] turns, by [asker].
  ElicitationWait asked({required num at, bool between = false, String? asker});

  /// This wait, asked by task agent [subagentId].
  ElicitationWait askedBy(String subagentId);

  /// This wait, now between turns.
  ElicitationWait get leftOpen;
}

/// [wait] as a record keeps it: everything but when it was asked, which a
/// reopened session never counts down.
Map<String, Object?> elicitationWaitJson(ElicitationWait wait) => {
  'id': wait.id,
  'message': wait.message,
  'toolCallId': ?wait.toolCallId,
  'subagentId': ?wait.subagentId,
  if (wait.between) 'between': true,
  'asker': ?wait.asker,
  ...switch (wait) {
    FormWait(:final schema, :final questions) => {
      'mode': 'form',
      'schema': schema,
      if (questions != null) 'questions': questions.toJson(),
    },
    LinkWait(:final url) => {'mode': 'url', 'url': url},
  },
};

/// [json] as a record keeps a form or link; none when it does not read.
ElicitationWait? elicitationWaitFrom(Object? json) {
  if (json case {
    'id': final String id,
    'message': final String message,
  } when json is Map<String, Object?>) {
    final toolCallId = json['toolCallId'] is String
        ? json['toolCallId'] as String
        : null;
    final asker = json['asker'] is String ? json['asker'] as String : null;
    final subagentId = json['subagentId'] is String
        ? json['subagentId'] as String
        : null;
    final between = json['between'] == true;
    return switch (json) {
      {'mode': 'url', 'url': final String url} => LinkWait(
        id,
        message,
        url,
        toolCallId: toolCallId,
        between: between,
        asker: asker,
        subagentId: subagentId,
      ),
      {'mode': 'form'} => FormWait(
        id,
        message,
        schema: switch (json['schema']) {
          final Map<String, Object?> schema => schema,
          _ => const {},
        },
        questions: Questions.fromJson(json['questions']),
        toolCallId: toolCallId,
        between: between,
        asker: asker,
        subagentId: subagentId,
      ),
      _ => null,
    };
  }
  return null;
}

/// [answer] as a record keeps it.
Map<String, Object?> elicitationAnswerJson(ElicitationAnswer answer) =>
    switch (answer) {
      ElicitationAccepted(:final content) => {
        'type': 'accepted',
        'content': ?content,
      },
      ElicitationDeclined() => {'type': 'declined'},
      ElicitationCancelled() => {'type': 'cancelled'},
      ElicitationWithdrawn() => {'type': 'withdrawn'},
      ElicitationTimedOut() => {'type': 'timed_out'},
    };

/// [json] as a record keeps an answer; none when it does not read.
ElicitationAnswer? elicitationAnswerFrom(Object? json) => switch (json) {
  {'type': 'accepted', 'content': final Map<String, Object?> content} =>
    ElicitationAccepted(content),
  {'type': 'accepted'} => const ElicitationAccepted(),
  {'type': 'declined'} => const ElicitationDeclined(),
  {'type': 'cancelled'} => const ElicitationCancelled(),
  {'type': 'withdrawn'} => const ElicitationWithdrawn(),
  {'type': 'timed_out'} => const ElicitationTimedOut(),
  _ => null,
};

/// A form, by the schema the agent sent.
final class FormWait extends ElicitationWait {
  const FormWait(
    super.id,
    super.message, {
    this.schema = const {},
    this.questions,
    super.toolCallId,
    super.at,
    super.between,
    super.asker,
    super.subagentId,
  });

  /// ACP's `requestedSchema`, as it came.
  final Map<String, Object?> schema;

  /// The form's questions, where an enricher read the adapter's form.
  final Questions? questions;

  @override
  FormWait asked({required num at, bool between = false, String? asker}) =>
      FormWait(
        id,
        message,
        schema: schema,
        questions: questions,
        toolCallId: toolCallId,
        at: at,
        between: between,
        asker: asker,
        subagentId: subagentId,
      );

  @override
  FormWait askedBy(String subagentId) => FormWait(
    id,
    message,
    schema: schema,
    questions: questions,
    toolCallId: toolCallId,
    at: at,
    between: between,
    asker: asker,
    subagentId: subagentId,
  );

  @override
  FormWait get leftOpen => FormWait(
    id,
    message,
    schema: schema,
    questions: questions,
    toolCallId: toolCallId,
    at: at,
    between: true,
    asker: asker,
    subagentId: subagentId,
  );
}

/// A link to open, usually a sign-in.
final class LinkWait extends ElicitationWait {
  const LinkWait(
    super.id,
    super.message,
    this.url, {
    super.toolCallId,
    super.at,
    super.between,
    super.asker,
    super.subagentId,
  });

  /// The link.
  final String url;

  @override
  LinkWait asked({required num at, bool between = false, String? asker}) =>
      LinkWait(
        id,
        message,
        url,
        toolCallId: toolCallId,
        at: at,
        between: between,
        asker: asker,
        subagentId: subagentId,
      );

  @override
  LinkWait askedBy(String subagentId) => LinkWait(
    id,
    message,
    url,
    toolCallId: toolCallId,
    at: at,
    between: between,
    asker: asker,
    subagentId: subagentId,
  );

  @override
  LinkWait get leftOpen => LinkWait(
    id,
    message,
    url,
    toolCallId: toolCallId,
    at: at,
    between: true,
    asker: asker,
    subagentId: subagentId,
  );
}

/// How an elicitation stopped waiting: answered, or withdrawn because its
/// turn ended or the session closed, which its record calls cancelled.
sealed class ElicitationAnswer {
  const ElicitationAnswer();
}

/// The form accepted, with what it sent; a link opened.
final class ElicitationAccepted extends ElicitationAnswer {
  const ElicitationAccepted([this.content]);
  final Map<String, Object?>? content;
}

/// Declined.
final class ElicitationDeclined extends ElicitationAnswer {
  const ElicitationDeclined();
}

/// Cancelled, as Esc does.
final class ElicitationCancelled extends ElicitationAnswer {
  const ElicitationCancelled();
}

/// It stopped mattering before an answer.
final class ElicitationWithdrawn extends ElicitationAnswer {
  const ElicitationWithdrawn();
}

/// Withdrawn as the wait its agent gave for an answer ran out.
final class ElicitationTimedOut extends ElicitationAnswer {
  const ElicitationTimedOut();
}

/// A plan whose every step was completed when its turn settled.
final class FinishedPlanEntry extends Entry {
  const FinishedPlanEntry(super.turnId, this.entries, {super.identity});

  /// The plan's steps, as the agent last sent them.
  final List<acp.PlanEntry> entries;
}

/// One tool call, merged from its `tool_call` and every update to it.
final class ToolCall {
  const ToolCall(
    this.id, {
    this.title,
    this.kind,
    this.status,
    this.locations,
    this.content,
    this.rawInput,
    this.rawOutput,
    this.guardian,
    this.mcp,
    this.review,
    this.terminals,
    this.plan,
    this.asked = false,
    this.chord,
    this.cut = false,
  });

  /// The request chord's own MCP server served for it, once the call is
  /// known to be that one; its headline and lines are read from this, not
  /// the title.
  final ChordCall? chord;

  /// The agent cut the call off before it ran, as Claude's adapter does to
  /// a batch a steer interrupts: one of chord's that nothing was served for
  /// never reached chord.
  final bool cut;

  /// This call tied to the request chord served for it.
  ToolCall withChord(ChordCall chord) => ToolCall(
    id,
    title: title,
    kind: kind,
    status: status,
    locations: locations,
    content: content,
    rawInput: rawInput,
    rawOutput: rawOutput,
    guardian: guardian,
    mcp: mcp,
    review: review,
    terminals: terminals,
    plan: plan,
    asked: asked,
    chord: chord,
    cut: cut,
  );

  /// Its questions are asked in chord's question box, from when it opens:
  /// the call reads as asking, and the box's record under it stands in for
  /// its own lines while folded.
  final bool asked;

  /// The plan its agent put to the person out of it, and their answer once
  /// given: drawn under it in place of its content.
  final PlanAsk? plan;

  /// This call with [plan] put to the person out of it.
  ToolCall withPlan(PlanAsk plan) => ToolCall(
    id,
    title: title,
    kind: kind,
    status: status,
    locations: locations,
    content: content,
    rawInput: rawInput,
    rawOutput: rawOutput,
    guardian: guardian,
    mcp: mcp,
    review: review,
    terminals: terminals,
    plan: plan,
    asked: asked,
    chord: chord,
    cut: cut,
  );

  /// This call, its questions asked in chord's box.
  ToolCall get askedHere => ToolCall(
    id,
    title: title,
    kind: kind,
    status: status,
    locations: locations,
    content: content,
    rawInput: rawInput,
    rawOutput: rawOutput,
    guardian: guardian,
    mcp: mcp,
    review: review,
    terminals: terminals,
    plan: plan,
    asked: true,
    chord: chord,
    cut: cut,
  );

  /// The agent's id for the call.
  final String id;

  /// The agent's latest title for it; none until it gave one.
  final String? title;

  /// One of ACP's tool kinds, or one chord does not know yet.
  final String? kind;

  /// `pending`, `in_progress`, `completed` or `failed`; it only moves
  /// forward.
  final String? status;

  /// The files, and lines, the call touches.
  final List<acp.ToolCallLocation>? locations;

  /// Text, diffs and terminals, as the agent sent them.
  final List<acp.ToolCallContent>? content;

  /// The call's arguments, as the agent sent them.
  final Object? rawInput;

  /// The call's result, as the agent sent it.
  final Object? rawOutput;

  /// The last Codex Guardian review status chord read: inProgress,
  /// approved, denied, timedOut, aborted, or another.
  final String? guardian;

  /// An MCP call's server, tool and arguments, where the agent wrapped
  /// them in its `rawInput`.
  final McpCall? mcp;

  /// A generic agent's safety review, kept after its permission box closes.
  final PermissionReview? review;

  /// The terminals the call ran its commands in, in the order the agent
  /// first named them, with what each wrote; none until it named one.
  final List<Terminal>? terminals;
}

/// A plan an agent asks the person to take or leave: cursor's
/// `cursor/create_plan` or grok's `x.ai/exit_plan_mode`, under the tool
/// call it names.
final class PlanWait {
  const PlanWait(
    this.id,
    this.agent, {
    required this.toolCallId,
    this.plan,
    this.name,
    this.overview,
    this.todos,
    this.phases,
  });

  final String id;

  /// Whose request, which says what it takes as an answer.
  final PlanAgent agent;
  final String toolCallId;

  /// The plan's markdown; none from grok when it wrote no plan.
  final String? plan;
  final String? name;
  final String? overview;
  final List<PlanTodo>? todos;

  /// cursor's phases, each its name over todos of its own.
  final List<PlanPhase>? phases;

  /// As a record keeps it.
  Map<String, Object?> toJson() => {
    'id': id,
    ...PlanRequest(
      agent,
      toolCallId: toolCallId,
      plan: plan,
      name: name,
      overview: overview,
      todos: todos,
      phases: phases,
    ).toJson(),
  };

  /// [json] as a record keeps one; none when it does not read.
  static PlanWait? fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['id'] is! String) return null;
    final agent = PlanAgent.values
        .where((each) => each.name == json['agent'])
        .firstOrNull;
    // Read as the request would be, by its agent's own reader.
    final request = switch (agent) {
      PlanAgent.cursor => cursorPlan(json),
      PlanAgent.grok => grokPlan({
        'sessionId': '',
        ...json,
        'planContent': ?json['plan'],
      }),
      null => null,
    };
    if (request == null) return null;
    return PlanWait(
      json['id'] as String,
      request.agent,
      toolCallId: request.toolCallId,
      plan: request.plan,
      name: request.name,
      overview: request.overview,
      todos: request.todos,
      phases: request.phases,
    );
  }
}

/// The person's answer to a plan: take it, keep planning with a note, or,
/// grok's alone, leave plan mode; cancelled or withdrawn when it was not
/// theirs, which the agent hears as `cancelled`, never a yes.
sealed class PlanAnswer {
  const PlanAnswer();

  /// As a record keeps it.
  Map<String, Object?> toJson() => switch (this) {
    PlanAccepted() => {'type': 'accepted'},
    PlanKept(:final note) => {'type': 'kept', 'note': ?note},
    PlanLeft() => {'type': 'left'},
    PlanCancelled() => {'type': 'cancelled'},
    PlanWithdrawn() => {'type': 'withdrawn'},
  };

  /// [json] as a record keeps one; none when it does not read.
  static PlanAnswer? fromJson(Object? json) => switch (json) {
    {'type': 'accepted'} => const PlanAccepted(),
    {'type': 'kept', 'note': final String note} => PlanKept(note),
    final Map<String, Object?> kept
        when kept['type'] == 'kept' && kept['note'] == null =>
      const PlanKept(),
    {'type': 'left'} => const PlanLeft(),
    {'type': 'cancelled'} => const PlanCancelled(),
    {'type': 'withdrawn'} => const PlanWithdrawn(),
    _ => null,
  };
}

final class PlanAccepted extends PlanAnswer {
  const PlanAccepted();
}

final class PlanKept extends PlanAnswer {
  const PlanKept([this.note]);
  final String? note;
}

final class PlanLeft extends PlanAnswer {
  const PlanLeft();
}

final class PlanCancelled extends PlanAnswer {
  const PlanCancelled();
}

final class PlanWithdrawn extends PlanAnswer {
  const PlanWithdrawn();
}

/// A plan put to the person, and their answer once there is one.
final class PlanAsk {
  const PlanAsk(this.turnId, this.wait, {this.answer, this.after = const []});

  final String turnId;
  final PlanWait wait;
  final PlanAnswer? answer;

  /// The permissions already waiting when it came, which go before it: a
  /// plan ranks with them, the oldest first.
  final List<String> after;

  /// This ask answered by [answer].
  PlanAsk answered(PlanAnswer answer) =>
      PlanAsk(turnId, wait, answer: answer, after: after);
}

/// A terminal a tool call ran a command in, as its `_meta` told it.
final class Terminal {
  const Terminal(
    this.id, {
    this.output = '',
    this.cursor,
    this.escape,
    this.cwd,
    this.exited = false,
    this.exitCode,
    this.signal,
    this.truncated = false,
  });

  /// The agent's id for the terminal.
  final String id;

  /// What it wrote, as a screen would leave it: plain text, its cursor
  /// controls applied and every other escape dropped. Only the last
  /// [outputLimit] characters, from a line's start.
  final String output;

  /// Where its next output lands, when not at the end of what it wrote.
  final TerminalCursor? cursor;

  /// The escape its output so far ends inside, which a later delta ends.
  final OpenEscape? escape;

  /// The directory it ran in, when the agent says.
  final String? cwd;

  /// `terminal_exit` came: the command is over.
  final bool exited;

  /// Its exit code, once it exited with one, the agent's number.
  final num? exitCode;

  /// The signal that ended it, once one did, as plain as the output.
  final String? signal;

  /// Output ran past [outputLimit] and its start was dropped.
  final bool truncated;
}

/// How much of a terminal's output a tool call keeps: its last characters,
/// as a running command's latest lines are the ones to see.
const outputLimit = 30000;

/// An MCP call's server, tool and arguments, as chord's enrichers file them.
final class McpCall {
  const McpCall(this.tool, this.input, {this.server});

  /// The MCP server, when the agent named it.
  final String? server;

  /// The MCP tool called.
  final String tool;

  /// The tool's arguments.
  final Object? input;
}

/// Where the session's turn stands.
sealed class TurnState {
  const TurnState();
}

/// No turn running.
final class Idle extends TurnState {
  const Idle();
}

/// A turn running since [since], epoch milliseconds.
final class Working extends TurnState {
  const Working(this.turnId, this.since, {this.cycle = false});

  /// The running turn.
  final String turnId;

  /// When the turn started, epoch milliseconds.
  final num since;

  /// A cycle of the agent's own, which the person did not start: what it
  /// asks is held as between turns.
  final bool cycle;
}

/// A turn, or the time between turns, waiting on the person to answer
/// [permissions].
final class AwaitingPermission extends TurnState {
  const AwaitingPermission(
    this.turnId,
    this.since,
    this.permissions, {
    this.between = false,
    this.cycle = false,
    this.cycleSince,
  });

  /// The turn that waits, or the last one when [between].
  final String turnId;

  /// When the turn started, or when the wait began between turns.
  final num since;

  /// The requests waiting, oldest first; the first is shown.
  final List<PermissionWait> permissions;

  /// Asked, or left open, with no turn running.
  final bool between;

  /// Asked in a cycle of the agent's own, which works on once every
  /// request is answered.
  final bool cycle;

  /// When that cycle started, which its working line counts from again once
  /// every request is answered; [since] is when the wait began.
  final num? cycleSince;
}

/// A cancel asked for at [cancelledAt]; the turn has not settled yet.
final class Cancelling extends TurnState {
  const Cancelling(this.turnId, this.since, this.cancelledAt);

  /// The turn being cancelled.
  final String turnId;

  /// When the turn started, epoch milliseconds.
  final num since;

  /// When the cancel was asked for, epoch milliseconds.
  final num cancelledAt;
}

/// A permission the agent asks, as the screens draw it while it waits.
final class PermissionWait {
  const PermissionWait(
    this.id, {
    this.toolCallId,
    this.title,
    this.kind,
    this.locations,
    this.content,
    this.rawInput,
    this.options = const [],
    this.review,
    this.deadlineAt,
    this.at,
    this.subagentId,
    this.detail,
    this.save,
  });

  /// What chord's own question is about, in words: for who is asked
  /// through another client and sees no box drawn beside the call.
  final String? detail;

  /// chord's own question rather than the agent's, whose answer is drawn
  /// on the call, so it leaves no record of its own.
  final SaveBox? save;

  /// The subagent that asks, when the session's own agent does not.
  final String? subagentId;

  /// The bridge's id for the request, not the tool call's.
  final String id;

  /// The tool call the request is about.
  final String? toolCallId;

  /// The tool call's title, as the request named it.
  final String? title;

  /// The tool call's kind.
  final String? kind;

  /// The files, and lines, the call would touch.
  final List<acp.ToolCallLocation>? locations;

  /// Proposed changes the agent supplied, shown before an answer.
  final List<acp.ToolCallContent>? content;

  /// The call's arguments, kept only when the request has no content.
  final Object? rawInput;

  /// The agent's own options, in the agent's order.
  final List<acp.PermissionOption> options;

  /// A safety review of the request, from `_meta["chord/permission"]`.
  final PermissionReview? review;

  /// The agent's own deadline for an answer, epoch milliseconds; chord
  /// never computes one.
  final num? deadlineAt;

  /// When the request reached chord, for a request with a deadline or one a
  /// subagent asks.
  final num? at;

  /// This request, reached chord at [at].
  PermissionWait askedAt(num at) => PermissionWait(
    id,
    toolCallId: toolCallId,
    title: title,
    kind: kind,
    locations: locations,
    content: content,
    rawInput: rawInput,
    options: options,
    review: review,
    deadlineAt: deadlineAt,
    at: at,
    subagentId: subagentId,
    detail: detail,
    save: save,
  );

  /// This request, asked by subagent [subagentId].
  PermissionWait askedBy(String subagentId) => PermissionWait(
    id,
    toolCallId: toolCallId,
    title: title,
    kind: kind,
    locations: locations,
    content: content,
    rawInput: rawInput,
    options: options,
    review: review,
    deadlineAt: deadlineAt,
    at: at,
    subagentId: subagentId,
    detail: detail,
    save: save,
  );
}

/// chord's own question in the permission box: what it asks, and the file
/// each choice writes.
final class SaveBox {
  const SaveBox({
    required this.question,
    this.files = const {},
    required this.escape,
    this.asked,
  });

  /// `Change theme?`.
  final String question;

  /// The file each option writes, by its id, as the window shows paths.
  final Map<String, String> files;

  /// What Esc does: `tell claude what to change`.
  final String escape;

  /// The `asked` of the call this box is about, where its row can outgrow
  /// the transcript: which of several waiting calls it is.
  final String? asked;
}

/// How the person answered a permission.
sealed class PermissionAnswer {
  const PermissionAnswer();
}

/// The person chose the agent's option [optionId].
final class Chosen extends PermissionAnswer {
  const Chosen(this.optionId);

  /// The option chosen.
  final String optionId;
}

/// The person rejected the request with Esc.
final class Rejected extends PermissionAnswer {
  const Rejected();
}

/// The request stopped mattering before an answer, as when its turn was
/// cancelled.
final class Withdrawn extends PermissionAnswer {
  const Withdrawn();
}

/// How a turn ended: the agent's answer to its prompt, or why there was
/// none.
sealed class TurnResult {
  const TurnResult();
}

/// The agent answered the prompt with [stopReason].
final class TurnAnswered extends TurnResult {
  const TurnAnswered(this.stopReason, {this.recordedStatus, this.usage});

  /// The turn's tokens as the agent's answer gave them, ACP's `Usage`
  /// without its nulls; null where it gave none.
  final Map<String, num>? usage;

  /// The agent's stop reason: `end_turn`, `cancelled`, or another.
  final String stopReason;

  /// Whether the agent ended the turn because it was cancelled.
  bool get cancelled => recordedStatus == null
      ? stopReason == acp.StopReason.cancelled
      : recordedStatus == 'cancelled';

  /// Historical status is authoritative even when its stop reason disagrees.
  final String? recordedStatus;
}

/// The prompt failed: a JSON-RPC error, or the agent gone.
final class TurnFailed extends TurnResult {
  const TurnFailed(this.message, {this.code, this.recordedCode, this.signIn});

  /// What went wrong.
  final String message;

  /// The JSON-RPC error's code, when there was one.
  final int? code;

  /// The sign-in the agent asked for, when it refused the prompt with
  /// `authRequired`: its words, its ways in and its account then.
  final SignIn? signIn;

  /// Original historical text, retained even when no numeric display fits.
  final String? recordedCode;
}

/// The fields of a `usage_update` chord may work out itself.
const usageFields = ['used', 'size', 'cost'];

/// How much of its context window the session uses, as the agent says.
final class Usage {
  const Usage(this.used, this.size, {this.estimated = const []});

  /// The fields chord worked out itself, among [usageFields]: from the
  /// model's window or the turn's tokens, not the agent's figures.
  final List<String> estimated;

  /// Tokens in the context window now, the agent's number.
  final num used;

  /// The context window's size in tokens; 0 when nobody knows it.
  final num size;
}

/// A session's transcript: its entries, the live plan, the turn, and the
/// status facts the agent reported.
final class Transcript {
  const Transcript({
    this.entries = const [],
    this.plan = const [],
    this.planId,
    this.turn = const Idle(),
    this.usage,
    this.mode,
    this.planAsks = const [],
    this.asking = const [],
    this.served = const [],
  });

  /// Requests chord's server served whose tool call has not come yet,
  /// oldest first; each is tied to its call when that comes.
  final List<ChordCall> served;

  /// The plans put to the person, oldest first, with their answers.
  final List<PlanAsk> planAsks;

  /// Forms and links waiting on the person, oldest first; the first is on
  /// screen. Apart from the turn's status, as a permission may be asked
  /// while one is open.
  final List<ElicitationWait> asking;

  /// Nothing yet: no entries, no plan, no turn.
  static const empty = Transcript();

  /// What the turns drew, oldest first.
  final List<Entry> entries;

  /// The latest plan; each `plan` update replaces it, `[]` clears it.
  final List<acp.PlanEntry> plan;

  /// The id a `plan_update` gave the latest plan, so a `plan_removed` for
  /// another plan leaves it; none when it came as an older `plan` update.
  final String? planId;

  /// Where the turn stands.
  final TurnState turn;

  /// The context window's use, from `usage_update`.
  final Usage? usage;

  /// The current mode's id, from `current_mode_update`.
  final String? mode;

  /// This transcript with [entries] instead.
  Transcript withEntries(List<Entry> entries) => Transcript(
    entries: entries,
    plan: plan,
    planId: planId,
    turn: turn,
    usage: usage,
    mode: mode,
    planAsks: planAsks,
    asking: asking,
    served: served,
  );

  /// This transcript with [turn] instead.
  Transcript withTurn(TurnState turn) => Transcript(
    entries: entries,
    plan: plan,
    planId: planId,
    turn: turn,
    usage: usage,
    mode: mode,
    planAsks: planAsks,
    asking: asking,
    served: served,
  );
}

/// One happening the reducer folds: the agent's update, or a moment no
/// update carries.
sealed class TranscriptAction {
  const TranscriptAction(this.turnId);

  /// The turn the happening belongs to.
  final String turnId;
}

/// The person's prompt, sent at [at].
final class PromptAction extends TranscriptAction {
  const PromptAction(
    super.turnId,
    this.text,
    this.at, {
    this.into,
    this.from,
    this.team,
  });

  /// Who sent it, when another agent or chord did.
  final MessageFrom? from;

  /// The team part that went ahead of the message.
  final TeamPart? team;

  /// The already running turn a personal steering message belongs to.
  final String? into;

  /// The prompt's text.
  final String text;

  /// When it was sent, epoch milliseconds.
  final num at;
}

/// A request chord's own MCP server served to the session: the call that
/// asked for it is drawn by it.
final class ServedAction extends TranscriptAction {
  const ServedAction(super.turnId, this.call, {this.subagentId});

  /// The task agent whose own call it answers, drawn among its work; none
  /// for the session's own.
  final String? subagentId;

  /// The tool, its arguments and chord's answer or refusal.
  final ChordCall call;
}

/// The adapter started an unwanted turn, which chord interrupted.
final class SelfStartedAction extends TranscriptAction {
  const SelfStartedAction(super.turnId, {this.from});

  /// Who sent the message the agent started its turn with, when not the
  /// person.
  final MessageFrom? from;
}

/// One `session/update` from the agent, as it came.
final class UpdateAction extends TranscriptAction {
  const UpdateAction(
    super.turnId,
    this.update, {
    this.at,
    this.unasked = false,
    this.subagentId,
  });

  /// The subagent whose session it came for; none for the session's own.
  final String? subagentId;

  /// A compaction's first update that came with no turn, cycle or settling
  /// under way: the compaction is unasked.
  final bool unasked;

  /// The update, unchecked.
  final acp.SessionUpdate update;

  /// When it reached chord, epoch milliseconds.
  final num? at;
}

/// The agent asked a permission.
final class PermissionRequestedAction extends TranscriptAction {
  const PermissionRequestedAction(
    super.turnId,
    this.wait, {
    this.at,
    this.between = false,
  });

  /// The request, as the screens draw it.
  final PermissionWait wait;

  /// When it was asked, epoch milliseconds.
  final num? at;

  /// Asked with no turn of chord's running.
  final bool between;
}

/// The person answered permission [id], or it was withdrawn.
final class PermissionSettledAction extends TranscriptAction {
  const PermissionSettledAction(super.turnId, this.id, this.answer);

  /// The bridge's id for the request.
  final String id;

  /// How it was answered.
  final PermissionAnswer answer;
}

/// The person asked for the turn to stop, at [at].
final class CancelAction extends TranscriptAction {
  const CancelAction(super.turnId, this.at);

  /// When the cancel was asked for, epoch milliseconds.
  final num at;
}

/// The person stopped subagent [subagentId] alone, or, [stopping] false,
/// the stop could not be sent; recorded, so a resumed transcript says the
/// person ended it.
final class SubagentStoppingAction extends TranscriptAction {
  const SubagentStoppingAction(super.turnId, this.subagentId, this.stopping);
  final String subagentId;
  final bool stopping;
}

/// The agent went away.
final class DisconnectedAction extends TranscriptAction {
  const DisconnectedAction(super.turnId, {this.at});

  /// When chord heard it go, epoch milliseconds.
  final num? at;
}

/// The agent asked a form or link.
final class ElicitationRequestedAction extends TranscriptAction {
  const ElicitationRequestedAction(super.turnId, this.elicitation);
  final ElicitationWait elicitation;
}

/// Form or link [id] was answered, or stopped mattering.
final class ElicitationSettledAction extends TranscriptAction {
  const ElicitationSettledAction(super.turnId, this.id, this.answer);
  final String id;
  final ElicitationAnswer answer;
}

/// The agent put plan [plan] to the person.
final class PlanRequestedAction extends TranscriptAction {
  const PlanRequestedAction(super.turnId, this.plan);
  final PlanWait plan;
}

/// Plan [id] was answered, or stopped mattering.
final class PlanSettledAction extends TranscriptAction {
  const PlanSettledAction(super.turnId, this.id, this.answer);
  final String id;
  final PlanAnswer answer;
}

/// The agent began a cycle of its own, [turnId], with no turn of the
/// person's running, at [at]; its [ResultAction] ends it.
final class CycleStartedAction extends TranscriptAction {
  const CycleStartedAction(super.turnId, this.at);

  /// When it began, epoch milliseconds.
  final num at;
}

final class ResultAction extends TranscriptAction {
  const ResultAction(super.turnId, this.result);

  /// How the turn ended.
  final TurnResult result;
}

/// A turn's figures: its tokens as its answer gave them, empty for an
/// agent's own cycle, and what it cost on its own, with the model it ended
/// on. Said again, whole, when its cost comes after its end; the last for a
/// turn is its. The transcript draws nothing of it.
final class UsageAction extends TranscriptAction {
  const UsageAction(super.turnId, this.figures);

  final TurnFigures figures;
}

/// A failure chord tells, outside a turn's result.
final class FailedAction extends TranscriptAction {
  const FailedAction(super.turnId, this.message);

  /// What failed.
  final String message;
}

/// A warning chord tells.
final class WarnedAction extends TranscriptAction {
  const WarnedAction(super.turnId, this.message);

  /// The warning's words.
  final String message;
}

/// A resumed session's long-lived agents that were open when it was left,
/// which are not reopened with it; [turnId] is the note's own id.
final class LeftOpenAction extends TranscriptAction {
  const LeftOpenAction(super.turnId, this.agents);

  /// Each agent left open, by its name and runtime, a team's run as one.
  final List<LeftOpen> agents;
}

/// Where a fork parted from what it was forked from, by that agent's name,
/// [from], at [at]: what is above it is the source's conversation as it
/// stood.
final class ForkedAction extends TranscriptAction {
  const ForkedAction(super.turnId, this.from, this.at);

  final String from;
  final num at;
}

/// A resumed session's monitors that were running when it was left, which
/// nothing restarts; [turnId] is the note's own id.
final class MonitorsLeftAction extends TranscriptAction {
  const MonitorsLeftAction(super.turnId, this.monitors);

  final List<PastMonitor> monitors;
}

/// A command started by the person, outside an agent turn.
final class ShellStartedAction extends TranscriptAction {
  const ShellStartedAction(super.turnId, this.command);
  final String command;
}

/// Raw stdout or stderr from a running local command.
final class ShellOutputAction extends TranscriptAction {
  const ShellOutputAction(super.turnId, this.stderr, this.text);
  final bool stderr;
  final String text;
}

/// A local shell ended; late or retired actions leave the transcript alone.
final class ShellEndedAction extends TranscriptAction {
  const ShellEndedAction(
    super.turnId, {
    this.code,
    this.stopped = false,
    this.error,
  });
  final num? code;
  final bool stopped;
  final String? error;
}

/// A recorded local run restored from a prompt's context envelope.
final class ShellReplayedAction extends TranscriptAction {
  const ShellReplayedAction(super.turnId, this.run);
  final ShellRun run;
}

/// The tools chord's own MCP server offers, by their wire names.
enum ChordTool {
  listAgents('list_agents'),
  getBudgets('get_budgets'),
  listSessions('list_sessions'),
  listTeams('list_teams'),
  spawnTask('spawn_task'),
  openAgent('open_agent'),
  runTeam('run_team'),
  proposeTeam('propose_team'),
  settings('settings'),
  sendMessage('send_message'),
  closeAgent('close_agent'),
  clearAgent('clear_agent'),
  monitor('monitor'),
  stopMonitor('stop_monitor'),
  listMonitors('list_monitors');

  const ChordTool(this.wire);

  /// The name an agent calls it by.
  final String wire;
}

/// A request chord's MCP server served: the tool, the arguments it was
/// called with, and its answer, or the refusal it gave. A task's id when it
/// started one.
final class ChordCall {
  const ChordCall({
    required this.tool,
    required this.input,
    this.answer,
    this.error,
    this.task,
    this.queued = false,
    this.asked,
    this.pending = false,
    this.settingsFiles,
  });

  final ChordTool tool;
  final Map<String, Object?> input;

  /// The answer, as JSON.
  final Object? answer;

  /// chord's refusal, which the call reads as its failure.
  final String? error;

  /// The task agent `spawn_task` started, by the id it answered.
  final String? task;

  /// A message that waited behind its recipient's turn.
  final bool queued;

  /// What a call served again shares with the one it takes the place of:
  /// a message served sent and again once it went queued after all.
  final String? asked;

  /// Served while the call still waits on the person, as a `settings`
  /// change is drawn while its box is open; the answer served after takes
  /// its place.
  final bool pending;

  /// What a `settings` read of every key says of each file on its row: its
  /// name and state as the window shows them, which the agent's answer
  /// does not hold.
  final ({String user, String project})? settingsFiles;

  /// As a record's `served` and `ran` lines keep it.
  Map<String, Object?> toJson() => {
    'tool': tool.wire,
    'input': input,
    'answer': ?answer,
    'error': ?error,
    'task': ?task,
    if (queued) 'queued': true,
    'asked': ?asked,
    if (pending) 'pending': true,
    if (settingsFiles case (:final user, :final project))
      'settingsFiles': {'user': user, 'project': project},
  };

  /// [json] as a record line keeps a call; none for a tool chord does not
  /// serve or a shape it does not write.
  static ChordCall? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final wire = json['tool'];
    ChordTool? tool;
    for (final each in ChordTool.values) {
      if (each.wire == wire) tool = each;
    }
    final input = json['input'];
    if (tool == null ||
        input is! Map<String, Object?> ||
        (json['error'] != null && json['error'] is! String) ||
        (json['task'] != null && json['task'] is! String) ||
        (json['asked'] != null && json['asked'] is! String)) {
      return null;
    }
    final files = json['settingsFiles'];
    return ChordCall(
      tool: tool,
      input: input,
      answer: json['answer'],
      error: json['error'] as String?,
      task: json['task'] as String?,
      queued: json['queued'] == true,
      asked: json['asked'] as String?,
      pending: json['pending'] == true,
      settingsFiles: switch (files) {
        {'user': final String user, 'project': final String project} => (
          user: user,
          project: project,
        ),
        _ => null,
      },
    );
  }
}

/// What a task's message says beside its words: its report, or the error
/// it ended with.
enum MessageNote { report, failed }

/// Who a message to an agent came from: another agent of the window, or
/// chord.
final class MessageFrom {
  const MessageFrom(
    this.name, {
    this.runtime,
    this.note,
    this.reachable = false,
    this.monitor,
  });

  /// A child's name, `main` for the parent, or `chord`; a monitor's
  /// description.
  final String name;
  final String? runtime;
  final MessageNote? note;

  /// `send_message` reaches it by its name: `main`, or a long-lived child;
  /// never a task, whose name is its title, or chord. Its rows draw
  /// `@name`.
  final bool reachable;

  /// A monitor's events, by its id, and its end on the message that tells
  /// of it.
  final ({String id, MonitorEnd? end})? monitor;

  @override
  bool operator ==(Object other) =>
      other is MessageFrom &&
      other.name == name &&
      other.runtime == runtime &&
      other.note == note &&
      other.reachable == reachable &&
      other.monitor == monitor;

  @override
  int get hashCode => Object.hash(name, runtime, note, reachable, monitor);

  /// As a record keeps it.
  Map<String, Object?> toJson() => {
    'name': name,
    'runtime': ?runtime,
    'note': ?note?.name,
    if (reachable) 'reachable': true,
    if (monitor case (:final id, :final end)?)
      'monitor': {'id': id, 'end': ?end?.toJson()},
  };

  /// [json] as a record keeps a sender; none for a shape it does not know.
  static MessageFrom? fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['name'] is! String) return null;
    if (json['monitor'] case final monitor?) {
      if (monitor is! Map<String, Object?> || monitor['id'] is! String) {
        return null;
      }
      final end = monitor['end'];
      final ended = MonitorEnd.fromJson(end);
      if (end != null && ended == null) return null;
      return MessageFrom(
        json['name'] as String,
        monitor: (id: monitor['id'] as String, end: ended),
        // A legacy wrapper's monitor named as a reachable agent keeps both,
        // as the original's legacyFrom spread does.
        reachable: json['reachable'] == true,
      );
    }
    final runtime = json['runtime'];
    if (runtime != null && runtime is! String) return null;
    return MessageFrom(
      json['name'] as String,
      runtime: runtime as String?,
      note: switch (json['note']) {
        'report' => MessageNote.report,
        'failed' => MessageNote.failed,
        _ => null,
      },
      reachable: json['reachable'] == true,
    );
  }

  @override
  String toString() =>
      'MessageFrom($name, $runtime, $note, $reachable, $monitor)';
}
