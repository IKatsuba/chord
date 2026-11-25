// The original's Conversation.stopSubagent (conversation.ts): the person's
// stop of one subagent alone reads stopping at once, and goes back as it
// was when the stop could not be sent, the parent's turn untouched.
import 'dart:async';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/subagents.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

void main() {
  late ScriptedSession session;
  late Conversation conversation;
  late List<ConversationEvent> events;

  Subagent shown(String id) => subagentsIn(
    [
      for (final event in events)
        if (event case Transcribed(:final action)) action,
    ].fold(Transcript.empty, reduceTranscript).entries,
  ).firstWhere((each) => each.id == id);

  setUp(() async {
    session = ScriptedSession();
    events = [];
    conversation = Conversation(
      ({required onTraffic, required cancellationToken}) async => session,
    )..listen(events.add);
    addTearDown(conversation.close);
    conversation.start();
    while (!events.any((event) => event is Connected)) {
      await Future<void>.delayed(Duration.zero);
    }
    conversation.send('work');
    while (session.turns.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    session.say({
      'sessionUpdate': 'subagent_update',
      'sessionId': 'worker',
      'title': 'watcher',
      'state': {'state': 'running'},
      'capabilities': {'cancel': <String, Object?>{}},
    });
    await Future<void>.delayed(Duration.zero);
  });

  test('a stop marks the subagent stopping and goes to its agent by its own '
      'id', () async {
    await conversation.stopSubagent('worker');
    expect(session.stopped, ['worker']);
    expect(shown('worker').stopping, isTrue);
    expect(shown('worker').state, SubagentState.running);
    expect(session.cancels, 0);
  });

  test('a stop that cannot be sent is taken back, and its failure is the '
      "caller's, the parent's turn going on", () async {
    final notice = Completer<void>();
    session.stopping = (_) => notice.future;
    final stop = conversation.stopSubagent('worker');
    await Future<void>.delayed(Duration.zero);
    expect(shown('worker').stopping, isTrue);
    notice.completeError(StateError('Broken pipe'));
    await expectLater(stop, throwsA(isA<StateError>()));
    expect(shown('worker').stopping, isFalse);
    expect(shown('worker').state, SubagentState.running);
    expect(
      events.any((e) => e is Transcribed && e.action is CancelAction),
      isFalse,
    );
    expect(session.cancels, 0);
  });

  test('with no agent connected, a stop says so and marks nothing', () async {
    final idle = Conversation(
      ({required onTraffic, required cancellationToken}) =>
          Completer<Never>().future,
    );
    final heard = <ConversationEvent>[];
    idle.listen(heard.add);
    await expectLater(idle.stopSubagent('worker'), throwsStateError);
    expect(heard, isEmpty);
  });

  group('CTUI-83 tester: stop races', () {
    test(
      'completion crossing a failed send stays completed after rollback',
      () async {
        final notice = Completer<void>();
        session.stopping = (_) => notice.future;
        final stop = conversation.stopSubagent('worker');
        await Future<void>.delayed(Duration.zero);
        expect(shown('worker').stopping, isTrue);
        session.say({
          'sessionUpdate': 'subagent_update',
          'sessionId': 'worker',
          'state': {'state': 'idle', 'stopReason': 'end_turn'},
        });
        await Future<void>.delayed(Duration.zero);
        expect(shown('worker').state, SubagentState.completed);
        notice.completeError(StateError('send failed late'));
        await expectLater(stop, throwsStateError);
        expect(shown('worker').state, SubagentState.completed);
        expect(shown('worker').stopping, isFalse);
        expect(session.cancels, 0);
      },
    );
  });
}
