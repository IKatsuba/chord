/// A compaction the agent ran, by its id, with the summary it kept, from the
/// original's `session/transcript/compactions.ts`.
library;

import '../../acp/schema.dart' as acp;
import 'entries.dart';
import 'messages.dart';
import 'types.dart';

/// [state] with [update], a `compaction_update` or
/// `compaction_summary_chunk`, folded in: a compaction where its first
/// update put it, each later update patching it in place as ACP says. A
/// `summary` or `error` left out keeps what was there, `null` clears it.
/// The first update may already be the last, as when an agent replays a
/// compaction that is over. A chunk for a compaction never opened is
/// dropped, as ACP sends none before one. Whether it is [unasked] is said
/// by its opening update and kept by every later one.
Transcript mergeCompaction(
  Transcript state,
  String turnId,
  acp.SessionUpdate update, {
  bool unasked = false,
}) {
  final json = update.toJson();
  final id = json['compactionId'] as String;
  final index = state.entries.lastIndexWhere(
    (entry) => entry is CompactionEntry && entry.compaction.id == id,
  );
  final found = index < 0 ? null : state.entries[index] as CompactionEntry;

  if (update.kind == acp.SessionUpdateKind.compactionSummaryChunk) {
    final text = textOf(
      acp.ContentBlock.fromJson(json['content'] as Map<String, Object?>),
    );
    if (found == null || text.isEmpty) return state;
    final before = found.compaction;
    return state.withEntries(
      replacedAt(
        state.entries,
        index,
        CompactionEntry(
          found.turnId,
          Compaction(
            before.id,
            before.status,
            summary: before.summary + text,
            error: before.error,
            unasked: before.unasked,
          ),
        ),
      ),
    );
  }

  final status = json['status'] as String;
  final before = found?.compaction ?? Compaction(id, status, unasked: unasked);
  final summary = json.containsKey('summary')
      ? [
          for (final block in (json['summary'] as List<Object?>?) ?? const [])
            textOf(acp.ContentBlock.fromJson(block as Map<String, Object?>)),
        ].join()
      : before.summary;
  final error = json.containsKey('error')
      ? json['error'] as String?
      : before.error;
  final compaction = Compaction(
    id,
    status,
    summary: summary,
    error: error,
    unasked: before.unasked,
  );

  if (found == null) {
    return state.withEntries(
      appended(state.entries, [CompactionEntry(turnId, compaction)]),
    );
  }
  return state.withEntries(
    replacedAt(state.entries, index, CompactionEntry(found.turnId, compaction)),
  );
}
