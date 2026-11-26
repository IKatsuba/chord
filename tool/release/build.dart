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
import 'x64_sdk.dart';

/// The program every binary is compiled from, from the repository's root.
const entry = 'bin/chord.dart';

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
  /// The host's [dart] at [version], the x64 SDK kept under [cache] and
  /// downloaded with [fetch].
  const Sdks({
    required this.dart,
    required this.version,
    required this.cache,
    this.fetch = httpFetch,
  });

  /// The SDKs of this process: the Dart running it, and the x64 SDK kept in
  /// the user cache that [env] and [home] give.
  factory Sdks.of(Map<String, String> env, String home) => Sdks(
    dart: Platform.resolvedExecutable,
    version: Platform.version.split(' ').first,
    cache: userCache(env, home),
  );

  /// The host SDK's `dart`.
  final String dart;

  /// The host SDK's version, such as `3.13.5`.
  final String version;

  /// The user cache the x64 SDK is kept in, by version.
  final String cache;

  /// Downloads the x64 SDK and its checksum.
  final Fetch fetch;
}

/// What makes a binary the release's own (the owner's Q365): `chord upgrade`
/// reads `bool.fromEnvironment('chord.official')`, true only in what the
/// release compiles, never under `dart run`, a plain compile or CI's check.
const officialDefine = '--define=chord.official=true';

/// The command that compiles [target] into [binaryOf]'s path: the host SDK
/// for its own platform and for Linux, the x64 SDK's [x64Dart] under
/// Rosetta for Intel macOS, which only that target needs.
List<String> compileArgv(Target target, Sdks sdks, {String? x64Dart}) {
  final out = ['compile', 'exe', officialDefine, entry, '-o', binaryOf(target)];
  return switch ((target.os, target.cpu)) {
    ('darwin', 'arm64') => [sdks.dart, ...out],
    ('darwin', 'x64') => [
      'arch',
      '-x86_64',
      x64Dart ?? (throw ArgumentError.notNull('x64Dart')),
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

/// Every binary built, each checked to be the kind its target builds; the
/// x64 SDK is found or downloaded first, saying so through [out].
Future<void> compile(
  ReleaseRunner runner,
  Sdks sdks,
  String root,
  void Function(String line) out,
) async {
  final x64Dart = await provideX64Sdk(
    runner: runner,
    version: sdks.version,
    cache: sdks.cache,
    fetch: sdks.fetch,
    out: out,
  );
  for (final target in targets) {
    Directory(
      p.join(root, p.dirname(binaryOf(target))),
    ).createSync(recursive: true);
    final [command, ...args] = compileArgv(target, sdks, x64Dart: x64Dart);
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
