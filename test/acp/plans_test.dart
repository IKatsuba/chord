// From the original's tests/acp/plans_test.ts.
import 'package:chord/acp/plans.dart';
import 'package:test/test.dart';

const todo = {'id': 'read', 'content': 'Read it', 'status': 'pending'};

void main() {
  test("cursor's create_plan reads its plan, name, overview, todos and "
      'phases; anything else stays out', () {
    expect(
      cursorPlan({
        'toolCallId': 'call-1',
        'name': 'Route',
        'overview': 'Split it.',
        'plan': '# Route',
        'todos': [todo],
        'phases': [
          {
            'name': 'Read',
            'todos': [todo],
          },
        ],
        'isProject': true,
      })?.toJson(),
      {
        'agent': 'cursor',
        'toolCallId': 'call-1',
        'plan': '# Route',
        'name': 'Route',
        'overview': 'Split it.',
        'todos': [todo],
        'phases': [
          {
            'name': 'Read',
            'todos': [todo],
          },
        ],
      },
    );
    expect(
      cursorPlan({'toolCallId': 'call-1', 'plan': '', 'todos': []})?.toJson(),
      {'agent': 'cursor', 'toolCallId': 'call-1', 'plan': '', 'todos': []},
    );
  });

  test('a create_plan that does not read as cursor documents it reads as '
      'none, so it is answered cancelled', () {
    for (final params in <Object?>[
      null,
      'plan',
      {'plan': '# Route', 'todos': []},
      {'toolCallId': 'call-1', 'todos': []},
      {'toolCallId': 'call-1', 'plan': '# Route'},
      {'toolCallId': 'call-1', 'plan': '# Route', 'todos': 'three'},
      {
        'toolCallId': 'call-1',
        'plan': '# Route',
        'todos': [
          {...todo, 'status': 'done'},
        ],
      },
      {
        'toolCallId': 'call-1',
        'plan': '# Route',
        'todos': [],
        'phases': [
          {
            'name': 'Read',
            'todoIds': ['read'],
          },
        ],
      },
    ]) {
      expect(cursorPlan(params), isNull, reason: '$params');
    }
  });

  test("grok's exit_plan_mode reads its session, call and plan, with or "
      'without a plan', () {
    expect(
      grokPlan({
        'sessionId': 's',
        'toolCallId': 'c',
        'planContent': '# Route',
      })?.toJson(),
      {'agent': 'grok', 'sessionId': 's', 'toolCallId': 'c', 'plan': '# Route'},
    );
    expect(grokPlan({'sessionId': 's', 'toolCallId': 'c'})?.toJson(), {
      'agent': 'grok',
      'sessionId': 's',
      'toolCallId': 'c',
    });
    for (final params in [
      {'toolCallId': 'c'},
      {'sessionId': 's'},
      {'sessionId': 's', 'toolCallId': 'c', 'planContent': 3},
    ]) {
      expect(grokPlan(params), isNull);
    }
  });

  test('null and nested malformed known fields never become an approvable '
      'request', () {
    for (final extra in <Map<String, Object?>>[
      {'sessionId': null},
      {'name': 3},
      {'overview': []},
      {
        'phases': [
          {
            'name': 'Read',
            'todos': [null],
          },
        ],
      },
      {
        'todos': [
          {'id': 'a', 'content': 'Read', 'status': null},
        ],
      },
    ]) {
      expect(
        cursorPlan({
          'toolCallId': 'c',
          'plan': '# Route',
          'todos': [],
          ...extra,
        }),
        isNull,
        reason: '$extra',
      );
    }
    for (final extra in <Map<String, Object?>>[
      {'sessionId': null},
      {'toolCallId': []},
      {'planContent': null},
    ]) {
      expect(
        grokPlan({'sessionId': 's', 'toolCallId': 'c', ...extra}),
        isNull,
        reason: '$extra',
      );
    }
  });

  test('each method names its own reader', () {
    expect(PlanAgent.cursor.method, 'cursor/create_plan');
    expect(PlanAgent.grok.method, 'x.ai/exit_plan_mode');
    expect(
      planOf('x.ai/exit_plan_mode', {
        'sessionId': 's',
        'toolCallId': 'c',
      })?.agent,
      PlanAgent.grok,
    );
    expect(planOf('other', {'sessionId': 's', 'toolCallId': 'c'}), isNull);
  });
}
