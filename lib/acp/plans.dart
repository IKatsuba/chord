/// The two requests an agent puts its plan to the client with, and their
/// answers, from the original's `acp/plans.ts`: cursor's
/// `cursor/create_plan` and grok's `x.ai/exit_plan_mode`. Each is read into
/// one shape; a request that does not read is answered `cancelled`, never a
/// yes.
library;

/// Whose plan, so its answers are its own; [method] is its request's.
enum PlanAgent {
  cursor('cursor/create_plan'),
  grok('x.ai/exit_plan_mode');

  const PlanAgent(this.method);
  final String method;
}

/// The statuses a cursor todo has.
const planTodoStatuses = ['pending', 'in_progress', 'completed', 'cancelled'];

/// One of cursor's todos, as its request sends it.
typedef PlanTodo = ({String id, String content, String status});

/// One of cursor's phases: a name over todos of its own, sent whole.
typedef PlanPhase = ({String name, List<PlanTodo> todos});

/// A plan request as chord reads it.
final class PlanRequest {
  const PlanRequest(
    this.agent, {
    this.sessionId,
    required this.toolCallId,
    this.plan,
    this.name,
    this.overview,
    this.todos,
    this.phases,
  });

  final PlanAgent agent;

  /// The session that asks, when its request names one.
  final String? sessionId;
  final String toolCallId;

  /// The plan's markdown; grok sends none when it wrote no plan.
  final String? plan;
  final String? name;
  final String? overview;
  final List<PlanTodo>? todos;
  final List<PlanPhase>? phases;

  /// What it read, as plain values.
  Map<String, Object?> toJson() => {
    'agent': agent.name,
    'sessionId': ?sessionId,
    'toolCallId': toolCallId,
    'plan': ?plan,
    'name': ?name,
    'overview': ?overview,
    if (todos case final todos?) 'todos': [for (final t in todos) _todo(t)],
    if (phases case final phases?)
      'phases': [
        for (final p in phases)
          {
            'name': p.name,
            'todos': [for (final t in p.todos) _todo(t)],
          },
      ],
  };
}

Map<String, Object?> _todo(PlanTodo todo) => {
  'id': todo.id,
  'content': todo.content,
  'status': todo.status,
};

/// The answer every request is given that is not the person's.
const planCancelled = <String, Object?>{'outcome': 'cancelled'};

/// [json]'s [key] as a string; null when absent; throws when another thing.
String? _string(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value is String) return value;
  throw const FormatException();
}

String _required(Map<String, Object?> json, String key) =>
    _string(json, key) ?? (throw const FormatException());

List<PlanTodo> _todos(Object? value) {
  if (value is! List) throw const FormatException();
  return [
    for (final todo in value)
      if (todo case {
        'id': final String id,
        'content': final String content,
        'status': final String status,
      } when planTodoStatuses.contains(status))
        (id: id, content: content, status: status)
      else
        throw const FormatException(),
  ];
}

/// `cursor/create_plan`'s params as chord reads them; none when they do not.
PlanRequest? cursorPlan(Object? params) {
  if (params is! Map<String, Object?>) return null;
  try {
    final phases = params.containsKey('phases')
        ? switch (params['phases']) {
            final List<Object?> phases => [
              for (final phase in phases)
                if (phase case {
                  'name': final String name,
                  'todos': final Object? todos,
                })
                  (name: name, todos: _todos(todos))
                else
                  throw const FormatException(),
            ],
            _ => throw const FormatException(),
          }
        : null;
    return PlanRequest(
      PlanAgent.cursor,
      sessionId: _string(params, 'sessionId'),
      toolCallId: _required(params, 'toolCallId'),
      plan: _required(params, 'plan'),
      name: _string(params, 'name'),
      overview: _string(params, 'overview'),
      todos: _todos(params['todos']),
      phases: phases,
    );
  } on FormatException {
    return null;
  }
}

/// `x.ai/exit_plan_mode`'s params as chord reads them; none when they do
/// not.
PlanRequest? grokPlan(Object? params) {
  if (params is! Map<String, Object?>) return null;
  try {
    return PlanRequest(
      PlanAgent.grok,
      sessionId: _required(params, 'sessionId'),
      toolCallId: _required(params, 'toolCallId'),
      plan: _string(params, 'planContent'),
    );
  } on FormatException {
    return null;
  }
}

/// The request [method] names, read; none for another method or params
/// that do not read.
PlanRequest? planOf(String method, Object? params) => switch (method) {
  'cursor/create_plan' => cursorPlan(params),
  'x.ai/exit_plan_mode' => grokPlan(params),
  _ => null,
};
