/// Maps the providers' documented limit fields into plain windows, never
/// account identity. From the original's `session/resource_normalization.ts`,
/// whose zod checks are written out here in the same order.
library;

import 'budgets.dart';

/// A used share: a number from 0 to 100, or null.
bool _percent(Object? value) =>
    value == null || (value is num && value >= 0 && value <= 100);

const _maxSafe = 9007199254740991;

/// A provider's window it did not fill as documented reads as unknown.
ResourceWindow _unknownWindow(String name) => (
  name: name,
  usedPercent: null,
  windowSeconds: null,
  resetsAt: null,
  models: null,
);

/// A JavaScript `Date` of [milliseconds] since the epoch in `toISOString`'s
/// words; null where JavaScript's would be invalid.
String? _isoOf(num milliseconds) {
  if (!milliseconds.isFinite || milliseconds.abs() > 8.64e15) return null;
  return isoTime(
    DateTime.fromMillisecondsSinceEpoch(milliseconds.truncate(), isUtc: true),
  );
}

Map<String, Object?>? _map(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// One of Codex's windows, checked; null where it is not documented.
ResourceWindow? _codexWindow(String name, Object? raw) {
  final map = _map(raw);
  if (map == null ||
      !map.containsKey('usedPercent') ||
      !map.containsKey('windowDurationMins') ||
      !map.containsKey('resetsAt')) {
    return null;
  }
  final (used, minutes, resets) = (
    map['usedPercent'],
    map['windowDurationMins'],
    map['resetsAt'],
  );
  if (!_percent(used)) return null;
  if (minutes != null &&
      !(minutes is num && minutes > 0 && minutes <= _maxSafe / 60)) {
    return null;
  }
  if (resets != null &&
      !(resets is num &&
          resets.isFinite &&
          resets == resets.truncateToDouble() &&
          resets >= 0 &&
          resets <= _maxSafe)) {
    return null;
  }
  return (
    name: name,
    usedPercent: used as num?,
    windowSeconds: minutes == null ? null : (minutes as num) * 60,
    resetsAt: resets == null ? null : _isoOf((resets as num) * 1000),
    models: null,
  );
}

/// Codex's [account] and [limits] as windows: each bucket's primary and
/// secondary, the map over the legacy duplicate; unavailable for an account
/// that is not a ChatGPT subscription, or a snapshot not as documented.
ProviderLimits normalizeCodex(Object? account, Object? limits) {
  final inner = _map(_map(account)?['account']);
  if (inner == null || inner['type'] != 'chatgpt') {
    return const ProviderUnavailable(
      'codex',
      'Subscription account metadata is unavailable or unsupported.',
    );
  }
  const malformed = ProviderUnavailable(
    'codex',
    'Malformed rate-limit snapshot.',
  );
  final parsed = _map(limits);
  if (parsed == null ||
      !parsed.containsKey('rateLimitsByLimitId') ||
      (parsed['rateLimitsByLimitId'] != null &&
          _map(parsed['rateLimitsByLimitId']) == null)) {
    return malformed;
  }
  final byId = _map(parsed['rateLimitsByLimitId']);
  // The map supersedes the legacy duplicate, including when it is empty.
  final buckets = byId == null
      ? [(null as String?, parsed['rateLimits'])]
      : [
          for (final MapEntry(:key, :value) in byId.entries)
            (key as String?, value),
        ];
  if (buckets.length > 64) {
    return const ProviderUnavailable(
      'codex',
      'The quota map exceeds the supported bound.',
    );
  }
  final windows = <ResourceWindow>[];
  for (final (id, value) in buckets) {
    final bucket = _map(value);
    if (bucket == null) return malformed;
    for (final kind in const ['primary', 'secondary']) {
      final raw = bucket[kind];
      final name = id == null ? kind : '$id.$kind';
      if (raw == null) continue;
      windows.add(_codexWindow(name, raw) ?? _unknownWindow(name));
    }
  }
  return ProviderWindows('codex', windows);
}

// zod v4's `iso.datetime({offset: true})`: a calendar date, then seconds,
// a fraction if any, and Z or an offset.
const _date =
    r'(?:(?:\d\d[2468][048]|\d\d[13579][26]|\d\d0[48]|[02468][048]00|'
    r'[13579][26]00)-02-29|\d{4}-(?:(?:0[13578]|1[02])-(?:0[1-9]|[12]\d|'
    r'3[01])|(?:0[469]|11)-(?:0[1-9]|[12]\d|30)|(?:02)-(?:0[1-9]|1\d|2[0-8])))';
final _datetime = RegExp(
  '^${_date}T(?:(?:[01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d(?:\\.\\d+)?'
  '(?:Z|([+-](?:[01]\\d|2[0-3]):[0-5]\\d)))\$',
);

/// [value] as Claude's reset: an offset ISO time, or null; false when it is
/// neither.
bool _resetsAt(Object? value) =>
    value == null || (value is String && _datetime.hasMatch(value));

/// One of Claude's windows, checked; null where it is not documented.
({num? utilization, String? resetsAt})? _claudeWindow(Object? raw) {
  final map = _map(raw);
  if (map == null ||
      !map.containsKey('utilization') ||
      !map.containsKey('resets_at') ||
      !_percent(map['utilization']) ||
      !_resetsAt(map['resets_at'])) {
    return null;
  }
  return (
    utilization: map['utilization'] as num?,
    resetsAt: map['resets_at'] as String?,
  );
}

/// [resetsAt] as JavaScript's `new Date(…).toISOString()` writes it, Z
/// form; null where it reads as no time.
String? _claudeReset(String? resetsAt) {
  if (resetsAt == null) return null;
  final parsed = DateTime.tryParse(resetsAt);
  return parsed == null ? null : _isoOf(parsed.millisecondsSinceEpoch);
}

/// Claude's usage snapshot as windows: its fixed windows by name, each
/// model-scoped one with its model; unavailable where the source has no
/// limits or the snapshot is not as documented.
ProviderLimits normalizeClaude(Object? usage) {
  final parsed = _map(usage);
  final available = parsed?['rate_limits_available'];
  final limits = parsed?['rate_limits'];
  if (parsed == null ||
      available is! bool ||
      !parsed.containsKey('rate_limits') ||
      (limits != null && _map(limits) == null)) {
    return const ProviderUnavailable(
      'claude',
      'Malformed experimental usage snapshot.',
    );
  }
  final rateLimits = _map(limits);
  if (!available || rateLimits == null) {
    return const ProviderUnavailable(
      'claude',
      'Subscription limits unavailable: unsupported authentication source or '
          'missing profile scope.',
    );
  }
  final windows = <ResourceWindow>[];
  void append(String name, Object? raw, int seconds, List<String>? models) {
    if (raw == null) return;
    final window = _claudeWindow(raw);
    windows.add(
      window == null
          ? _unknownWindow(name)
          : (
              name: name,
              usedPercent: window.utilization,
              windowSeconds: seconds,
              resetsAt: _claudeReset(window.resetsAt),
              models: models,
            ),
    );
  }

  for (final name in const [
    'five_hour',
    'seven_day',
    'seven_day_oauth_apps',
    'seven_day_opus',
    'seven_day_sonnet',
  ]) {
    append(name, rateLimits[name], name == 'five_hour' ? 18000 : 604800, null);
  }
  final scoped = rateLimits['model_scoped'];
  final models = _models(scoped);
  if (models != null) {
    for (final model in models) {
      append('model_scoped', model, 604800, [model['display_name']! as String]);
    }
  } else if (scoped != null) {
    windows.add(_unknownWindow('model_scoped'));
  }
  return ProviderWindows('claude', windows);
}

/// Claude's model-scoped windows, each with a display name of 1 to 128
/// characters, at most 123; null when they are not so.
List<Map<String, Object?>>? _models(Object? scoped) {
  if (scoped is! List || scoped.length > 123) return null;
  final models = <Map<String, Object?>>[];
  for (final each in scoped) {
    final model = _map(each);
    final name = model?['display_name'];
    if (model == null ||
        name is! String ||
        name.isEmpty ||
        name.length > 128 ||
        _claudeWindow(model) == null) {
      return null;
    }
    models.add(model);
  }
  return models;
}
