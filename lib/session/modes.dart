import 'config.dart';

/// A mode in the agent's own words.
typedef AgentMode = ({String id, String name});

/// The modes offered and the current id, including an unknown current id.
typedef AgentModes = ({List<AgentMode> available, String? current});

/// The config option through which modes are set, when offered.
String? modeConfigId(Object? options) =>
    configSelect(options, 'mode')?['id'] as String?;

/// Modes from the preferred config select, or the older session answer.
AgentModes? modesFrom(Object? options, [Map<String, Object?>? legacy]) {
  final option = configSelect(options, 'mode');
  if (option != null) {
    final values = optionValues(option);
    return values.isEmpty
        ? null
        : (
            available: [for (final v in values) (id: v.value, name: v.name)],
            current: option['currentValue'] as String?,
          );
  }
  final available = legacy?['availableModes'];
  if (available is! List || available.isEmpty) return null;
  return (
    available: [
      for (final mode in available.whereType<Map<String, Object?>>())
        if (mode['id'] is String && mode['name'] is String)
          (id: mode['id'] as String, name: mode['name'] as String),
    ],
    current: legacy?['currentModeId'] as String?,
  );
}

/// The next mode, wrapping in the agent's order; none with fewer than two.
String? nextMode(List<AgentMode> available, String? current) =>
    available.length < 2
    ? null
    : available[(available.indexWhere((m) => m.id == current) + 1) %
              available.length]
          .id;
