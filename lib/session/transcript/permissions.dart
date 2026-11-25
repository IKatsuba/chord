/// What a turn asks the person: a permission, waited on in the turn's
/// status; each answer leaves its record.
library;

import 'dart:collection';

import '../permission_review.dart';
import 'entries.dart';
import 'subagents.dart' show changeSubagent, findSubagent;
import 'turn.dart';
import 'types.dart';

/// [state] with [asked] waiting on the person: in the running turn, or
/// between turns when [between] and none runs.
Transcript permissionRequested(
  Transcript state,
  String turnId,
  PermissionWait asked, {
  num at = 0,
  bool between = false,
}) {
  final turn = state.turn;
  // Timed requests and subagents' count from the ask, not the turn's start.
  final permission = asked.subagentId == null && asked.deadlineAt == null
      ? asked
      : asked.askedAt(at);
  // A task agent outlives the turn that started it, so its request is
  // outside any turn, as one the agent asked with no turn of chord's
  // running is.
  final outside = between || taskWaits(state, [permission]).isNotEmpty;
  final entries = _reviewedIn(state.entries, permission);

  // The agent may ask with no turn running, as its own work goes on past
  // its answer; the session waits on the person until it is answered.
  if (turn is Idle && outside) {
    return _with(
      state,
      entries,
      AwaitingPermission(turnId, at, _list([permission]), between: true),
    );
  }

  // One asked in the agent's own cycle is held as between turns: the
  // person did not start it, and may be typing.
  if (turn is Working && turn.cycle && outside) {
    return _with(
      state,
      entries,
      AwaitingPermission(
        turn.turnId,
        at,
        _list([permission]),
        between: true,
        cycle: true,
        cycleSince: turn.since,
      ),
    );
  }

  if (turn is AwaitingPermission &&
      turn.between &&
      outside &&
      !turn.permissions.any((wait) => wait.id == permission.id)) {
    return _with(
      state,
      entries,
      AwaitingPermission(
        turn.turnId,
        turn.since,
        _list([...turn.permissions, permission]),
        between: true,
        cycle: turn.cycle,
        cycleSince: turn.cycleSince,
      ),
    );
  }

  // One asked as a turn of chord's started waits in that turn.
  final running = current(turn);
  final owner = between && running != null ? running.$1 : turnId;

  if (running == null || running.$1 != owner || turn is Cancelling) {
    return state;
  }

  final waiting = turn is AwaitingPermission
      ? turn.permissions
      : const <PermissionWait>[];

  if (waiting.any((wait) => wait.id == permission.id)) {
    return state;
  }

  return _with(
    state,
    entries,
    AwaitingPermission(owner, running.$2, _list([...waiting, permission])),
  );
}

/// A review belongs to the call that asked, kept on it after the box
/// closes: among the session's own entries, or a subagent's when one asks,
/// whose call ids are its own.
List<Entry> _reviewedIn(List<Entry> entries, PermissionWait wait) {
  final review = wait.review;
  final toolCallId = wait.toolCallId;

  if (review == null || toolCallId == null) {
    return entries;
  }

  final asker = wait.subagentId;
  return asker == null
      ? _marked(entries, toolCallId, review)
      : changeSubagent(
          entries,
          asker,
          (subagent) => subagent.copyWith(
            entries: _marked(subagent.entries, toolCallId, review),
          ),
        );
}

/// [entries] with the last call [toolCallId] among them carrying [review].
List<Entry> _marked(
  List<Entry> entries,
  String toolCallId,
  PermissionReview review,
) {
  final index = entries.lastIndexWhere(
    (entry) => entry is ToolEntry && entry.call.id == toolCallId,
  );

  if (index < 0) {
    return entries;
  }

  final found = entries[index] as ToolEntry;
  final call = found.call;

  return replacedAt(
    entries,
    index,
    ToolEntry(
      found.turnId,
      ToolCall(
        call.id,
        title: call.title,
        kind: call.kind,
        status: call.status,
        locations: call.locations,
        content: call.content,
        rawInput: call.rawInput,
        rawOutput: call.rawOutput,
        guardian: call.guardian,
        mcp: call.mcp,
        review: review,
        terminals: call.terminals,
        plan: call.plan,
        asked: call.asked,
        chord: call.chord,
        cut: call.cut,
      ),
    ),
  );
}

/// [state] with permission [id] answered by [answer]: its record drawn,
/// unless it was withdrawn, and the turn working again once none waits.
Transcript permissionSettled(
  Transcript state,
  String turnId,
  String id,
  PermissionAnswer answer,
) {
  final turn = state.turn;

  // Found by its id alone: a request may have been asked in an earlier turn
  // than the one it is answered in.
  if (turn is! AwaitingPermission) {
    return state;
  }

  final wait = turn.permissions.where((each) => each.id == id).firstOrNull;

  if (wait == null) {
    return state;
  }

  final permissions = [
    for (final other in turn.permissions)
      if (!identical(other, wait)) other,
  ];
  final option = switch (answer) {
    Chosen(:final optionId) =>
      wait.options.where((each) => each.optionId == optionId).firstOrNull,
    _ => null,
  };
  // chord's own question is answered on the call that asked it.
  final entry = answer is Withdrawn || wait.save != null
      ? null
      : PermissionEntry(
          turnId,
          title: wait.title,
          option: option,
          review: wait.review,
        );
  // A subagent's answer is part of its work, not its parent's.
  final asker = wait.subagentId;
  final entries = entry == null
      ? state.entries
      : asker != null && findSubagent(state.entries, asker) != null
      ? changeSubagent(
          state.entries,
          asker,
          (subagent) =>
              subagent.copyWith(entries: [...subagent.entries, entry]),
        )
      : appended(state.entries, [entry]);

  return _with(
    state,
    entries,
    permissions.isNotEmpty
        ? AwaitingPermission(
            turn.turnId,
            turn.since,
            _list(permissions),
            between: turn.between,
            cycle: turn.cycle,
            cycleSince: turn.cycleSince,
          )
        // The cycle works on, its working line counting from its start.
        : turn.cycle
        ? Working(turn.turnId, turn.cycleSince ?? turn.since, cycle: true)
        : turn.between
        ? const Idle()
        : Working(turn.turnId, turn.since),
  );
}

List<PermissionWait> _list(List<PermissionWait> waits) =>
    UnmodifiableListView(waits);

Transcript _with(Transcript state, List<Entry> entries, TurnState turn) =>
    Transcript(
      entries: entries,
      plan: state.plan,
      planId: state.planId,
      turn: turn,
      usage: state.usage,
      mode: state.mode,
      planAsks: state.planAsks,
      asking: state.asking,
      served: state.served,
    );

Transcript _asking(
  Transcript state,
  List<Entry> entries,
  List<ElicitationWait> asking,
) => Transcript(
  entries: entries,
  plan: state.plan,
  planId: state.planId,
  turn: state.turn,
  usage: state.usage,
  mode: state.mode,
  planAsks: state.planAsks,
  asking: UnmodifiableListView(asking),
  served: state.served,
);

/// The agent asked a form or link: it waits on the person, after those
/// already waiting. One for a turn that is not the one running, or one
/// being cancelled, is not drawn, unless it was asked between turns; one
/// already asked is not asked twice.
Transcript elicitationRequested(
  Transcript state,
  String turnId,
  ElicitationWait elicitation,
) {
  final turn = state.turn;
  final running = current(turn);
  final outside = elicitation.subagentId != null || elicitation.between;
  if ((!outside && (running?.$1 != turnId || turn is Cancelling)) ||
      state.asking.any((wait) => wait.id == elicitation.id)) {
    return state;
  }
  return _asking(state, _askedIn(state.entries, elicitation), [
    ...state.asking,
    elicitation,
  ]);
}

/// [entries] with the tool call a box of questions came out of marked as
/// asked there, from when the box opens: it reads as asking while the
/// person answers, and the box's record stands in for its own lines.
List<Entry> _askedIn(List<Entry> entries, ElicitationWait wait) {
  final id = wait is FormWait && wait.questions != null
      ? wait.toolCallId
      : null;
  if (id == null) return entries;
  // A task's question is its own call's, among its own work: a call of the
  // session's with the same id is another.
  if (wait.subagentId case final asker?) {
    return changeSubagent(entries, asker, (subagent) {
      final marked = _askedCall(subagent.entries, id);
      return identical(marked, subagent.entries)
          ? subagent
          : subagent.copyWith(entries: marked);
    });
  }
  return _askedCall(entries, id);
}

/// [entries] with the last call [id] among them marked as asked there.
List<Entry> _askedCall(List<Entry> entries, String id) {
  final index = entries.lastIndexWhere(
    (entry) => entry is ToolEntry && entry.call.id == id,
  );
  if (index < 0) return entries;
  final found = entries[index] as ToolEntry;
  if (found.call.asked) return entries;
  return replacedAt(
    entries,
    index,
    ToolEntry(found.turnId, found.call.askedHere, identity: found.identity),
  );
}

/// The person's answer to a form or link, or its withdrawal, as a record:
/// one withdrawn reads cancelled.
Transcript elicitationSettled(
  Transcript state,
  String turnId,
  String id,
  ElicitationAnswer answer,
) {
  final wait = state.asking.where((each) => each.id == id).firstOrNull;
  if (wait == null ||
      (wait.subagentId == null &&
          !wait.between &&
          current(state.turn)?.$1 != turnId)) {
    return state;
  }
  final entry = ElicitationEntry(turnId, wait, switch (answer) {
    ElicitationAccepted() => ElicitationOutcome.accepted,
    ElicitationDeclined() => ElicitationOutcome.declined,
    ElicitationCancelled() ||
    ElicitationWithdrawn() => ElicitationOutcome.cancelled,
    ElicitationTimedOut() => ElicitationOutcome.timedOut,
  }, content: answer is ElicitationAccepted ? answer.content : null);
  final marked = _askedIn(state.entries, wait);
  // A task's box of questions out of its own call is recorded under that
  // call, among the task's work, as the call is.
  final asker = wait.subagentId;
  final inTask =
      asker != null &&
          wait is FormWait &&
          wait.questions != null &&
          wait.toolCallId != null
      ? changeSubagent(
          marked,
          asker,
          (subagent) =>
              subagent.copyWith(entries: [...subagent.entries, entry]),
        )
      : marked;
  return _asking(
    state,
    identical(inTask, marked) ? appended(marked, [entry]) : inTask,
    [
      for (final each in state.asking)
        if (!identical(each, wait)) each,
    ],
  );
}
