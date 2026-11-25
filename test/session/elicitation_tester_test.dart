import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/elicitations.dart';
import 'package:chord/session/questions.dart'
    show Questions, QuestionsAgent, questionsKey;
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

Map<String, Object?> _form([String message = 'Form']) => {
  'sessionId': 's1',
  'mode': 'form',
  'message': message,
  'requestedSchema': {'type': 'object', 'properties': <String, Object?>{}},
};

List<TranscriptAction> _actions(List<ConversationEvent> events) => [
  for (final event in events)
    if (event case Transcribed(:final action)) action,
];

void main() {
  group('CTUI-68 tester: receipt-relative withdrawal race', () {
    for (final waited in [1999, 2000, 3000]) {
      test(
        'withdrawal after $waited ms settles once and ignores late answers',
        () {
          fakeAsync((async) {
            final s = Scripted();
            s.conversation.start();
            async.flushMicrotasks();
            s.conversation.send('work');
            async.flushMicrotasks();
            late PendingElicitation pending;
            s.session.elicitations.subscribe((request) => pending = request);
            final token = CancellationToken();
            Map<String, Object?>? wireAnswer;
            s.session.elicitations
                .handler({
                  ..._form(),
                  '_meta': {
                    questionsKey: const Questions(
                      QuestionsAgent.codex,
                      [],
                      expiresInMs: 3000,
                    ).toJson(),
                  },
                }, token)
                .then((answer) => wireAnswer = answer);
            async.flushMicrotasks();
            async.elapse(Duration(milliseconds: waited));
            token.cancel();
            async.flushMicrotasks();
            pending.answer(const AcceptReply({'stale': 'late'}));
            s.conversation.answer(pending.id, const DeclineReply());
            async.flushMicrotasks();
            final settled = _actions(
              s.events,
            ).whereType<ElicitationSettledAction>().toList();
            expect(settled, hasLength(1));
            expect(
              settled.single.answer,
              waited < 2000
                  ? isA<ElicitationWithdrawn>()
                  : isA<ElicitationTimedOut>(),
            );
            expect(wireAnswer, {'action': 'cancel'});
            s.session.turns.single.answer();
            async.flushMicrotasks();
            s.conversation.close();
            async.flushMicrotasks();
            expect(
              _actions(s.events).whereType<ElicitationSettledAction>(),
              hasLength(1),
            );
          });
        },
      );
    }
  });

  group('CTUI-68 tester: question wait preservation', () {
    test(
      'asked and leftOpen preserve questions, schema and routing fields',
      () {
        final shape = const Questions(QuestionsAgent.codex, [], expiresInMs: 0);
        final raw = {
          ..._form('Question'),
          'toolCallId': 'call-1',
          '_meta': {questionsKey: shape.toJson()},
        };
        final initial = waitOf('ask-1', raw) as FormWait;
        final asked = initial.asked(at: 12.5, between: false, asker: 'child');
        final held = asked.leftOpen;
        for (final wait in [initial, asked, held]) {
          expect(wait.id, 'ask-1');
          expect(wait.message, 'Question');
          expect(wait.toolCallId, 'call-1');
          expect(identical(wait.schema, raw['requestedSchema']), isTrue);
          expect(wait.questions?.toJson(), shape.toJson());
          expect(identical(wait.questions, initial.questions), isTrue);
        }
        expect(initial.at, isNull);
        expect(initial.between, isFalse);
        expect((asked.at, asked.between, asked.asker), (12.5, false, 'child'));
        expect((held.at, held.between, held.asker), (12.5, true, 'child'));
      },
    );

    test('generic forms and links do not acquire question data', () {
      final generic = waitOf('generic', _form()) as FormWait;
      expect(generic.questions, isNull);
      expect(generic.asked(at: 0).leftOpen.questions, isNull);
      expect(
        waitOf('link', {
          ..._form(),
          'mode': 'url',
          'url': 'https://example.com',
          '_meta': {
            questionsKey: const Questions(QuestionsAgent.codex, []).toJson(),
          },
        }),
        isA<LinkWait>(),
      );
    });
  });

  group('tester elicitation bridge lifecycle', () {
    test(
      'synchronous answers settle once despite later answer and withdrawal',
      () async {
        final bridge = ElicitationBridge();
        final token = CancellationToken();
        late PendingElicitation pending;
        bridge.subscribe((request) {
          pending = request;
          request.answer(const AcceptReply({'text': '界🙂e\u0301'}));
          request.answer(const DeclineReply());
        });
        final answer = bridge.handler(_form(), token);
        token.cancel();
        bridge.close();
        pending.answer(const CancelReply());
        expect(await answer, {
          'action': 'accept',
          'content': {'text': '界🙂e\u0301'},
        });
      },
    );

    test(
      'close cancels all parked asks and later calls without delivery',
      () async {
        final bridge = ElicitationBridge();
        final pending = <PendingElicitation>[];
        bridge.subscribe(pending.add);
        final first = bridge.handler(_form(), CancellationToken());
        final second = bridge.handler({
          ..._form(),
          'mode': 'url',
          'url': 'https://example.com',
        }, CancellationToken());
        expect(pending.map((p) => p.id).toSet(), hasLength(2));
        bridge.close();
        bridge.close();
        for (final answer in await Future.wait([first, second])) {
          expect(answer, {'action': 'cancel'});
        }
        expect(pending.every((p) => p.withdrawn.isCancelled), isTrue);
        expect(await bridge.handler(_form(), CancellationToken()), {
          'action': 'cancel',
        });
        expect(pending, hasLength(2));
      },
    );

    test('pre-cancelled and unsubscribed calls are never delivered', () async {
      final bridge = ElicitationBridge();
      var heard = 0;
      final unsubscribe = bridge.subscribe((_) => heard++);
      final token = CancellationToken()..cancel();
      expect(await bridge.handler(_form(), token), {'action': 'cancel'});
      unsubscribe();
      expect(await bridge.handler(_form(), CancellationToken()), {
        'action': 'cancel',
      });
      expect(heard, 0);
      bridge.close();
    });
  });

  group('tester elicitation conversation reentrancy', () {
    test('answering from requested notification records one answer', () {
      fakeAsync((async) {
        final s = Scripted();
        s.conversation.listen((event) {
          if (event case Transcribed(
            action: ElicitationRequestedAction(:final elicitation),
          )) {
            s.conversation.answer(
              elicitation.id,
              const AcceptReply({'name': 'synchronous'}),
            );
          }
        });
        s.conversation.start();
        async.flushMicrotasks();
        Map<String, Object?>? answer;
        final token = CancellationToken();
        s.session.elicitations
            .handler(_form(), token)
            .then((value) => answer = value);
        async.flushMicrotasks();
        expect(answer, {
          'action': 'accept',
          'content': {'name': 'synchronous'},
        });
        token.cancel();
        async.flushMicrotasks();
        expect(
          _actions(s.events).whereType<ElicitationSettledAction>(),
          hasLength(1),
        );
        s.conversation.close();
        async.flushMicrotasks();
      });
    });

    test(
      'withdrawal during requested delivery settles once and unblocks queue',
      () {
        fakeAsync((async) {
          final s = Scripted();
          final token = CancellationToken();
          s.conversation.listen((event) {
            if (event case Transcribed(action: ElicitationRequestedAction())) {
              s.conversation.send('queued');
              token.cancel();
            }
          });
          s.conversation.start();
          async.flushMicrotasks();
          Map<String, Object?>? answer;
          s.session.elicitations
              .handler(_form(), token)
              .then((value) => answer = value);
          async.elapse(const Duration(seconds: 2));
          expect(answer, {'action': 'cancel'});
          expect(
            _actions(s.events).whereType<ElicitationSettledAction>(),
            hasLength(1),
          );
          expect(s.session.turns.single.text, 'queued');
          s.session.turns.single.answer();
          async.flushMicrotasks();
          s.conversation.close();
          async.flushMicrotasks();
        });
      },
    );

    test('clear during request cannot withdraw replacement with reused id', () {
      fakeAsync((async) {
        final old = ScriptedSession(), fresh = ScriptedSession();
        var opens = 0, replacing = false;
        final conversation = Conversation(
          ({required onTraffic, required cancellationToken}) async =>
              opens++ == 0 ? old : fresh,
        );
        final events = <ConversationEvent>[];
        conversation.listen((event) {
          events.add(event);
          if (event case Transcribed(
            action: ElicitationRequestedAction(),
          ) when !replacing) {
            replacing = true;
            conversation.clear();
          }
        });
        conversation.start();
        async.flushMicrotasks();
        final oldToken = CancellationToken();
        Map<String, Object?>? oldAnswer, freshAnswer;
        old.elicitations
            .handler(_form(), oldToken)
            .then((answer) => oldAnswer = answer);
        async.flushMicrotasks();
        expect(oldAnswer, {'action': 'cancel'});
        fresh.elicitations
            .handler(_form('Fresh'), CancellationToken())
            .then((answer) => freshAnswer = answer);
        async.flushMicrotasks();
        final id = _actions(
          events,
        ).whereType<ElicitationRequestedAction>().last.elicitation.id;
        expect(
          id,
          isNot(
            _actions(
              events,
            ).whereType<ElicitationRequestedAction>().first.elicitation.id,
          ),
        );
        oldToken.cancel();
        async.flushMicrotasks();
        expect(conversation.elicitationRequest(id)!.wait.message, 'Fresh');
        conversation.answer(id, const DeclineReply());
        async.flushMicrotasks();
        expect(freshAnswer, {'action': 'decline'});
        conversation.close();
        async.flushMicrotasks();
        expect((old.closes, fresh.closes), (1, 1));
      });
    });

    test(
      'mixed permission and form release queued work only after both settle',
      () {
        fakeAsync((async) {
          final s = Scripted();
          s.conversation.start();
          async.flushMicrotasks();
          s.session.ask();
          final token = CancellationToken();
          s.session.elicitations.handler(_form(), token);
          async.flushMicrotasks();
          s.conversation.send('queued');
          async.flushMicrotasks();
          final permission = _actions(
            s.events,
          ).whereType<PermissionRequestedAction>().single;
          s.conversation.choose(permission.wait.id, 'allow');
          async.elapse(const Duration(seconds: 2));
          expect(s.session.turns, isEmpty);
          token.cancel();
          async.elapse(const Duration(seconds: 2));
          expect(s.session.turns.single.text, 'queued');
          expect(
            _actions(
              s.events,
            ).whereType<ElicitationSettledAction>().single.answer,
            isA<ElicitationWithdrawn>(),
          );
          s.session.turns.single.answer();
          async.flushMicrotasks();
          s.conversation.close();
          async.flushMicrotasks();
        });
      },
    );

    test(
      'close reentered from request settles wire cancel and rejects new work',
      () {
        fakeAsync((async) {
          final s = Scripted();
          s.conversation.listen((event) {
            if (event case Transcribed(action: ElicitationRequestedAction())) {
              s.conversation.close();
            }
          });
          s.conversation.start();
          async.flushMicrotasks();
          Map<String, Object?>? answer;
          s.session.elicitations
              .handler(_form(), CancellationToken())
              .then((value) => answer = value);
          async.flushMicrotasks();
          expect(answer, {'action': 'cancel'});
          expect(s.session.closes, 1);
          expect(s.conversation.send('late'), isFalse);
        });
      },
    );
  });
}
