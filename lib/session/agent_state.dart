/// What the agent has said about a session besides its turns: its config
/// options, its modes and models the older way, and its slash commands,
/// from the answer that opened the session and the updates since. Pure; the
/// session folds into it as each comes. M1 reads it only, as the status
/// line shows what the agent reports.
library;

import 'dart:collection';

import '../acp/schema.dart' as acp;

/// The agent's own facts about a session, as it reported them.
final class AgentState {
  const AgentState({
    this.configOptions = const [],
    this.modes,
    this.models,
    this.commands = const [],
  });

  /// Nothing reported yet.
  static const empty = AgentState();

  /// The session's config options, each as the agent sent it.
  final List<Map<String, Object?>> configOptions;

  /// `modes` as `session/new` gave them, for an agent with no mode option.
  final Map<String, Object?>? modes;

  /// `models` as `session/new` gave them, unchecked: not stable in ACP v1.
  final Object? models;

  /// The slash commands the agent offers.
  final List<acp.AvailableCommand> commands;
}

/// The state `session/new`'s [answer] seeds.
AgentState stateOf(acp.SessionResponse answer) {
  final json = answer.toJson();
  final modes = json['modes'];

  return AgentState(
    configOptions: _options(json['configOptions']) ?? const [],
    modes: modes is Map<String, Object?> ? modes : null,
    models: json['models'],
  );
}

/// [state] after one of the agent's updates; most leave it identical.
AgentState foldUpdate(AgentState state, acp.SessionUpdate update) {
  final json = update.toJson();

  switch (update.kind) {
    case 'config_option_update':
      return withOptions(state, json['configOptions']);
    case acp.SessionUpdateKind.currentModeUpdate:
      final id = json['currentModeId'];
      return id is String ? _withMode(state, id) : state;
    case acp.SessionUpdateKind.availableCommandsUpdate:
      final commands = json['availableCommands'];
      return commands is List
          ? AgentState(
              configOptions: state.configOptions,
              modes: state.modes,
              models: state.models,
              commands: UnmodifiableListView([
                for (final each in commands)
                  if (each is Map<String, Object?>)
                    acp.AvailableCommand.fromJson(each),
              ]),
            )
          : state;
    default:
      return state;
  }
}

/// [state] with the config options an agent answered or sent. A value that
/// is no list, as some answers carry, leaves the options as they were.
AgentState withOptions(AgentState state, Object? configOptions) {
  final options = _options(configOptions);

  return options == null
      ? state
      : AgentState(
          configOptions: options,
          modes: state.modes,
          models: state.models,
          commands: state.commands,
        );
}

List<Map<String, Object?>>? _options(Object? value) => value is List
    ? UnmodifiableListView([
        for (final each in value)
          if (each is Map<String, Object?>) each,
      ])
    : null;

/// [state] in the mode the agent reports, in its mode config option too,
/// so the option it last sent does not undo a `current_mode_update`.
AgentState _withMode(AgentState state, String id) {
  final key = _modeConfigId(state.configOptions);
  final modes = state.modes;

  return AgentState(
    configOptions: UnmodifiableListView([
      for (final option in state.configOptions)
        option['id'] == key && option['type'] == 'select'
            ? {...option, 'currentValue': id}
            : option,
    ]),
    modes: modes == null ? null : {...modes, 'currentModeId': id},
    models: state.models,
    commands: state.commands,
  );
}

/// The id of the select option that holds the mode, if one does.
String? _modeConfigId(List<Map<String, Object?>> options) {
  for (final option in options) {
    if (option['type'] == 'select' &&
        (option['category'] == 'mode' || option['id'] == 'mode')) {
      final id = option['id'];
      return id is String ? id : null;
    }
  }
  return null;
}
