/// Where the release finds the x64 Dart SDK that builds darwin-x64 under
/// Rosetta (docs/decisions.md, CHD-635): the Dart archive's zip of the
/// running Dart's version and channel, checked against the `.sha256sum`
/// published beside it, kept in the user cache by version.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
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

/// Reads [url]'s body whole; throws, or dies, when it cannot.
typedef Fetch = Future<List<int>> Function(Uri url);

/// The release's [Fetch]: an HTTPS GET that dies unless it answers 200.
Future<List<int>> httpFetch(Uri url) async {
  final client = http.Client();
  try {
    final response = await client.get(url);
    if (response.statusCode != 200) {
      die('$url answered ${response.statusCode}');
    }
    return response.bodyBytes;
  } finally {
    client.close();
  }
}

final _sdkVersion = RegExp(r'Dart SDK version: (\S+)');

/// The version [dart] says under Rosetta, or null when it says none; dies
/// when it does not run there, which no download mends.
Future<String?> x64VersionOf(ReleaseRunner runner, String dart) async {
  final ran = await runner.run('arch', ['-x86_64', dart, '--version']);
  if (ran.status != 0) {
    die('arch -x86_64 $dart --version failed: ${said(ran.stderr)}');
  }
  return _sdkVersion.firstMatch('${ran.stdout}${ran.stderr}')?.group(1);
}

/// Why [dart], which says [said], is not the x64 SDK of [version].
String otherVersion(String dart, String? said, String version) =>
    '$dart is Dart ${said ?? 'of no version it says'}, not $version: '
    'darwin-x64 is built by the same SDK as the rest';

/// The x64 SDK's `dart` at [version], kept under [cache]. A kept SDK passed
/// both checks when it was kept: one that no longer runs under Rosetta is
/// refused, as a download would fail the same way; one that says another
/// version was damaged, and is downloaded again. A download goes through
/// [fetch], is checked against its published sha256, unzipped by `ditto`
/// into a folder of this call's own beside the cache folder, and renamed
/// into place only once its `dart` passes [x64VersionOf] at [version].
/// Releases in other checkouts share the cache: no call touches a folder
/// it did not make, and when another has kept the SDK first, that one is
/// checked and taken. What it downloads, and where to, is said through
/// [out].
Future<String> provideX64Sdk({
  required ReleaseRunner runner,
  required String version,
  required String cache,
  required Fetch fetch,
  required void Function(String line) out,
}) async {
  final folder = sdkFolder(cache, version);
  final keptFolder = Directory(folder);
  final damaged = keptFolder.existsSync();
  if (damaged) {
    final dart = sdkDart(folder);
    final kept = await x64VersionOf(runner, dart);
    if (kept == version) return dart;
    out(
      'The kept x64 Dart SDK is damaged (${otherVersion(dart, kept, version)}); '
      'downloading it again.',
    );
  }
  final zipUrl = sdkZipUrl(version);
  // A name of its own: what an interrupted or concurrent run is staging is
  // never reused, and never removed by this one.
  final parent = Directory(p.dirname(folder))..createSync(recursive: true);
  final partial = parent.createTempSync('${p.basename(folder)}.partial-');
  try {
    out('Downloading the x64 Dart SDK $version from $zipUrl into $folder');
    final sum = checksumOf(
      utf8.decode(
        await _fetched(fetch, sdkChecksumUrl(version)),
        allowMalformed: true,
      ),
    );
    final zip = await _fetched(fetch, zipUrl);
    final got = sha256.convert(zip).toString();
    if (got != sum) {
      die(
        '$sdkZipName of $version has sha256 $got, not the published $sum: '
        'nothing is kept',
      );
    }
    final zipFile = File(p.join(partial.path, sdkZipName))
      ..writeAsBytesSync(zip);
    final unzipped = await runner.run('ditto', [
      '-x',
      '-k',
      zipFile.path,
      partial.path,
    ]);
    if (unzipped.status != 0) {
      die('ditto -x -k ${zipFile.path} failed: ${said(unzipped.stderr)}');
    }
    final sdk = p.join(partial.path, 'dart-sdk');
    final fresh = await x64VersionOf(runner, sdkDart(sdk));
    if (fresh != version) die(otherVersion(sdkDart(sdk), fresh, version));
    if (damaged && keptFolder.existsSync()) {
      keptFolder.deleteSync(recursive: true);
    }
    if (!keptFolder.existsSync()) {
      try {
        Directory(sdk).renameSync(folder);
        return sdkDart(folder);
      } on FileSystemException catch (error) {
        if (!keptFolder.existsSync()) {
          die('cannot move the x64 Dart SDK into $folder: ${error.message}');
        }
      }
    }
    out('Another run kept the x64 Dart SDK in $folder first; taking it.');
    final theirs = await x64VersionOf(runner, sdkDart(folder));
    if (theirs != version) die(otherVersion(sdkDart(folder), theirs, version));
    return sdkDart(folder);
  } finally {
    if (partial.existsSync()) partial.deleteSync(recursive: true);
  }
}

Future<List<int>> _fetched(Fetch fetch, String url) async {
  try {
    return await fetch(Uri.parse(url));
  } on ReleaseError catch (error) {
    die('download of $url failed: ${error.message}');
  } on Object catch (error) {
    die('download of $url failed: $error');
  }
}
