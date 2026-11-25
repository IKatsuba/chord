/// chord's own calls: a request chord's MCP server served, tied to the tool
/// call the agent made for it by the arguments both carry, since chord knows
/// its own calls by what it served and not by how an adapter titles them.
/// A `spawn_task` call is replaced by the task agent it started, which then
/// stands where the call stood.
library;

import 'package:collection/collection.dart';

import 'entries.dart';
import 'subagents.dart' show changeSubagent;
import 'types.dart';

/// `mcp__<server>__<tool>`: the server up to the next `__`, the tool the
/// rest.
final mcpTitle = RegExp(r'^mcp__(.+?)__(.+)$', dotAll: true);

/// chord's tool called [wire] on its server; none for another name.
ChordTool? chordToolNamed(String wire) {
  for (final tool in ChordTool.values) {
    if (tool.wire == wire) return tool;
  }
  return null;
}

/// The call of chord's own tools [call] asked for, served or not: the
/// request chord served for it, or else the tool and arguments read from
/// the call as the agent sent it, Codex's wrapper as chord's enrichers filed
/// it or Claude's `mcp__<server>__<tool>` title with its `rawInput`, on the
/// server the session gave chord's, [chordServer]; none for any other.
ChordCall? chordCallOf(ToolCall call, String? chordServer) {
  if (call.chord case final chord?) return chord;
  final String? server;
  final String? tool;
  final Object? input;
  if (call.mcp case final mcp?) {
    (server, tool, input) = (mcp.server, mcp.tool, mcp.input);
  } else {
    final match = mcpTitle.firstMatch(call.title?.trim() ?? '');
    (server, tool, input) = (match?[1], match?[2], call.rawInput);
  }
  final named = tool == null ? null : chordToolNamed(tool);
  if (chordServer == null || server != chordServer || named == null) {
    return null;
  }
  return ChordCall(
    tool: named,
    input: input is Map<String, Object?> ? input : const {},
  );
}

/// A request served: tied to its call where that is already in the
/// transcript, or kept until the call comes. A task agent's own call, by
/// [subagentId], is tied among its work, where its call always came first.
Transcript served(Transcript state, ChordCall call, {String? subagentId}) {
  if (subagentId != null) {
    final entries = changeSubagent(state.entries, subagentId, (subagent) {
      final linked = _link(subagent.entries, call);
      return linked == null ? subagent : subagent.copyWith(entries: linked);
    });
    return identical(entries, state.entries)
        ? state
        : state.withEntries(entries);
  }
  final linked = _link(state.entries, call);
  if (linked != null) return state.withEntries(linked);
  // A call served again, whose call has not come yet either.
  final waiting = state.served;
  final pending = waiting.indexWhere((each) => _answers(call, each));
  return _withServed(
    state,
    pending < 0
        ? [...waiting, call]
        : [for (final (i, each) in waiting.indexed) i == pending ? call : each],
  );
}

/// After call [toolCallId] was merged: tied to a request served before it
/// came, if one with its arguments waits.
Transcript awaitedCall(Transcript state, String toolCallId) {
  final waiting = state.served;
  if (waiting.isEmpty) return state;
  final at = state.entries.lastIndexWhere(
    (entry) => entry is ToolEntry && entry.call.id == toolCallId,
  );
  if (at < 0) return state;
  final call = (state.entries[at] as ToolEntry).call;
  if (call.chord != null) return state;
  final match = waiting.indexWhere((each) => _sameCall(call, each));
  if (match < 0) return state;
  final linked = _link(state.entries, waiting[match]);
  if (linked == null) return state;
  return _withServed(state.withEntries(linked), [
    for (final (i, each) in waiting.indexed)
      if (i != match) each,
  ]);
}

Transcript _withServed(Transcript state, List<ChordCall> served) => Transcript(
  entries: state.entries,
  plan: state.plan,
  planId: state.planId,
  turn: state.turn,
  usage: state.usage,
  mode: state.mode,
  planAsks: state.planAsks,
  asking: state.asking,
  served: List.unmodifiable(served),
);

/// Whether [call] takes the place of [earlier]: it served again, as a
/// message that went queued after all is.
bool _answers(ChordCall call, ChordCall earlier) =>
    earlier.asked != null && earlier.asked == call.asked;

/// Whether [call] is the one [chord] served: the arguments are the same, as
/// its `rawInput` holds them or, where the agent wrapped them, as chord's
/// enrichers filed them with the tool's name, which must be the same too;
/// which server the agent named is not read.
bool _sameCall(ToolCall call, ChordCall chord) {
  if (call.chord != null) return false;
  final mcp = call.mcp;
  return mcp == null
      ? call.rawInput != null && _equal(call.rawInput, chord.input)
      : mcp.tool == chord.tool.wire && _equal(mcp.input, chord.input);
}

/// [entries] with [chord] tied to its call, the latest not yet tied with
/// the same arguments, one whose title names the tool first; null when
/// none is there.
List<Entry>? _link(List<Entry> entries, ChordCall chord) {
  // A call served again takes the place of what was served before.
  final waited = entries.lastIndexWhere(
    (entry) =>
        entry is ToolEntry &&
        entry.call.chord != null &&
        _answers(chord, entry.call.chord!),
  );
  if (waited >= 0) return _tied(entries, waited, chord);
  final candidates = [
    for (final (i, entry) in entries.indexed)
      if (entry is ToolEntry && _sameCall(entry.call, chord)) i,
  ];
  final named = candidates.where(
    (i) =>
        ((entries[i] as ToolEntry).call.title ?? '').contains(chord.tool.wire),
  );
  final at = named.lastOrNull ?? candidates.lastOrNull;
  if (at == null) return null;
  final task = chord.task == null
      ? -1
      : entries.indexWhere(
          (each) => each is SubagentEntry && each.subagent.id == chord.task,
        );
  if (task < 0) return _tied(entries, at, chord);
  // The task stands where its call stood, and takes the call's updates.
  final call = entries[at] as ToolEntry;
  final started = (entries[task] as SubagentEntry).subagent;
  return movedTo(
    entries,
    task,
    at,
    SubagentEntry(call.turnId, started.copyWith(callId: call.call.id)),
  );
}

/// Whether an update for [toolCallId] is a `spawn_task` call's that a task
/// already stands in place of, and so draws nothing more.
bool replacedCall(List<Entry> entries, String toolCallId) => entries.any(
  (entry) => entry is SubagentEntry && entry.subagent.callId == toolCallId,
);

List<Entry> _tied(List<Entry> entries, int at, ChordCall chord) {
  final entry = entries[at] as ToolEntry;
  return replacedAt(
    entries,
    at,
    ToolEntry(
      entry.turnId,
      entry.call.withChord(chord),
      identity: entry.identity,
    ),
  );
}

/// JSON values compared by what they hold, as the original's
/// `isDeepStrictEqual` compares arguments: maps by key, lists in order.
bool _equal(Object? a, Object? b) =>
    const DeepCollectionEquality().equals(a, b);
