// Plans through the conversation over scripted sessions: ownership across a
// clear, where the old session's withdrawal comes late.
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/plans.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/plan_asks.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

/// Has [session]'s agent announce call [id], then put a plan out of it.
CancellationToken ask(
  FakeAsync async,
  ScriptedSession session,
  String id,
  List<Map<String, Object?>> answers,
) {
  session.say({
    'sessionUpdate': 'tool_call',
    'toolCallId': id,
    'title': 'Plan',
    'kind': 'switch_mode',
    'status': 'pending',
  });
  final token = CancellationToken();
  session.plans
      .handler(
        PlanRequest(
          PlanAgent.cursor,
          toolCallId: id,
          plan: '# P',
          todos: const [],
        ),
        token,
      )
      .then(answers.add);
  async.flushMicrotasks();
  return token;
}

void main() {
  test("an old session's late withdrawal never settles the new session's "
      'plan', () {
    fakeAsync((async) {
      var opens = 0;
      final sessions = [ScriptedSession(), ScriptedSession()];
      final events = <ConversationEvent>[];
      final conversation =
          Conversation(
              ({required onTraffic, required cancellationToken}) =>
                  Future.value(sessions[opens++]),
            )
            ..listen(events.add)
            ..start();
      async.flushMicrotasks();
      final oldAnswers = <Map<String, Object?>>[],
          newAnswers = <Map<String, Object?>>[];
      conversation.send('first');
      async.flushMicrotasks();
      final oldToken = ask(async, sessions[0], 'c1', oldAnswers);
      conversation.clear();
      async.flushMicrotasks();
      conversation.send('second');
      async.flushMicrotasks();
      ask(async, sessions[1], 'c1', newAnswers);
      List<PlanWait> asked() => [
        for (final event in events)
          if (event case Transcribed(action: PlanRequestedAction(:final plan)))
            plan,
      ];
      List<String> settled() => [
        for (final event in events)
          if (event case Transcribed(action: PlanSettledAction(:final id))) id,
      ];
      final fresh = asked().last;
      // The old session's withdrawal arrives late.
      oldToken.cancel();
      async.flushMicrotasks();
      expect(settled(), isNot(contains(fresh.id)));
      expect(newAnswers, isEmpty);
      // The new plan is still the person's to answer.
      conversation.answerPlan(fresh.id, const PlanAccepted());
      async.flushMicrotasks();
      expect(newAnswers, [
        {'outcome': 'accepted'},
      ]);
      expect(oldAnswers, [
        {'outcome': 'cancelled'},
      ]);
      conversation.close();
      async.flushMicrotasks();
    });
  });

  test('plans of two sessions never share an id', () {
    final ids = <String>{};
    for (final bridge in [PlanBridge(), PlanBridge()]) {
      bridge.subscribe((pending) => ids.add(pending.wait.id));
      bridge.handler(
        const PlanRequest(PlanAgent.grok, sessionId: 's', toolCallId: 'c'),
        CancellationToken(),
      );
    }
    expect(ids, hasLength(2));
  });

  test("a resumed past's plan never stands for a fresh one", () {
    fakeAsync((async) {
      // The id a fresh bridge in a new process would once have given.
      final session = ScriptedSession()
        ..prepared = PreparedHistory(
          rawHasPast: true,
          omitted: false,
          actions: const [
            PromptAction('history-1', 'before', 0),
            PlanRequestedAction(
              'history-1',
              PlanWait('plan-1', PlanAgent.grok, toolCallId: 'c0'),
            ),
            PlanSettledAction('history-1', 'plan-1', PlanAccepted()),
          ],
        );
      final events = <ConversationEvent>[];
      final conversation =
          Conversation(
              ({required onTraffic, required cancellationToken}) =>
                  Future.value(session),
            )
            ..listen(events.add)
            ..start();
      async.flushMicrotasks();
      conversation.send('again');
      async.flushMicrotasks();
      final answers = <Map<String, Object?>>[];
      ask(async, session, 'c1', answers);
      final fresh = [
        for (final event in events)
          if (event case Transcribed(action: PlanRequestedAction(:final plan)))
            plan,
      ].single;
      expect(fresh.id, isNot('plan-1'));
      conversation.answerPlan(fresh.id, const PlanAccepted());
      async.flushMicrotasks();
      expect(answers, [
        {'outcome': 'accepted'},
      ]);
      conversation.close();
      async.flushMicrotasks();
    });
  });
}
