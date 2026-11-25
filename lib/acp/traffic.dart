/// Everything that crosses between chord and an agent, as the one subscriber
/// hears it.
library;

/// One thing that crossed: a JSON-RPC message either way, as decoded, or
/// what the agent wrote to stderr.
sealed class Traffic {
  const Traffic();

  /// A message the agent sent.
  const factory Traffic.agent(Map<String, Object?> message) = AgentTraffic;

  /// A message chord sent.
  const factory Traffic.chord(Map<String, Object?> message) = ChordTraffic;

  /// A piece of the agent's stderr.
  const factory Traffic.stderr(String text) = StderrTraffic;
}

/// A message the agent sent, before it is routed.
final class AgentTraffic extends Traffic {
  /// The decoded [message]; nobody mutates it.
  const AgentTraffic(this.message);

  final Map<String, Object?> message;

  @override
  String toString() => 'Traffic.agent($message)';
}

/// A message chord sent, as it goes on the wire.
final class ChordTraffic extends Traffic {
  /// The [message] written; nobody mutates it.
  const ChordTraffic(this.message);

  final Map<String, Object?> message;

  @override
  String toString() => 'Traffic.chord($message)';
}

/// A piece of the agent's stderr, as it came.
final class StderrTraffic extends Traffic {
  /// The [text] the agent wrote.
  const StderrTraffic(this.text);

  final String text;

  @override
  String toString() => 'Traffic.stderr($text)';
}

/// Hands each crossing to the subscriber in wire order, before routing, so
/// an update sent ahead of a reply reaches it before the reply's future
/// completes. The subscriber must not throw; one that does is caught and
/// dropped, so a reducer's bug cannot kill the pipe's listener, and the
/// message is still routed.
class TrafficTap {
  /// A tap onto [onTraffic].
  const TrafficTap(this.onTraffic);

  final void Function(Traffic traffic) onTraffic;

  /// Hands [traffic] on.
  void hear(Traffic traffic) {
    try {
      onTraffic(traffic);
    } catch (_) {
      // The subscriber's own failure; the connection goes on without it.
    }
  }
}
