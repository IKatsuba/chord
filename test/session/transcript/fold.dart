/// Folding actions through the transcript's reducer, and describing the
/// state by value, for its tests.
library;

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/terminal_text.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';

/// [actions] folded from [from].
Transcript fold(List<TranscriptAction> actions, [Transcript? from]) =>
    actions.fold(from ?? Transcript.empty, reduceTranscript);

/// The state after each action, to check what happened on the way.
List<Transcript> states(List<TranscriptAction> actions) {
  final seen = <Transcript>[];

  actions.fold(Transcript.empty, (state, action) {
    final next = reduceTranscript(state, action);

    seen.add(next);

    return next;
  });

  return seen;
}

/// An update from its JSON.
UpdateAction update(String turnId, Map<String, Object?> json) =>
    UpdateAction(turnId, acp.SessionUpdate.fromJson(json));

/// An `agent_message_chunk` of [text].
UpdateAction say(String turnId, String text, {String? messageId}) =>
    update(turnId, {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': text},
      'messageId': ?messageId,
    });

/// An `agent_thought_chunk` of [text].
UpdateAction think(String turnId, String text) => update(turnId, {
  'sessionUpdate': 'agent_thought_chunk',
  'content': {'type': 'text', 'text': text},
});

/// A `plan` update of [steps], each `(content, status)`.
UpdateAction plan(String turnId, List<(String, String)> steps) =>
    update(turnId, {
      'sessionUpdate': 'plan',
      'entries': [
        for (final (content, status) in steps)
          {'content': content, 'priority': 'medium', 'status': status},
      ],
    });

/// [transcript] as plain values, every field of every kind.
Map<String, Object?> described(Transcript transcript) => {
  'entries': transcript.entries.map(describedEntry).toList(),
  'plan': transcript.plan.map(_step).toList(),
  'turn': describedTurn(transcript.turn),
  if (transcript.usage case final usage?)
    'usage': {'used': usage.used, 'size': usage.size},
  'mode': ?transcript.mode,
};

/// One entry as plain values.
Map<String, Object?> describedEntry(Entry entry) => {
  'turnId': entry.turnId,
  ...switch (entry) {
    HistoryOmittedEntry() => {'kind': 'history_omitted'},
    ShellEntry(:final run) => {
      'kind': 'shell',
      'command': run.command,
      'stdout': run.stdout,
      'stderr': run.stderr,
      'running': run.running,
      'code': ?run.code,
      if (run.stopped) 'stopped': true,
      'error': ?run.error,
      if (run.truncated) 'truncated': true,
    },
    UserEntry(:final text) => {'kind': 'user', 'text': text},
    NoticeEntry(:final severity, :final title, :final description) => {
      'kind': 'notice',
      'severity': severity.name,
      'title': title,
      'description': ?description,
    },
    ElicitationEntry(:final wait, :final outcome, :final content) => {
      'kind': 'elicitation',
      'wait': describedElicitation(wait),
      'outcome': outcome.name,
      'content': ?content,
    },
    SubagentEntry(:final subagent) => {
      'kind': 'subagent',
      'subagent': describedSubagent(subagent),
    },
    AgentMessageEntry(
      :final messageId,
      :final toSubagent,
      :final agentId,
      :final title,
      :final text,
      :final launch,
    ) =>
      {
        'kind': 'agent_message',
        'messageId': messageId,
        'direction': toSubagent ? 'to' : 'from',
        'agentId': agentId,
        'title': ?title,
        'text': text,
        if (launch) 'launch': true,
      },
    ChildMessageEntry(
      :final from,
      :final text,
      :final messageId,
      :final byAgent,
    ) =>
      {
        'kind': 'message',
        'from': from,
        'text': text,
        'messageId': ?messageId,
        if (byAgent) 'byAgent': true,
      },
    ItemEndedEntry(
      :final name,
      :final end,
      :final startedAt,
      :final endedAt,
      :final error,
    ) =>
      {
        'kind': 'item_ended',
        'name': name,
        'end': end.name,
        'startedAt': ?startedAt,
        'endedAt': ?endedAt,
        'error': ?error,
      },
    CompactionEntry(:final compaction) => {
      'kind': 'compaction',
      'compaction': describedCompaction(compaction),
    },
    SelfStartedEntry(:final alone) => {'kind': 'self_started', 'alone': alone},
    ReportEntry(:final command, :final rows) => {
      'kind': 'report',
      'command': command,
      'rows': rows,
    },
    TeamPartEntry(:final part) => {
      'kind': 'team_part',
      'team': part.team,
      'member': part.member,
    },
    TeamShownEntry(:final command, :final shown) => {
      'kind': 'team_shown',
      'command': command,
      'shown': shown.runtimeType.toString(),
    },
    LeftOpenEntry(:final agents) => {
      'kind': 'left_open',
      'agents': [for (final a in agents) '${a.name} (${a.runtime})'],
    },
    ForkedEntry(:final from) => {'kind': 'forked', 'from': from},
    MonitorsLeftEntry(:final monitors) => {
      'kind': 'monitors_left',
      'monitors': [for (final m in monitors) '${m.id} (${m.description})'],
    },
    TypedCallEntry(:final command, :final call) => {
      'kind': 'typed_call',
      'command': command,
      'tool': call.tool.wire,
      'input': call.input,
      'answer': ?call.answer,
    },
    NotedEntry(:final command, :final text, :final failed) => {
      'kind': 'noted',
      'command': command,
      'text': text,
      'failed': failed,
    },
    AssistantEntry(:final text, :final messageId) => {
      'kind': 'assistant',
      'text': text.text,
      'messageId': ?messageId,
    },
    ThoughtEntry(:final text, :final messageId) => {
      'kind': 'thought',
      'text': text.text,
      'messageId': ?messageId,
    },
    ToolEntry(:final call) => {'kind': 'tool', 'call': describedCall(call)},
    PermissionEntry(:final title, :final option, :final review) => {
      'kind': 'permission',
      'title': ?title,
      if (option != null) 'option': describedOption(option),
      if (review != null) 'review': describedReview(review),
    },
    CancelledEntry() => {'kind': 'cancelled'},
    StoppedEntry(:final reason) => {'kind': 'stopped', 'reason': reason},
    ErrorEntry(:final message, :final code) => {
      'kind': 'error',
      'message': message,
      'code': ?code,
    },
    WarningEntry(:final message) => {'kind': 'warning', 'message': message},
    FinishedPlanEntry(:final entries) => {
      'kind': 'plan',
      'entries': entries.map(_step).toList(),
    },
  },
};

/// A form or link as plain values.
Map<String, Object?> describedElicitation(ElicitationWait wait) => {
  'id': wait.id,
  'message': wait.message,
  'toolCallId': ?wait.toolCallId,
  'at': ?wait.at,
  if (wait.between) 'between': true,
  'asker': ?wait.asker,
  ...switch (wait) {
    FormWait(:final schema) => {'mode': 'form', 'schema': schema},
    LinkWait(:final url) => {'mode': 'url', 'url': url},
  },
};

/// A subagent as plain values, as the original's tests compare it.
Map<String, Object?> describedSubagent(Subagent subagent) => {
  'id': subagent.id,
  'title': ?subagent.title,
  'description': ?subagent.description,
  'prompt': ?subagent.prompt,
  'promptId': ?subagent.promptId,
  if (subagent.addressed) 'addressed': true,
  if (subagent.namedByTitle) 'namedByTitle': true,
  'state': subagent.state.name,
  if (subagent.cancellable) 'cancellable': true,
  if (subagent.offeredCancel) 'offeredCancel': true,
  if (subagent.waiting case final waiting?)
    'waiting': {'since': ?waiting.since},
  'error': ?subagent.error,
  'startedAt': ?subagent.startedAt,
  'endedAt': ?subagent.endedAt,
  'entries': subagent.entries.map(describedEntry).toList(),
  'plan': [for (final step in subagent.plan) step.content],
  'planId': ?subagent.planId,
  'planAt': ?subagent.planAt,
};

/// A compaction as plain values, as the original's tests compare it.
Map<String, Object?> describedCompaction(Compaction compaction) => {
  'id': compaction.id,
  'status': compaction.status,
  'summary': compaction.summary,
  'error': ?compaction.error,
  if (compaction.unasked) 'unasked': true,
};

/// A tool call as plain values, ACP's data as it came.
Map<String, Object?> describedCall(ToolCall call) => {
  'id': call.id,
  'title': ?call.title,
  'kind': ?call.kind,
  'status': ?call.status,
  if (call.locations case final locations?)
    'locations': [
      for (final location in locations)
        {'path': location.path, 'line': ?location.line},
    ],
  if (call.content case final content?)
    'content': [for (final item in content) item.toJson()],
  'rawInput': ?call.rawInput,
  'rawOutput': ?call.rawOutput,
  'guardian': ?call.guardian,
  if (call.mcp case final mcp?)
    'mcp': {'server': ?mcp.server, 'tool': mcp.tool, 'input': mcp.input},
  if (call.review case final review?) 'review': describedReview(review),
  if (call.terminals case final terminals?)
    'terminals': terminals.map(describedTerminal).toList(),
};

/// A terminal as plain values, as the original's tests compare it.
Map<String, Object?> describedTerminal(Terminal terminal) => {
  'id': terminal.id,
  'output': terminal.output,
  if (terminal.cursor case final cursor?)
    'cursor': {'row': cursor.row, 'column': cursor.column},
  if (terminal.escape case final escape?)
    'escape': switch (escape) {
      EscapeOpen(:final intermediates) => {
        'kind': 'escape',
        if (intermediates) 'intermediates': true,
      },
      CsiOpen(:final params, :final ignored) => {
        'kind': 'csi',
        'params': params,
        if (ignored) 'ignored': true,
      },
      StringOpen() => {'kind': 'string'},
    },
  'cwd': ?terminal.cwd,
  'exited': terminal.exited,
  'exitCode': ?terminal.exitCode,
  'signal': ?terminal.signal,
  if (terminal.truncated) 'truncated': true,
};

/// A permission option as plain values.
Map<String, Object?> describedOption(acp.PermissionOption option) => {
  'optionId': option.optionId,
  'name': option.name,
  'kind': option.kind,
};

/// A review as plain values.
Map<String, Object?> describedReview(PermissionReview review) => {
  'outcome': review.outcome,
  'reason': review.reason,
};

/// A permission wait as plain values, ACP's data as it came.
Map<String, Object?> describedWait(PermissionWait wait) => {
  'id': wait.id,
  'toolCallId': ?wait.toolCallId,
  'title': ?wait.title,
  'kind': ?wait.kind,
  if (wait.locations case final locations?)
    'locations': [
      for (final location in locations)
        {'path': location.path, 'line': ?location.line},
    ],
  if (wait.content case final content?)
    'content': [for (final item in content) item.toJson()],
  'rawInput': ?wait.rawInput,
  'options': wait.options.map(describedOption).toList(),
  if (wait.review case final review?) 'review': describedReview(review),
  'deadlineAt': ?wait.deadlineAt,
  'at': ?wait.at,
};

/// A turn as plain values.
Map<String, Object?> describedTurn(TurnState turn) => switch (turn) {
  Idle() => {'status': 'idle'},
  Working(:final turnId, :final since) => {
    'status': 'working',
    'turnId': turnId,
    'since': since,
  },
  AwaitingPermission(
    :final turnId,
    :final since,
    :final permissions,
    :final between,
  ) =>
    {
      'status': 'awaiting_permission',
      'turnId': turnId,
      'since': since,
      'permissions': permissions.map(describedWait).toList(),
      if (between) 'between': true,
    },
  Cancelling(:final turnId, :final since, :final cancelledAt) => {
    'status': 'cancelling',
    'turnId': turnId,
    'since': since,
    'cancelledAt': cancelledAt,
  },
};

List<String> _step(acp.PlanEntry step) => [
  step.content,
  step.priority,
  step.status,
];
