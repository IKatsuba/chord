// A turn as every scenario plays it: the updates it sends on its session, at
// the agent's pace, and the ids of the calls it starts, as the original's
// turn.ts.
import 'dart:async';

import 'options.dart';
import 'rpc.dart';
import 'signals.dart';

export 'rpc.dart' show Client;
export 'signals.dart';

/// An update, as a map.
typedef Update = Map<String, Object?>;

/// A scenario: it plays one turn and says how the turn ended.
typedef Play = Future<String> Function(Turn turn);

/// A step, or [ms], on [signal]: fails with its reason once it aborts.
Future<void> pause(Signal signal, [num? ms]) =>
    sleep(signal, milliseconds(ms ?? stepMs));

/// Until [count] messages were steered into [turn], or 10 s without them
/// (CHD-399).
Future<void> steeredIn(Turn turn, int count) async {
  final deadline = DateTime.now().millisecondsSinceEpoch + 10000;
  while (turn.told < count &&
      DateTime.now().millisecondsSinceEpoch < deadline) {
    await pause(turn.signal);
  }
}

/// Aborted once the client has closed the connection: work that outlives
/// every turn ends on it.
final Aborter lifetime = Aborter();

/// How many tool calls each session has started, to number the next one.
final _callCounts = <String, int>{};

/// A mark for each session this process loaded or resumed rather than
/// created, so its calls take ids an earlier process never gave.
final loadMarks = <String, String>{};

/// Who a message chord wrapped is from, as its row names them first.
String? senderOf(String text) => RegExp(
  r'^<message from="([^"]*)"',
).firstMatch(text)?.group(1)?.split(' · ').first;

final class Turn {
  Turn(this.client, this.sessionId, this.signal);

  final Client client;
  final String sessionId;
  final Signal signal;

  /// Token usage the turn's answer reports.
  Map<String, Object?>? usage;

  final _steered = <({String text, List<String> received})>[];
  var _read = 0;
  final _over = Completer<void>();

  /// A new call's id, unique within its session.
  String callId(String name) {
    final count = (_callCounts[sessionId] ?? 0) + 1;
    _callCounts[sessionId] = count;
    final mark = loadMarks[sessionId];
    return mark == null ? '$name-$count' : '$name-$mark-$count';
  }

  Future<void> send(Update update) async {
    await pause(signal);
    await read();
    await client.notify('session/update', {
      'sessionId': sessionId,
      'update': update,
    });
  }

  /// Settles once the turn's play has returned and its answer goes out
  /// next (CHD-399).
  Future<void> get over => _over.future;

  /// Marks the turn's play returned: [over] settles.
  void end() {
    if (!_over.isCompleted) _over.complete();
  }

  /// A message steered into the turn, read at its next step or its end.
  void steer(String text, [List<String> received = const []]) =>
      _steered.add((text: text, received: received));

  /// Whether a message steered in waits for the turn's next step.
  bool get steered => _steered.isNotEmpty;

  /// How many messages steered in, read or waiting, the turn has had.
  int get told => _read + _steered.length;

  /// Answers each message steered in since the last step, saying whose.
  Future<void> read() async {
    final waiting = List.of(_steered);
    _steered.clear();
    for (final (:text, :received) in waiting) {
      _read += 1;
      await client.notify('session/update', {
        'sessionId': sessionId,
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {
            'type': 'text',
            'text': [
              'Read the message from ${senderOf(text) ?? 'nobody'}.\n\n',
              ...received,
            ].join(),
          },
        },
      });
    }
  }

  Future<void> say(List<String> chunks) async {
    for (final text in chunks) {
      await send({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': text},
      });
    }
  }

  Future<void> think(List<String> chunks) async {
    for (final text in chunks) {
      await send({
        'sessionUpdate': 'agent_thought_chunk',
        'content': {'type': 'text', 'text': text},
      });
    }
  }
}
