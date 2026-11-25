/// Which `session/prompt` a turn answers, from the original's
/// `acp/upstream_turns.ts`. `Conversation.send` emits before it returns,
/// and an agent's own turn may run with prompts queued behind it, so
/// arrival cannot say: a request binds its turn before it sends.
library;

import '../session/conversation.dart';
import '../session/transcript/types.dart';

/// Who began the turn running now.
enum TurnOrigin {
  /// A client's prompt, or a steer that runs as its own turn.
  client,

  /// A message no client sent.
  message,

  /// The agent's own cycle, or a turn it started itself.
  agent,
}

/// The turn running now and who began it.
typedef RunningTurn = ({String turnId, TurnOrigin origin});

/// The table: each prompt not yet answered, the turn running, the one lost
/// with its agent, and the turns a client steered.
final class Turns {
  /// A table of [bound] prompts, [running], [lost] and [steered].
  const Turns({
    this.bound = const {},
    this.running,
    this.lost,
    this.steered = const {},
  });

  /// Each prompt not yet answered, its JSON-RPC id by its turn, in the
  /// order bound.
  final Map<String, Object?> bound;

  /// The turn running now, if any.
  final RunningTurn? running;

  /// The bound turn that was running when its agent went: its result is
  /// still to come, and it answers then, unlike a prompt that was queued.
  final String? lost;

  /// Turns a client steered, which answer no request: when one runs as its
  /// own turn it is the client's, and its words are not told back.
  final Set<String> steered;

  Turns _with({
    Map<String, Object?>? bound,
    (RunningTurn?,)? running,
    (String?,)? lost,
    Set<String>? steered,
  }) => Turns(
    bound: bound ?? this.bound,
    running: running == null ? this.running : running.$1,
    lost: lost == null ? this.lost : lost.$1,
    steered: steered ?? this.steered,
  );
}

/// The empty table.
const noTurns = Turns();

/// What the table hears: the handler's own, and the conversation's events.
sealed class TurnInput {
  const TurnInput();
}

/// A request bound to the turn it is about to send.
final class TurnBind extends TurnInput {
  /// [requestId] bound to [turnId].
  const TurnBind(this.requestId, this.turnId);

  /// The `session/prompt` request's id.
  final Object? requestId;

  /// The turn it sends.
  final String turnId;
}

/// `send` refused it, so no turn of it will ever be heard of.
final class TurnUnbind extends TurnInput {
  /// [turnId] given up.
  const TurnUnbind(this.turnId);

  /// The turn that will never be heard of.
  final String turnId;
}

/// A turn `_chord/session/steer` sends, before it is sent.
final class TurnSteered extends TurnInput {
  /// [turnId] steered.
  const TurnSteered(this.turnId);

  /// The steer's turn.
  final String turnId;
}

/// A prompt the conversation sent.
final class TurnPrompt extends TurnInput {
  /// The prompt of [turnId] with its [text], [from] and [into].
  const TurnPrompt(this.turnId, this.text, {this.from, this.into});

  /// Its turn.
  final String turnId;

  /// What the person sees of it.
  final String text;

  /// Who sent a message, as the record's `from` holds it.
  final Map<String, Object?>? from;

  /// Set on a message steered into a running turn; it gets no result.
  final String? into;
}

/// A turn ended.
final class TurnEnded extends TurnInput {
  /// [turnId] ended with [result].
  const TurnEnded(this.turnId, this.result);

  /// The turn.
  final String turnId;

  /// How it ended.
  final TurnResult result;
}

/// Queued turns taken out of the queue unsent.
final class TurnsWithdrawn extends TurnInput {
  /// [turnIds] withdrawn.
  const TurnsWithdrawn(this.turnIds);

  /// The turns withdrawn.
  final List<String> turnIds;
}

/// A turn of the agent's own began: a cycle, or one it started itself.
final class TurnByAgent extends TurnInput {
  /// The agent began [turnId].
  const TurnByAgent(this.turnId);

  /// Its turn.
  final String turnId;
}

/// The agent went.
final class TurnsDisconnected extends TurnInput {
  /// The one disconnection.
  const TurnsDisconnected();
}

/// `session/close`, or the way out.
final class TurnsClosing extends TurnInput {
  /// The one close.
  const TurnsClosing();
}

/// What the table says to do about what it heard.
sealed class TurnSend {
  const TurnSend();
}

/// Answer [requestId] with [result].
final class TurnAnswer extends TurnSend {
  /// The answer [result] to [requestId].
  const TurnAnswer(this.requestId, this.result);

  /// The request answered.
  final Object? requestId;

  /// Its turn's result.
  final TurnResult result;
}

/// Answer [requestId] `{stopReason: cancelled}`.
final class TurnCancelled extends TurnSend {
  /// [requestId] cancelled.
  const TurnCancelled(this.requestId);

  /// The request answered.
  final Object? requestId;
}

/// Queued when its agent went: [turnId] is still to be taken out of the
/// queue, and [requestId] answers -32002.
final class TurnSessionGone extends TurnSend {
  /// [requestId] of [turnId], whose session is gone.
  const TurnSessionGone(this.requestId, this.turnId);

  /// The request answered.
  final Object? requestId;

  /// Its turn, still queued.
  final String turnId;
}

/// A turn no client began: the client is told what started it.
final class TurnMessage extends TurnSend {
  /// The words [text], from [from].
  const TurnMessage(this.text, {this.from});

  /// What started it.
  final String text;

  /// Who sent it.
  final Map<String, Object?>? from;
}

/// The table after an input, and what to send.
typedef TurnStep = ({Turns turns, List<TurnSend> sends});

/// The turn [requestId] is bound to; none once it has been answered.
String? turnOf(Turns turns, Object? requestId) {
  for (final MapEntry(:key, :value) in turns.bound.entries) {
    if (value == requestId) return key;
  }
  return null;
}

Turns _unsteered(Turns turns, Iterable<String> turnIds) =>
    turns._with(steered: {...turns.steered}..removeAll(turnIds));

Map<String, Object?> _without(
  Map<String, Object?> bound,
  Iterable<String> turnIds,
) => {...bound}..removeWhere((turnId, _) => turnIds.contains(turnId));

/// [turns] after [input].
TurnStep reduceTurns(Turns turns, TurnInput input) {
  switch (input) {
    case TurnBind(:final requestId, :final turnId):
      return (
        turns: turns._with(bound: {...turns.bound, turnId: requestId}),
        sends: const [],
      );
    case TurnUnbind(:final turnId):
      return (
        turns: _unsteered(turns._with(bound: _without(turns.bound, [turnId])), [
          turnId,
        ]),
        sends: const [],
      );
    case TurnSteered(:final turnId):
      return (
        turns: turns._with(steered: {...turns.steered, turnId}),
        sends: const [],
      );
    case TurnPrompt(:final turnId, :final text, :final from, :final into):
      if (turns.steered.contains(turnId)) {
        final left = _unsteered(turns, [turnId]);
        return (
          turns: into == null
              ? left._with(
                  running: ((turnId: turnId, origin: TurnOrigin.client),),
                )
              : left,
          sends: const [],
        );
      }
      final message = TurnMessage(text, from: from);
      if (into != null) return (turns: turns, sends: [message]);
      // Over a cycle too: a prompt takes it over, and the cycle gets no
      // result.
      return turns.bound.containsKey(turnId)
          ? (
              turns: turns._with(
                running: ((turnId: turnId, origin: TurnOrigin.client),),
              ),
              sends: const [],
            )
          : (
              turns: turns._with(
                running: ((turnId: turnId, origin: TurnOrigin.message),),
              ),
              sends: [message],
            );
    case TurnEnded(:final turnId, :final result):
      final rest = _unsteered(turns, [turnId]);
      final requestId = turns.bound[turnId];
      final answered = turns.bound.containsKey(turnId);
      return (
        turns: Turns(
          bound: _without(turns.bound, [turnId]),
          running: turns.running?.turnId == turnId ? null : turns.running,
          lost: turns.lost == turnId ? null : turns.lost,
          steered: rest.steered,
        ),
        sends: [if (answered) TurnAnswer(requestId, result)],
      );
    case TurnsWithdrawn(:final turnIds):
      return (
        turns: _unsteered(
          turns._with(bound: _without(turns.bound, turnIds)),
          turnIds,
        ),
        sends: [
          for (final turnId in turnIds)
            if (turns.bound.containsKey(turnId))
              TurnCancelled(turns.bound[turnId]),
        ],
      );
    case TurnByAgent(:final turnId):
      return (
        turns: turns._with(
          running: ((turnId: turnId, origin: TurnOrigin.agent),),
        ),
        sends: const [],
      );
    case TurnsDisconnected():
      final lost = turns.running?.turnId ?? turns.lost;
      final queued = [
        for (final MapEntry(:key, :value) in turns.bound.entries)
          if (key != lost) (turnId: key, requestId: value),
      ];
      return (
        turns: Turns(
          bound: _without(turns.bound, [for (final q in queued) q.turnId]),
          lost: lost != null && turns.bound.containsKey(lost) ? lost : null,
          steered: turns.steered,
        ),
        sends: [for (final q in queued) TurnSessionGone(q.requestId, q.turnId)],
      );
    case TurnsClosing():
      return (
        turns: noTurns,
        sends: [
          for (final requestId in turns.bound.values) TurnCancelled(requestId),
        ],
      );
  }
}

/// What `_chord/session/state` says of a session.
enum SessionStateKind {
  /// A turn runs.
  running,

  /// An ask of its own is open.
  requiresAction,

  /// Nothing runs.
  idle;

  /// Its word on the wire.
  String get wire => switch (this) {
    running => 'running',
    requiresAction => 'requires_action',
    idle => 'idle',
  };
}

/// A session's state and, unless idle, who began its turn.
typedef SessionState = ({SessionStateKind state, TurnOrigin? origin});

/// Main's state, from the turn running and whether an ask of its own is
/// open: read after each step, so only a change need go.
SessionState sessionStateOf(Turns turns, {required bool asking}) {
  final origin = turns.running?.origin;
  if (asking) return (state: SessionStateKind.requiresAction, origin: origin);
  return origin == null
      ? (state: SessionStateKind.idle, origin: null)
      : (state: SessionStateKind.running, origin: origin);
}

/// [state] as `_chord/session/state`'s params for [sessionId].
Map<String, Object?> sessionStateParams(String sessionId, SessionState state) =>
    {
      'sessionId': sessionId,
      'state': state.state.wire,
      if (state.origin case final origin?) 'origin': origin.name,
    };

/// What the table hears of a conversation's [event], if anything.
TurnInput? turnInputOf(ConversationEvent event) => switch (event) {
  Transcribed(
    action: PromptAction(:final turnId, :final text, :final from, :final into),
  ) =>
    TurnPrompt(turnId, text, from: from?.toJson(), into: into),
  Transcribed(action: ResultAction(:final turnId, :final result)) => TurnEnded(
    turnId,
    result,
  ),
  Transcribed(action: CycleStartedAction(:final turnId)) ||
  Transcribed(action: SelfStartedAction(:final turnId)) => TurnByAgent(turnId),
  QueueWithdrawn(:final prompts) => TurnsWithdrawn([
    for (final prompt in prompts) prompt.turnId,
  ]),
  Gone() => const TurnsDisconnected(),
  _ => null,
};
