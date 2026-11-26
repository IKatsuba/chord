/// Where the release finds the x64 Dart SDK that builds darwin-x64 under
/// Rosetta (docs/decisions.md, CHD-635): the Dart archive's zip of the
/// running Dart's version and channel, checked against the `.sha256sum`
/// published beside it, kept in the user cache by version.
library;

import 'package:path/path.dart' as p;

import 'runner.dart';

/// The Dart archive's channel of [version]: `stable` for a plain release,
/// `beta` or `dev` as its prerelease says; dies on any other, which the
/// archive does not publish.
String channelOf(String version) {
  final match = RegExp(
    r'^\d+\.\d+\.\d+(?:-\d+\.\d+\.(beta|dev))?$',
  ).firstMatch(version);
  if (match == null) {
    die(
      'Dart $version is of no channel the Dart archive publishes '
      '(stable, beta or dev): the x64 SDK cannot be downloaded for it',
    );
  }
  return match.group(1) ?? 'stable';
}

/// The Dart archive's zip of the x64 macOS SDK at [version].
String sdkZipUrl(String version) =>
    'https://storage.googleapis.com/dart-archive/channels/'
    '${channelOf(version)}/release/$version/sdk/$sdkZipName';

/// The checksum the Dart archive publishes beside [sdkZipUrl].
String sdkChecksumUrl(String version) => '${sdkZipUrl(version)}.sha256sum';

/// The zip's file name, as the archive and its checksum name it.
const sdkZipName = 'dartsdk-macos-x64-release.zip';

/// The user cache: `$XDG_CACHE_HOME` when set, else macOS's
/// `~/Library/Caches` under [home].
String userCache(Map<String, String> env, String home) =>
    switch (env['XDG_CACHE_HOME']) {
      final cache? when cache.isNotEmpty => cache,
      _ => p.join(home, 'Library', 'Caches'),
    };

/// The folder the x64 SDK at [version] is kept in, under [cache].
String sdkFolder(String cache, String version) =>
    p.join(cache, 'chord-release', 'dart-sdk', version, 'macos-x64');

/// The kept SDK's `dart` in [folder].
String sdkDart(String folder) => p.join(folder, 'bin', 'dart');

/// The lowercase sha256 a `.sha256sum` file says for [sdkZipName]: a
/// `<hex> *<name>` or `<hex>  <name>` line, as sha256sum(1) writes it.
/// Dies when it names another file or no hash.
String checksumOf(String sum) {
  final match = RegExp(
    r'^([0-9a-fA-F]{64}) [ *](\S+)\s*$',
  ).firstMatch(sum.trim());
  if (match == null) die('the SDK checksum says no sha256: ${said(sum)}');
  if (match.group(2) != sdkZipName) {
    die('the SDK checksum is of ${match.group(2)}, not $sdkZipName');
  }
  return match.group(1)!.toLowerCase();
}
