import 'config.dart';

/// An effort value the current model offers.
typedef AgentEffort = ({String id, String name});

/// The effort select, its values and its current value.
typedef AgentEfforts = ({
  String option,
  List<AgentEffort> available,
  String current,
});

/// Efforts identified only by ACP's thought_level category.
AgentEfforts? effortsFrom(Object? options) {
  final option = configSelect(options, 'thought_level', legacyId: false);
  if (option == null ||
      option['id'] is! String ||
      option['currentValue'] is! String) {
    return null;
  }
  final values = optionValues(option);
  return values.isEmpty
      ? null
      : (
          option: option['id'] as String,
          available: [
            for (final v in values)
              (id: v.value, name: v.name.isEmpty ? v.value : v.name),
          ],
          current: option['currentValue'] as String,
        );
}

/// What is said when [agent] offers no effort for [model]: the model left
/// out when it has no name yet, as while the agent starts, rather than the
/// original's "for ." with nothing before the stop.
String noEffortNote(String agent, String model) => model.isEmpty
    ? '$agent offers no effort.'
    : '$agent offers no effort for $model.';
