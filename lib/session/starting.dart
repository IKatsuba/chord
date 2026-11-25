/// The model, effort and mode a session starts on, asked for once it exists
/// and before anything is shown or sent: the window's `Conversation` and
/// `-p`'s oneshot both ask through here, so a refusal reads the same in
/// either.
library;

import '../acp/connection.dart';

/// A starting value, by the agent's id for it.
class StartingValue {
  const StartingValue(this.id, {this.from, this.required = false});

  final String id;

  /// Where it was set, as a refusal says it, such as `set in
  /// .chord/settings.json`, so the person knows what to change.
  final String? from;

  /// Whether the agent must end on this value: [askStarting] then reports
  /// one the agent answers and leaves, `the agent is in <current>`, and
  /// the session's start fails on that refusal, as the model open_agent
  /// asks for (the original's conversation.ts:3532 and agents_host.ts:1375);
  /// the window and `-p` never set it.
  final bool required;
}

/// What asking for one starting value needs of the session.
class StartingAsk {
  const StartingAsk({
    required this.value,
    required this.what,
    required this.kind,
    required this.offered,
    required this.ask,
    this.listedOnly = false,
    this.current,
  });

  final StartingValue value;

  /// What is being started, as a refusal says it: `in plan mode`.
  final String what;

  /// What the agent would list, as a refusal says it: `modes`.
  final String kind;

  /// Whether an agent that lists none is refused without being asked, as
  /// for a mode; a model is asked for all the same.
  final bool listedOnly;

  /// The ids the agent lists; none when it lists none.
  final Future<List<String>?> Function() offered;

  /// The value the session is on now, read before the ask and after it.
  final String? Function()? current;
  final Future<void> Function() ask;
}

/// The agent's own words for a refusal: the `details` in its JSON-RPC
/// error's data, where Claude's adapter puts the reason under a generic
/// message, or else the message itself.
String agentMessageOf(Object error) {
  if (error case RpcException(:final data, :final message)) {
    if (data case {
      'details': final String details,
    } when details.trim().isNotEmpty) {
      return details.trim();
    }
    return message;
  }
  return switch (error) {
    AgentGone(:final message) => message,
    FormatException(:final message) => message,
    _ => '$error',
  };
}

/// Asks for one starting value; resolves to what a refusal says after
/// "could not", such as `start in yolo mode, set by --permission-mode: the
/// agent offers default, plan`, or to null when the agent took it. A value
/// the agent does not list is not asked for; with `listedOnly`, neither is
/// one when the agent lists nothing. One the session is on already is not
/// asked for either. When the agent answers and is still on another, a
/// required value is refused; an optional one is the agent's choice.
Future<String?> askStarting(StartingAsk starting) async {
  final StartingAsk(:value, :current) = starting;
  String? reason;

  if (current?.call() == value.id) return null;

  try {
    final ids = await starting.offered() ?? const <String>[];
    if (ids.isEmpty && starting.listedOnly) {
      reason = 'the agent offers no ${starting.kind}';
    } else if (ids.isNotEmpty && !ids.contains(value.id)) {
      reason = 'the agent offers ${ids.join(', ')}';
    } else {
      await starting.ask();
      final now = current?.call();
      if (value.required && now != null && now != value.id) {
        reason = 'the agent is in $now';
      }
    }
  } catch (error) {
    reason = agentMessageOf(error);
  }

  return reason == null
      ? null
      : 'start ${starting.what}'
            '${value.from == null ? '' : ', ${value.from}'}: $reason';
}
