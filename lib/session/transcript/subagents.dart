/// Subagents in the transcript, from the original's
/// `session/transcript/subagents.ts`: each an entry where its first update
/// came among its parent's, holding its own work apart from the parent's,
/// and its state as the adapters word it, with what chord says of its own
/// task agents.
library;

import 'dart:collection';

import '../../acp/schema.dart' as acp;
import '../enrich.dart' show namedByTitleKey, recordOf;
import '../usage.dart' show tokenFields;
import 'entries.dart';
import 'types.dart';

/// How the reducer folds a session's own update; a subagent's work folds
/// through it too.
typedef ApplyUpdate =
    Transcript Function(
      Transcript state,
      String turnId,
      acp.SessionUpdate update,
      num? at,
    );

String? _textOf(Object? content) => switch (content) {
  null => null,
  final List<Object?> blocks => [
    for (final block in blocks)
      if (block case {'type': 'text', 'text': final String text}) text,
  ].join(),
  _ => '',
};

/// A subagent's update, folded into its own work, apart from its parent's;
/// one for a subagent the transcript does not hold is dropped rather than
/// drawn as the parent's.
Transcript childUpdate(
  Transcript state,
  UpdateAction action,
  ApplyUpdate applyUpdate,
) {
  final subagentId = action.subagentId;
  if (subagentId == null) return state;
  final update = action.update.toJson();
  final entries = changeSubagent(
    state.entries,
    subagentId,
    (subagent) =>
        update['sessionUpdate'] == 'session_message' &&
            !_itsOwn(subagent, update)
        ? _messaged(subagent, action.turnId, update, state.entries)
        : _worked(
            subagent,
            action.turnId,
            action.update,
            action.at,
            applyUpdate,
          ),
  );
  return identical(entries, state.entries) ? state : state.withEntries(entries);
}

/// Whether a `session_message` on [subagent]'s session is its own side of
/// an exchange, sent by it or by a subagent of its, not one it was told.
bool _itsOwn(Subagent subagent, Map<String, Object?> update) {
  final sender = update['senderSessionId'];
  return sender == subagent.id ||
      subagent.entries.any(
        (entry) =>
            entry is AgentMessageEntry &&
            entry.messageId == update['messageId'],
      ) ||
      (sender is String && _childOf(subagent.entries, sender) != null);
}

/// The subagent [id] directly among [entries], not one under them.
int? _childOf(List<Entry> entries, String id) {
  final at = entries.indexWhere(
    (entry) => entry is SubagentEntry && entry.subagent.id == id,
  );
  return at < 0 ? null : at;
}

/// Where a `→` row goes for the subagent at [index]: directly above it, or
/// above the first of the run it stands in, so a launch's rows never split
/// a group.
int _aboveRun(List<Entry> entries, int index) {
  var at = index;
  while (at > 0 && entries[at - 1] is SubagentEntry) {
    at--;
  }
  return at;
}

/// [state] with a `session_message` between its agent and a subagent
/// directly under it, upserted by its id: a message left out keeps its
/// text, one with none takes the row away. A message that names no such
/// subagent is none of this transcript's.
Transcript agentMessage(
  Transcript state,
  String turnId,
  acp.SessionUpdate message,
) {
  final update = message.toJson();
  final messageId = update['messageId'];
  if (messageId is! String) {
    throw const FormatException('A session message has no id.');
  }
  final text = update.containsKey('content')
      ? _textOf(update['content']) ?? ''
      : null;
  final at = state.entries.indexWhere(
    (each) => each is AgentMessageEntry && each.messageId == messageId,
  );
  if (at >= 0) {
    final was = state.entries[at] as AgentMessageEntry;
    if (text == null) return state;
    if (text.isEmpty) {
      return state.withEntries(
        UnmodifiableListView([...state.entries]..removeAt(at)),
      );
    }
    return state.withEntries(
      replacedAt(
        state.entries,
        at,
        AgentMessageEntry(
          was.turnId,
          was.messageId,
          toSubagent: was.toSubagent,
          agentId: was.agentId,
          title: was.title,
          text: text,
          launch: was.launch,
        ),
      ),
    );
  }
  final recipient = update['recipientSessionId'];
  final sender = update['senderSessionId'];
  final to = recipient is String ? _childOf(state.entries, recipient) : null;
  final from = sender is String ? _childOf(state.entries, sender) : null;
  final child = to ?? from;
  if (child == null || text == null || text.isEmpty) return state;
  final entry = state.entries[child] as SubagentEntry;
  final subagent = entry.subagent;
  final row = AgentMessageEntry(
    turnId,
    messageId,
    toSubagent: to != null,
    agentId: subagent.id,
    title: subagent.title,
    text: text,
    launch: to != null && !subagent.addressed,
  );
  if (to == null) return state.withEntries(appended(state.entries, [row]));
  final entries = subagent.addressed
      ? state.entries
      : replacedAt(
          state.entries,
          to,
          SubagentEntry(entry.turnId, subagent.copyWith(addressed: true)),
        );
  if (!row.launch) return state.withEntries(appended(entries, [row]));
  // A launch's stands above the block, as an entry of its own.
  final above = _aboveRun(entries, to);
  final placed = appended(entries, [row]);
  final list = [...placed];
  final moved = list.removeLast();
  list.insert(above, moved);
  return state.withEntries(UnmodifiableListView(list));
}

/// [subagent] with a `session_message` it got upserted by its id: the
/// first is its whole task, and each later one a message among its work.
Subagent _messaged(
  Subagent subagent,
  String turnId,
  Map<String, Object?> update,
  List<Entry> around,
) {
  final messageId = update['messageId'];
  if (messageId is! String) return subagent;
  final text = update.containsKey('content')
      ? _textOf(update['content']) ?? ''
      : null;
  if (subagent.promptId == null || subagent.promptId == messageId) {
    final prompt = text ?? subagent.prompt;
    return subagent.copyWith(
      promptId: messageId,
      prompt: prompt == null || prompt.isEmpty ? null : prompt,
      clear: {if (prompt == null || prompt.isEmpty) 'prompt'},
    );
  }
  final at = subagent.entries.indexWhere(
    (entry) => entry is ChildMessageEntry && entry.messageId == messageId,
  );
  if (text == null) return subagent;
  if (text.isEmpty) {
    if (at < 0) return subagent;
    final planAt = subagent.planAt;
    return subagent.copyWith(
      entries: UnmodifiableListView([...subagent.entries]..removeAt(at)),
      planAt: planAt != null && at < planAt ? planAt - 1 : null,
    );
  }
  final senderId = update['senderSessionId'];
  final sender = senderId is String ? findSubagent(around, senderId) : null;
  final was = at < 0 ? null : subagent.entries[at] as ChildMessageEntry;
  final entry = sender != null
      ? ChildMessageEntry(
          turnId,
          'Agent(${sender.title ?? ''})',
          text,
          messageId: messageId,
        )
      : was != null && senderId == null
      ? ChildMessageEntry(
          turnId,
          was.from,
          text,
          messageId: messageId,
          byAgent: was.byAgent,
        )
      : ChildMessageEntry(
          turnId,
          '',
          text,
          messageId: messageId,
          byAgent: true,
        );
  return subagent.copyWith(
    entries: at < 0
        ? appended(subagent.entries, [entry])
        : replacedAt(subagent.entries, at, entry),
  );
}

/// [subagent] with [update] folded into its work through the reducer that
/// folds a session's own. What a subagent says of usage, modes or commands
/// is its parent's session's to say, and dropped.
Subagent _worked(
  Subagent subagent,
  String turnId,
  acp.SessionUpdate update,
  num? at,
  ApplyUpdate applyUpdate,
) {
  final before = Transcript(
    entries: subagent.entries,
    plan: subagent.plan,
    planId: subagent.planId,
  );
  final after = applyUpdate(before, turnId, update, at);
  if (identical(after.entries, before.entries) &&
      identical(after.plan, before.plan) &&
      after.planId == before.planId) {
    return subagent;
  }
  var moved = 0;
  while (moved < after.entries.length &&
      moved < subagent.entries.length &&
      identical(after.entries[moved], subagent.entries[moved])) {
    moved++;
  }
  final wasAt = subagent.planAt;
  final planAt = wasAt != null && moved < wasAt
      ? wasAt + after.entries.length - subagent.entries.length
      : wasAt ?? (after.plan.isNotEmpty ? subagent.entries.length : null);
  return subagent.copyWith(
    entries: after.entries,
    plan: after.plan,
    planId: after.planId,
    planAt: planAt,
    clear: {if (after.planId == null) 'planId'},
  );
}

/// A `subagent_update`, from the session or from a subagent: the subagent
/// it names changed where it stands, or, the first time, put at the end of
/// its parent's entries. A reopened subagent comes under an id of its own
/// and is a new one.
Transcript mergeSubagent(
  Transcript state,
  String turnId,
  acp.SessionUpdate subagentUpdate,
  num? at,
) {
  final update = subagentUpdate.toJson();
  final id = update['sessionId'];
  if (id is! String) {
    throw const FormatException('A subagent update names no session.');
  }
  if (findSubagent(state.entries, id) != null) {
    final entries = changeSubagent(
      state.entries,
      id,
      (subagent) => _patched(subagent, update, at),
    );
    return state.withEntries(
      update.containsKey('title')
          ? _retitled(entries, id, update['title'] as String?)
          : entries,
    );
  }
  final subagent = _patched(Subagent(id, startedAt: at), update, at);
  return state.withEntries(
    appended(state.entries, [SubagentEntry(turnId, subagent)]),
  );
}

/// The rows about subagent [id] under the title it now goes by.
List<Entry> _retitled(List<Entry> entries, String id, String? title) {
  var out = entries;
  for (final (index, entry) in entries.indexed) {
    if (entry is AgentMessageEntry && entry.agentId == id) {
      out = replacedAt(
        out,
        index,
        AgentMessageEntry(
          entry.turnId,
          entry.messageId,
          toSubagent: entry.toSubagent,
          agentId: entry.agentId,
          title: title,
          text: entry.text,
          launch: entry.launch,
        ),
      );
    }
  }
  return out;
}

/// [subagent] patched as ACP says: a field left out is kept, `null` clears
/// it, a value replaces it. A state ACP has no word for here keeps the one
/// it had.
Subagent _patched(Subagent subagent, Map<String, Object?> update, num? at) {
  final state = update['state'];
  final told = subagentStateOf(state);
  final next = told ?? subagent.state;
  final namedByTitle =
      subagent.namedByTitle ||
      recordOf(update['_meta'])[namedByTitleKey] == true;
  final waiting = told == null
      ? subagent.waiting
      : recordOf(state)['state'] == 'requires_action'
      ? (subagent.waiting ?? (since: at))
      : null;
  final capabilities = update['capabilities'];
  final cancellable = update.containsKey('capabilities')
      ? capabilities is Map && capabilities['cancel'] != null
      : subagent.cancellable;
  // An untracked subagent may have worked on: its time stands at the
  // `unknown`, and runs again to the next state it is told.
  final moved =
      subagent.state == SubagentState.running ||
      (subagent.state == SubagentState.untracked &&
          told != null &&
          told != SubagentState.untracked);
  final ended = next == SubagentState.running
      ? null
      : moved
      ? at
      : subagent.endedAt;
  final error = told == null ? subagent.error : _errorOf(state);
  // A stop pending holds until its agent tells a state it is not at work in.
  final stopping =
      (told == null || told == SubagentState.running) && subagent.stopping;
  String? field(String key, String? had) => update.containsKey(key)
      ? (update[key] is String ? update[key] as String : null)
      : had;
  final title = field('title', subagent.title);
  final description = field('description', subagent.description);
  // chord says a task's effort once it is up, after the block is drawn, and
  // what it spent and who stopped it on its end.
  final meta = recordOf(update['_meta']);
  final taskTold = _taskOf(meta);
  final known = taskTold == null
      ? subagent.task
      : subagent.task?.told(taskTold) ?? taskTold;
  final task = known?.ended(
    spent: _spentOf(meta),
    stoppedWith: _stoppedOf(meta),
  );
  return Subagent(
    subagent.id,
    state: next,
    title: title,
    description: description,
    prompt: subagent.prompt,
    promptId: subagent.promptId,
    addressed: subagent.addressed,
    namedByTitle: namedByTitle,
    cancellable: cancellable,
    offeredCancel: subagent.offeredCancel || cancellable,
    stopping: stopping,
    waiting: waiting,
    error: error,
    startedAt: subagent.startedAt,
    endedAt: ended,
    entries: subagent.entries,
    plan: subagent.plan,
    planId: subagent.planId,
    planAt: subagent.planAt,
    task: task,
    callId: subagent.callId,
  );
}

/// Where a `subagent_update` chord sends for a task agent it started says
/// so: its name, runtime and model, which no adapter's subagent has.
const taskMetaKey = 'chord/task';

/// Where a task's ending `subagent_update` carries what it spent.
const taskSpentMetaKey = 'chord/spent';

/// Where a stopped task's ending `subagent_update` says who stopped it.
const taskStoppedMetaKey = 'chord/stopped';

/// The task a `subagent_update`'s [meta] describes, when chord sent it for
/// one.
TaskInfo? _taskOf(Map<String, Object?> meta) {
  final task = meta[taskMetaKey];
  if (task is! Map) return null;
  final name = task['name'], runtime = task['runtime'];
  if (name is! String || runtime is! String) return null;
  final model = task['model'], effort = task['effort'];
  return TaskInfo(
    name: name,
    runtime: runtime,
    model: model is String ? model : null,
    effort: effort is String ? effort : null,
    workLost: task['workLost'] == true,
  );
}

/// What a task's ending update says it spent, which a record or an agent
/// may have bent: each part that does not read as one left out, a token
/// count on its own, and `estimated` standing only with a cost; none when
/// it says nothing.
TaskSpent? _spentOf(Map<String, Object?> meta) {
  final spent = meta[taskSpentMetaKey];
  if (spent is! Map) return null;
  final read = spent['tokens'];
  final tokens = <String, num>{
    if (read is Map)
      for (final field in tokenFields)
        if (read[field] case final int count when count >= 0) field: count,
  };
  final cost = switch (spent['cost']) {
    {'amount': final num amount, 'currency': final String currency}
        when amount >= 0 && currency.isNotEmpty =>
      (amount: amount, currency: currency),
    _ => null,
  };
  if (tokens.isEmpty && cost == null) return null;
  return TaskSpent(
    tokens: tokens.isEmpty ? null : tokens,
    cost: cost,
    estimated: cost != null && spent['estimated'] == true,
  );
}

/// Who stopped a task, as its ending update says; none when it does not.
TaskStop? _stoppedOf(Map<String, Object?> meta) =>
    switch (meta[taskStoppedMetaKey]) {
      'x' => TaskStop.x,
      'esc' => TaskStop.esc,
      {'agent': final String agent} => TaskStop.agent(agent),
      _ => null,
    };

const _endings = {
  'completed': SubagentState.completed,
  'failed': SubagentState.failed,
  'cancelled': SubagentState.cancelled,
  'disconnected': SubagentState.disconnected,
};

/// A subagent's state from ACP's state object: at work while `running` or
/// waiting on the person (`requires_action`), ended by its stop reason once
/// `idle`, untracked once `unknown`, or ended as the adapters' words say.
/// None, `null` and any other word say nothing.
SubagentState? subagentStateOf(Object? state) {
  final word = recordOf(state)['state'];
  return switch (word) {
    'running' || 'requires_action' => SubagentState.running,
    'unknown' => SubagentState.untracked,
    'idle' => switch (recordOf(state)['stopReason']) {
      'end_turn' => SubagentState.completed,
      'error' => SubagentState.failed,
      'cancelled' => SubagentState.cancelled,
      _ => SubagentState.ended,
    },
    final String word => _endings[word],
    _ => null,
  };
}

/// The message of the error an `idle` with stop reason `error` carries.
String? _errorOf(Object? state) {
  final read = recordOf(state);
  if (read['state'] != 'idle' || read['stopReason'] != 'error') return null;
  final message = recordOf(read['error'])['message'];
  return message is String && message.isNotEmpty ? message : null;
}

/// Whether a subagent is a background `agent` item: every one its agent
/// announced on a session of its own, which chord's own tasks are not; one
/// with no `capabilities.cancel` is an item that offers no stop.
bool isAgentItem(Subagent subagent) => subagent.task == null;

/// An agent item's name: its short task, else its title. On Claude's
/// adapter the description is only a role and the title the name.
String agentItemName(Subagent subagent) =>
    (subagent.namedByTitle
        ? subagent.title ?? subagent.description
        : subagent.description ?? subagent.title) ??
    'agent';

const _itemEnds = {
  SubagentState.completed: ItemEnd.done,
  SubagentState.failed: ItemEnd.failed,
  SubagentState.cancelled: ItemEnd.stopped,
  SubagentState.ended: ItemEnd.ended,
  SubagentState.disconnected: ItemEnd.disconnected,
};

/// The lines to add for the agent items and tasks [entries] ended since
/// [before]: one each, unless the turn that announced it, [turn]'s while it
/// runs, says it in its own block; a task's only when it was stopped, as
/// its report or its failure is its own message.
List<Entry> itemEndLines(
  List<Entry> before,
  List<Entry> entries,
  TurnState turn,
) {
  final running = switch (turn) {
    Idle() => null,
    Working(:final turnId) ||
    AwaitingPermission(:final turnId) ||
    Cancelling(:final turnId) => turnId,
  };
  return [
    for (final (:subagent, :turnId) in _itemsIn(before))
      if (findSubagent(entries, subagent.id) case final now?)
        if ((subagent.state == SubagentState.running ||
                subagent.state == SubagentState.untracked) &&
            running != turnId)
          ?_endLine(subagent, now, turnId),
  ];
}

/// The line [now]'s end leaves, once its turn has gone: an agent item's as
/// it ended, the person's when [was] stood stopping; a task's only when it
/// was stopped.
ItemEndedEntry? _endLine(Subagent was, Subagent now, String turnId) {
  if (now.task case final task?) {
    return now.state == SubagentState.cancelled
        ? _taskStopLine(now, task, turnId)
        : null;
  }
  final end = _itemEnds[now.state];
  return end == null
      ? null
      : ItemEndedEntry(
          turnId,
          agentItemName(now),
          end,
          byPerson:
              was.stopping && (end == ItemEnd.stopped || end == ItemEnd.ended),
          startedAt: now.startedAt,
          endedAt: now.endedAt,
          error: end == ItemEnd.failed ? now.error : null,
        );
}

/// A stopped task's line: by its name, and who stopped it, if the person or
/// its agent did.
ItemEndedEntry _taskStopLine(Subagent subagent, TaskInfo task, String turnId) =>
    ItemEndedEntry(
      turnId,
      task.name,
      ItemEnd.stopped,
      item: ItemKind.task,
      byPerson: task.stoppedWith == TaskStop.x,
      byEsc: task.stoppedWith == TaskStop.esc,
      byAgent: task.stoppedWith?.agent,
      startedAt: subagent.startedAt,
      endedAt: subagent.endedAt,
    );

/// Every subagent among [entries], with the turn its outermost came in.
List<({Subagent subagent, String turnId})> _itemsIn(
  List<Entry> entries, [
  String? turnId,
]) => [
  for (final entry in entries)
    if (entry is SubagentEntry) ...[
      (subagent: entry.subagent, turnId: turnId ?? entry.turnId),
      ..._itemsIn(entry.subagent.entries, turnId ?? entry.turnId),
    ],
];

/// Whether a subagent is at work, as far as chord knows.
bool isRunning(Subagent subagent) => subagent.state == SubagentState.running;

/// [entries] with every subagent among or under them that [ends] picks,
/// those still running unless told otherwise, ended as [state], at [at]
/// when it is known; the same list when none was.
List<Entry> endRunning(
  List<Entry> entries,
  SubagentState state,
  num? at, [
  bool Function(Subagent subagent) ends = isRunning,
]) {
  var out = entries;
  for (final (index, entry) in entries.indexed) {
    if (entry is! SubagentEntry) continue;
    final subagent = entry.subagent;
    final inner = endRunning(subagent.entries, state, at, ends);
    final ending = ends(subagent);
    if (!ending && identical(inner, subagent.entries)) continue;
    out = replacedAt(
      out,
      index,
      SubagentEntry(
        entry.turnId,
        ending
            ? subagent.copyWith(entries: inner, state: state, endedAt: at)
            : subagent.copyWith(entries: inner),
      ),
    );
  }
  return out;
}

/// The subagent [id], among [entries] or under them, at any depth.
Subagent? findSubagent(List<Entry> entries, String id) {
  for (final entry in entries) {
    if (entry is! SubagentEntry) continue;
    if (entry.subagent.id == id) return entry.subagent;
    final inner = findSubagent(entry.subagent.entries, id);
    if (inner != null) return inner;
  }
  return null;
}

/// [entries] with the subagent [id], wherever it stands among or under
/// them, changed by [change]; the same list when it is not there or did not
/// change.
List<Entry> changeSubagent(
  List<Entry> entries,
  String id,
  Subagent Function(Subagent subagent) change,
) {
  for (final (index, entry) in entries.indexed) {
    if (entry is! SubagentEntry) continue;
    final subagent = entry.subagent;
    if (subagent.id == id) {
      final next = change(subagent);
      return identical(next, subagent)
          ? entries
          : replacedAt(entries, index, SubagentEntry(entry.turnId, next));
    }
    final inner = changeSubagent(subagent.entries, id, change);
    if (!identical(inner, subagent.entries)) {
      return replacedAt(
        entries,
        index,
        SubagentEntry(entry.turnId, subagent.copyWith(entries: inner)),
      );
    }
  }
  return entries;
}

/// Subagent [id] marked stopping while it runs, or, [stopping] false, its
/// stop that could not be sent taken back.
Transcript subagentStopping(Transcript state, String id, bool stopping) {
  final entries = changeSubagent(state.entries, id, (subagent) {
    if (stopping) {
      return subagent.state == SubagentState.running && !subagent.stopping
          ? subagent.copyWith(stopping: true)
          : subagent;
    }
    return subagent.stopping ? subagent.copyWith(stopping: false) : subagent;
  });
  return identical(entries, state.entries) ? state : state.withEntries(entries);
}

/// Every subagent among [entries] and under them, parents before children.
List<Subagent> subagentsIn(List<Entry> entries) => [
  for (final entry in entries)
    if (entry is SubagentEntry) ...[
      entry.subagent,
      ...subagentsIn(entry.subagent.entries),
    ],
];

/// How many of the session's subagents, at any depth, are still at work.
int runningSubagents(Transcript transcript) =>
    subagentsIn(transcript.entries).where(isRunning).length;

/// The subagents from the session down to [id], outermost first; empty when
/// the transcript holds no such subagent.
List<Subagent> subagentPath(List<Entry> entries, String id) {
  for (final entry in entries) {
    if (entry is! SubagentEntry) continue;
    if (entry.subagent.id == id) return [entry.subagent];
    final inner = subagentPath(entry.subagent.entries, id);
    if (inner.isNotEmpty) return [entry.subagent, ...inner];
  }
  return const [];
}
