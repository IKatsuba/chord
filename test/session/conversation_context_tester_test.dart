import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

void main() {
  group('tester: queued shell payload crosses permission boundaries', () {
    for (final withdraw in [false, true]) {
      test(
        'held payload survives ${withdraw ? 'withdrawal' : 'answer'} and queue relabelling',
        () {
          fakeAsync((async) {
            final s = Scripted();
            s.conversation.start();
            async.flushMicrotasks();
            s.conversation.send('first');
            s.conversation.send('typed second', 'held output second');
            final token = CancellationToken();
            s.session.ask(token: token).ignore();
            async.flushMicrotasks();
            s.session.turns.first.answer();
            async.flushMicrotasks();
            async.elapse(const Duration(seconds: 2));
            expect(s.session.turns, hasLength(1));
            expect(s.events.whereType<Queued>().last.afterAnswer, isTrue);
            if (withdraw) {
              token.cancel();
            } else {
              s.conversation.choose(
                s.session.permissions.pending().single.id,
                'allow',
              );
            }
            async.flushMicrotasks();
            async.elapse(const Duration(seconds: 1));
            async.flushMicrotasks();
            expect(s.session.turns.last.text, 'held output second');
            expect(s.events.whereType<Queued>().last.afterAnswer, isFalse);
            expect(
              s.events
                  .whereType<Transcribed>()
                  .map((e) => e.action)
                  .whereType<PromptAction>()
                  .last
                  .text,
              'typed second',
            );
            s.session.turns.last.answer();
            async.flushMicrotasks();
            s.conversation.close();
            async.flushMicrotasks();
          });
        },
      );
    }
  });
}
