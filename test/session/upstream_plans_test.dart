// A plan as chord acp puts it to its client, from the original's
// session/upstream.ts planPermission and planAnswerOf.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/upstream.dart';
import 'package:test/test.dart';

void main() {
  test("a plan is a permission: its call, its markdown, the agent's "
      'choices', () {
    const cursor = PlanWait(
      'p',
      PlanAgent.cursor,
      toolCallId: 'c',
      name: 'Route',
      overview: 'Split it.',
      plan: '# Route',
      todos: [
        (id: 'a', content: 'Read', status: 'completed'),
        (id: 'b', content: 'Move', status: 'pending'),
      ],
      phases: [
        (name: 'Move', todos: [(id: 'b', content: 'Move', status: 'pending')]),
      ],
    );
    expect(planPermission('s', cursor), {
      'sessionId': 's',
      'toolCall': {
        'toolCallId': 'c',
        'title': 'Route',
        'content': [
          {
            'type': 'content',
            'content': {
              'type': 'text',
              'text':
                  'Split it.\n\n# Route\n\n- [x] Read\n- [ ] Move\n\n## Move\n- [ ] Move',
            },
          },
        ],
      },
      'options': [
        {
          'optionId': 'accepted',
          'name': 'Yes, accept the plan',
          'kind': 'allow_once',
        },
        {
          'optionId': 'kept',
          'name': 'No, keep planning',
          'kind': 'reject_once',
        },
      ],
    });
    final grok = planPermission(
      's',
      const PlanWait('p', PlanAgent.grok, toolCallId: 'c'),
    );
    expect((grok['toolCall'] as Map)['title'], 'Plan');
    expect((grok['options'] as List).last, {
      'optionId': 'left',
      'name': 'No, and leave plan mode',
      'kind': 'reject_once',
    });
  });

  test("the client's answer: a cancel, an error or an id not offered is "
      'cancelled, never a yes', () {
    const cursor = PlanWait('p', PlanAgent.cursor, toolCallId: 'c');
    const grok = PlanWait('p', PlanAgent.grok, toolCallId: 'c');
    Map<String, Object?> selected(String id) => {
      'outcome': {'outcome': 'selected', 'optionId': id},
    };
    expect(planAnswerOf(cursor, selected('accepted')), isA<PlanAccepted>());
    expect(planAnswerOf(cursor, selected('kept')), isA<PlanKept>());
    expect(planAnswerOf(grok, selected('left')), isA<PlanLeft>());
    for (final answer in [
      null,
      selected('left'),
      selected('yes'),
      {
        'outcome': {'outcome': 'cancelled'},
      },
    ]) {
      expect(planAnswerOf(cursor, answer), isA<PlanCancelled>());
    }
  });
}
