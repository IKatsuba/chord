import 'config.dart';

/// A model by its id and display name.
typedef AgentModel = ({String id, String name});

/// Models offered and the current id, which need not be among them.
typedef AgentModels = ({List<AgentModel> available, String? current});

/// The config select through which models are set, when offered.
String? modelConfigId(Object? options) =>
    configSelect(options, 'model')?['id'] as String?;

/// Reads the unstable legacy model state only when its full shape is valid.
bool isModelState(Object? value) =>
    value is Map<String, Object?> &&
    value['currentModelId'] is String &&
    value['availableModels'] is List &&
    (value['availableModels'] as List).every(
      (m) => m is Map<String, Object?> && m['modelId'] is String,
    );

/// Models from the preferred config select, or the older session answer.
AgentModels? modelsFrom(Object? options, Object? legacy) {
  final option = configSelect(options, 'model');
  List<AgentModel> available;
  String? current;
  if (option != null) {
    available = [
      for (final v in optionValues(option))
        (id: v.value, name: v.name.isEmpty ? v.value : v.name),
    ];
    current = option['currentValue'] as String?;
  } else if (isModelState(legacy)) {
    final state = legacy as Map<String, Object?>;
    available = [
      for (final m in state['availableModels'] as List)
        (
          id: m['modelId'] as String,
          name: m['name'] is String && m['name'] != ''
              ? m['name'] as String
              : m['modelId'] as String,
        ),
    ];
    current = state['currentModelId'] as String;
  } else {
    return null;
  }
  return available.isEmpty && (current == null || current.isEmpty)
      ? null
      : (available: available, current: current);
}

/// The current model's name, or its id when it is not listed.
String? modelName(AgentModels? models) {
  final id = models?.current;
  if (id == null) return null;
  for (final model in models!.available) {
    if (model.id == id) return model.name;
  }
  return id;
}
