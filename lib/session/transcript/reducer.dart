/// The transcript's reducer: folds the session layer's happenings, the
/// agent's updates as they came and the moments no update carries, into
/// [Transcript].
library;

import 'dart:collection';

import '../../acp/schema.dart' as acp;
import '../enrich.dart' show filledIn;
import 'chord.dart';
import 'compactions.dart';
import 'subagents.dart';
import 'entries.dart';
import 'messages.dart';
import 'notices.dart';
import 'permissions.dart';
import 'plans.dart';
import 'tools.dart';
import 'turn.dart';
import 'shell.dart';
import 'types.dart';

/// [state] with [action] folded in; the identical state when it changes
/// nothing.
Transcript reduceTranscript(Transcript state, TranscriptAction action) {
  final last = state.entries.lastOrNull;
  if (last is SelfStartedEntry &&
      action is! SelfStartedAction &&
      action.turnId == last.turnId) {
    final under = _reduceAction(
      state.withEntries(lastRemoved(state.entries)),
      action,
    );
    return under.withEntries(
      lastRestored(under.entries, _closed(under.entries, last)),
    );
  }
  return _reduceAction(state, action);
}

SelfStartedEntry _closed(List<Entry> entries, SelfStartedEntry line) {
  final alone = entries.lastOrNull?.turnId != line.turnId;
  return line.alone == alone
      ? line
      : SelfStartedEntry(
          line.turnId,
          alone: alone,
          from: line.from,
          identity: line.identity,
        );
}

Transcript _reduceAction(Transcript state, TranscriptAction action) =>
    switch (action) {
      ShellStartedAction() ||
      ShellOutputAction() ||
      ShellEndedAction() ||
      ShellReplayedAction() => reduceShell(state, action),
      PromptAction(
        :final turnId,
        :final text,
        :final at,
        :final into,
        :final from,
        :final team,
      ) =>
        prompted(state, turnId, text, at, into: into, from: from, team: team),
      SelfStartedAction(:final turnId, :final from) => state.withEntries(
        appended(state.entries, [
          _closed(state.entries, SelfStartedEntry(turnId, from: from)),
        ]),
      ),
      UpdateAction() => _update(state, action),
      PermissionRequestedAction(
        :final turnId,
        :final wait,
        :final at,
        :final between,
      ) =>
        permissionRequested(state, turnId, wait, at: at ?? 0, between: between),
      PermissionSettledAction(:final turnId, :final id, :final answer) =>
        permissionSettled(state, turnId, id, answer),
      ElicitationRequestedAction(:final turnId, :final elicitation) =>
        elicitationRequested(state, turnId, elicitation),
      ElicitationSettledAction(:final turnId, :final id, :final answer) =>
        elicitationSettled(state, turnId, id, answer),
      PlanRequestedAction(:final turnId, :final plan) => _planRequested(
        state,
        turnId,
        plan,
      ),
      PlanSettledAction(:final id, :final answer) => _planSettled(
        state,
        id,
        answer,
      ),
      CancelAction(:final turnId, :final at) => cancelled(state, turnId, at),
      SubagentStoppingAction(:final subagentId, :final stopping) =>
        subagentStopping(state, subagentId, stopping),
      DisconnectedAction(:final at) => disconnected(state, at),
      CycleStartedAction(:final turnId, :final at) => cycleStarted(
        state,
        turnId,
        at,
      ),
      ResultAction(:final turnId, :final result) => settle(
        state,
        turnId,
        result,
      ),
      UsageAction() => state,
      ServedAction(:final call, :final subagentId) => served(
        state,
        call,
        subagentId: subagentId,
      ),
      LeftOpenAction(:final turnId, :final agents) => state.withEntries(
        appended(state.entries, [LeftOpenEntry(turnId, agents)]),
      ),
      ForkedAction(:final turnId, :final from, :final at) => state.withEntries(
        appended(state.entries, [ForkedEntry(turnId, from, at)]),
      ),
      MonitorsLeftAction(:final turnId, :final monitors) => state.withEntries(
        appended(state.entries, [MonitorsLeftEntry(turnId, monitors)]),
      ),
      FailedAction(:final turnId, :final message) => state.withEntries(
        appended(state.entries, [ErrorEntry(turnId, message)]),
      ),
      WarnedAction(:final turnId, :final message) => state.withEntries(
        appended(state.entries, [WarningEntry(turnId, message)]),
      ),
    };

Transcript _update(Transcript state, UpdateAction action) {
  try {
    final next = action.subagentId == null
        ? applyUpdate(
            state,
            action.turnId,
            action.update,
            unasked: action.unasked,
            at: action.at,
          )
        : childUpdate(
            state,
            action,
            (state, turnId, update, at) =>
                applyUpdate(state, turnId, update, at: at),
          );
    // Said here, at the top, with the turn that runs, whether the agent item
    // that ended is the session's own or one under another's work.
    if (action.update.kind == 'subagent_update' && !identical(next, state)) {
      final lines = itemEndLines(state.entries, next.entries, state.turn);
      return lines.isEmpty
          ? next
          : next.withEntries(appended(next.entries, lines));
    }
    return next;
  } on Object {
    // Updates are not checked on arrival (CTUI-12): one the agent sent
    // malformed draws nothing, and the next still draws.
    return state;
  }
}

/// [state] with the agent's [update] folded in under turn [turnId]; throws
/// where the update is malformed, leaving [state] as it was.
Transcript applyUpdate(
  Transcript state,
  String turnId,
  acp.SessionUpdate update, {
  bool unasked = false,
  num? at,
}) {
  switch (update.kind) {
    case 'subagent_update':
      return mergeSubagent(state, turnId, update, at);
    case 'session_message':
      return agentMessage(state, turnId, update);
    case acp.SessionUpdateKind.agentMessageChunk:
    case acp.SessionUpdateKind.agentThoughtChunk:
      final chunk = update as acp.ContentChunk;

      return appendText(
        state,
        turnId,
        thought: update.kind == acp.SessionUpdateKind.agentThoughtChunk,
        content: chunk.content,
        messageId: chunk.messageId,
      );
    case acp.SessionUpdateKind.toolCall:
    case acp.SessionUpdateKind.toolCallUpdate:
      final id = (update as acp.ToolCallUpdate).toolCallId;
      return replacedCall(state.entries, id)
          ? state
          : awaitedCall(mergeToolCall(state, turnId, update), id);
    case acp.SessionUpdateKind.plan:
      final steps = (update as acp.Plan).entries;

      // The views read lazily: a step's fields are read here, inside the
      // catch, so a malformed one never reaches state for settle or a
      // screen to trip on.
      for (final step in steps) {
        (step.content, step.priority, step.status);
      }

      return Transcript(
        entries: state.entries,
        plan: UnmodifiableListView(steps),
        turn: state.turn,
        usage: state.usage,
        mode: state.mode,
        planAsks: state.planAsks,
        asking: state.asking,
        served: state.served,
      );
    case acp.SessionUpdateKind.planUpdate:
      return updatePlan(
        state,
        turnId,
        update.toJson()['plan']! as Map<String, Object?>,
      );
    case acp.SessionUpdateKind.planRemoved:
      return removePlan(state, update.toJson()['planId']! as String);
    case acp.SessionUpdateKind.usageUpdate:
      final usage = update as acp.UsageUpdate;

      return Transcript(
        entries: state.entries,
        plan: state.plan,
        planId: state.planId,
        turn: state.turn,
        usage: Usage(
          usage.used,
          usage.size,
          estimated: [
            for (final field in filledIn(update.toJson()))
              if (usageFields.contains(field)) field,
          ],
        ),
        mode: state.mode,
        planAsks: state.planAsks,
        asking: state.asking,
        served: state.served,
      );
    case acp.SessionUpdateKind.currentModeUpdate:
      return Transcript(
        entries: state.entries,
        plan: state.plan,
        planId: state.planId,
        turn: state.turn,
        usage: state.usage,
        mode: (update as acp.CurrentModeUpdate).currentModeId,
        planAsks: state.planAsks,
        asking: state.asking,
        served: state.served,
      );
    case acp.SessionUpdateKind.notice:
      return addNotice(state, turnId, update);
    case acp.SessionUpdateKind.compactionUpdate:
    case acp.SessionUpdateKind.compactionSummaryChunk:
      return mergeCompaction(state, turnId, update, unasked: unasked);
    // The prompt is drawn from what was sent; the rest is not drawn yet.
    default:
      return state;
  }
}

/// Inserts or replaces a local command note by its stable operation id.
Transcript noted(
  Transcript state,
  String id,
  String command,
  String text, {
  bool failed = false,
}) {
  final index = state.entries.indexWhere(
    (e) => e is NotedEntry && e.turnId == id,
  );
  final entry = NotedEntry(id, command, text, failed: failed);
  return state.withEntries(
    index < 0
        ? appended(state.entries, [entry])
        : replacedAt(state.entries, index, entry),
  );
}

/// [entries] with [ask] drawn under the tool call it names, the latest one
/// of that id; as they were when there is none.
List<Entry> _withPlan(List<Entry> entries, PlanAsk ask) {
  final at = entries.lastIndexWhere(
    (entry) => entry is ToolEntry && entry.call.id == ask.wait.toolCallId,
  );
  if (at < 0) return entries;
  final entry = entries[at] as ToolEntry;
  return replacedAt(
    entries,
    at,
    ToolEntry(entry.turnId, entry.call.withPlan(ask), identity: entry.identity),
  );
}

Transcript _withAsks(
  Transcript state,
  List<Entry> entries,
  List<PlanAsk> asks,
) => Transcript(
  entries: entries,
  plan: state.plan,
  planId: state.planId,
  turn: state.turn,
  usage: state.usage,
  mode: state.mode,
  planAsks: UnmodifiableListView(asks),
  asking: state.asking,
  served: state.served,
);

/// A plan put to the person, after the permissions already waiting, which
/// go before it; one already asked is not asked twice.
Transcript _planRequested(Transcript state, String turnId, PlanWait plan) {
  if (state.planAsks.any((ask) => ask.wait.id == plan.id)) return state;
  final turn = state.turn;
  final waiting = turn is AwaitingPermission
      ? [for (final wait in turn.permissions) wait.id]
      : const <String>[];
  final ask = PlanAsk(turnId, plan, after: List.unmodifiable(waiting));
  return _withAsks(state, _withPlan(state.entries, ask), [
    ...state.planAsks,
    ask,
  ]);
}

/// Plan [id] answered: its answer drawn under its call.
Transcript _planSettled(Transcript state, String id, PlanAnswer answer) {
  final ask = state.planAsks
      .where((each) => each.wait.id == id && each.answer == null)
      .firstOrNull;
  if (ask == null) return state;
  final answered = ask.answered(answer);
  return _withAsks(state, _withPlan(state.entries, answered), [
    for (final each in state.planAsks) identical(each, ask) ? answered : each,
  ]);
}
