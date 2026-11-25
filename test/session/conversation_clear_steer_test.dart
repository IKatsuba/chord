// A clear gives back the person's steer still held for the calls a steer
// would cut, with their queued prompts, in order, and sends it to neither
// the old session nor the fresh one; another's message is let go.
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

void main() {
  test("a clear returns the person's held steer and queued prompts, in "
      "order, and lets another's message go", () {
    fakeAsync((async) {
      final sessions = <ScriptedSession>[];
      final conversation = Conversation(({
        required onTraffic,
        required cancellationToken,
      }) {
        final session = ScriptedSession()
          ..steering = true
          ..cutsSteeringCalls = true;
        sessions.add(session);
        return Future.value(session);
      });
      final events = <ConversationEvent>[];
      conversation.listen(events.add);
      conversation.start();
      async.flushMicrotasks();
      conversation.send('running');
      async.flushMicrotasks();
      sessions.single.say({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'c1',
        'title': 'c1',
        'status': 'in_progress',
      });
      async.flushMicrotasks();
      conversation.send('first');
      conversation.send('second');
      expect(conversation.steerQueued(), 'sent');
      async.flushMicrotasks();
      // Held for the open call, not out yet.
      expect(sessions.single.steered, isEmpty);
      conversation.deliver(
        const MessageFrom('main', reachable: true),
        'theirs',
      );
      conversation.clear().ignore();
      async.flushMicrotasks();
      final withdrawn = events.whereType<QueueWithdrawn>().single;
      expect([for (final p in withdrawn.prompts) p.text], ['first', 'second']);
      async.elapse(const Duration(seconds: 5));
      for (final session in sessions) {
        expect(session.steered, isEmpty);
        expect([
          for (final turn in session.turns) turn.text,
        ], isNot(contains('first')));
      }
      conversation.close();
      async.flushMicrotasks();
    });
  });
}
