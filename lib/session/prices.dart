/// What a model costs and how large its context window is, from
/// @pydantic/genai-prices' data as the original pins it (price_data.dart):
/// nothing is fetched, and the data moves only with the pinned version.
///
/// The lookup and pricing follow genai-prices 0.2.3's calcPrice for a model
/// id alone (no provider, URL or price context), which is how the original
/// calls it. https://github.com/pydantic/genai-prices, MIT License,
/// Copyright (c) Pydantic Services Inc. 2025 to present; the notice is in
/// price_data.dart.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:clock/clock.dart';

import 'price_data.dart';
import 'usage.dart';

/// The currency genai-prices gives every price in.
const priceCurrency = 'USD';

/// What a turn's tokens cost on [model], in [priceCurrency]; null for a
/// model the data does not know, or tokens it cannot price.
double? turnCost(String model, TokenUsage tokens) =>
    _lookUp(model, _priced(tokens))?.total;

/// [model]'s context window in tokens, when the data gives one.
int? contextWindow(String model) {
  final size = _lookUp(model, const {
    'input_tokens': 0,
  })?.model['context_window'];
  return size is num && size > 0 ? size.toInt() : null;
}

/// The tokens that fill the context after a turn: what went in and what
/// came out.
num contextFrom(TokenUsage tokens) {
  final usage = _priced(tokens);
  return (usage['input_tokens'] ?? 0) + (usage['output_tokens'] ?? 0);
}

/// ACP's counts as genai-prices takes them, where the input includes what
/// was read from or written to the cache and the output the thinking. The
/// total says which sum the agent made; without one the counts are taken as
/// apart, the way ACP lists them.
Map<String, num> _priced(TokenUsage tokens) {
  final input = tokens['inputTokens'] ?? 0;
  final output = tokens['outputTokens'] ?? 0;
  final read = tokens['cachedReadTokens'] ?? 0;
  final written = tokens['cachedWriteTokens'] ?? 0;
  final thought = tokens['thoughtTokens'] ?? 0;
  final total = tokens['totalTokens'];
  final cacheInside =
      total != null &&
      (total == input + output + thought || total == input + output);
  final thoughtInside =
      total != null &&
      (total == input + output + read + written || total == input + output);
  return {
    'input_tokens': cacheInside ? input : input + read + written,
    'output_tokens': thoughtInside ? output : output + thought,
    'cache_read_tokens': read,
    'cache_write_tokens': written,
  };
}

/// The data's entry for [model]. Agents name models their own way: Codex's
/// adapter adds the effort after a slash, Claude's a `[1m]`, a router puts
/// the provider first; each shorter name is tried after the whole one.
({Map<String, Object?> model, double total})? _lookUp(
  String model,
  Map<String, num> usage,
) {
  final bare = model.replaceFirst(RegExp(r'\[[^\]]*\]$'), '');
  final parts = bare.split('/');
  for (final name in {model, bare, parts.first, parts.last}) {
    try {
      final found = calcPrice(usage, name);
      if (found != null) return found;
    } on _PriceError {
      // Counts the data refuses, such as more read from the cache than went
      // in, price nothing rather than stop the session.
      return null;
    }
  }
  return null;
}

/// What genai-prices refuses to price, as its calcPrice throws.
final class _PriceError implements Exception {
  const _PriceError(this.message);
  final String message;
  @override
  String toString() => message;
}

final _data = jsonDecode(priceData) as Map<String, Object?>;
final _units = _Units(_data['units'] as Map<String, Object?>);
final _providers = [
  for (final provider in _data['providers'] as List)
    provider as Map<String, Object?>,
];

/// genai-prices' calcPrice for [modelId] alone, at [at] (now by default):
/// the model's entry and the turn's total price, or null where no provider
/// or model matches.
({Map<String, Object?> model, double total})? calcPrice(
  Map<String, num> usage,
  String modelId, {
  DateTime? at,
}) {
  final id = modelId.toLowerCase().trim();
  final provider = _providers
      .where((p) => _matches(p['model_match'], id))
      .firstOrNull;
  if (provider == null) return null;
  final model =
      _findModel(provider, id) ?? _findModel(provider, _withDashes(id));
  if (model == null) return null;
  final prices = _pricesAt(model, at ?? clock.now());
  return (model: model, total: _calculate(usage, prices));
}

bool _matches(Object? logic, String text) {
  if (logic is! Map) return false;
  final lower = text.toLowerCase();
  String of(String key) => (logic[key] as String).toLowerCase();
  if (logic['or'] case final List any) return any.any((l) => _matches(l, text));
  if (logic['and'] case final List all) {
    return all.every((l) => _matches(l, text));
  }
  if (logic.containsKey('equals')) return lower == of('equals');
  if (logic.containsKey('starts_with')) {
    return lower.startsWith(of('starts_with'));
  }
  if (logic.containsKey('ends_with')) return lower.endsWith(of('ends_with'));
  if (logic.containsKey('contains')) return lower.contains(of('contains'));
  if (logic['regex'] case final String regex) {
    return RegExp(regex).hasMatch(text);
  }
  return false;
}

Map<String, Object?>? _findModel(
  Map<String, Object?> provider,
  String id, {
  bool fallbacks = true,
}) {
  for (final model in provider['models'] as List) {
    if (model case final Map<String, Object?> m when _matches(m['match'], id)) {
      return m;
    }
  }
  if (!fallbacks) return null;
  for (final fallback
      in (provider['fallback_model_providers'] as List?) ?? const []) {
    final other = _providers.where((p) => p['id'] == fallback).firstOrNull;
    if (other == null) continue;
    final found = _findModel(other, id, fallbacks: false);
    if (found != null) return found;
  }
  return null;
}

final _compactDate = RegExp(
  r'(-)(20\d{2})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?=-|:|$)',
);

/// A model id's compact dates, `-20250514`, written with dashes, where the
/// date is a real one.
String _withDashes(String id) => id.replaceAllMapped(_compactDate, (m) {
  final year = int.parse(m[2]!),
      month = int.parse(m[3]!),
      day = int.parse(m[4]!);
  final date = DateTime.utc(year, month, day);
  return date.year != year || date.month != month || date.day != day
      ? m[0]!
      : '${m[1]}${m[2]}-${m[3]}-${m[4]}';
});

/// The model's prices at [at]: the last of its dated prices whose
/// constraint holds, else the first.
Map<String, Object?> _pricesAt(Map<String, Object?> model, DateTime at) {
  final prices = model['prices'];
  if (prices is! List) return prices as Map<String, Object?>;
  for (final conditional in prices.reversed) {
    final c = conditional as Map<String, Object?>;
    if (_holds(c['constraint'], at, model['id'])) {
      return c['prices'] as Map<String, Object?>;
    }
  }
  return (prices.first as Map<String, Object?>)['prices']
      as Map<String, Object?>;
}

bool _holds(Object? constraint, DateTime at, Object? model) {
  if (constraint == null) return true;
  final c = constraint as Map<String, Object?>;
  final utc = at.toUtc();
  if (c['type'] == 'start_date' ||
      (c['type'] == null && c.containsKey('start_date'))) {
    return !utc.isBefore(DateTime.parse('${c['start_date']}T00:00:00Z'));
  }
  if (c['type'] == 'time_of_date' ||
      (c['type'] == null && c.containsKey('start_time'))) {
    final now =
        utc.hour * 3600 + utc.minute * 60 + utc.second + utc.millisecond / 1000;
    final start = _secondsOfDay(c['start_time'] as String);
    final end = _secondsOfDay(c['end_time'] as String);
    return end < start ? now >= start || now < end : now >= start && now < end;
  }
  throw _PriceError('Unknown price constraint for model $model');
}

double _secondsOfDay(String time) {
  final m = RegExp(
    r'^(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|([+-])(\d{2}):(\d{2}))$',
  ).firstMatch(time);
  if (m == null) throw _PriceError('Invalid time-of-day constraint: $time');
  final h = int.parse(m[1]!), min = int.parse(m[2]!), s = int.parse(m[3]!);
  final oh = m[7] ?? '00', om = m[8] ?? '00';
  if (h > 23 ||
      min > 59 ||
      s > 59 ||
      oh.compareTo('23') > 0 ||
      om.compareTo('59') > 0) {
    throw _PriceError('Invalid time-of-day constraint: $time');
  }
  final offset = (int.parse(oh) * 60 + int.parse(om)) * 60;
  final seconds = h * 3600 + min * 60 + s + double.parse('0.${m[4] ?? ''}');
  final shift = m[5] == 'Z'
      ? 0
      : m[6] == '+'
      ? offset
      : -offset;
  return (seconds - shift + 86400) % 86400;
}

/// One unit of usage: what it counts, per how many a price is given, and
/// its dimensions.
final class _Unit {
  _Unit(this.usageKey, this.priceKey, this.per, this.dimensions);
  final String usageKey, priceKey;
  final num per;
  final Map<String, String> dimensions;
}

/// genai-prices' unit registry.
final class _Units {
  _Units(Map<String, Object?> table) {
    for (final MapEntry(:key, :value) in table.entries) {
      final v = value as Map<String, Object?>;
      final unit = _Unit(
        key,
        (v['price_key'] as String?) ?? key,
        v['per'] as num,
        (v['dimensions'] as Map).cast<String, String>(),
      );
      byUsage[key] = unit;
      byPrice[unit.priceKey] = unit;
      byDimensions[_dimensionKey(unit.dimensions)] = unit;
    }
    for (final unit in byUsage.values) {
      ancestors[unit.usageKey] = {
        for (final other in byUsage.values)
          if (other != unit && _within(other, unit)) other.usageKey,
      };
    }
  }

  final byUsage = <String, _Unit>{};
  final byPrice = <String, _Unit>{};
  final byDimensions = <String, _Unit>{};
  final ancestors = <String, Set<String>>{};

  bool reported(String usageKey) =>
      byUsage.containsKey(usageKey) && usageKey != 'requests';

  _Unit? join(_Unit a, _Unit b) => _compatible(a, b)
      ? byDimensions[_dimensionKey({...a.dimensions, ...b.dimensions})]
      : null;
}

String _dimensionKey(Map<String, String> dimensions) => jsonEncode([
  for (final key in dimensions.keys.toList()..sort()) [key, dimensions[key]],
]);

/// Whether [a]'s dimensions all hold in [b]: [a] is [b]'s ancestor or [b].
bool _within(_Unit a, _Unit b) =>
    a.dimensions.entries.every((e) => b.dimensions[e.key] == e.value);

/// Whether no dimension of [a] contradicts [b].
bool _compatible(_Unit a, _Unit b) => a.dimensions.entries.every(
  (e) => b.dimensions[e.key] == null || b.dimensions[e.key] == e.value,
);

double _calculate(Map<String, num> usage, Map<String, Object?> prices) {
  final priced = <(_Unit, Object)>[];
  for (final MapEntry(:key, :value) in prices.entries) {
    if (value == null) continue;
    final unit = _units.byPrice[key];
    if (unit == null) continue;
    priced.add((unit, _price(key, value)));
  }
  final units = [for (final (unit, _) in priced) unit];
  _checkAncestors(units);
  _checkJoins(units);
  final tiered = priced.any((p) => p.$2 is! num);
  final inputTokens = tiered ? _usageOf(usage, 'input_tokens') : 0;
  final keys = {
    for (final unit in units)
      if (unit.usageKey != 'requests') unit.usageKey,
  };
  final leaves = _leaves(keys, usage);
  if (units.any((u) => u.usageKey == 'requests')) leaves['requests'] = 1;
  var total = 0.0;
  for (final (unit, price) in priced) {
    total += _cost(price, leaves[unit.usageKey] ?? 0, inputTokens, unit.per);
  }
  return total;
}

Object _price(String key, Object value) {
  if (value is num && value.isFinite && value >= 0) return value;
  if (value case {'base': final num base, 'tiers': final List tiers}) {
    return (
      base: base,
      tiers: [
        for (final tier in tiers)
          (start: (tier as Map)['start'] as num, price: tier['price'] as num),
      ]..sort((a, b) => a.start.compareTo(b.start)),
    );
  }
  throw _PriceError('Invalid price value for $key');
}

double _cost(Object price, num count, num inputTokens, num per) {
  if (price is num) return price * count / per;
  final (:base, :tiers) =
      price as ({num base, List<({num start, num price})> tiers});
  if (count <= 0) return 0;
  var rate = base;
  for (final tier in tiers) {
    if (inputTokens > tier.start) rate = tier.price;
  }
  return rate * count / 1e6 * 1e6 / per;
}

void _checkAncestors(List<_Unit> units) {
  final keys = {for (final u in units) u.priceKey};
  for (final unit in units) {
    for (final ancestor in _units.ancestors[unit.usageKey]!) {
      if (!keys.contains(_units.byUsage[ancestor]!.priceKey)) {
        throw _PriceError('Missing ancestor price key for ${unit.priceKey}');
      }
    }
  }
}

void _checkJoins(List<_Unit> units) {
  final keys = {for (final u in units) u.priceKey};
  for (var i = 0; i < units.length; i++) {
    for (var j = i + 1; j < units.length; j++) {
      final (a, b) = (units[i], units[j]);
      if (!_compatible(a, b)) continue;
      final join = _units.join(a, b);
      if (join == null || !keys.contains(join.priceKey)) {
        throw _PriceError('Missing join price key for ${a.priceKey}');
      }
    }
  }
}

/// The usage at [key]: as given, else none, unless a more specific count
/// given says there was some.
num _usageOf(Map<String, num> usage, String key) {
  final target = _units.byUsage[key]!;
  final given = usage[key];
  if (given != null) return _valid(key, given);
  for (final MapEntry(key: name, :value) in usage.entries) {
    if (!_units.reported(name) || _valid(name, value) <= 0 || name == key) {
      continue;
    }
    if (_units.ancestors[name]!.contains(key)) {
      throw _PriceError('Missing usage value for $key');
    }
  }
  final positive = [
    for (final MapEntry(key: name, :value) in usage.entries)
      if (_units.reported(name) && _valid(name, value) > 0)
        _units.byUsage[name]!,
  ];
  for (var i = 0; i < positive.length; i++) {
    for (var j = i + 1; j < positive.length; j++) {
      final (a, b) = (positive[i], positive[j]);
      final related =
          a == b ||
          _units.ancestors[b.usageKey]!.contains(a.usageKey) ||
          _units.ancestors[a.usageKey]!.contains(b.usageKey);
      if (_compatible(a, b) && !related && _units.join(a, b) == target) {
        throw _PriceError('Missing usage value for $key');
      }
    }
  }
  return 0;
}

num _valid(String key, num value) {
  if (!value.isFinite || value < 0) {
    throw _PriceError('Invalid usage value for $key');
  }
  return value;
}

/// Each priced unit's own share of the usage: its count less what its more
/// specific units counted.
Map<String, num> _leaves(Set<String> keys, Map<String, num> usage) {
  final units = [for (final key in keys) ?_units.byUsage[key]]
    ..sort((a, b) {
      final by = b.dimensions.length - a.dimensions.length;
      return by != 0 ? by : a.usageKey.compareTo(b.usageKey);
    });
  final leaves = <String, num>{};
  for (final unit in units) {
    final count = _usageOf(usage, unit.usageKey);
    num inside = 0;
    for (final other in units) {
      if (other == unit || !_within(unit, other)) continue;
      inside += leaves[other.usageKey]!;
    }
    var own = count - inside;
    final epsilon =
        2.220446049250313e-16 *
        math.max(1, math.max(count.abs(), inside.abs())) *
        (units.length + 1);
    if (own < 0 && own.abs() <= epsilon) own = 0;
    if (own < 0) throw _PriceError('Invalid usage data for ${unit.usageKey}');
    leaves[unit.usageKey] = own;
  }
  return leaves;
}
