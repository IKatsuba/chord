// From the original's tests/ui/transcript/tools/plan_ask_test.ts.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/tools/plan_ask.dart';
import 'package:test/test.dart';

PlanAsk ask({
  PlanAgent agent = PlanAgent.cursor,
  String? plan = '# Route',
  String? overview,
  List<PlanTodo>? todos,
  List<PlanPhase>? phases,
  PlanAnswer? answer,
}) => PlanAsk(
  't1',
  PlanWait(
    'p',
    agent,
    toolCallId: 'c',
    plan: plan,
    overview: overview,
    todos: todos,
    phases: phases,
  ),
  answer: answer,
);

void main() {
  test('the call says it waits, then how the person answered', () {
    expect(
      [
        null,
        const PlanAccepted(),
        const PlanKept(),
        const PlanKept('smaller'),
        const PlanLeft(),
        const PlanCancelled(),
        const PlanWithdrawn(),
      ].map((answer) => planStatus(ask(answer: answer))),
      [
        'Waiting…',
        'Accepted',
        'Kept planning',
        'Kept planning: smaller',
        'Left plan mode',
        'Cancelled',
        'Cancelled',
      ],
    );
  });

  test('the plan reads its overview, then its markdown; none when grok '
      'wrote none', () {
    expect(planText(ask(overview: 'Split it.')), 'Split it.\n\n# Route');
    expect(planText(ask(agent: PlanAgent.grok, plan: null)), isNull);
    expect(planText(ask(plan: '  ')), isNull);
    expect(noPlanLine('fake'), 'fake has written no plan.');
  });

  test("cursor's phases as sent, each over its todos, then all its todos "
      "under Todos, a cancelled one's box empty", () {
    const read = (id: 'r', content: 'Read', status: 'completed');
    const move = (id: 'm', content: 'Move', status: 'in_progress');
    const drop = (id: 'd', content: 'Drop', status: 'cancelled');
    final rows = todoRows(
      ask(
        todos: [read, move, drop],
        phases: [
          (name: 'Move', todos: [move]),
        ],
      ),
    );
    expect(
      rows.map(
        (row) => switch (row) {
          TodoHeading(:final text) => text,
          TodoItem(:final mark, :final todo) => '$mark ${todo.content}',
        },
      ),
      ['Move', '◐ Move', 'Todos', '☒ Read', '◐ Move', '☐ Drop'],
    );
    expect(todoRows(ask()), isEmpty);
  });
}
