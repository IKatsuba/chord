/// The select settings the agent offers, in its own order.
library;

/// One selectable setting value.
typedef AgentOptionValue = ({String value, String name});

/// A session setting other than its mode and model.
typedef AgentOption = ({
  String id,
  String name,
  List<AgentOptionValue> values,
  String current,
});

/// Select options read from the agent's last report.
List<Map<String, Object?>> selects(Object? options) => options is List
    ? options
          .whereType<Map<String, Object?>>()
          .where((o) => o['type'] == 'select')
          .toList()
    : [];

/// Grouped select values, flattened in the order supplied by the agent.
List<AgentOptionValue> optionValues(Map<String, Object?> option) {
  final entries = option['options'];
  if (entries is! List) return [];
  return [
    for (final entry in entries.whereType<Map<String, Object?>>())
      if (entry.containsKey('group'))
        ...optionValues({'options': entry['options']})
      else if (entry['value'] is String && entry['name'] is String)
        (value: entry['value'] as String, name: entry['name'] as String),
  ];
}

/// Finds a select by its ACP category, or its legacy id.
Map<String, Object?>? configSelect(
  Object? options,
  String category, {
  bool legacyId = true,
}) {
  for (final option in selects(options)) {
    if (option['category'] == category ||
        (legacyId && option['id'] == category)) {
      return option;
    }
  }
  return null;
}

/// Settable options except mode and model; empty selects are left out.
List<AgentOption> optionsFromConfigOptions(Object? options) => [
  for (final option in selects(options))
    if (!['mode', 'model'].contains(option['category']) &&
        !['mode', 'model'].contains(option['id']) &&
        option['id'] is String &&
        option['name'] is String &&
        option['currentValue'] is String &&
        optionValues(option).isNotEmpty)
      (
        id: option['id'] as String,
        name: option['name'] as String,
        values: optionValues(option),
        current: option['currentValue'] as String,
      ),
];

/// The agent's name for a value, falling back to its id.
String valueName(AgentOption option, String value) {
  for (final entry in option.values) {
    if (entry.value == value) return entry.name;
  }
  return value;
}

/// The agent's name for an option, falling back to its id.
String optionName(Object? options, String id) {
  for (final option in selects(options)) {
    if (option['id'] == id &&
        option['name'] is String &&
        option['name'] != '') {
      return option['name'] as String;
    }
  }
  return id;
}
