/// The providers' usage limits `get_budgets` reads, and their checks, as
/// the original's `session/budgets.ts`. The team selection settings it
/// also holds there are `settings.dart`'s.
library;

/// One provider window as the provider names it; null is what it did not
/// say.
typedef ResourceWindow = ({
  String name,
  num? usedPercent,
  num? windowSeconds,
  String? resetsAt,
  List<String>? models,
});

/// A provider's windows, or why they could not be read.
sealed class ProviderLimits {
  const ProviderLimits(this.agent);

  /// The runtime read, as list_agents names it.
  final String agent;

  /// As the answer gives it.
  Map<String, Object?> toJson();
}

/// A provider read: its windows.
final class ProviderWindows extends ProviderLimits {
  const ProviderWindows(super.agent, this.windows);

  final List<ResourceWindow> windows;

  @override
  Map<String, Object?> toJson() => {
    'agent': agent,
    'windows': [for (final window in windows) windowJson(window)],
  };
}

/// A provider not read, and why.
final class ProviderUnavailable extends ProviderLimits {
  const ProviderUnavailable(super.agent, this.unavailable);

  final String unavailable;

  @override
  Map<String, Object?> toJson() => {'agent': agent, 'unavailable': unavailable};
}

/// [window] as the answer gives it.
Map<String, Object?> windowJson(ResourceWindow window) => {
  'name': window.name,
  'usedPercent': window.usedPercent,
  'windowSeconds': window.windowSeconds,
  'resetsAt': window.resetsAt,
  'models': window.models,
};

/// What get_budgets answers: each provider read when it was called.
typedef Budgets = ({String readAt, List<ProviderLimits> providers});

/// [budgets] as the answer gives it.
Map<String, Object?> budgetsJson(Budgets budgets) => {
  'readAt': budgets.readAt,
  'providers': [for (final provider in budgets.providers) provider.toJson()],
};

bool _ref(Object? value) =>
    value is String && value.isNotEmpty && value.length <= 128;

bool _text(Object? value) =>
    value is String && value.isNotEmpty && value.length <= 500;

// zod v4's `z.iso.datetime()` with its defaults, its own regex: a real
// Gregorian date, seconds required, any fraction, `Z` only. Dart's parser
// would roll an out-of-range day or hour into another time instead.
final _datetime = RegExp(
  r'^(?:(?:\d\d[2468][048]|\d\d[13579][26]|\d\d0[48]|[02468][048]00|'
  r'[13579][26]00)-02-29|\d{4}-(?:(?:0[13578]|1[02])-(?:0[1-9]|[12]\d|3[01])|'
  r'(?:0[469]|11)-(?:0[1-9]|[12]\d|30)|(?:02)-(?:0[1-9]|1\d|2[0-8])))'
  r'T(?:(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z))$',
);

bool _time(Object? value) => value is String && _datetime.hasMatch(value);

/// Whether [value] is a time as the original's `z.iso.datetime()` takes it.
bool isIsoTime(Object? value) => _time(value);

bool _ids(Object? value) =>
    value is List && value.length <= 128 && value.every(_ref);

/// [json] as a strict object of exactly [keys], or null.
Map<String, Object?>? _strict(Object? json, Set<String> keys) =>
    json is Map<String, Object?> && json.keys.every(keys.contains)
    ? json
    : null;

ResourceWindow? _window(Object? json) {
  final map = _strict(json, const {
    'name',
    'usedPercent',
    'windowSeconds',
    'resetsAt',
    'models',
  });
  if (map == null || !map.keys.toSet().containsAll(const ['name'])) {
    return null;
  }
  final (name, used, seconds, resets, models) = (
    map['name'],
    map['usedPercent'],
    map['windowSeconds'],
    map['resetsAt'],
    map['models'],
  );
  // Each key is there: null says the provider did not say it.
  if (map.length != 5 ||
      !_ref(name) ||
      !(used == null || (used is num && used >= 0 && used <= 100)) ||
      !(seconds == null ||
          (seconds is num && seconds.isFinite && seconds > 0)) ||
      !(resets == null || _time(resets)) ||
      !(models == null || _ids(models))) {
    return null;
  }
  return (
    name: name as String,
    usedPercent: used as num?,
    windowSeconds: seconds as num?,
    resetsAt: resets as String?,
    models: models == null ? null : (models as List).cast<String>(),
  );
}

ProviderLimits? _provider(Object? json) {
  if (json is! Map<String, Object?> || !_ref(json['agent'])) return null;
  final agent = json['agent'] as String;
  if (_strict(json, const {'agent', 'windows'}) != null &&
      json.containsKey('windows')) {
    final windows = json['windows'];
    if (windows is! List || windows.length > 256) return null;
    final read = [for (final window in windows) _window(window)];
    if (read.any((window) => window == null)) return null;
    return ProviderWindows(agent, read.cast<ResourceWindow>());
  }
  if (_strict(json, const {'agent', 'unavailable'}) != null &&
      _text(json['unavailable'])) {
    return ProviderUnavailable(agent, json['unavailable'] as String);
  }
  return null;
}

/// [json] as a check of `Budgets` reads it, or null where it is not one,
/// as a record of an older format.
Budgets? budgetsOf(Object? json) {
  final map = _strict(json, const {'readAt', 'providers'});
  if (map == null || !_time(map['readAt'])) return null;
  final providers = map['providers'];
  if (providers is! List || providers.length > 128) return null;
  final read = [for (final provider in providers) _provider(provider)];
  if (read.any((provider) => provider == null)) return null;
  return (
    readAt: map['readAt'] as String,
    providers: read.cast<ProviderLimits>(),
  );
}

/// [time] in UTC to the millisecond, as JavaScript's `toISOString` writes
/// it: `2026-10-27T13:00:00.000Z`.
String isoTime(DateTime time) {
  final utc = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
      '${two(utc.second)}.${utc.millisecond.toString().padLeft(3, '0')}Z';
}
