import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/transcript/reports.dart' show runningTurn;
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

void main() {
  group('tester: cycle permission prompt admission', () {
    test('an ended cycle gates a queued prompt on every held request', () {
      fakeAsync((async) {
        final s = Scripted();
        s.conversation.start();
        async.flushMicrotasks();
        s.session.say({
          'sessionUpdate': 'session_info_update',
          '_meta': {'codebuddy.ai/unsolicitedTurn': true},
        });
        s.session.ask(toolCallId: 'one').ignore();
        s.session.ask(toolCallId: 'two').ignore();
        async.flushMicrotasks();
        final pending = s.session.permissions.pending();
        expect(pending, hasLength(2));
        final before = s.events
            .fold(AppState.starting, reduceApp)
            .transcript
            .turn;
        expect(runningTurn(before), isNotNull);
        expect(s.conversation.send('after permission'), isTrue);
        async.flushMicrotasks();
        expect(s.session.turns, isEmpty);
        s.session.say({'sessionUpdate': 'session_end'});
        final ended =
            s.events.fold(AppState.starting, reduceApp).transcript.turn
                as AwaitingPermission;
        expect((ended.between, ended.cycle), (true, false));
        expect(runningTurn(ended), isNull);
        s.conversation.choose(pending.first.id, 'allow');
        async.flushMicrotasks();
        expect(s.session.turns, isEmpty);
        s.conversation.choose(pending.last.id, 'deny');
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: quietMs));
        expect(s.session.turns.single.text, 'after permission');
        expect([
          for (final event in s.events)
            if (event case Transcribed(action: CycleStartedAction())) event,
        ], hasLength(1));
        final prompt =
            s.events.fold(AppState.starting, reduceApp).transcript.turn
                as Working;
        expect(prompt.cycle, isFalse);
        s.session.turns.single.answer();
        async.flushMicrotasks();
        s.conversation.close();
        async.flushMicrotasks();
      });
    });
  });
}
