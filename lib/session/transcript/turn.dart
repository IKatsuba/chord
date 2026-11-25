/// The turn itself: its prompt, a cancel asked for, the agent's answer that
/// settles it, and the agent going away.
library;

import 'dart:collection';

import '../../acp/schema.dart' as acp;
import 'entries.dart';
import 'subagents.dart';
import 'types.dart';

/// A turn starts on the person's prompt, drawn as its first entry. The
/// requests left waiting between turns go on waiting in the new one.
Transcript prompted(
  Transcript state,
  String turnId,
  String text,
  num at, {
  String? into,
  MessageFrom? from,
  TeamPart? team,
}) {
  final owner = into ?? turnId;
  // A message draws after the team part that went ahead of it, if one did.
  final added = [
    if (team != null) TeamPartEntry(owner, team),
    UserEntry(owner, text, from: from),
  ];
  if (into != null) {
    return state.withEntries(appended(state.entries, added));
  }
  final waiting = switch (state.turn) {
    AwaitingPermission(:final permissions) => permissions,
    _ => const <PermissionWait>[],
  };

  return Transcript(
    entries: appended(state.entries, added),
    plan: state.plan,
    planId: state.planId,
    turn: waiting.isNotEmpty
        ? AwaitingPermission(turnId, at, waiting)
        : Working(turnId, at),
    usage: state.usage,
    mode: state.mode,
    planAsks: state.planAsks,
    asking: state.asking,
    served: state.served,
  );
}

/// A cycle the agent began on its own: working, as a turn is, with nothing
/// of the person's to draw. The permissions it found waiting stay, held as
/// they were, as the person did not start it.
Transcript cycleStarted(Transcript state, String turnId, num at) =>
    state.withTurn(switch (state.turn) {
      AwaitingPermission(:final since, :final permissions, :final between)
          when permissions.isNotEmpty =>
        AwaitingPermission(
          turnId,
          since,
          permissions,
          between: between,
          cycle: true,
          cycleSince: at,
        ),
      _ => Working(turnId, at, cycle: true),
    });

/// The running turn [turnId], marked cancelling from [at]; any other turn,
/// or one already cancelling, is left as it is.
Transcript cancelled(Transcript state, String turnId, num at) =>
    switch (state.turn) {
      Working(turnId: final id, :final since) ||
      AwaitingPermission(
        turnId: final id,
        :final since,
      ) when id == turnId => state.withTurn(Cancelling(id, since, at)),
      _ => state,
    };

/// The agent going away: the subagents still running or untracked, at any
/// depth, are disconnected with it, each said once.
Transcript disconnected(Transcript state, num? at) {
  final entries = endRunning(
    state.entries,
    SubagentState.disconnected,
    at,
    (subagent) =>
        isRunning(subagent) || subagent.state == SubagentState.untracked,
  );
  return identical(entries, state.entries)
      ? state
      : state.withEntries(
          appended(entries, itemEndLines(state.entries, entries, state.turn)),
        );
}

/// The turn that is running, as its id and start, or null when idle.
(String, num)? current(TurnState turn) => switch (turn) {
  Idle() => null,
  Working(:final turnId, :final since) => (turnId, since),
  AwaitingPermission(:final turnId, :final since) => (turnId, since),
  Cancelling(:final turnId, :final since) => (turnId, since),
};

/// Turn [turnId] settled with [result]: its ending drawn, a finished plan
/// moved into the transcript, and the turn idle.
Transcript settle(Transcript state, String turnId, TurnResult result) {
  final ending = _endingOf(turnId, result);

  final running = current(state.turn);

  if (running == null || running.$1 != turnId) {
    return ending == null
        ? state
        : state.withEntries(appended(state.entries, [ending]));
  }

  // A cancel stops the turn's subagents with it, as the adapters' draft
  // form does. One that can be cancelled alone is left for its agent to
  // report: it may live on, as a background one does; and so is chord's
  // own task, whose end chord always tells, with the key that stopped it.
  // Those still running after a turn that ended on its own are left: they
  // may outlive it.
  if (result is TurnAnswered && result.cancelled) {
    state = state.withEntries(
      endRunning(
        state.entries,
        SubagentState.cancelled,
        state.turn is Cancelling
            ? (state.turn as Cancelling).cancelledAt
            : null,
        (subagent) =>
            isRunning(subagent) &&
            !subagent.cancellable &&
            subagent.task == null,
      ),
    );
  }

  // A finished plan moves from above the prompt into the transcript, as the
  // turn's record of what it did; an unfinished one stays live for the next.
  final finished =
      state.plan.isNotEmpty &&
      state.plan.every((entry) => entry.status == 'completed');
  // Every permission still open outlives the turn: the agent's own still
  // waits on the person, now between turns.
  final kept = switch (state.turn) {
    AwaitingPermission(:final permissions) => permissions,
    _ => const <PermissionWait>[],
  };
  final added = [if (finished) FinishedPlanEntry(turnId, state.plan), ?ending];

  return Transcript(
    // The same list when nothing is added: a new one reads as news.
    entries: added.isEmpty ? state.entries : appended(state.entries, added),
    plan: finished ? const [] : state.plan,
    planId: state.planId,
    turn: kept.isNotEmpty
        ? AwaitingPermission(turnId, running.$2, kept, between: true)
        : const Idle(),
    usage: state.usage,
    mode: state.mode,
    planAsks: state.planAsks,
    // So does every form or link, the agent's own now asked between turns;
    // a task's waits as the task does.
    asking:
        state.asking.every((wait) => wait.between || wait.subagentId != null)
        ? state.asking
        : UnmodifiableListView([
            for (final wait in state.asking)
              wait.between || wait.subagentId != null ? wait : wait.leftOpen,
          ]),
    served: state.served,
  );
}

Entry? _endingOf(String turnId, TurnResult result) => switch (result) {
  TurnFailed(:final message, :final code, :final signIn) => ErrorEntry(
    turnId,
    message,
    code: code,
    signIn: signIn,
  ),
  TurnAnswered(cancelled: true) => CancelledEntry(turnId),
  TurnAnswered(:final stopReason) =>
    stopReason == acp.StopReason.endTurn
        ? null
        : StoppedEntry(turnId, stopReason),
};

/// Of [waits], the requests a turn leaves waiting as it ends: those of task
/// agents still running, which outlive it.
List<PermissionWait> taskWaits(Transcript state, List<PermissionWait> waits) =>
    [
      for (final wait in waits)
        if (wait.subagentId case final asker?)
          if (state.entries.any(
            (entry) =>
                entry is SubagentEntry &&
                entry.subagent.task != null &&
                entry.subagent.state == SubagentState.running &&
                (entry.subagent.id == asker ||
                    findSubagent(entry.subagent.entries, asker) != null),
          ))
            wait,
    ];
