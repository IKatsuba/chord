/// A plan by id: `plan_update` and `plan_removed`. The older `plan` update,
/// which only replaces the live list, the reducer folds itself. From the
/// original's `session/transcript/plans.ts`.
library;

import 'dart:collection';

import '../../acp/schema.dart' as acp;
import 'entries.dart';
import 'text_run.dart';
import 'types.dart';

/// [state] with the plan [planId] gone, whichever way it was drawn: the
/// live list it is, or the reply its markdown or file became. Other
/// replies and plans stay.
Transcript removePlan(Transcript state, String planId) {
  final entries = [
    for (final entry in state.entries)
      if (!(entry is AssistantEntry && entry.planId == planId)) entry,
  ];
  final listed = state.planId == planId;
  if (!listed && entries.length == state.entries.length) return state;
  return Transcript(
    entries: entries.length == state.entries.length
        ? state.entries
        : UnmodifiableListView(entries),
    plan: listed ? const [] : state.plan,
    planId: listed ? null : state.planId,
    turn: state.turn,
    usage: state.usage,
    mode: state.mode,
    planAsks: state.planAsks,
    asking: state.asking,
    served: state.served,
  );
}

/// A plan by id, as agents that know the client takes one send it: [plan],
/// a `plan_update`'s `plan`. Entries are the live list, as a `plan`
/// update's are; a plan written as markdown or kept in a file is the
/// agent's reply, as such an agent sends it to a client that takes no plan,
/// and each update to it rewrites that reply where it stands.
Transcript updatePlan(
  Transcript state,
  String turnId,
  Map<String, Object?> plan,
) {
  final planId = plan['planId'] as String;
  final type = plan['type'] as String;

  if (type == 'items') {
    final steps = [
      for (final step in plan['entries'] as List<Object?>? ?? const [])
        acp.PlanEntry.fromJson(step as Map<String, Object?>),
    ];
    // Read here, inside the reducer's catch, so a malformed step never
    // reaches state.
    for (final step in steps) {
      (step.content, step.priority, step.status);
    }
    return Transcript(
      entries: state.entries,
      plan: UnmodifiableListView(steps),
      planId: planId,
      turn: state.turn,
      usage: state.usage,
      mode: state.mode,
      planAsks: state.planAsks,
      asking: state.asking,
      served: state.served,
    );
  }

  final text = switch (type) {
    'markdown' => plan['content'] as String,
    'file' => plan['uri'] as String,
    _ => null,
  };
  if (text == null) return state;

  if (type == 'markdown') {
    state = state.withEntries(_shownOnce(state.entries, turnId, text));
  }

  final index = state.entries.indexWhere(
    (entry) => entry is AssistantEntry && entry.planId == planId,
  );
  if (index < 0) {
    return text.isEmpty
        ? state
        : state.withEntries(
            appended(state.entries, [
              AssistantEntry(turnId, TextRun.empty.plus(text), planId: planId),
            ]),
          );
  }
  final entry = state.entries[index] as AssistantEntry;
  return state.withEntries(
    replacedAt(
      state.entries,
      index,
      AssistantEntry(
        entry.turnId,
        TextRun.empty.plus(text),
        messageId: entry.messageId,
        planId: planId,
        identity: entry.identity,
      ),
    ),
  );
}

/// [entries] with the plan [text] taken out of the turn's latest mode
/// switch that carries it as its content, as Claude's adapter sends an
/// approved plan both ways: the plan is shown once, as the plan. A switch
/// whose text is not the plan, as a rejected or edited one is, keeps it.
List<Entry> _shownOnce(List<Entry> entries, String turnId, String text) {
  final plan = text.trim();
  final index = entries.lastIndexWhere(
    (entry) =>
        entry is ToolEntry &&
        entry.turnId == turnId &&
        entry.call.kind == 'switch_mode',
  );
  if (index < 0 || plan.isEmpty) return entries;
  final entry = entries[index] as ToolEntry;
  final content = entry.call.content ?? const <acp.ToolCallContent>[];
  bool isText(acp.ToolCallContent block) =>
      block.type == 'content' && block.content!.type == 'text';
  final said = [
    for (final block in content)
      if (isText(block)) block.content!.text!,
  ].join().trim();
  if (said != plan) return entries;
  final call = entry.call;
  return replacedAt(
    entries,
    index,
    ToolEntry(
      entry.turnId,
      ToolCall(
        call.id,
        title: call.title,
        kind: call.kind,
        status: call.status,
        locations: call.locations,
        content: UnmodifiableListView([
          for (final block in content)
            if (!isText(block)) block,
        ]),
        rawInput: call.rawInput,
        rawOutput: call.rawOutput,
        guardian: call.guardian,
        mcp: call.mcp,
        review: call.review,
        terminals: call.terminals,
        plan: call.plan,
        asked: call.asked,
        chord: call.chord,
        cut: call.cut,
      ),
      identity: entry.identity,
    ),
  );
}
