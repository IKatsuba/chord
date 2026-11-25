/// The version a release makes (CHD-412, CHD-577), as the original's
/// `scripts/dev/release/version.ts`, `select.ts` and the pure part of
/// `bump.ts`: pubspec.yaml's when none is given or the one given is it,
/// else an exact version above it or a bump of it. On a channel, a
/// pre-release of that version numbered from pubspec.yaml's. A bump there
/// counts from npm's latest stable, as pubspec.yaml holds a pre-release. A
/// version with a label is never given: `--channel` is the only way to name
/// one, so the label and the channel cannot disagree.
library;

import 'package:chord/channel.dart';
import 'package:chord/node_semver.dart';

export 'package:chord/channel.dart' show VersionError;

/// The file the release reads and writes the version in, as the messages
/// name it.
const manifest = 'pubspec.yaml';

/// The bumps `--bump` takes; `fix` is `patch`'s other name.
enum Bump {
  /// `x` of `x.y.z` up by one.
  major,

  /// `y` of `x.y.z` up by one.
  minor,

  /// `z` of `x.y.z` up by one.
  patch,

  /// `patch`'s other name.
  fix;

  /// The bump [word] names, or null.
  static Bump? named(String word) {
    for (final bump in values) {
      if (bump.name == word) return bump;
    }
    return null;
  }

  Part get _part => switch (this) {
    major => Part.major,
    minor => Part.minor,
    patch || fix => Part.patch,
  };
}

/// Whether [word] can be `--bump`'s value: a bump, or a version written as
/// semver writes it, so `v1.2.3` or `1.2.3+build` is not taken for another.
bool isVersionArgument(String word) =>
    Bump.named(word) != null || valid(word) == word;

/// The version a release of [wanted] makes of [current], pubspec.yaml's, on
/// [channel] if any. [stable] answers npm's latest stable, and is asked
/// only for a bump on a channel, the one case that needs the registry.
String releaseVersion(
  String current,
  String? wanted, {
  String? channel,
  String Function()? stable,
}) {
  if (channel != null) checkChannel(channel);

  if (wanted == null) {
    if (channel != null && channelOf(current) != channel) {
      throw VersionError(
        "$manifest's version $current is not on channel $channel; name a "
        'version or a bump',
      );
    }
    return current;
  }

  if (!isVersionArgument(wanted)) {
    throw VersionError(
      '$wanted is neither a version nor one of '
      '${Bump.values.map((bump) => bump.name).join(', ')}',
    );
  }

  if (prerelease(wanted) != null) {
    throw VersionError(
      '$wanted has a pre-release label; --channel is the only way to name one',
    );
  }

  if (valid(current) == null) {
    throw VersionError("$manifest's version $current is no version");
  }

  if (channel != null) {
    return _channelVersion(
      current,
      wanted,
      channel,
      stable ??
          () => throw const VersionError(
            "a bump on a channel needs npm's latest stable",
          ),
    );
  }

  if (Bump.named(wanted) case final bump?) {
    if (prerelease(current) != null) {
      throw VersionError(
        "$manifest's version $current is a pre-release, so a bump would not "
        'say which release it means; name the version',
      );
    }
    return incStable(current, bump._part);
  }

  // pubspec.yaml's own, so a rerun after a failed publish can name it.
  if (wanted == current) return current;

  if (!gt(wanted, current)) {
    throw VersionError("$wanted is not above $manifest's version $current");
  }
  return wanted;
}

/// The pre-release of [wanted] on [channel], the one after pubspec.yaml's.
String _channelVersion(
  String current,
  String wanted,
  String channel,
  String Function() stable,
) {
  final base = switch (Bump.named(wanted)) {
    final bump? => _bumpStable(stable(), bump),
    null => wanted,
  };

  if (channelOf(current) == channel && current.startsWith('$base-')) {
    return incChannel(current, channel);
  }

  final first = '$base-$channel.0';
  if (!gt(first, current)) {
    throw VersionError("$first is not above $manifest's version $current");
  }
  return first;
}

String _bumpStable(String stable, Bump bump) {
  if (valid(stable) == null || prerelease(stable) != null) {
    throw VersionError("npm's latest $stable is no stable version");
  }
  return incStable(stable, bump._part);
}

final _pubspecVersion = RegExp(r'^(version:[ \t]*)\S+', multiLine: true);
// The framework's entry in the port's pubspec.lock, up to its version.
final _lockedFramework = RegExp(
  r'^(  chord_tui:\n(?:    .*\n)*?    version: )"[^"]*"',
  multiLine: true,
);
final _heldVersion = RegExp(r"^(const version = )'[^']*'", multiLine: true);

/// pubspec.yaml's [text] with only its version value replaced, so the rest
/// of the file stays as it was laid out; null when it has no version line.
String? withVersion(String text, String version) =>
    _replaced(text, _pubspecVersion, (key) => '$key$version');

/// The port's pubspec.lock [text] with only the framework's locked
/// version replaced, as `dart pub get` would record the path dependency
/// at [version]; null when it locks no chord_tui.
String? withLockedVersion(String text, String version) =>
    _replaced(text, _lockedFramework, (key) => '$key"$version"');

/// `lib/version.dart`'s [text] with only the held constant replaced; null
/// when it holds none.
String? withHeldVersion(String text, String version) =>
    _replaced(text, _heldVersion, (key) => "$key'$version'");

String? _replaced(String text, RegExp pattern, String Function(String) to) {
  if (!pattern.hasMatch(text)) return null;
  return text.replaceFirstMapped(pattern, (match) => to(match.group(1)!));
}
