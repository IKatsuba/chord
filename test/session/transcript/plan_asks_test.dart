// A plan ask folded into the transcript, from the original's reducer
// (plan_requested, plan_settled).
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

const prompt = PromptAction('t1', 'go', 0);
TranscriptAction call(String id) => UpdateAction(
  't1',
  acp.SessionUpdate.fromJson({
    'sessionUpdate': 'tool_call',
    'toolCallId': id,
    'title': 'Plan',
    'kind': 'switch_mode',
    'status': 'pending',
  }),
);
const plan = PlanWait(
  'plan-1',
  PlanAgent.cursor,
  toolCallId: 'c1',
  plan: '# Route',
  todos: [],
);

void main() {
  test(
    'a plan is drawn under the call it names, and its answer once given',
    () {
      final asked = fold([
        prompt,
        call('c1'),
        const PlanRequestedAction('t1', plan),
      ]);
      final ask = asked.planAsks.single;
      expect((ask.turnId, ask.wait.id, ask.answer), ('t1', 'plan-1', null));
      expect(ask.after, isEmpty);
      expect(asked.entries.whereType<ToolEntry>().single.call.plan, same(ask));
      final answered = fold([
        const PlanSettledAction('t1', 'plan-1', PlanKept('Smaller.')),
      ], asked);
      final kept = answered.planAsks.single.answer;
      expect(kept, isA<PlanKept>().having((k) => k.note, 'note', 'Smaller.'));
      expect(
        answered.entries.whereType<ToolEntry>().single.call.plan?.answer,
        same(kept),
      );
      // Answered once: a second answer changes nothing.
      expect(
        fold([
          const PlanSettledAction('t1', 'plan-1', PlanAccepted()),
        ], answered),
        same(answered),
      );
    },
  );

  test('a plan asked twice is one ask; one under no call is kept all the '
      'same', () {
    final once = fold([prompt, const PlanRequestedAction('t1', plan)]);
    expect(once.planAsks, hasLength(1));
    expect(fold([const PlanRequestedAction('t1', plan)], once), same(once));
  });

  test('the permissions already waiting go before it', () {
    final waiting = fold([
      prompt,
      call('c1'),
      const PermissionRequestedAction('t1', PermissionWait('p1')),
      const PlanRequestedAction('t1', plan),
    ]);
    expect(waiting.planAsks.single.after, ['p1']);
  });

  test('a later update to its call keeps the plan under it', () {
    final state = fold([
      prompt,
      call('c1'),
      const PlanRequestedAction('t1', plan),
      UpdateAction(
        't1',
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'c1',
          'status': 'completed',
        }),
      ),
    ]);
    expect(
      state.entries.whereType<ToolEntry>().single.call.plan?.wait.id,
      'plan-1',
    );
  });
}
