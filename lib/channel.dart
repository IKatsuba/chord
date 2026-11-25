/// The release channel a version is on (CHD-577), worked out from the
/// version alone: the npm tag, the branch and the GitHub pre-release mark
/// all come from here, so a labelled version cannot be published without
/// its tag. It holds no release code, as the running chord asks it which
/// tag to follow.
library;

import 'node_semver.dart';

/// Why a version cannot be released, said as the release dies with it.
final class VersionError implements Exception {
  /// A refusal saying [message].
  const VersionError(this.message);

  /// What is wrong, in the original's words.
  final String message;

  @override
  String toString() => message;
}

final _channelName = RegExp(r'^[a-z][a-z0-9-]*$');

/// Refuses a name that cannot be a channel, which is an npm tag and a branch.
void checkChannel(String name) {
  if (!_channelName.hasMatch(name)) {
    throw VersionError(
      '$name is no channel name: a lower-case letter, then lower-case '
      'letters, digits and hyphens',
    );
  }
  if (isRangeName(name)) {
    throw VersionError(
      '$name is no channel name: npm refuses a tag that is a version range',
    );
  }
  if (name == 'latest') {
    throw const VersionError(
      "latest is no channel name: it would publish over npm's latest",
    );
  }
  if (name == 'main') {
    throw const VersionError(
      'main is no channel name: main is the stable branch',
    );
  }
}

/// The channel of [version], its first pre-release identifier; null for a
/// stable version. What is no version, or a pre-release not shaped
/// `<x.y.z>-<channel>.<n>`, throws: taken for stable, a mistyped label such
/// as `1.0.0-next.01` would go to main and publish with no tag.
String? channelOf(String version) {
  final normalised = valid(version);
  if (normalised == null) throw VersionError('$version is no version');
  final label = prerelease(version);
  if (label == null) return null;
  if (label case [final String channel, int _] when normalised == version) {
    checkChannel(channel);
    return channel;
  }
  throw VersionError(
    '$version is not a release of a channel: a pre-release is written '
    '<x.y.z>-<channel>.<n>',
  );
}
