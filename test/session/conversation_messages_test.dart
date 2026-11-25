// Messages between agents in a conversation, as the original's
// conversation.ts delivers and tells them: a turn of the recipient's,
// wrapped with its sender; steered into a running turn on an agent that
// steers, held for the calls a steer cuts and for the person's answer; a
// steer refused or answered with the agent's own turn goes as the next
// turn, the sender told so; and the record writes it once, with its sender.
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

const parser = MessageFrom('parser', runtime: 'codex', reachable: true);

/// The prompts a record was given, with their sender and the turn they
/// went into.
final class _Prompts implements Recording {
  final prompts = <({String prompt, String? into, MessageFrom? from})>[];

  @override
  void sent(
    String turnId,
    String prompt,
    num images,
    List<Map<String, Object?>> links,
    num at, {
    List<Map<String, Object?>> resources = const [],
    String? into,
    MessageFrom? from,
  }) => prompts.add((prompt: prompt, into: into, from: from));

  @override
  Future<void> flushed() async {}

  @override
  void noSuchMethod(Invocation invocation) {}
}

final class _Rig {
  _Rig(FakeAsync async, {bool steering = true, bool cuts = false}) {
    conversation = Conversation(({
      required onTraffic,
      required cancellationToken,
    }) {
      session = ScriptedSession()
        ..steering = steering
        ..cutsSteeringCalls = cuts;
      return Future.value(session);
    }, recording: record);
    conversation.listen(events.add);
    conversation.start();
    async.flushMicrotasks();
  }
  late ScriptedSession session;
  late final Conversation conversation;
  final record = _Prompts();
  final events = <ConversationEvent>[];
  Iterable<Queued> get queued => events.whereType<Queued>();
  Iterable<PromptAction> get prompts => events
      .whereType<Transcribed>()
      .map((e) => e.action)
      .whereType<PromptAction>();
}

void main() {
  testerMessageBoundaryTests();
  test('a message delivered while idle is a turn of its own, wrapped with '
      'its sender, recorded once with it', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      expect(
        rig.conversation.deliver(parser, 'Two tests fail.'),
        Delivery.sent,
      );
      async.flushMicrotasks();
      expect(
        rig.session.turns.single.text,
        wrapMessage(parser, 'Two tests fail.'),
      );
      final prompt = rig.prompts.single;
      expect(prompt.text, 'Two tests fail.');
      expect(prompt.from, parser);
      expect(rig.record.prompts.single.from, parser);
      expect(rig.record.prompts.single.into, isNull);
    });
  });

  test('a message delivered behind a running turn waits as the next turn, '
      'its sender on its row', () {
    fakeAsync((async) {
      final rig = _Rig(async, steering: false);
      rig.conversation.send('running');
      async.flushMicrotasks();
      expect(rig.conversation.deliver(parser, 'after you'), Delivery.queued);
      expect(rig.queued.last.from, parser);
      expect(rig.conversation.queuedFrom, [parser]);
      rig.session.turns.first.answer();
      async.elapse(const Duration(seconds: 5));
      expect(rig.session.turns.last.text, wrapMessage(parser, 'after you'));
      expect(rig.prompts.last.from, parser);
    });
  });

  test('a message told into a running turn of an agent that steers goes in '
      'at once', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      rig.conversation.send('running');
      async.flushMicrotasks();
      expect(rig.conversation.tell(parser, 'look at x'), Delivery.sent);
      async.flushMicrotasks();
      final steer = rig.session.steered.single;
      expect(steer.text, wrapMessage(parser, 'look at x'));
      steer.answer();
      async.flushMicrotasks();
      final prompt = rig.prompts.last;
      expect(prompt.from, parser);
      expect(prompt.into, rig.prompts.first.turnId);
      final recorded = rig.record.prompts.last;
      expect(recorded.from, parser);
      expect(recorded.into, prompt.into);
      expect(rig.record.prompts.where((r) => r.from == parser), hasLength(1));
    });
  });

  test('on an agent that steers none, a told message is delivered', () {
    fakeAsync((async) {
      final rig = _Rig(async, steering: false);
      rig.conversation.send('running');
      async.flushMicrotasks();
      expect(rig.conversation.tell(parser, 'later'), Delivery.queued);
      expect(rig.session.steered, isEmpty);
    });
  });

  test('a message is held for the calls a steer would cut, then goes in', () {
    fakeAsync((async) {
      final rig = _Rig(async, cuts: true);
      rig.conversation.send('running');
      async.flushMicrotasks();
      rig.session.say({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'c1',
        'title': 'c1',
        'status': 'in_progress',
      });
      async.flushMicrotasks();
      expect(rig.conversation.tell(parser, 'held'), Delivery.sent);
      async.flushMicrotasks();
      expect(rig.session.steered, isEmpty);
      final held = rig.queued.last;
      expect((held.afterCalls, held.from), (true, parser));
      expect(rig.conversation.queuedFrom, [parser]);
      rig.session.say({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'c1',
        'status': 'completed',
      });
      async.flushMicrotasks();
      expect(rig.session.steered.single.text, wrapMessage(parser, 'held'));
      expect(rig.conversation.queuedFrom, isEmpty);
    });
  });

  test(
    "a message is held for the person's answer, then goes into the turn",
    () {
      fakeAsync((async) {
        final rig = _Rig(async);
        rig.conversation.send('running');
        async.flushMicrotasks();
        rig.session.ask().ignore();
        async.flushMicrotasks();
        expect(
          rig.conversation.tell(parser, 'after the answer'),
          Delivery.queued,
        );
        final held = rig.queued.last;
        expect((held.afterAnswer, held.from), (true, parser));
        expect(rig.session.steered, isEmpty);
        final asked = rig.events
            .whereType<Transcribed>()
            .map((e) => e.action)
            .whereType<PermissionRequestedAction>()
            .single;
        rig.conversation.choose(asked.wait.id, 'allow');
        async.flushMicrotasks();
        expect(
          rig.session.steered.single.text,
          wrapMessage(parser, 'after the answer'),
        );
      });
    },
  );

  test('a steer refused goes as the next turn, and the sender is told it '
      'was queued', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      rig.conversation.send('running');
      async.flushMicrotasks();
      var queued = 0;
      rig.conversation.tell(parser, 'refused', () => queued++);
      async.flushMicrotasks();
      rig.session.steered.single.answer(SteerOutcome.refused);
      async.flushMicrotasks();
      expect(queued, 1);
      expect(rig.queued.last.from, parser);
      rig.session.turns.first.answer();
      async.elapse(const Duration(seconds: 5));
      expect(rig.session.turns.last.text, wrapMessage(parser, 'refused'));
      expect(rig.prompts.last.from, parser);
      expect(rig.record.prompts.where((r) => r.from == parser), hasLength(1));
    });
  });

  test("a steer the agent starts its own turn with is cancelled, and the "
      'message goes next', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      rig.conversation.send('running');
      async.flushMicrotasks();
      var queued = 0;
      rig.conversation.tell(parser, 'mine', () => queued++);
      async.flushMicrotasks();
      rig.session.steered.single.answer(SteerOutcome.startedNewTurn);
      async.flushMicrotasks();
      expect(rig.session.cancels, greaterThan(0));
      expect(queued, 1);
      final self = rig.events
          .whereType<Transcribed>()
          .map((e) => e.action)
          .whereType<SelfStartedAction>()
          .single;
      expect(self.from, parser);
      rig.session.turns.first.answer();
      async.elapse(const Duration(seconds: 5));
      expect(rig.session.turns.last.text, wrapMessage(parser, 'mine'));
    });
  });

  test('a turn that ends while a message waits for its calls never takes '
      'it: it goes as the next turn, the sender told, recorded once', () {
    fakeAsync((async) {
      final rig = _Rig(async, cuts: true);
      rig.conversation.send('running');
      async.flushMicrotasks();
      rig.session.say({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'c1',
        'title': 'c1',
        'status': 'in_progress',
      });
      async.flushMicrotasks();
      var queued = 0;
      expect(
        rig.conversation.tell(parser, 'on the way', () => queued++),
        Delivery.sent,
      );
      async.flushMicrotasks();
      expect(rig.session.steered, isEmpty);
      rig.session.turns.first.answer();
      async.elapse(const Duration(seconds: 5));
      expect(rig.session.steered, isEmpty);
      expect(queued, 1);
      expect(rig.session.turns.last.text, wrapMessage(parser, 'on the way'));
      expect(rig.prompts.last.from, parser);
      expect(rig.prompts.last.into, isNull);
      expect(rig.record.prompts.where((r) => r.from == parser), hasLength(1));
    });
  });

  test('a clear lets go of the messages held for a session, and a steer of '
      'the old one landing late changes nothing in the new', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      rig.conversation.send('running');
      async.flushMicrotasks();
      rig.session.admitSteers = false;
      rig.conversation.tell(parser, 'first');
      async.flushMicrotasks();
      // Behind the first steer, which the agent has not answered.
      rig.conversation.tell(parser, 'second');
      async.flushMicrotasks();
      expect(rig.conversation.queuedFrom, [parser]);
      final old = rig.session;
      List<MessageFrom>? atClear;
      rig.conversation.listen((event) {
        if (event is Cleared) atClear = rig.conversation.queuedFrom;
      });
      rig.conversation.clear().ignore();
      async.flushMicrotasks();
      expect(atClear, isEmpty);
      expect(rig.conversation.queuedFrom, isEmpty);
      final before = rig.prompts.length;
      old.steered.first.answer();
      async.elapse(const Duration(seconds: 5));
      expect(rig.prompts.length, before);
      expect(rig.conversation.queuedFrom, isEmpty);
    });
  });

  test("Esc takes back the person's queued prompts, never another's "
      'message', () {
    fakeAsync((async) {
      final rig = _Rig(async, steering: false);
      rig.conversation.send('running');
      async.flushMicrotasks();
      rig.conversation.send('mine');
      rig.conversation.deliver(parser, 'theirs');
      rig.conversation.interrupt();
      async.flushMicrotasks();
      expect(
        [
          for (final p in rig.events.whereType<QueueWithdrawn>().single.prompts)
            p.text,
        ],
        ['mine'],
      );
      expect(rig.conversation.queuedFrom, [parser]);
    });
  });

  test('before the session is up, and once closing, a message reaches no '
      'one', () {
    fakeAsync((async) {
      final down = Conversation(
        ({required onTraffic, required cancellationToken}) async =>
            ScriptedSession(),
      );
      expect(down.deliver(parser, 'x'), isNull);
      expect(down.tell(parser, 'x'), isNull);
      final rig = _Rig(async);
      rig.conversation.close();
      async.flushMicrotasks();
      expect(rig.conversation.deliver(parser, 'x'), isNull);
      expect(rig.conversation.tell(parser, 'x'), isNull);
    });
  });
}

void testerMessageBoundaryTests() {
  group('tester: original message steering boundaries', () {
    test(
      'two messages wait only for calls open when told and retain their order',
      () {
        fakeAsync((async) {
          final rig = _Rig(async, cuts: true);
          rig.conversation.send('running');
          async.flushMicrotasks();
          rig.session.say({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'a',
            'title': 'a',
            'status': 'in_progress',
          });
          async.flushMicrotasks();
          rig.conversation.tell(parser, 'first');
          rig.conversation.tell(parser, 'second');
          async.flushMicrotasks();
          expect(rig.queued.map((event) => event.text), ['first', 'second']);
          expect(rig.queued.every((event) => event.afterCalls), isTrue);
          rig.session.say({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'b',
            'title': 'b',
            'status': 'in_progress',
          });
          rig.session.say({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'a',
            'status': 'completed',
          });
          async.flushMicrotasks();
          expect(rig.session.steered.single.text, wrapMessage(parser, 'first'));
          rig.session.steered.first.answer();
          async.flushMicrotasks();
          expect(rig.session.steered.last.text, wrapMessage(parser, 'second'));
          rig.session.steered.last.answer();
          async.flushMicrotasks();
          expect(
            rig.record.prompts
                .where((entry) => entry.from == parser)
                .map((entry) => entry.prompt),
            [wrapMessage(parser, 'first'), wrapMessage(parser, 'second')],
          );
          expect(
            rig.prompts
                .where((entry) => entry.from == parser)
                .every((entry) => entry.into == rig.prompts.first.turnId),
            isTrue,
          );
          rig.conversation.close();
          async.flushMicrotasks();
        });
      },
    );

    test(
      'Esc releases an answer-held message as a separate turn without restoring it',
      () {
        fakeAsync((async) {
          final rig = _Rig(async);
          rig.conversation.send('running');
          async.flushMicrotasks();
          final token = CancellationToken();
          rig.session.ask(token: token).ignore();
          rig.session.onCancel = () {
            token.cancel();
            rig.session.turns.first.answer(const TurnAnswered('cancelled'));
          };
          async.flushMicrotasks();
          expect(
            rig.conversation.tell(parser, 'after interruption'),
            Delivery.queued,
          );
          rig.conversation.interrupt();
          async.elapse(const Duration(seconds: 5));
          expect(rig.session.steered, isEmpty);
          expect(
            rig.session.turns.last.text,
            wrapMessage(parser, 'after interruption'),
          );
          expect(rig.prompts.last.into, isNull);
          expect(rig.queued.last.afterAnswer, isFalse);
          expect(
            rig.events
                .whereType<QueueWithdrawn>()
                .expand((event) => event.prompts)
                .where((prompt) => prompt.from != null),
            isEmpty,
          );
          expect(
            rig.record.prompts.where((entry) => entry.from == parser),
            hasLength(1),
          );
          rig.conversation.close();
          async.flushMicrotasks();
        });
      },
    );

    test(
      'late steer outcome after close never requeues or records a message',
      () {
        fakeAsync((async) {
          final rig = _Rig(async);
          rig.conversation.send('running');
          async.flushMicrotasks();
          rig.session.admitSteers = false;
          var queued = 0;
          rig.conversation.tell(parser, 'retired', () => queued++);
          async.flushMicrotasks();
          final pending = rig.session.steered.single;
          rig.conversation.close();
          async.flushMicrotasks();
          pending.answer(SteerOutcome.refused);
          async.elapse(const Duration(seconds: 5));
          expect(queued, 0);
          expect(
            rig.record.prompts.where((entry) => entry.from == parser),
            isEmpty,
          );
          expect(rig.conversation.queuedFrom, isEmpty);
        });
      },
    );
  });
}
