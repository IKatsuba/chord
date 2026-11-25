import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'conversation_fake.dart';

void main() {
  test(
    'sent payload differs from typed transcript and stays with queued prompt',
    () {
      fakeAsync((async) {
        final s = Scripted();
        s.conversation.start();
        async.flushMicrotasks();
        expect(
          s.conversation.send('typed one', '<context>one</context>'),
          isTrue,
        );
        expect(s.session.turns.single.text, '<context>one</context>');
        s.conversation.send('typed two', '<context>two</context>');
        expect(s.events.whereType<Queued>().single.text, 'typed two');
        s.session.turns.first.answer();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(s.session.turns.last.text, '<context>two</context>');
        expect(
          s.events
              .whereType<Transcribed>()
              .map((e) => e.action)
              .whereType<PromptAction>()
              .map((a) => a.text),
          ['typed one', 'typed two'],
        );
        s.session.turns.last.answer();
        async.flushMicrotasks();
        s.conversation.close();
        async.flushMicrotasks();
      });
    },
  );
  test('withdrawn queued payload stays associated with its typed text', () {
    fakeAsync((async) {
      final s = Scripted();
      s.conversation.start();
      async.flushMicrotasks();
      s.conversation.send('first');
      s.conversation.send('second', 'context second');
      s.conversation.interrupt();
      async.flushMicrotasks();
      final withdrawn = s.events
          .whereType<QueueWithdrawn>()
          .single
          .prompts
          .single;
      expect((withdrawn.text, withdrawn.prompt), ('second', 'context second'));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
}
