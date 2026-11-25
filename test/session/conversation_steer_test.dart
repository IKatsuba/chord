import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';
import 'recording_conversation_test.dart' show Spy;

final class _Rig {
  _Rig(
    FakeAsync async, {
    bool steering = true,
    bool cuts = false,
    Recording? recording,
  }) {
    conversation = Conversation(({
      required onTraffic,
      required cancellationToken,
    }) {
      final session = ScriptedSession()
        ..steering = steering
        ..cutsSteeringCalls = cuts;
      sessions.add(session);
      return Future.value(session);
    }, recording: recording);
    conversation.listen(events.add);
    conversation.start();
    async.flushMicrotasks();
  }
  final sessions = <ScriptedSession>[];
  ScriptedSession get session => sessions.last;
  late final Conversation conversation;
  final events = <ConversationEvent>[];
  Iterable<Queued> get queued => events.whereType<Queued>();
  Iterable<TranscriptAction> get actions =>
      events.whereType<Transcribed>().map((e) => e.action);
  void running() => conversation.send('running');
  void call(String id, {String status = 'in_progress'}) => session.say({
    'sessionUpdate': 'tool_call',
    'toolCallId': id,
    'title': id,
    'status': status,
  });
  void endCall(String id) => session.say({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': id,
    'status': 'completed',
  });
  void close(FakeAsync async) {
    conversation.close();
    async.flushMicrotasks();
  }
}

void main() {
  _testerConversationSteeringLifetimes();
  test(
    'steerQueued preserves original readiness, capability and admitted-turn gates',
    () {
      fakeAsync((async) {
        final down = Conversation(
          ({required onTraffic, required cancellationToken}) async =>
              ScriptedSession(),
        );
        expect(down.steerQueued(), isNull);
        down.close();
        async.flushMicrotasks();
        final rig = _Rig(async, steering: false);
        expect(rig.conversation.steerQueued(), 'none');
        rig.running();
        rig.conversation.send('queued');
        expect(rig.conversation.steerQueued(), 'unsteerable');
        expect(rig.session.steered, isEmpty);
        expect(rig.queued.where((row) => row.taken), isEmpty);
        rig.conversation.interrupt();
        expect(
          rig.events.whereType<QueueWithdrawn>().single.prompts.single.text,
          'queued',
        );
        rig.close(async);
        expect(rig.conversation.steerQueued(), isNull);
        final unsent = _Rig(async);
        unsent.session.admitPrompts = false;
        unsent.running();
        unsent.conversation.send('queued');
        expect(unsent.conversation.steerQueued(), 'none');
        expect(unsent.session.steered, isEmpty);
        unsent.close(async);
      });
    },
  );

  test(
    'oldest identity, shell payload and mentions survive accepted-only echo and recording',
    () {
      fakeAsync((async) {
        final spy = Spy([]), rig = _Rig(async, recording: null);
        rig.close(async);
        final recorded = _Rig(async, recording: spy);
        recorded.running();
        recorded.session.admitSteers = false;
        final paths = ['notes.txt'];
        recorded.conversation.send(
          'typed @notes.txt',
          '<bash-input>echo held</bash-input>\nheld context\n\ntyped @notes.txt',
          paths,
        );
        paths.add('late');
        recorded.conversation.send('second');
        expect(recorded.conversation.steerQueued(), 'sent');
        expect(recorded.queued.last.taken, isTrue);
        async.flushMicrotasks();
        final request = recorded.session.steered.single;
        expect(request.mentions, ['notes.txt']);
        expect(request.text, contains('held context'));
        expect(recorded.actions.whereType<PromptAction>(), hasLength(1));
        expect(spy.prompts, hasLength(1));
        async.elapse(const Duration(milliseconds: 499));
        expect(recorded.queued.where((row) => row.steering), isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(recorded.queued.last.steering, isTrue);
        expect(request.admitted, isFalse);
        request.admit(
          links: [
            {
              'type': 'resource_link',
              'uri': 'file:///project/notes.txt',
              'futureFact': 1.5,
            },
          ],
        );
        expect(spy.prompts, hasLength(1));
        request.answer();
        async.flushMicrotasks();
        final accepted = recorded.actions.whereType<PromptAction>().last;
        expect(accepted.turnId, request.turnId);
        expect(accepted.text, 'typed @notes.txt');
        expect(accepted.into, 'turn-1');
        expect(spy.prompts.last['into'], 'turn-1');
        expect(spy.prompts.last['prompt'], request.text);
        expect((spy.prompts.last['links'] as List).single['futureFact'], 1.5);
        expect(recorded.session.turns, hasLength(1));
        recorded.close(async);
      });
    },
  );

  for (final cuts in [false, true]) {
    test('call barrier captures arrival IDs only, cuts=$cuts', () {
      fakeAsync((async) {
        final rig = _Rig(async, cuts: cuts);
        rig.running();
        rig.call('first');
        rig.conversation.send('queued');
        expect(rig.conversation.steerQueued(), 'sent');
        rig.call('later');
        async.flushMicrotasks();
        expect(rig.session.steered, hasLength(cuts ? 0 : 1));
        if (cuts) {
          expect(rig.queued.last.afterCalls, isTrue);
          rig.endCall('first');
          async.flushMicrotasks();
          expect(rig.session.steered, hasLength(1));
          expect(rig.queued.last.steering, isTrue);
        }
        rig.session.steered.single.answer();
        async.flushMicrotasks();
        expect(rig.actions.whereType<PromptAction>().last.into, 'turn-1');
        rig.close(async);
      });
    });
  }

  test(
    'permission waits take priority over captured open calls and release once',
    () {
      fakeAsync((async) {
        final rig = _Rig(async, cuts: true);
        rig.running();
        rig.call('first');
        rig.session.ask().ignore();
        async.flushMicrotasks();
        final wait = rig.actions
            .whereType<PermissionRequestedAction>()
            .single
            .wait;
        rig.conversation.send('queued');
        rig.conversation.steerQueued();
        async.flushMicrotasks();
        expect(rig.queued.last.afterAnswer, isTrue);
        expect(rig.session.steered, isEmpty);
        rig.endCall('first');
        rig.call('newer');
        async.flushMicrotasks();
        expect(rig.session.steered, isEmpty);
        rig.conversation.choose(wait.id, 'allow');
        async.flushMicrotasks();
        expect(rig.session.steered, hasLength(1));
        expect(rig.queued.last.steering, isTrue);
        rig.session.steered.single.answer();
        async.flushMicrotasks();
        rig.close(async);
      });
    },
  );

  for (final question in [false, true]) {
    test(
      'Esc restores explicit ${question ? 'question' : 'call'} holds in original queue order',
      () {
        fakeAsync((async) {
          final rig = _Rig(async, cuts: true);
          rig.running();
          if (question) {
            rig.session.ask().ignore();
          } else {
            rig.call('open');
          }
          async.flushMicrotasks();
          rig.conversation.send('oldest', 'held shell payload', ['a']);
          rig.conversation.send('later');
          rig.conversation.steerQueued();
          async.flushMicrotasks();
          expect(rig.session.steered, isEmpty);
          rig.conversation.interrupt();
          async.flushMicrotasks();
          final withdrawn = rig.events
              .whereType<QueueWithdrawn>()
              .single
              .prompts;
          expect(withdrawn.map((row) => row.text), ['oldest', 'later']);
          expect(withdrawn.first.prompt, 'held shell payload');
          expect(withdrawn.first.mentions, ['a']);
          rig.endCall('open');
          for (final permission
              in rig.actions.whereType<PermissionRequestedAction>().toList()) {
            rig.conversation.reject(permission.wait.id);
          }
          rig.session.turns.single.answer(const TurnAnswered('cancelled'));
          async.elapse(const Duration(seconds: 2));
          expect(rig.session.steered, isEmpty);
          expect(rig.session.turns, hasLength(1));
          rig.close(async);
        });
      },
    );
  }

  for (final delay in [100, 600]) {
    test(
      'Esc leaves dispatched resolver taken before and after pending label, delay=$delay',
      () {
        fakeAsync((async) {
          final rig = _Rig(async);
          rig.running();
          rig.session.admitSteers = false;
          rig.conversation.send('dispatched', 'payload @a', ['a']);
          rig.conversation.send('unsent');
          rig.conversation.steerQueued();
          async.flushMicrotasks();
          final request = rig.session.steered.single;
          async.elapse(Duration(milliseconds: delay));
          rig.conversation.interrupt();
          expect(
            rig.events.whereType<QueueWithdrawn>().single.prompts.single.text,
            'unsent',
          );
          rig.session.turns.single.answer(const TurnAnswered('cancelled'));
          async.flushMicrotasks();
          request.admit();
          request.answer();
          async.flushMicrotasks();
          final accepted = rig.actions
              .whereType<PromptAction>()
              .where((a) => a.text == 'dispatched')
              .toList();
          expect(accepted, hasLength(1));
          expect(accepted.single.into, 'turn-1');
          expect(rig.session.turns, hasLength(1));
          rig.close(async);
        });
      },
    );
  }

  test('an explicit call hold whose target ends goes as one later prompt', () {
    fakeAsync((async) {
      final rig = _Rig(async, cuts: true);
      rig.running();
      rig.call('open');
      rig.conversation.send('queued');
      rig.conversation.steerQueued();
      async.flushMicrotasks();
      rig.session.turns.first.answer();
      async.flushMicrotasks();
      expect(rig.session.steered, isEmpty);
      expect(rig.session.turns.map((t) => t.text), ['running', 'queued']);
      expect(
        rig.actions.whereType<PromptAction>().where((a) => a.text == 'queued'),
        hasLength(1),
      );
      rig.close(async);
    });
  });

  test(
    'withdrawn permission wakes a steer but cannot extend captured call set',
    () {
      fakeAsync((async) {
        final rig = _Rig(async, cuts: true);
        rig.running();
        final token = CancellationToken();
        rig.session.ask(token: token).ignore();
        async.flushMicrotasks();
        rig.conversation.send('queued');
        rig.conversation.steerQueued();
        async.flushMicrotasks();
        expect(rig.session.steered, isEmpty);
        rig.call('opened-after-arrival');
        token.cancel();
        async.flushMicrotasks();
        expect(rig.session.steered, hasLength(1));
        rig.session.steered.single.answer();
        async.flushMicrotasks();
        rig.close(async);
      });
    },
  );

  test(
    'serialization starts each 500ms clock at its own Session.steer call',
    () {
      fakeAsync((async) {
        final rig = _Rig(async);
        rig.running();
        rig.conversation.send('first');
        rig.conversation.send('second');
        rig.conversation.steerQueued();
        rig.conversation.steerQueued();
        async.flushMicrotasks();
        expect(rig.session.steered, hasLength(1));
        expect(rig.queued.where((row) => row.taken), hasLength(2));
        async.elapse(const Duration(milliseconds: 600));
        expect(rig.queued.where((row) => row.steering).map((e) => e.text), [
          'first',
        ]);
        rig.session.steered.first.answer();
        async.flushMicrotasks();
        expect(rig.session.steered, hasLength(2));
        async.elapse(const Duration(milliseconds: 499));
        expect(rig.queued.where((row) => row.steering), hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(rig.queued.last.text, 'second');
        expect(rig.queued.last.steering, isTrue);
        rig.session.steered.last.answer();
        async.flushMicrotasks();
        expect(
          rig.actions
              .whereType<PromptAction>()
              .where((a) => a.into != null)
              .map((a) => a.text),
          ['first', 'second'],
        );
        rig.close(async);
      });
    },
  );

  test(
    'Esc keeps serialized dispatch taken and refusal restores its original place',
    () {
      fakeAsync((async) {
        final rig = _Rig(async);
        rig.running();
        for (final text in ['first', 'second', 'unsent']) {
          rig.conversation.send(text);
        }
        rig.conversation.steerQueued();
        rig.conversation.steerQueued();
        async.flushMicrotasks();
        rig.conversation.interrupt();
        expect(
          rig.events.whereType<QueueWithdrawn>().single.prompts.map(
            (p) => p.text,
          ),
          ['unsent'],
        );
        rig.session.steered.single.answer(SteerOutcome.refused);
        async.flushMicrotasks();
        expect(rig.session.steered, hasLength(1));
        expect(rig.queued.where((e) => e.refused).map((e) => e.text), [
          'first',
          'second',
        ]);
        rig.session.turns.first.answer(const TurnAnswered('cancelled'));
        async.elapse(const Duration(seconds: 1));
        expect(rig.session.turns.map((t) => t.text), ['running', 'first']);
        rig.session.turns.last.answer();
        async.elapse(const Duration(seconds: 1));
        expect(rig.session.turns.map((t) => t.text), [
          'running',
          'first',
          'second',
        ]);
        rig.close(async);
      });
    },
  );

  for (final accepted in [false, true]) {
    test(
      'late ${accepted ? 'injection' : 'refusal'} blocks advance and delivers exactly once',
      () {
        fakeAsync((async) {
          final rig = _Rig(async);
          rig.running();
          rig.conversation.send('first');
          rig.conversation.send('second');
          rig.conversation.steerQueued();
          async.flushMicrotasks();
          rig.session.turns.first.answer();
          async.elapse(const Duration(seconds: 2));
          expect(rig.session.turns, hasLength(1));
          expect(rig.conversation.steerQueued(), 'none');
          rig.session.steered.single.answer(
            accepted ? SteerOutcome.injected : SteerOutcome.refused,
          );
          async.flushMicrotasks();
          expect(rig.queued.where((row) => row.refused), isEmpty);
          expect(
            rig.session.turns.map((t) => t.text),
            accepted ? ['running', 'second'] : ['running', 'first'],
          );
          if (!accepted) {
            rig.session.turns.last.answer();
            async.elapse(const Duration(seconds: 1));
            expect(rig.session.turns.map((t) => t.text), [
              'running',
              'first',
              'second',
            ]);
          }
          expect(
            rig.actions.whereType<PromptAction>().where(
              (a) => a.text == 'first',
            ),
            hasLength(1),
          );
          rig.close(async);
        });
      },
    );
  }

  test(
    'transport refusal restores queue position without echo or another steer into the sealed turn',
    () {
      fakeAsync((async) {
        final rig = _Rig(async);
        rig.running();
        rig.conversation.send('first');
        rig.conversation.send('second');
        rig.conversation.steerQueued();
        async.flushMicrotasks();
        rig.session.steered.single.fail(StateError('method refused'));
        async.flushMicrotasks();
        expect(rig.queued.last.text, 'first');
        expect(rig.queued.last.refused, isTrue);
        expect(rig.actions.whereType<PromptAction>(), hasLength(1));
        expect(rig.conversation.steerQueued(), 'none');
        rig.session.turns.first.answer();
        async.elapse(const Duration(seconds: 1));
        expect(rig.session.turns.map((t) => t.text), ['running', 'first']);
        rig.close(async);
      });
    },
  );

  test(
    'startedNewTurn cancels, keeps late work under its closure and waits for quiet',
    () {
      fakeAsync((async) {
        final spy = Spy([]), rig = _Rig(async);
        rig.close(async);
        final recorded = _Rig(async, recording: spy);
        recorded.running();
        recorded.conversation.send('first');
        recorded.conversation.steerQueued();
        async.flushMicrotasks();
        recorded.session.turns.first.answer();
        async.flushMicrotasks();
        recorded.session.steered.single.answer(SteerOutcome.startedNewTurn);
        async.flushMicrotasks();
        expect(recorded.session.cancels, 1);
        final own = recorded.actions
            .whereType<SelfStartedAction>()
            .single
            .turnId;
        expect(recorded.session.turns, hasLength(1));
        expect(spy.prompts, hasLength(1));
        recorded.session.chunk('self-started visible work');
        expect(recorded.actions.whereType<UpdateAction>().last.turnId, own);
        async.elapse(const Duration(milliseconds: 999));
        expect(recorded.session.turns, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(recorded.session.turns.map((t) => t.text), ['running', 'first']);
        expect(spy.prompts, hasLength(2));
        expect(spy.prompts.last.containsKey('into'), isFalse);
        expect(
          recorded.actions.whereType<PromptAction>().where(
            (a) => a.into != null,
          ),
          isEmpty,
        );
        recorded.close(async);
      });
    },
  );

  test(
    'self-start recovery reserves queue ownership before closure observers send',
    () {
      fakeAsync((async) {
        final rig = _Rig(async);
        rig.running();
        rig.conversation.send('first');
        rig.conversation.steerQueued();
        async.flushMicrotasks();
        rig.session.turns.first.answer();
        async.flushMicrotasks();
        String? own;
        rig.conversation.listen((event) {
          if (event case Transcribed(
            action: SelfStartedAction(:final turnId),
          )) {
            own = turnId;
            rig.conversation.send('observer');
          }
        });
        rig.session.steered.single.answer(SteerOutcome.startedNewTurn);
        async.flushMicrotasks();
        expect(rig.session.turns.map((t) => t.text), ['running']);
        rig.session.chunk('self-started late work');
        expect(rig.actions.whereType<UpdateAction>().last.turnId, own);
        async.elapse(const Duration(milliseconds: 999));
        expect(rig.session.turns, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(rig.session.turns.map((t) => t.text), ['running', 'first']);
        rig.session.turns.last.answer();
        async.elapse(const Duration(seconds: 1));
        expect(rig.session.turns.map((t) => t.text), [
          'running',
          'first',
          'observer',
        ]);
        rig.close(async);
      });
    },
  );

  test(
    'self-start recovery also owns idle before synchronous cancel observers send',
    () {
      fakeAsync((async) {
        final rig = _Rig(async);
        rig.running();
        rig.conversation.send('first');
        rig.conversation.steerQueued();
        async.flushMicrotasks();
        rig.session.turns.first.answer();
        async.flushMicrotasks();
        rig.session.onCancel = () => rig.conversation.send('observer');
        rig.session.steered.single.answer(SteerOutcome.startedNewTurn);
        async.flushMicrotasks();
        expect(rig.session.turns.map((t) => t.text), ['running']);
        final own = rig.actions.whereType<SelfStartedAction>().single.turnId;
        rig.session.chunk('late self-started work');
        expect(rig.actions.whereType<UpdateAction>().last.turnId, own);
        async.elapse(const Duration(seconds: 1));
        expect(rig.session.turns.map((t) => t.text), ['running', 'first']);
        rig.session.turns.last.answer();
        async.elapse(const Duration(seconds: 1));
        expect(rig.session.turns.map((t) => t.text), [
          'running',
          'first',
          'observer',
        ]);
        rig.session.onCancel = null;
        rig.close(async);
      });
    },
  );

  for (final replace in [false, true]) {
    test(
      'self-start closure observer ${replace ? 'swap' : 'close'} retires recovery without old echo or timers',
      () {
        fakeAsync((async) {
          final rig = _Rig(async);
          rig.running();
          rig.conversation.send('first');
          rig.conversation.steerQueued();
          async.flushMicrotasks();
          rig.session.turns.first.answer();
          async.flushMicrotasks();
          rig.conversation.listen((event) {
            if (event is Transcribed && event.action is SelfStartedAction) {
              if (replace) {
                rig.conversation.clear();
              } else {
                rig.conversation.close();
              }
            }
          });
          final old = rig.session;
          old.steered.single.answer(SteerOutcome.startedNewTurn);
          async.flushMicrotasks();
          final count = rig.events.length;
          old.chunk('retired recovery work');
          async.elapse(const Duration(seconds: 2));
          expect(rig.events.length, count);
          expect(old.turns, hasLength(1));
          expect(async.nonPeriodicTimerCount, 0);
          if (replace) {
            rig.running();
            expect(rig.session.turns, hasLength(1));
            rig.close(async);
          }
        });
      },
    );
  }

  for (final replace in [false, true]) {
    test(
      '${replace ? 'swap' : 'close'} suppresses pending timer, late outcome and held dispatch',
      () {
        fakeAsync((async) {
          final rig = _Rig(async);
          rig.running();
          rig.conversation.send('pending');
          rig.conversation.steerQueued();
          async.flushMicrotasks();
          final old = rig.session;
          if (replace) {
            rig.conversation.clear();
          } else {
            rig.conversation.close();
          }
          async.flushMicrotasks();
          final count = rig.events.length;
          old.steered.single.answer();
          // A swapped session closes once its turn is over or the settle
          // limit passes, as the original.
          async.elapse(const Duration(milliseconds: settleLimitMs + quietMs));
          expect(rig.events.length, count);
          expect(async.nonPeriodicTimerCount, 0);
          expect(old.closes, 1);
          if (replace) {
            rig.running();
            expect(rig.session.turns, hasLength(1));
            rig.close(async);
          }
        });
      },
    );
  }

  for (final replace in [false, true]) {
    test(
      '${replace ? 'swap' : 'close'} wakes and retires explicit call holds without dispatch',
      () {
        fakeAsync((async) {
          final rig = _Rig(async, cuts: true);
          rig.running();
          rig.call('open');
          rig.conversation.send('held');
          rig.conversation.steerQueued();
          async.flushMicrotasks();
          final old = rig.session;
          expect(old.steered, isEmpty);
          expect(rig.queued.last.afterCalls, isTrue);
          if (replace) {
            rig.conversation.clear();
          } else {
            rig.conversation.close();
          }
          async.flushMicrotasks();
          final count = rig.events.length;
          old.say({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'open',
            'status': 'completed',
          });
          async.elapse(const Duration(milliseconds: settleLimitMs + quietMs));
          expect(old.steered, isEmpty);
          expect(rig.events.length, count);
          expect(async.nonPeriodicTimerCount, 0);
          if (replace) rig.close(async);
        });
      },
    );
  }

  test(
    'serialized dispatch becomes withdrawable only when explicitly shown for a new question',
    () {
      fakeAsync((async) {
        final rig = _Rig(async);
        rig.running();
        rig.conversation.send('first');
        rig.conversation.send('second');
        rig.conversation.steerQueued();
        rig.conversation.steerQueued();
        async.flushMicrotasks();
        rig.session.ask().ignore();
        async.flushMicrotasks();
        rig.session.steered.single.answer();
        async.flushMicrotasks();
        expect(rig.queued.last.text, 'second');
        expect(rig.queued.last.afterAnswer, isTrue);
        rig.conversation.interrupt();
        async.flushMicrotasks();
        expect(
          rig.events.whereType<QueueWithdrawn>().single.prompts.single.text,
          'second',
        );
        expect(rig.session.steered, hasLength(1));
        rig.close(async);
      });
    },
  );

  test(
    'reentrant clear from taken event prevents old dispatch and accepted observer cannot record into new session',
    () {
      fakeAsync((async) {
        final spy = Spy([]), rig = _Rig(async, recording: null);
        rig.running();
        rig.conversation.send('queued');
        rig.conversation.listen((event) {
          if (event is Queued && event.taken) rig.conversation.clear();
        });
        final old = rig.session;
        rig.conversation.steerQueued();
        async.flushMicrotasks();
        expect(old.steered, isEmpty);
        rig.close(async);
        final recorded = _Rig(async, recording: spy);
        recorded.running();
        recorded.conversation.send('queued');
        recorded.conversation.listen((event) {
          if (event case Transcribed(
            action: PromptAction(into: final into),
          ) when into != null) {
            recorded.conversation.clear();
          }
        });
        recorded.conversation.steerQueued();
        async.flushMicrotasks();
        recorded.session.steered.single.answer();
        async.flushMicrotasks();
        expect(spy.prompts, hasLength(1));
        recorded.close(async);
      });
    },
  );
}

void _testerConversationSteeringLifetimes() {
  group('tester: independent conversation steering lifetimes', () {
    test(
      'matching session and turn ids retain independent replies and queue owners',
      () {
        fakeAsync((async) {
          final a = _Rig(async), b = _Rig(async);
          a.running();
          b.running();
          a.conversation.send('first personal');
          b.conversation.send('second personal');
          a.conversation.steerQueued();
          b.conversation.steerQueued();
          async.flushMicrotasks();
          expect(
            a.session.steered.single.turnId,
            b.session.steered.single.turnId,
          );
          async.elapse(const Duration(milliseconds: 500));
          a.conversation.interrupt();
          a.session.turns.first.answer(const TurnAnswered('cancelled'));
          b.session.steered.single.answer(SteerOutcome.refused);
          async.flushMicrotasks();
          a.session.steered.single.answer();
          async.flushMicrotasks();
          expect(
            a.actions
                .whereType<PromptAction>()
                .where((p) => p.into != null)
                .map((p) => p.text),
            ['first personal'],
          );
          expect(
            b.actions.whereType<PromptAction>().where((p) => p.into != null),
            isEmpty,
          );
          expect(
            b.queued.where((p) => p.refused).single.text,
            'second personal',
          );
          a.close(async);
          b.session.turns.first.answer();
          async.elapse(const Duration(seconds: 1));
          expect(b.session.turns.map((t) => t.text), [
            'running',
            'second personal',
          ]);
          b.close(async);
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'an hour-silent taken reply blocks queue advance and is retired on close',
      () {
        fakeAsync((async) {
          final spy = Spy([]), rig = _Rig(async, recording: spy);
          rig.running();
          rig.conversation.send('界 😀 é', 'held context\n界 😀 é', ['a']);
          rig.conversation.send('next');
          rig.conversation.steerQueued();
          async.flushMicrotasks();
          rig.session.turns.first.answer();
          async.elapse(const Duration(hours: 1));
          expect(rig.session.turns, hasLength(1));
          expect(rig.queued.where((p) => p.steering), hasLength(1));
          expect(spy.prompts, hasLength(1));
          final request = rig.session.steered.single;
          rig.close(async);
          final count = rig.events.length;
          request.answer();
          async.elapse(const Duration(hours: 1));
          expect(rig.events.length, count);
          expect(spy.prompts, hasLength(1));
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'recovery trailing chunks extend quiet only to the five-second cap',
      () {
        fakeAsync((async) {
          final spy = Spy([]), rig = _Rig(async, recording: spy);
          rig.running();
          rig.conversation.send('original place');
          rig.conversation.steerQueued();
          async.flushMicrotasks();
          rig.session.turns.first.answer();
          async.flushMicrotasks();
          rig.conversation.listen((event) {
            if (event is Transcribed && event.action is SelfStartedAction) {
              rig.conversation.send('observer tail');
            }
          });
          rig.session.steered.single.answer(SteerOutcome.startedNewTurn);
          async.flushMicrotasks();
          final own = rig.actions.whereType<SelfStartedAction>().single.turnId;
          for (var i = 0; i < 5; i++) {
            async.elapse(const Duration(milliseconds: 900));
            rig.session.chunk('late 界😀 é $i');
            expect(rig.actions.whereType<UpdateAction>().last.turnId, own);
            expect(rig.session.turns, hasLength(1));
            expect(spy.prompts, hasLength(1));
          }
          async.elapse(const Duration(milliseconds: 499));
          expect(rig.session.turns, hasLength(1));
          async.elapse(const Duration(milliseconds: 1));
          expect(rig.session.turns.map((t) => t.text), [
            'running',
            'original place',
          ]);
          expect(spy.prompts.last.containsKey('into'), isFalse);
          rig.session.turns.last.answer();
          async.elapse(const Duration(seconds: 1));
          expect(rig.session.turns.map((t) => t.text), [
            'running',
            'original place',
            'observer tail',
          ]);
          rig.close(async);
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'clear immediately before extended recovery quiet cannot replay into the replacement',
      () {
        fakeAsync((async) {
          final rig = _Rig(async);
          rig.running();
          rig.conversation.send('old personal');
          rig.conversation.steerQueued();
          async.flushMicrotasks();
          final old = rig.session;
          old.turns.first.answer();
          async.flushMicrotasks();
          old.steered.single.answer(SteerOutcome.startedNewTurn);
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 900));
          old.chunk('late work');
          async.elapse(const Duration(milliseconds: 999));
          expect(old.turns, hasLength(1));
          rig.conversation.clear();
          async.flushMicrotasks();
          final count = rig.events.length;
          old.chunk('retired tail');
          async.elapse(const Duration(seconds: 10));
          expect(rig.events.length, count);
          expect(async.nonPeriodicTimerCount, 0);
          rig.conversation.send('new personal');
          expect(rig.session.turns.map((t) => t.text), ['new personal']);
          expect(
            rig.actions.whereType<PromptAction>().where(
              (p) => p.text == 'old personal',
            ),
            isEmpty,
          );
          rig.close(async);
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );
  });
}
