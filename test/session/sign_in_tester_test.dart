import 'dart:async';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/sign_in.dart';
import 'package:chord/session/start_failure.dart';
import 'package:chord/ui/app/state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

const _signIn = SignIn('Authentication required', [
  (name: 'Browser', description: null),
]);
const _failure = StartFailure(
  step: StartStep.newSession,
  code: -32000,
  pinned: 'fixture-acp@1.0.0',
);

SignInNeeded _needed() => SignInNeeded(
  _signIn,
  StartFailed(_failure, message: _signIn.message, cause: StateError('fixture')),
);

void main() {
  group('tester: failed-start sign-in ownership', () {
    test('two concurrent starts retain only their own structural facts', () {
      fakeAsync((async) {
        final authEvents = <ConversationEvent>[];
        final plainEvents = <ConversationEvent>[];
        final auth = Conversation(
          ({required onTraffic, required cancellationToken}) async =>
              throw ResumeError('cannot resume', cause: _needed()),
        )..listen(authEvents.add);
        final plain = Conversation(
          ({required onTraffic, required cancellationToken}) async =>
              throw StateError('Authentication required'),
        )..listen(plainEvents.add);
        auth.start();
        plain.start();
        async.flushMicrotasks();
        final failure = authEvents.whereType<ConnectFailed>().single;
        expect(failure.signIn, same(_signIn));
        expect(failure.failure, same(_failure));
        final other = plainEvents.whereType<ConnectFailed>().single;
        expect(other.signIn, isNull);
        expect(other.failure, isNull);
        auth.close();
        plain.close();
        async.flushMicrotasks();
      });
    });

    test('retired held opener cannot publish late sign-in or pin', () {
      fakeAsync((async) {
        final held = Completer<Session>();
        final next = ScriptedSession();
        final events = <ConversationEvent>[];
        var openings = 0;
        final conversation = Conversation(
          ({required onTraffic, required cancellationToken}) =>
              openings++ == 0 ? held.future : Future.value(next),
        )..listen(events.add);
        conversation.start();
        async.flushMicrotasks();
        expect(events.whereType<ConnectFailed>(), isEmpty);
        conversation.clear();
        async.flushMicrotasks();
        expect(events.whereType<Connected>(), hasLength(1));
        held.completeError(_needed());
        async.flushMicrotasks();
        expect(events.whereType<ConnectFailed>(), isEmpty);
        conversation.close();
        async.flushMicrotasks();
        expect(next.closes, 1);
      });
    });

    test('a duplicate failed-start event cannot replace settled facts', () {
      final state = reduceApp(
        AppState.starting,
        const ConnectFailed('auth', signIn: _signIn, failure: _failure),
      );
      final duplicate = reduceApp(
        state,
        const ConnectFailed('late generic failure'),
      );
      expect(duplicate, same(state));
      expect(duplicate.start.signIn, same(_signIn));
      expect(duplicate.start.failure, same(_failure));
    });
  });
}
