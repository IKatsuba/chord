/// The release's binaries, as the original's `scripts/dev/release/build.ts`
/// compile stage: every target built on this arm64 Mac, each checked to be
/// the kind its target builds. Dart cross-compiles to Linux but not to Intel
/// macOS, so darwin-x64 is built by an x64 Dart SDK of the same version
/// under Rosetta (the owner's Q362).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../targets.dart';
import 'runner.dart';

/// The program every binary is compiled from, from the repository's root.
const entry = 'bin/chord.dart';

/// The variable naming the x64 SDK's `bin/dart`.
const x64DartVariable = 'CHORD_DART_X64';

/// Where Dart's SDK archives are listed.
const sdkArchive = 'https://dart.dev/get-dart/archive';

/// The binary of [target], from the repository's root.
String binaryOf(Target target) =>
    p.join('build', 'release', target.name, 'chord');

/// What file(1) says each target's binary is.
const kinds = {
  'darwin-arm64': 'Mach-O 64-bit executable arm64',
  'darwin-x64': 'Mach-O 64-bit executable x86_64',
  'linux-x64': 'ELF 64-bit LSB pie executable, x86-64',
  'linux-arm64': 'ELF 64-bit LSB pie executable, ARM aarch64',
};

/// The Dart SDKs a build compiles with.
final class Sdks {
  /// The host's [dart] at [version], and the x64 SDK's [x64Dart] if named.
  const Sdks({required this.dart, required this.version, this.x64Dart});

  /// The SDKs of this process: the Dart running it, and the x64 SDK [env]
  /// names in [x64DartVariable].
  factory Sdks.of(Map<String, String> env) => Sdks(
    dart: Platform.resolvedExecutable,
    version: Platform.version.split(' ').first,
    x64Dart: switch (env[x64DartVariable]) {
      final path? when path.isNotEmpty => path,
      _ => null,
    },
  );

  /// The host SDK's `dart`.
  final String dart;

  /// The host SDK's version, such as `3.13.5`.
  final String version;

  /// The x64 SDK's `bin/dart`, run under Rosetta; null when not named.
  final String? x64Dart;
}

/// What makes a binary the release's own (the owner's Q365): `chord upgrade`
/// reads `bool.fromEnvironment('chord.official')`, true only in what the
/// release compiles, never under `dart run`, a plain compile or CI's check.
const officialDefine = '--define=chord.official=true';

/// The command that compiles [target] into [binaryOf]'s path: the host SDK
/// for its own platform and for Linux, the x64 SDK under Rosetta for Intel
/// macOS.
List<String> compileArgv(Target target, Sdks sdks) {
  final out = ['compile', 'exe', officialDefine, entry, '-o', binaryOf(target)];
  return switch ((target.os, target.cpu)) {
    ('darwin', 'arm64') => [sdks.dart, ...out],
    ('darwin', 'x64') => [
      'arch',
      '-x86_64',
      sdks.x64Dart ?? _noX64(sdks),
      ...out,
    ],
    _ => [
      sdks.dart,
      'compile',
      'exe',
      '--target-os=${target.dartOs}',
      '--target-arch=${target.dartArch}',
      officialDefine,
      entry,
      '-o',
      binaryOf(target),
    ],
  };
}

Never _noX64(Sdks sdks) => die(
  '$x64DartVariable is not set: darwin-x64 is built by the x64 Dart SDK '
  '${sdks.version} under Rosetta; download dartsdk-macos-x64-release.zip '
  'of ${sdks.version} from $sdkArchive and set $x64DartVariable to its '
  'bin/dart',
);

final _sdkVersion = RegExp(r'Dart SDK version: (\S+)');

/// Refuses an x64 SDK that is missing, does not run under Rosetta, or is
/// not the host SDK's version.
Future<void> checkX64Sdk(ReleaseRunner runner, Sdks sdks) async {
  final x64 = sdks.x64Dart ?? _noX64(sdks);
  final ran = await runner.run('arch', ['-x86_64', x64, '--version']);
  if (ran.status != 0) {
    die('arch -x86_64 $x64 --version failed: ${said(ran.stderr)}');
  }
  final version = _sdkVersion.firstMatch('${ran.stdout}${ran.stderr}');
  if (version?.group(1) != sdks.version) {
    die(
      '$x64 is Dart ${version?.group(1) ?? 'of no version it says'}, not '
      '${sdks.version}: darwin-x64 is built by the same SDK as the rest',
    );
  }
}

/// Every binary built, each checked to be the kind its target builds.
Future<void> compile(ReleaseRunner runner, Sdks sdks, String root) async {
  await checkX64Sdk(runner, sdks);
  for (final target in targets) {
    Directory(
      p.join(root, p.dirname(binaryOf(target))),
    ).createSync(recursive: true);
    final [command, ...args] = compileArgv(target, sdks);
    if ((await runner.run(command, args, loud: true)).status != 0) {
      die('compile of $target failed');
    }
  }
  for (final target in targets) {
    await checkKind(runner, target);
  }
}

/// Refuses [target]'s binary unless file(1) says it is [kinds]' kind.
Future<void> checkKind(ReleaseRunner runner, Target target) async {
  final binary = binaryOf(target);
  final ran = await runner.run('file', [binary]);
  // A failed file(1) certifies nothing, whatever it printed.
  if (ran.status != 0) die('file $binary failed: ${said(ran.stderr)}');
  final kind = said(ran.stdout);
  if (!kind.contains(kinds[target.name]!)) die('$binary is $kind');
}
