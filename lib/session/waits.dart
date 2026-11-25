/// Where an agent of the window stands with the person: what it asks, what
/// of it is not yet seen, whether it works, as the status line and the
/// terminal's status read it. From the original's `session/waits.ts`.
library;

import '../notify.dart';
import 'conversation.dart';
import 'tasks.dart' show senderName;
import 'transcript/types.dart';

/// What failed: the agent's process exited, the agent never came up, or a
/// turn failed with the agent still open, gravest first.
enum Failure { exited, start, turn }

/// The graver of two failures.
Failure _graver(Failure? a, Failure b) =>
    a != null && a.index < b.index ? a : b;

/// A permission or form open, and since when, epoch milliseconds.
typedef Asking = ({AskingWait on, num since});

/// Why an unseen wait is news: a turn's end or failure, or a message from
/// another agent that came in while it was not shown.
enum UnseenKind { replied, failed, message }

/// A turn that ended or failed, or an agent that never came up, while the
/// agent was not shown, and since when; gone once the person goes to it.
final class Unseen {
  const Unseen(
    this.kind, {
    required this.since,
    this.failure,
    this.failedAt,
    this.repliedAt,
    this.from,
  });

  /// Who a message came from, by the name its row gives.
  final String? from;

  final UnseenKind kind;

  /// The first news of any kind, for the order.
  final num since;

  /// A failure's cause, the gravest seen since it was last looked at.
  final Failure? failure;

  /// When the first failure came, which a failed turn counts its time from.
  final num? failedAt;

  /// When the newest reply came, which its age counts from.
  final num? repliedAt;
}

/// Where one agent stands with the person. Times are epoch milliseconds.
final class AgentWait {
  const AgentWait({
    this.watch = emptyWatch,
    this.asking,
    this.unseen,
    this.ended,
    this.working,
    this.stopped,
    this.exited = false,
  });

  /// What `notify.dart` has folded of the session's events so far.
  final Watch watch;

  /// A permission or form open in it, and since when; kept while the agent
  /// is shown too, as it lasts until it is answered.
  final Asking? asking;

  /// News while the agent was not shown.
  final Unseen? unseen;

  /// A turn that ended or failed, or an agent that never came up, as the
  /// terminal's status reports it: gone once the person presses a key while
  /// it is shown, or its next turn starts. Holds its failure, if any.
  final ({Failure? failure})? ended;

  /// When the turn running now began, while one runs.
  final num? working;

  /// When its agent last stopped working: its turn's or own cycle's end,
  /// else when it came up.
  final num? stopped;

  /// Its agent has exited.
  final bool exited;
}

/// Nothing yet.
const idle = AgentWait();

/// A wait's failure, if it has one: an exit, while the agent is gone, first.
Failure? failureOf(AgentWait wait) {
  final unseen = wait.unseen;
  if (unseen == null || unseen.kind != UnseenKind.failed) return null;
  return wait.exited ? Failure.exited : (unseen.failure ?? Failure.turn);
}

/// Folds one of an agent's events into its wait, [front] while it is the one
/// shown, and says the wait it starts, if any, as `notify.dart` classes
/// waits.
({AgentWait wait, Wait? started}) heardWait(
  AgentWait before,
  ConversationEvent event,
  num now, {
  bool front = true,
}) {
  final watched = watchWaits(before.watch, event);
  return (
    wait: _waitAfter(before, watched.watch, event, watched.wait, now, front),
    started: watched.wait,
  );
}

TranscriptAction? _action(ConversationEvent event) =>
    event is Transcribed ? event.action : null;

AgentWait _waitAfter(
  AgentWait before,
  Watch watch,
  ConversationEvent event,
  Wait? started,
  num now,
  bool front,
) {
  if (event is Cleared) return idle;
  final action = _action(event);
  final Asking? asking = started is AskingWait
      ? (on: started, since: now)
      : watch.asking.isEmpty || before.asking == null
      ? null
      // Still waiting since it began, on whichever request is the oldest
      // still open: the one answered may have been another's.
      : (
          on: askingNow(watch) ?? before.asking!.on,
          since: before.asking!.since,
        );
  final disconnected = action is DisconnectedAction;
  final connectFailed = event is ConnectFailed;
  // An exit is news even with no turn running: the agent is gone.
  final failed =
      connectFailed ||
      disconnected ||
      (started is TurnEnded &&
          action is ResultAction &&
          action.result is TurnFailed);
  final ended = failed || started is TurnEnded;
  final exits = disconnected || before.exited;
  final cause = exits
      ? Failure.exited
      : connectFailed
      ? Failure.start
      : Failure.turn;
  final beforeUnseen = before.unseen;
  // A failure outranks a reply, and the wait counts from the first of them.
  final failure = failed || beforeUnseen?.kind == UnseenKind.failed
      ? _graver(beforeUnseen?.failure, cause)
      : null;
  // A message from another agent, while not shown: its sender, as its row
  // names it.
  final message = switch (event) {
    Transcribed(action: PromptAction(:final from?)) => from,
    Queued(:final from?) => from,
    _ => null,
  };
  final Unseen? unseen = front
      ? beforeUnseen
      : !ended &&
            message != null &&
            beforeUnseen?.kind != UnseenKind.failed &&
            beforeUnseen?.kind != UnseenKind.replied
      ? Unseen(
          UnseenKind.message,
          since: beforeUnseen?.since ?? now,
          from: senderName(message),
        )
      : ended
      ? failure == null
            ? Unseen(
                UnseenKind.replied,
                since: beforeUnseen?.since ?? now,
                repliedAt: now,
              )
            : Unseen(
                UnseenKind.failed,
                since: beforeUnseen?.since ?? now,
                failure: failure,
                failedAt: beforeUnseen?.kind == UnseenKind.failed
                    ? (beforeUnseen!.failedAt ?? beforeUnseen.since)
                    : now,
              )
      : beforeUnseen;
  final endedFailure = failed
      ? _graver(before.ended?.failure, cause)
      : before.ended?.failure;
  final starts = action is PromptAction || action is CycleStartedAction;
  // The next turn's start leaves the last one's end behind.
  final ({Failure? failure})? endedNow = starts
      ? null
      : ended
      ? (failure: endedFailure)
      : before.ended;
  // A connection after an exit is the agent up again: an exit the session's
  // past replays on resume, or one before a restart, is not what the agent
  // does now.
  final up = event is Connected && before.exited;
  final unseenUp =
      up &&
          unseen?.kind == UnseenKind.failed &&
          unseen?.failure == Failure.exited
      ? null
      : unseen;
  final endedUp = up && endedNow?.failure == Failure.exited ? null : endedNow;
  // A cycle of the agent's own works as a turn does.
  final working = switch (action) {
    PromptAction(:final at) => before.working ?? at,
    CycleStartedAction(:final at) => before.working ?? at,
    ResultAction() => null,
    _ => connectFailed ? null : before.working,
  };
  final stopped = before.working != null && working == null
      ? now
      : event is Connected && before.stopped == null
      ? now
      : before.stopped;
  return AgentWait(
    watch: watch,
    asking: asking,
    unseen: unseenUp,
    ended: endedUp,
    working: working,
    stopped: stopped,
    exited: disconnected || (before.exited && !up),
  );
}

/// A key pressed in chord while the agent is shown: its turn's end is seen,
/// the window's one agent's form of the original's `keyed`.
AgentWait keyed(AgentWait wait) => wait.ended == null
    ? wait
    : AgentWait(
        watch: wait.watch,
        asking: wait.asking,
        unseen: wait.unseen,
        working: wait.working,
        stopped: wait.stopped,
        exited: wait.exited,
      );
