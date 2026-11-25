import '../../session/agent_state.dart';
import '../../session/transcript/types.dart';
import 'status.dart';

Map<String, Object?>? _option(AgentState state, String category, {String? id}) {
  for (final option in state.configOptions) {
    if (option['type'] == 'select' &&
        (option['category'] == category || id != null && option['id'] == id)) {
      return option;
    }
  }
  return null;
}

List<Map<String, Object?>> _values(Map<String, Object?>? option) {
  final values = option?['options'];
  if (values is! List) return const [];
  return [
    for (final value in values)
      if (value is Map<String, Object?>)
        if (value.containsKey('group')) ..._values(value) else value,
  ];
}

String? _string(Object? value) => value is String ? value : null;
String? _selected(Map<String, Object?>? option) =>
    _string(option?['currentValue']);
String? _name(List<Map<String, Object?>> values, String? id, String field) {
  for (final value in values) {
    if (value[field] == id) return _string(value['name']);
  }
  return null;
}

/// The model's display name, falling back to its id, from config or legacy data.
String? modelName(AgentState state) {
  final option = _option(state, 'model', id: 'model');
  if (option != null) {
    final id = _selected(option);
    if (id == null) return null;
    final name = _name(_values(option), id, 'value');
    return name == null || name.isEmpty ? id : name;
  }
  final legacy = state.models;
  if (legacy is! Map<String, Object?> ||
      legacy['currentModelId'] is! String ||
      legacy['availableModels'] is! List) {
    return null;
  }
  final values = legacy['availableModels'] as List;
  if (values.any(
    (value) => value is! Map<String, Object?> || value['modelId'] is! String,
  )) {
    return null;
  }
  final id = legacy['currentModelId'] as String;
  final name = _name(values.cast<Map<String, Object?>>(), id, 'modelId');
  return name == null || name.isEmpty ? id : name;
}

/// The current effort id, found only by the thought_level category.
String? effortOf(AgentState state) {
  final option = _option(state, 'thought_level');
  return _values(option).isEmpty ? null : _selected(option);
}

/// Agent-reported status, including the original mode seeding from its options.
StatusFacts statusFactsOf(
  AgentState state,
  Transcript transcript, {
  String? notice,
  bool failed = false,
  String? hint,
  String? cycleKey,
  WaitsNotice? waits,
  bool bash = false,
  String? vim,
}) {
  final option = _option(state, 'mode', id: 'mode');
  final values = _values(option);
  final legacy = state.modes;
  final legacyValues = legacy?['availableModes'];
  final mode =
      _selected(option) ?? _string(legacy?['currentModeId']) ?? transcript.mode;
  final name = option != null
      ? _name(values, mode, 'value')
      : legacyValues is List
      ? _name(
          [
            for (final value in legacyValues)
              if (value is Map<String, Object?>) value,
          ],
          mode,
          'id',
        )
      : null;
  return StatusFacts(
    model: modelName(state),
    effort: effortOf(state),
    mode: mode,
    modeName: name,
    usage: transcript.usage,
    notice: notice,
    failed: failed,
    hint: hint,
    cycleKey: cycleKey,
    waits: waits,
    bash: bash,
    vim: vim,
  );
}
