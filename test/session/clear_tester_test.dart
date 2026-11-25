import 'dart:async';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

void main() {
  group('tester clear lifecycle', () {
    test('clearing one conversation leaves another live turn untouched', () {
      fakeAsync((async) {
        final retired = ScriptedSession();
        final replacement = ScriptedSession();
        final other = Scripted();
        var opens = 0;
        final first = Conversation(
          ({required onTraffic, required cancellationToken}) async =>
              opens++ == 0 ? retired : replacement,
        );
        final events = <ConversationEvent>[];
        first.listen(events.add);
        first.start();
        other.conversation.start();
        async.flushMicrotasks();
        first.send('retired turn');
        other.conversation.send('independent turn');
        first.clear();
        async.flushMicrotasks();
        expect(retired.cancels, 1);
        async.elapse(const Duration(milliseconds: settleLimitMs + quietMs));
        expect(retired.closes, 1);
        expect(other.session.cancels, 0);
        expect(other.session.closes, 0);
        final count = events.length;
        retired.exit('late exit');
        retired.chunk('late text');
        async.flushMicrotasks();
        expect(events, hasLength(count));
        first.send('replacement turn');
        other.session.chunk('independent answer');
        expect(replacement.turns.single.text, 'replacement turn');
        expect(other.session.turns.single.text, 'independent turn');
        first.close();
        async.flushMicrotasks();
        expect(replacement.closes, 1);
        expect(other.session.closes, 0);
        other.conversation.close();
        async.flushMicrotasks();
        expect(other.session.closes, 1);
      });
    });

    test(
      'repeated clears retire late failed openings without poisoning fresh one',
      () {
        fakeAsync((async) {
          final pending = [Completer<Session>(), Completer<Session>()];
          final fresh = ScriptedSession();
          var opens = 0;
          final c = Conversation(
            ({required onTraffic, required cancellationToken}) =>
                opens < 2 ? pending[opens++].future : Future.value(fresh),
          );
          final events = <ConversationEvent>[];
          c.listen(events.add);
          c.start();
          c.clear();
          c.clear();
          async.flushMicrotasks();
          expect(events.whereType<Cleared>(), hasLength(2));
          expect(events.whereType<Connected>(), hasLength(1));
          pending[1].completeError(StateError('retired second opening'));
          pending[0].completeError(StateError('retired first opening'));
          async.flushMicrotasks();
          expect(events.whereType<ConnectFailed>(), isEmpty);
          c.setMode('plan').ignore();
          async.flushMicrotasks();
          expect(fresh.changes, [('mode', 'plan', null)]);
          var closed = false;
          c.close().then((_) => closed = true);
          async.flushMicrotasks();
          expect(closed, isTrue);
          expect(fresh.closes, 1);
          expect(events.last, isA<Closing>());
        });
      },
    );
  });
}
