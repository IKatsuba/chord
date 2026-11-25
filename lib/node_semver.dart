/// The parts of npm's `semver` the original's channels and release use:
/// `valid`, `prerelease`, `validRange` as far as a channel name reaches it,
/// `compare`, `gt` and `inc`. Our own grammar, as docs/decisions.md says:
/// pub_semver takes what semver refuses and the other way round, so it only
/// orders, with build metadata dropped first.
library;

import 'package:pub_semver/pub_semver.dart';

import 'js_trim.dart';

// semver's `MAX_LENGTH` and `Number.MAX_SAFE_INTEGER`.
const _maxLength = 256;
final _maxSafe = BigInt.from(9007199254740991);

// semver's strict `FULL`: one optional `v`, no leading zeros, a pre-release
// after `-`, build metadata after `+`.
const _number = r'0|[1-9]\d*';
const _identifier = '(?:\\d*[a-zA-Z-][a-zA-Z0-9-]*|$_number)';
final _full = RegExp(
  '^v?($_number)\\.($_number)\\.($_number)'
  '(?:-($_identifier(?:\\.$_identifier)*))?'
  r'(?:\+([a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*))?$',
);
final _digits = RegExp(r'^[0-9]+$');

// What a channel-shaped name `validRange` takes: `vN` and `x` mean a range.
final _rangeName = RegExp(r'^v*(x|0|[1-9][0-9]{0,15})$');
final _maxRangeNumber = BigInt.from(9007199254740990);

/// A version as semver parses it: three components and the pre-release
/// identifiers, an int where all digits and below 2^53 - 1, else a String.
typedef _Parsed = ({
  BigInt major,
  BigInt minor,
  BigInt patch,
  List<Object> pre,
});

_Parsed? _parse(String version) {
  if (version.length > _maxLength) return null;
  final match = _full.firstMatch(jsTrim(version));
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 3; i++) BigInt.parse(match.group(i)!)];
  if (parts.any((part) => part > _maxSafe)) return null;
  final pre = match.group(4);
  return (
    major: parts[0],
    minor: parts[1],
    patch: parts[2],
    pre: [
      if (pre != null)
        for (final id in pre.split('.'))
          if (_digits.hasMatch(id) && BigInt.parse(id) < _maxSafe)
            int.parse(id)
          else
            id,
    ],
  );
}

String _format(_Parsed v) => [
  '${v.major}.${v.minor}.${v.patch}',
  if (v.pre.isNotEmpty) v.pre.join('.'),
].join('-');

_Parsed _parseOrThrow(String version) =>
    _parse(version) ??
    (throw ArgumentError.value(version, 'version', 'Invalid Version'));

/// What `semver.valid` answers: [version] normalised (JavaScript-trimmed,
/// a leading `v` and build metadata dropped), or null when it is no version.
String? valid(String version) => switch (_parse(version)) {
  final parsed? => _format(parsed),
  null => null,
};

/// What `semver.prerelease` answers: the pre-release identifiers of a
/// version, null when it is stable or no version.
List<Object>? prerelease(String version) => switch (_parse(version)) {
  final parsed? when parsed.pre.isNotEmpty => parsed.pre,
  _ => null,
};

/// Whether npm takes [name], already shaped `^[a-z][a-z0-9-]*$`, for a
/// version range, as `semver.validRange(name) !== null` answers.
bool isRangeName(String name) {
  final match = _rangeName.firstMatch(name);
  if (match == null) return false;
  final number = match.group(1)!;
  return number == 'x' || BigInt.parse(number) <= _maxRangeNumber;
}

Version _ordered(String version) {
  final v = _parseOrThrow(version);
  return Version(
    v.major.toInt(),
    v.minor.toInt(),
    v.patch.toInt(),
    pre: v.pre.isEmpty ? null : v.pre.join('.'),
  );
}

/// `semver.compare`: below zero when [a] precedes [b], build metadata
/// ignored. Throws [ArgumentError] when either is no version.
///
/// One known difference: numeric identifiers above 2^53 - 1 order exactly
/// here, where semver's `+a` rounds them and may call two of them equal.
int compare(String a, String b) => _ordered(a).compareTo(_ordered(b)).sign;

/// `semver.gt`: whether [a] is above [b].
bool gt(String a, String b) => compare(a, b) > 0;

/// The parts of a stable version a bump raises.
enum Part {
  /// `x` of `x.y.z`.
  major,

  /// `y` of `x.y.z`.
  minor,

  /// `z` of `x.y.z`.
  patch,
}

/// `semver.inc(version, part)` for a stable version. Throws [ArgumentError]
/// when [version] is no version or a pre-release.
String incStable(String version, Part part) {
  final v = _ordered(version);
  if (v.isPreRelease) {
    throw ArgumentError.value(version, 'version', 'Not a stable version');
  }
  return switch (part) {
    Part.major => v.nextMajor,
    Part.minor => v.nextMinor,
    Part.patch => v.nextPatch,
  }.toString();
}

/// `semver.inc(version, 'prerelease', channel)` for a version already
/// written `<x.y.z>-<channel>.<n>`: its counter plus one. Throws
/// [ArgumentError] for any other version.
String incChannel(String version, String channel) {
  final v = _parseOrThrow(version);
  if (v.pre case [final String label, final int n] when label == channel) {
    return _format((
      major: v.major,
      minor: v.minor,
      patch: v.patch,
      pre: [channel, n + 1],
    ));
  }
  throw ArgumentError.value(version, 'version', 'Not a release of $channel');
}
