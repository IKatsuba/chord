/// How the reducers write a transcript's entries: each write gives a new,
/// unmodifiable list, so a new list is the change a screen reads as news.
library;

import 'dart:collection';

import 'types.dart';
import 'reducer.dart' show reduceTranscript;

/// [entries] with [more] after them.
List<Entry> appended(List<Entry> entries, List<Entry> more) {
  if (entries is _ReplayEntries) {
    for (final entry in more) {
      entries._entries.add(_identified(entry, EntryIdentity()));
      if (entries.work != null) entries.work!.appendedEntries++;
    }
    return entries;
  }
  return UnmodifiableListView([
    ...entries,
    for (final entry in more) _identified(entry, EntryIdentity()),
  ]);
}

/// [entries] with their last one [entry] instead.
List<Entry> lastReplaced(List<Entry> entries, Entry entry) =>
    replacedAt(entries, entries.length - 1, entry);

/// [entries] with the one at [at] [entry] instead.
List<Entry> replacedAt(List<Entry> entries, int at, Entry entry) {
  if (entries is _ReplayEntries) {
    entries._entries[at] = _identified(entry, entries[at].identity);
    if (entries.work != null) entries.work!.replacedEntries++;
    return entries;
  }
  final out = [...entries];

  out[at] = _identified(entry, entries[at].identity);

  return UnmodifiableListView(out);
}

/// [entries] with the one at [from] moved to stand at [at] as [entry], in
/// place of the one there. The moved one keeps its identity, as it is the
/// same occurrence standing somewhere else.
List<Entry> movedTo(List<Entry> entries, int from, int at, Entry entry) {
  final moved = _identified(entry, entries[from].identity);
  if (entries is _ReplayEntries) {
    entries._entries[at] = moved;
    entries._entries.removeAt(from);
    if (entries.work != null) entries.work!.replacedEntries++;
    return entries;
  }
  final out = [...entries];
  out[at] = moved;
  out.removeAt(from);
  return UnmodifiableListView(out);
}

/// Removes the final entry while folding work that belongs above it.
List<Entry> lastRemoved(List<Entry> entries) {
  if (entries is _ReplayEntries) {
    entries._entries.removeLast();
    return entries;
  }
  return UnmodifiableListView(entries.sublist(0, entries.length - 1));
}

/// Restores an existing tail occurrence without issuing it a new identity.
List<Entry> lastRestored(List<Entry> entries, Entry entry) {
  if (entries is _ReplayEntries) {
    entries._entries.add(entry);
    if (entries.work != null) entries.work!.appendedEntries++;
    return entries;
  }
  return UnmodifiableListView([...entries, entry]);
}

// A write preserves all payload fields while changing only occurrence metadata.
Entry _identified(Entry entry, EntryIdentity identity) => switch (entry) {
  HistoryOmittedEntry() => HistoryOmittedEntry(identity: identity),
  ShellEntry(:final turnId, :final run) => ShellEntry(
    turnId,
    run,
    identity: identity,
  ),
  UserEntry(:final turnId, :final text, :final from) => UserEntry(
    turnId,
    text,
    from: from,
    identity: identity,
  ),
  SelfStartedEntry(:final turnId, :final alone, :final from) =>
    SelfStartedEntry(turnId, alone: alone, from: from, identity: identity),
  AssistantEntry(:final turnId, :final text, :final messageId, :final planId) =>
    AssistantEntry(
      turnId,
      text,
      messageId: messageId,
      planId: planId,
      identity: identity,
    ),
  ThoughtEntry(:final turnId, :final text, :final messageId) => ThoughtEntry(
    turnId,
    text,
    messageId: messageId,
    identity: identity,
  ),
  ToolEntry(:final turnId, :final call) => ToolEntry(
    turnId,
    call,
    identity: identity,
  ),
  NotedEntry(:final turnId, :final command, :final text, :final failed) =>
    NotedEntry(turnId, command, text, failed: failed, identity: identity),
  TypedCallEntry(:final turnId, :final command, :final call) => TypedCallEntry(
    turnId,
    command,
    call,
    identity: identity,
  ),
  TeamPartEntry(:final turnId, :final part) => TeamPartEntry(
    turnId,
    part,
    identity: identity,
  ),
  TeamShownEntry(:final turnId, :final command, :final shown) => TeamShownEntry(
    turnId,
    command,
    shown,
    identity: identity,
  ),
  LeftOpenEntry(:final turnId, :final agents) => LeftOpenEntry(
    turnId,
    agents,
    identity: identity,
  ),
  ForkedEntry(:final turnId, :final from, :final at) => ForkedEntry(
    turnId,
    from,
    at,
    identity: identity,
  ),
  MonitorsLeftEntry(:final turnId, :final monitors) => MonitorsLeftEntry(
    turnId,
    monitors,
    identity: identity,
  ),
  ReportEntry(:final turnId, :final command, :final rows) => ReportEntry(
    turnId,
    command,
    rows,
    identity: identity,
  ),
  PermissionEntry(:final turnId, :final title, :final option, :final review) =>
    PermissionEntry(
      turnId,
      title: title,
      option: option,
      review: review,
      identity: identity,
    ),
  CancelledEntry(:final turnId) => CancelledEntry(turnId, identity: identity),
  StoppedEntry(:final turnId, :final reason) => StoppedEntry(
    turnId,
    reason,
    identity: identity,
  ),
  ErrorEntry(:final turnId, :final message, :final code, :final signIn) =>
    ErrorEntry(turnId, message, code: code, signIn: signIn, identity: identity),
  WarningEntry(:final turnId, :final message) => WarningEntry(
    turnId,
    message,
    identity: identity,
  ),
  NoticeEntry(
    :final turnId,
    :final severity,
    :final title,
    :final description,
  ) =>
    NoticeEntry(
      turnId,
      severity,
      title,
      description: description,
      identity: identity,
    ),
  SubagentEntry(:final turnId, :final subagent) => SubagentEntry(
    turnId,
    subagent,
    identity: identity,
  ),
  AgentMessageEntry(
    :final turnId,
    :final messageId,
    :final toSubagent,
    :final agentId,
    :final title,
    :final text,
    :final launch,
  ) =>
    AgentMessageEntry(
      turnId,
      messageId,
      toSubagent: toSubagent,
      agentId: agentId,
      title: title,
      text: text,
      launch: launch,
      identity: identity,
    ),
  ChildMessageEntry(
    :final turnId,
    :final from,
    :final text,
    :final messageId,
    :final byAgent,
  ) =>
    ChildMessageEntry(
      turnId,
      from,
      text,
      messageId: messageId,
      byAgent: byAgent,
      identity: identity,
    ),
  ItemEndedEntry(
    :final turnId,
    :final name,
    :final end,
    :final item,
    :final byPerson,
    :final byEsc,
    :final byAgent,
    :final startedAt,
    :final endedAt,
    :final error,
  ) =>
    ItemEndedEntry(
      turnId,
      name,
      end,
      item: item,
      byPerson: byPerson,
      byEsc: byEsc,
      byAgent: byAgent,
      startedAt: startedAt,
      endedAt: endedAt,
      error: error,
      identity: identity,
    ),
  CompactionEntry(:final turnId, :final compaction) => CompactionEntry(
    turnId,
    compaction,
    identity: identity,
  ),
  ElicitationEntry(
    :final turnId,
    :final wait,
    :final outcome,
    :final content,
  ) =>
    ElicitationEntry(
      turnId,
      wait,
      outcome,
      content: content,
      identity: identity,
    ),
  FinishedPlanEntry(:final turnId, :final entries) => FinishedPlanEntry(
    turnId,
    entries,
    identity: identity,
  ),
};

/// Actual work at the detached historical entry writers and final freeze.
final class ReplayWork {
  int appendedEntries = 0;
  int replacedEntries = 0;
  int copiedEntries = 0;
}

/// Folds a detached history without exposing intermediate mutable entry lists.
Transcript replayTranscript(
  Iterable<TranscriptAction> actions, {
  ReplayWork? work,
}) {
  final entries = _ReplayEntries(work);
  var state = Transcript(entries: entries);
  for (final action in actions) {
    state = reduceTranscript(state, action);
  }
  final frozen = <Entry>[];
  for (final entry in state.entries) {
    frozen.add(entry);
    if (work != null) work.copiedEntries++;
  }
  return Transcript(
    entries: UnmodifiableListView(frozen),
    plan: state.plan,
    planId: state.planId,
    turn: state.turn,
    usage: state.usage,
    mode: state.mode,
    planAsks: state.planAsks,
    asking: state.asking,
    served: state.served,
  );
}

final class _ReplayEntries extends ListBase<Entry> {
  _ReplayEntries(this.work);
  final ReplayWork? work;
  final _entries = <Entry>[];
  @override
  int get length => _entries.length;
  @override
  set length(int value) =>
      throw UnsupportedError('Only replay writers may mutate entries.');
  @override
  Entry operator [](int index) => _entries[index];
  @override
  void operator []=(int index, Entry value) =>
      throw UnsupportedError('Only replay writers may mutate entries.');
}
