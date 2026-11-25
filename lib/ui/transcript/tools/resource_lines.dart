/// One read of the providers' limits, a line per window or per provider
/// not read. From the original's `ui/transcript/tools/resource_lines.ts`.
library;

import '../../../session/budgets.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime utc) =>
    '${utc.year.toString().padLeft(4, '0')}-${_two(utc.month)}-${_two(utc.day)}';

/// [value] as a time of day in UTC, with its date when it is not [read]'s
/// day.
String _utc(String value, String read, {bool seconds = false}) {
  final date = DateTime.parse(value).toUtc();
  final time =
      '${_two(date.hour)}:${_two(date.minute)}'
      '${seconds ? ':${_two(date.second)}' : ''}';
  final sameDay = value.substring(0, 10) == read.substring(0, 10);
  return '${sameDay ? '' : '${_date(date)} '}$time UTC';
}

/// [seconds] in the largest whole unit: `5h`, `7d`, `90m`.
String _duration(num seconds) {
  for (final (unit, size) in const [('d', 86400), ('h', 3600), ('m', 60)]) {
    if (seconds % size == 0) return '${_number(seconds / size)}$unit';
  }
  return '${_number(seconds)}s';
}

/// A number as JavaScript writes it: `12.345`, `8`.
String _number(num value) => value == value.roundToDouble() && value.isFinite
    ? value.toInt().toString()
    : value.toString();

String _windowLine(String agent, ResourceWindow window, String read) {
  final seconds = window.windowSeconds;
  final label = seconds == null ? window.name : _duration(seconds);
  final used = window.usedPercent;
  final resets = window.resetsAt;
  final models = window.models;
  return '$agent · $label: '
      '${used == null ? 'usage unknown' : '${_number(used)}% used'} · '
      'reset ${resets == null ? 'unknown' : _utc(resets, read)} · '
      '${models == null ? 'models unknown' : 'models ${models.isEmpty ? 'none' : models.join(', ')}'}';
}

/// The lines under a `get_budgets` call: when it was read, then each
/// provider's windows or why it was not read; one line for an answer of an
/// older format.
List<String> resourceLines(Object? value) {
  final budgets = budgetsOf(value);
  if (budgets == null) return const ['Recorded in an older format; not shown.'];
  final (:readAt, :providers) = budgets;
  return [
    'Read: ${_utc(readAt, readAt, seconds: true)} · advisory snapshot',
    if (providers.isEmpty) 'No providers read.',
    for (final provider in providers)
      ...switch (provider) {
        ProviderUnavailable(:final agent, :final unavailable) => [
          '$agent: unavailable · $unavailable',
        ],
        ProviderWindows(:final agent, :final windows) when windows.isEmpty => [
          '$agent: no windows reported',
        ],
        ProviderWindows(:final agent, :final windows) => [
          for (final window in windows) _windowLine(agent, window, readAt),
        ],
      },
  ];
}
