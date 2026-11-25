// Plans: one that moves a step at a time, Codex's proposed plan, and the
// plans cursor and grok put to the client to approve (CHD-437, CHD-457),
// as the original's scenarios/plans.ts.
import 'package:uuid/uuid.dart';

import '../client.dart';
import '../options.dart';
import '../rpc.dart';
import '../turn.dart';
import 'agents.dart';

/// How long the `plan` scenario holds each step.
num get _planStepMs => stepMs * 400;

const _priorities = ['high', 'medium', 'low'];

const _steps = ['Read the code', 'Write the change', 'Run the tests'];

/// Three steps, the first in progress, then the first dropped: after a
/// while, or with [gated] once the test opens the gate.
Future<String> _planShrink(Turn turn, bool gated) async {
  Map<String, Object?> entry(String content, int index) => {
    'content': content,
    'priority': index < _priorities.length ? _priorities[index] : 'low',
    'status': index == 0 ? 'in_progress' : 'pending',
  };

  await turn.send({
    'sessionUpdate': 'plan',
    'entries': [for (final (i, step) in _steps.indexed) entry(step, i)],
  });
  await turn.say(['Planned.']);
  if (gated) {
    await gateOpened(turn, gateRelease);
  } else {
    await pause(turn.signal, stepMs * 200);
  }
  await turn.send({
    'sessionUpdate': 'plan',
    'entries': [
      for (final (i, step) in _steps.sublist(1).indexed) entry(step, i),
    ],
  });
  await turn.say([' Dropped a step.']);
  await pause(turn.signal, stepMs * 200);
  return 'end_turn';
}

/// The plan cursor's and grok's scenarios put to the person.
const askedPlan =
    '# Route updates by session\n\n1. Read src/acp/connection.ts.\n'
    '2. Move the routing into src/session/session.ts.\n3. Run the tests.';

/// cursor's todos for [askedPlan].
const _cursorTodos = [
  {'id': 'read', 'content': 'Read the connection', 'status': 'completed'},
  {'id': 'move', 'content': 'Move the routing', 'status': 'in_progress'},
  {'id': 'test', 'content': 'Run the tests', 'status': 'pending'},
];

/// The answer each session's last plan got, which `planheard` says.
final _planAnswers = <String, String>{};

/// Puts a plan to the client with [method] under a `Plan` call, announced
/// first unless [early], and says the answer it got back whole.
Future<String> _askPlan(
  Turn turn,
  String method,
  Map<String, Object?> Function(String toolCallId) params, {
  bool early = false,
}) async {
  final toolCallId = turn.callId('plan');
  Future<void> announce() => turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': 'Plan',
    'kind': 'switch_mode',
    'status': 'pending',
  });

  if (!early) await announce();
  final asked = turn.client.requestAny(method, params(toolCallId));
  if (early) await announce();
  final answer = await asked;

  // Kept before the turn goes on, which an interrupt may have ended.
  _planAnswers[turn.sessionId] = stringify(answer);

  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'completed',
  });
  await turn.say(['Plan answer: ${_planAnswers[turn.sessionId]}']);
  return 'end_turn';
}

final Map<String, Play> plans = {
  // The plan moves a step at a time, slowly enough to be seen mid-turn.
  'plan': (turn) async {
    List<Map<String, Object?>> at(int done) => [
      for (final (index, content) in _steps.indexed)
        {
          'content': content,
          'priority': index < _priorities.length ? _priorities[index] : 'low',
          'status': index < done
              ? 'completed'
              : index == done
              ? 'in_progress'
              : 'pending',
        },
    ];
    final planId = const Uuid().v4();
    Future<void> send(List<Map<String, Object?>> entries) async {
      if (!planCapabilityOnly) {
        await turn.send({'sessionUpdate': 'plan', 'entries': entries});
      } else if (clientTakesPlans) {
        await turn.send({
          'sessionUpdate': 'plan_update',
          'plan': {'type': 'items', 'planId': planId, 'entries': entries},
        });
      } else {
        await turn.say([
          [
            for (final entry in entries)
              '- [${entry['status'] == 'completed' ? 'x' : ' '}] '
                  '${entry['content']}\n',
          ].join(),
        ]);
      }
    }

    for (var done = 1; done <= _steps.length; done++) {
      await send(at(done));
      await turn.say([done == 1 ? 'Planned.' : ' Step $done done.']);
      if (done < _steps.length) await pause(turn.signal, _planStepMs);
    }
    return 'end_turn';
  },

  // A plan whose first step goes mid-turn.
  'planshrink': (turn) => _planShrink(turn, false),

  // As `planshrink`, the step dropped only once the gate is released
  // (CHD-399).
  'planshrinkgated': (turn) => _planShrink(turn, true),

  // Codex's proposed plan: whole markdown each time, rewritten from the
  // start, then a file plan beside it, then the markdown one withdrawn.
  'proposal': (turn) async {
    const drafts = [
      '1. Read the code',
      '1. Inspect the code',
      '1. Inspect the code\n2. Write the change',
    ];
    const uri = 'file:///plans/proposal.md';
    // Fresh ids each run.
    final draftId = const Uuid().v4();
    final fileId = const Uuid().v4();

    await turn.say(["I'll look first."]);
    if (!clientTakesPlans) {
      await turn.say(['\n\n${drafts.last}\n\n$uri\n\nPlan written.']);
      return 'end_turn';
    }
    for (final content in drafts) {
      await pause(turn.signal, _planStepMs);
      await turn.send({
        'sessionUpdate': 'plan_update',
        'plan': {'type': 'markdown', 'planId': draftId, 'content': content},
      });
    }
    await pause(turn.signal, _planStepMs);
    await turn.send({
      'sessionUpdate': 'plan_update',
      'plan': {'type': 'file', 'planId': fileId, 'uri': uri},
    });
    await turn.say(['Plan written.']);
    await pause(turn.signal, _planStepMs);
    await turn.send({'sessionUpdate': 'plan_removed', 'planId': draftId});
    await turn.say([' Draft dropped.']);
    return 'end_turn';
  },

  // cursor's cursor/create_plan, its todos and a phase of them.
  'cursorplan': (turn) => _askPlan(
    turn,
    'cursor/create_plan',
    (toolCallId) => {
      'toolCallId': toolCallId,
      'name': 'Route updates by session',
      'overview': 'Split the session routing out of the connection.',
      'plan': askedPlan,
      'todos': _cursorTodos,
      'phases': [
        {'name': 'Move', 'todos': _cursorTodos.sublist(1)},
      ],
    },
  ),

  // The same, asked before the call it names is announced.
  'cursorplanearly': (turn) => _askPlan(
    turn,
    'cursor/create_plan',
    (toolCallId) => {
      'toolCallId': toolCallId,
      'plan': askedPlan,
      'todos': <Object?>[],
    },
    early: true,
  ),

  // A plan request that does not read: its todos are no list.
  'cursorplanbad': (turn) => _askPlan(
    turn,
    'cursor/create_plan',
    (toolCallId) => {
      'toolCallId': toolCallId,
      'plan': askedPlan,
      'todos': 'three',
    },
  ),

  // grok's x.ai/exit_plan_mode, with its plan.
  'grokplan': (turn) => _askPlan(
    turn,
    'x.ai/exit_plan_mode',
    (toolCallId) => {
      'sessionId': turn.sessionId,
      'toolCallId': toolCallId,
      'planContent': askedPlan,
    },
  ),

  // grok's request naming a session other than its own.
  'grokplanwrong': (turn) => _askPlan(
    turn,
    'x.ai/exit_plan_mode',
    (toolCallId) => {
      'sessionId': 'another-session',
      'toolCallId': toolCallId,
      'planContent': askedPlan,
    },
  ),

  // cursor's request sent only once the turn has been cancelled, before
  // the turn ends: it waits for its answer, which only chord can give.
  'cursorplanlate': (turn) async {
    final toolCallId = turn.callId('plan');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': toolCallId,
      'title': 'Plan',
      'kind': 'switch_mode',
      'status': 'pending',
    });
    await untilAborted(turn.signal);
    final answer = await turn.client.requestAny('cursor/create_plan', {
      'toolCallId': toolCallId,
      'plan': askedPlan,
      'todos': <Object?>[],
    });
    _planAnswers[turn.sessionId] = stringify(answer);
    return 'cancelled';
  },

  // cursor's plan and a form asked at once, each waiting on its own
  // answer; says both, the plan's first.
  'planform': (turn) async {
    final toolCallId = turn.callId('plan');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': toolCallId,
      'title': 'Plan',
      'kind': 'switch_mode',
      'status': 'pending',
    });
    final plan = turn.client.requestAny('cursor/create_plan', {
      'toolCallId': toolCallId,
      'plan': askedPlan,
      'todos': <Object?>[],
    });
    final form = turn.client.request('elicitation/create', {
      'sessionId': turn.sessionId,
      'mode': 'form',
      'message': 'Name the branch',
      'requestedSchema': {
        'type': 'object',
        'properties': {
          'branch': {'type': 'string', 'title': 'Branch'},
        },
      },
    });
    final [planned, formed] = await Future.wait<Object?>([plan, form]);
    final action = (formed as Map)['action'];
    await turn.say([
      'Plan answer: ${stringify(planned)} · form: '
          '${action ?? 'undefined'}',
    ]);
    return 'end_turn';
  },

  // Says the answer the session's last plan got.
  'planheard': (turn) async {
    await turn.say(['Plan answer: ${_planAnswers[turn.sessionId] ?? 'none'}']);
    return 'end_turn';
  },

  'grokplanempty': (turn) => _askPlan(
    turn,
    'x.ai/exit_plan_mode',
    (toolCallId) => {'sessionId': turn.sessionId, 'toolCallId': toolCallId},
  ),
};
