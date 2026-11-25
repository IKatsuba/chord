/// The values a new session is asked to open on, sent as `session/new`'s
/// initial `configOptions` where the agent takes them (CHD-629): a value the
/// agent takes at setup then costs no request after the session is up.
library;

import '../acp/schema.dart' as acp;

/// The starting values chord was asked for, by the agent's id for each.
typedef InitialValues = ({String? model, String? effort, String? mode});

/// The config ids an adapter takes as initial `configOptions`, by the name
/// its `initialize` answer gives, as the original's table holds them.
const _initialConfigIds = {
  '@agentclientprotocol/claude-agent-acp': (
    model: 'model',
    effort: 'effort',
    mode: 'mode',
  ),
};

/// `session/new`'s initial entries for [values], only where the agent
/// advertises `sessionCapabilities.options`: one per value named, model,
/// effort, mode, in that order, since a model decides which efforts and
/// modes follow, where the table knows the agent; then a `chord acp`
/// client's [entries] as it sent them, which take the place of chord's for
/// the same id. chord adds no value of its own.
List<Map<String, Object?>> initialEntries(
  acp.InitializeResponse init,
  InitialValues values, {
  List<Map<String, Object?>> entries = const [],
}) {
  final options = init.agentCapabilities?.sessionCapabilities?['options'];
  if (!acp.jsTruthy(options)) return const [];
  final ids = _initialConfigIds[init.agentInfo?.name];
  final taken = {for (final entry in entries) entry['configId']};
  return [
    if (ids != null) ...[
      if (values.model case final model? when !taken.contains(ids.model))
        {'configId': ids.model, 'value': model},
      if (values.effort case final effort? when !taken.contains(ids.effort))
        {'configId': ids.effort, 'value': effort},
      if (values.mode case final mode? when !taken.contains(ids.mode))
        {'configId': ids.mode, 'value': mode},
    ],
    ...entries,
  ];
}
