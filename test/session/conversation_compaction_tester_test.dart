import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

Map<String, Object?> _compaction(String id, String status) => {
  'sessionUpdate': 'compaction_update',
  'compactionId': id,
  'status': status,
};

List<UpdateAction> _updates(List<ConversationEvent> events) => [
  for (final event in events)
    if (event case Transcribed(action: final UpdateAction action)) action,
];

void main() {
  group('tester compaction conversation ownership', () {
    test('clear resets seen ids and ignores a retired session late patch', () {
      fakeAsync((async) {
        final old = ScriptedSession(), fresh = ScriptedSession();
        var opens = 0;
        final conversation = Conversation(
          ({required onTraffic, required cancellationToken}) async =>
              opens++ == 0 ? old : fresh,
        );
        final events = <ConversationEvent>[];
        conversation.listen(events.add);
        conversation.start();
        async.flushMicrotasks();
        old.say(_compaction('reused', 'in_progress'));
        expect(_updates(events).single.unasked, isTrue);
        conversation.clear();
        async.flushMicrotasks();
        final count = events.length;
        old.say(_compaction('reused', 'failed'));
        expect(events, hasLength(count));
        fresh.say(_compaction('reused', 'completed'));
        expect(_updates(events).last.unasked, isTrue);
        fresh.say(_compaction('reused', 'completed'));
        expect(_updates(events).last.unasked, isFalse);
        conversation.close();
        async.flushMicrotasks();
        expect((old.closes, fresh.closes), (1, 1));
      });
    });

    test('a compaction first seen in a turn never becomes unasked later', () {
      fakeAsync((async) {
        final s = Scripted();
        s.conversation.start();
        async.flushMicrotasks();
        s.conversation.send('compact');
        async.flushMicrotasks();
        s.session.say(_compaction('asked', 'in_progress'));
        s.session.turns.single.answer();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        s.session.say(_compaction('asked', 'completed'));
        s.session.say(_compaction('new-id', 'completed'));
        expect(_updates(s.events).map((a) => a.unasked), [false, false, true]);
        s.conversation.close();
        async.flushMicrotasks();
      });
    });

    test('an active autonomous cycle keeps a new compaction asked', () {
      fakeAsync((async) {
        final s = Scripted();
        s.session.ownCycles = true;
        s.conversation.start();
        async.flushMicrotasks();
        s.conversation.send('first');
        async.flushMicrotasks();
        s.session.turns.single.answer();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        s.session.chunk('autonomous work');
        s.session.say(_compaction('cycle', 'in_progress'));
        expect(_updates(s.events).last.unasked, isFalse);
        expect(
          s.events
              .whereType<Transcribed>()
              .map((e) => e.action)
              .whereType<CycleStartedAction>(),
          hasLength(1),
        );
        s.conversation.close();
        async.flushMicrotasks();
      });
    });

    test('concurrent conversations classify the same id independently', () {
      fakeAsync((async) {
        final idle = Scripted(), active = Scripted();
        for (final s in [idle, active]) {
          s.conversation.start();
        }
        async.flushMicrotasks();
        active.conversation.send('hanging turn');
        async.flushMicrotasks();
        idle.session.say(_compaction('shared', 'in_progress'));
        active.session.say(_compaction('shared', 'in_progress'));
        expect(_updates(idle.events).single.unasked, isTrue);
        expect(_updates(active.events).single.unasked, isFalse);
        for (final s in [idle, active]) {
          s.conversation.close();
        }
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(idle.session.closes, 1);
        expect(active.session.closes, 1);
      });
    });
  });
}
