import 'package:chord/session/conversation.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'conversation_fake.dart';

void main() {
  test('queue snapshots mention paths with their typed and sent prompt', () {
    fakeAsync((async) {
      final s = Scripted();
      s.conversation.start();
      async.flushMicrotasks();
      final first = ['first.ts'];
      s.conversation.send('one', 'context one', first);
      first.add('late');
      final second = ['second.ts'];
      s.conversation.send('two', 'context two', second);
      second.clear();
      expect(s.session.turns.single.mentions, ['first.ts']);
      expect(
        () => s.session.turns.single.mentions.clear(),
        throwsUnsupportedError,
      );
      s.session.turns.first.answer();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(s.session.turns.last.text, 'context two');
      expect(s.session.turns.last.mentions, ['second.ts']);
      s.session.turns.last.answer();
      async.flushMicrotasks();
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
  test('interrupt withdraws immutable queued paths before any resolution', () {
    fakeAsync((async) {
      final s = Scripted();
      s.conversation.start();
      async.flushMicrotasks();
      s.conversation.send('one');
      s.conversation.send('two', 'context', ['b.ts']);
      s.conversation.interrupt();
      async.flushMicrotasks();
      final queued = s.events.whereType<QueueWithdrawn>().single.prompts.single;
      expect((queued.text, queued.prompt), ('two', 'context'));
      expect(queued.mentions, ['b.ts']);
      expect(s.session.turns, hasLength(1));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
  for (final withdraw in [false, true]) {
    test(
      'mention paths survive permission relabelling and ${withdraw ? 'withdrawal' : 'answer'}',
      () {
        fakeAsync((async) {
          final s = Scripted();
          s.conversation.start();
          async.flushMicrotasks();
          s.conversation.send('one');
          s.conversation.send('two', 'context two', ['b.ts']);
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
          expect(s.session.turns.last.text, 'context two');
          expect(s.session.turns.last.mentions, ['b.ts']);
          s.session.turns.last.answer();
          async.flushMicrotasks();
          s.conversation.close();
          async.flushMicrotasks();
        });
      },
    );
  }
}
