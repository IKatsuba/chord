import 'package:chord/acp/upstream_turns.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

/// A conversation over a scripted session, up, its events kept.
({
  Conversation conversation,
  ScriptedSession session,
  List<ConversationEvent> events,
})
up(FakeAsync async, {bool steering = false}) {
  final session = ScriptedSession()..steering = steering;
  final conversation = Conversation(
    ({required onTraffic, required cancellationToken}) => Future.value(session),
  );
  final events = <ConversationEvent>[];
  conversation.listen(events.add);
  conversation.start();
  async.flushMicrotasks();
  return (conversation: conversation, session: session, events: events);
}

void main() {
  group('a turn id the caller chose', () {
    test('an idle send emits its prompt under that id before it returns, '
        'so a request bound first is answered by it', () {
      fakeAsync((async) {
        final (:conversation, :session, :events) = up(async);
        var turns = noTurns;
        final sends = <TurnSend>[];
        conversation.listen((event) {
          if (turnInputOf(event) case final input?) {
            final step = reduceTurns(turns, input);
            turns = step.turns;
            sends.addAll(step.sends);
          }
        });
        turns = reduceTurns(turns, const TurnBind(7, 'acp-1')).turns;
        expect(conversation.sendTurn('acp-1', 'hi'), isTrue);
        final prompt = events
            .whereType<Transcribed>()
            .map((event) => event.action)
            .whereType<PromptAction>()
            .single;
        expect(prompt.turnId, 'acp-1');
        expect(turns.running, (turnId: 'acp-1', origin: TurnOrigin.client));
        expect(sends, isEmpty, reason: 'its own prompt is not told back');
        session.turns.single.answer();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(sends.whereType<TurnAnswer>().single.requestId, 7);
        conversation.close();
        async.flushMicrotasks();
      });
    });

    test('a queued send keeps its id, and the window\'s own still counts '
        'turn-n', () {
      fakeAsync((async) {
        final (:conversation, session: _, :events) = up(async);
        conversation.send('first');
        conversation.sendTurn('acp-2', 'second');
        final queued = events.whereType<Queued>().single;
        expect(queued.turnId, 'acp-2');
        final prompt = events
            .whereType<Transcribed>()
            .map((event) => event.action)
            .whereType<PromptAction>()
            .single;
        expect(prompt.turnId, 'turn-1');
        conversation.close();
        async.flushMicrotasks();
      });
    });

    test('before the session is up, a send is refused', () {
      fakeAsync((async) {
        final conversation = Conversation(
          ({required onTraffic, required cancellationToken}) async =>
              ScriptedSession(),
        );
        expect(conversation.sendTurn('acp-1', 'hi'), isFalse);
        conversation.close();
        async.flushMicrotasks();
      });
    });
  });

  group('a steer of its own prompt', () {
    test('it takes its own entry into the running turn, not the prompt '
        'queued ahead', () {
      fakeAsync((async) {
        final (:conversation, :session, :events) = up(async, steering: true);
        conversation.send('running');
        conversation.sendTurn('ahead', 'queued ahead');
        conversation.sendTurn('mine', 'steer me');
        expect(conversation.steerQueued('mine'), 'sent');
        async.flushMicrotasks();
        expect(session.steered.single.text, 'steer me');
        expect(
          events.whereType<Queued>().where((row) => row.taken).single.turnId,
          'mine',
        );
        conversation.interrupt();
        expect(
          events.whereType<QueueWithdrawn>().single.prompts.map(
            (prompt) => prompt.turnId,
          ),
          ['ahead'],
        );
        conversation.close();
        async.flushMicrotasks();
      });
    });

    test('a turn id not queued is none, and without one the oldest goes, '
        'as the window steers', () {
      fakeAsync((async) {
        final (:conversation, :session, events: _) = up(async, steering: true);
        conversation.send('running');
        conversation.sendTurn('a', 'first');
        conversation.sendTurn('b', 'second');
        expect(conversation.steerQueued('nothing'), 'none');
        expect(conversation.steerQueued(), 'sent');
        async.flushMicrotasks();
        expect(session.steered.single.text, 'first');
        conversation.close();
        async.flushMicrotasks();
      });
    });
  });

  group('tester U4 caller turn boundaries', () {
    test('queued delivery retains its caller id and snapshots mentions', () {
      fakeAsync((async) {
        final (:conversation, :session, :events) = up(async);
        conversation.sendTurn('first', 'running');
        final mentions = ['notes.md'];
        conversation.sendTurn(
          'second',
          '界👩‍💻e\u0301',
          prompt: 'wire context',
          mentions: mentions,
        );
        mentions.add('later.md');
        session.turns.first.answer();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(session.turns, hasLength(2));
        expect(session.turns.last.text, 'wire context');
        expect(session.turns.last.mentions, ['notes.md']);
        expect(
          events
              .whereType<Transcribed>()
              .map((e) => e.action)
              .whereType<PromptAction>()
              .map((a) => a.turnId),
          ['first', 'second'],
        );
        session.turns.last.answer();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(
          events
              .whereType<Transcribed>()
              .map((e) => e.action)
              .whereType<ResultAction>()
              .map((a) => a.turnId),
          ['first', 'second'],
        );
        conversation.close();
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test(
      'close refuses caller sends and targeted steering while late results settle',
      () {
        fakeAsync((async) {
          final (:conversation, :session, events: _) = up(
            async,
            steering: true,
          );
          conversation.sendTurn('running', 'running');
          conversation.sendTurn('queued', 'queued');
          conversation.close();
          expect(conversation.sendTurn('late', 'late'), isFalse);
          expect(conversation.steerQueued('queued'), isNull);
          session.turns.first.answer();
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 5));
          expect(session.turns, hasLength(1));
          expect(session.steered, isEmpty);
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );

    test('a targeted row held for an answer cannot be steered twice', () {
      fakeAsync((async) {
        final (:conversation, :session, :events) = up(async, steering: true);
        conversation.sendTurn('running', 'running');
        conversation.sendTurn('first', 'first');
        conversation.sendTurn('second', 'second');
        expect(conversation.steerQueued('first'), 'sent');
        expect(conversation.steerQueued('second'), 'sent');
        async.flushMicrotasks();
        session.ask().ignore();
        async.flushMicrotasks();
        session.steered.single.answer();
        async.flushMicrotasks();
        final restored = events.whereType<Queued>().last;
        expect(restored.turnId, 'second');
        expect(restored.afterAnswer, isTrue);
        expect(conversation.steerQueued('second'), 'none');
        expect(session.steered, hasLength(1));
        conversation.close();
        async.flushMicrotasks();
      });
    });

    test(
      'two conversations retain equal caller ids through one cancellation',
      () {
        fakeAsync((async) {
          final first = up(async);
          final second = up(async);
          first.conversation.sendTurn('same', 'first');
          second.conversation.sendTurn('same', 'second');
          first.conversation.interrupt();
          async.flushMicrotasks();
          expect(first.session.cancels, 1);
          expect(second.session.cancels, 0);
          second.session.turns.single.answer();
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 5));
          expect(
            second.events
                .whereType<Transcribed>()
                .map((e) => e.action)
                .whereType<ResultAction>()
                .single
                .turnId,
            'same',
          );
          first.conversation.close();
          second.conversation.close();
          async.flushMicrotasks();
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );
  });
}
