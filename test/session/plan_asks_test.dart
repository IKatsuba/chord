// From the original's tests/session/plan_asks_test.ts.
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/plans.dart';
import 'package:chord/session/plan_asks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

void main() {
  test("the person's answer in each agent's words, a note only with keep; "
      'anything not theirs is cancelled', () {
    expect(planResponse(PlanAgent.cursor, const PlanAccepted()), {
      'outcome': 'accepted',
    });
    expect(planResponse(PlanAgent.cursor, const PlanKept('Keep it small.')), {
      'outcome': 'rejected',
      'reason': 'Keep it small.',
    });
    expect(planResponse(PlanAgent.cursor, const PlanKept()), {
      'outcome': 'rejected',
    });
    expect(planResponse(PlanAgent.grok, const PlanAccepted()), {
      'outcome': 'approved',
    });
    expect(planResponse(PlanAgent.grok, const PlanKept('More tests.')), {
      'outcome': 'revise',
      'feedback': 'More tests.',
    });
    expect(planResponse(PlanAgent.grok, const PlanLeft()), {
      'outcome': 'abandoned',
    });
    for (final agent in PlanAgent.values) {
      for (final answer in const [PlanCancelled(), PlanWithdrawn()]) {
        expect(planResponse(agent, answer), {'outcome': 'cancelled'});
      }
    }
    // cursor has no way out of planning but a no; its box never offers it.
    expect(planResponse(PlanAgent.cursor, const PlanLeft()), {
      'outcome': 'cancelled',
    });
  });

  group('the bridge answers cancelled for every answer that is not the '
      "person's", () {
    const request = PlanRequest(
      PlanAgent.cursor,
      toolCallId: 'c',
      plan: '# Route',
      todos: [],
    );

    test('a request that did not read, or nobody to ask', () async {
      final bridge = PlanBridge();
      expect(await bridge.handler(request, CancellationToken()), {
        'outcome': 'cancelled',
      });
      bridge.subscribe((_) => fail('nothing to show'));
      expect(await bridge.handler(null, CancellationToken()), {
        'outcome': 'cancelled',
      });
    });

    test(
      'a withdrawn request, and one waiting when the session closes',
      () async {
        final bridge = PlanBridge();
        final shown = <PendingPlan>[];
        bridge.subscribe(shown.add);
        final token = CancellationToken();
        final withdrawn = bridge.handler(request, token);
        final closed = bridge.handler(request, CancellationToken());
        expect(shown, hasLength(2));
        expect(shown.first.wait.id, isNot(shown.last.wait.id));
        token.cancel();
        expect(await withdrawn, {'outcome': 'cancelled'});
        expect(shown.first.withdrawn.isCancelled, isTrue);
        bridge.close();
        expect(await closed, {'outcome': 'cancelled'});
        // A late yes after the answer went changes nothing.
        shown.last.answer(const PlanAccepted());
        // Closed, it shows nothing more.
        expect(await bridge.handler(request, CancellationToken()), {
          'outcome': 'cancelled',
        });
      },
    );

    test("the person's answer goes once, in the agent's words", () async {
      final bridge = PlanBridge();
      final shown = <PendingPlan>[];
      bridge.subscribe(shown.add);
      final answer = bridge.handler(
        const PlanRequest(
          PlanAgent.grok,
          sessionId: 's',
          toolCallId: 'c',
          plan: '# Route',
        ),
        CancellationToken(),
      );
      final pending = shown.single;
      expect(
        (pending.sessionId, pending.wait.agent, pending.wait.plan),
        ('s', PlanAgent.grok, '# Route'),
      );
      pending.answer(const PlanKept('More tests.'));
      pending.answer(const PlanAccepted());
      expect(await answer, {'outcome': 'revise', 'feedback': 'More tests.'});
    });
  });

  group('tester: plan answer ordering', () {
    const request = PlanRequest(
      PlanAgent.grok,
      sessionId: 's',
      toolCallId: 'c',
    );
    test(
      'an explicit answer wins before cancellation and later answers',
      () async {
        final bridge = PlanBridge();
        addTearDown(bridge.close);
        final shown = <PendingPlan>[];
        bridge.subscribe(shown.add);
        final token = CancellationToken();
        final result = bridge.handler(request, token);
        shown.single.answer(const PlanAccepted());
        token.cancel();
        shown.single.answer(const PlanLeft());
        expect(await result, {'outcome': 'approved'});
      },
    );
    test('pre-cancelled and unsubscribed requests offer no approval', () async {
      final bridge = PlanBridge();
      addTearDown(bridge.close);
      final shown = <PendingPlan>[];
      final unsubscribe = bridge.subscribe(shown.add);
      expect(await bridge.handler(request, CancellationToken()..cancel()), {
        'outcome': 'cancelled',
      });
      unsubscribe();
      expect(await bridge.handler(request, CancellationToken()), {
        'outcome': 'cancelled',
      });
      expect(shown, isEmpty);
    });
  });
}
