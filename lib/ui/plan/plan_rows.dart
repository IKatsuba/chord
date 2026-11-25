import 'dart:math' as math;

import '../../acp/schema.dart' as acp;

/// Checklist marks, matching the agent's plan statuses.
const planMarks = {'pending': '☐', 'in_progress': '◐', 'completed': '☒'};

/// The line a plan hangs from between turns.
String planSummary(List<acp.PlanEntry> plan) =>
    'Plan · ${plan.where((entry) => entry.status == 'completed').length} of ${plan.length} done';

/// A quarter of the window, never fewer than three plan rows.
int planRowLimit(int rows) => math.max(3, rows ~/ 4);

/// A selected plan step or a count of folded steps.
sealed class PlanRow {
  const PlanRow();
}

/// A complete step selected from the agent's plan.
final class EntryPlanRow extends PlanRow {
  const EntryPlanRow(this.entry);
  final acp.PlanEntry entry;
}

/// Completed steps folded before the first visible step.
final class DonePlanRow extends PlanRow {
  const DonePlanRow(this.count);
  final int count;
}

/// Steps folded after the last visible step.
final class MorePlanRow extends PlanRow {
  const MorePlanRow(this.count);
  final int count;
}

/// Fold finished steps first, then the end, retaining the original order.
List<PlanRow> planRows(List<acp.PlanEntry> plan, int limit) {
  final entries = <PlanRow>[for (final entry in plan) EntryPlanRow(entry)];
  if (plan.length <= limit) return entries;
  final open = plan.indexWhere((entry) => entry.status != 'completed');
  final finished = open == -1 ? plan.length : open;
  final folded = math.min(finished, plan.length - limit + 1);
  final head = <PlanRow>[if (folded > 1) DonePlanRow(folded)];
  final rest = entries.skip(folded > 1 ? folded : 0).toList();
  final room = limit - head.length;
  if (rest.length <= room) return [...head, ...rest];
  return [...head, ...rest.take(room - 1), MorePlanRow(rest.length - room + 1)];
}

/// Keys by step content, counting repeated words instead of their positions.
List<String> entryKeys(List<String> contents) {
  final seen = <String, int>{};
  return [for (final content in contents) _entryKey(content, seen)];
}

String _entryKey(String content, Map<String, int> seen) {
  final count = seen[content] ?? 0;
  seen[content] = count + 1;
  return '$count $content';
}
