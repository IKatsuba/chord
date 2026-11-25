/// The release's pack stage, as the original's `scripts/dev/release/
/// pack.ts`, and the gate the design adds before it (critic 4): only the
/// bytes notarise recorded go out. Each darwin binary must have the sha256
/// recorded when it was notarised and still verify; then the archives and
/// SHA256SUMS, NOTICES, the five npm packages packed into build/release/tgz
/// with their sums, the installed copies checked as a person gets them
/// (the same bytes as built, a macOS one still verifying and not
/// quarantined, self-tested through the shim and the x64 one under
/// Rosetta), and, for a stable version, the Homebrew formula. The
/// original's source archives are not fetched: the draft carries none.
library;

import 'dart:io';

import 'package:chord/channel.dart';
import 'package:path/path.dart' as p;

import '../formula.dart';
import '../npm.dart';
import '../targets.dart';
import 'archive.dart';
import 'build.dart';
import 'runner.dart';

/// Where the npm tarballs and their sums are written, from the root.
final tgzFolder = p.join('build', 'release', 'tgz');

/// The tarball `npm pack` makes of [package] at [version].
String tarballName(String package, String version) =>
    '${package.replaceFirst('@', '').replaceFirst('/', '-')}-$version.tgz';

/// The darwin binaries, from the root.
final darwinBinaries = [
  for (final target in targets)
    if (target.os == 'darwin') binaryOf(target),
];

/// What pack leaves for publish and the draft, from the root: the
/// tarballs, the archives and both SHA256SUMS.
List<String> packOutputs(String version, List<String> npmNames) => [
  for (final name in npmNames) p.join(tgzFolder, tarballName(name, version)),
  p.join(tgzFolder, sums),
  for (final target in targets) p.join(archivesFolder, target.archive),
  p.join(archivesFolder, sums),
];

/// Refuses to pack unless each darwin binary is the one notarised: its
/// sha256 is what [notarised] (path to sha256, as notarise recorded it)
/// holds, and it still verifies.
Future<void> checkNotarised(
  ReleaseRunner runner,
  String root,
  Map<String, String> notarised,
) async {
  for (final binary in darwinBinaries) {
    final recorded =
        notarised[binary] ??
        die('$binary has no notarisation recorded; run notarise first');
    final now = sha256Of(p.join(root, binary));
    if (now != recorded) {
      die(
        '$binary is not the binary notarised: its sha256 is $now, notarise '
        'recorded $recorded',
      );
    }
  }
}

/// Packs [version] in [root]: see the library's words. [npmNames] are the
/// packages in publish order, the main one last; [selftest] self-tests an
/// installed binary (absolute), under [arch] if given; [notices] is read
/// only once the gate has passed.
Future<void> pack(
  ReleaseRunner runner,
  String root, {
  required String version,
  required List<String> npmNames,
  required String Function() notices,
  required Map<String, String> notarised,
  required Future<void> Function(String binary, String? arch) selftest,
  required void Function(String line) out,
}) async {
  await checkNotarised(runner, root, notarised);
  final text = notices();
  await archive(
    runner,
    root,
    notices: text,
    notarised: {
      for (final target in targets)
        if (target.os == 'darwin') target.name,
    },
  );
  await layOutNpm(runner, root, version: version, notices: text);

  final tgz = Directory(p.join(root, tgzFolder));
  if (tgz.existsSync()) tgz.deleteSync(recursive: true);
  tgz.createSync(recursive: true);
  for (final name in npmNames) {
    final folder = p.join(npmFolder, name.split('/').last);
    final packed = await runner.run('npm', [
      'pack',
      '--pack-destination',
      tgz.path,
    ], cwd: folder);
    if (packed.status != 0) die('npm pack of ${name.split('/').last} failed');
  }

  await _installed(
    runner,
    root,
    version: version,
    npmNames: npmNames,
    selftest: selftest,
  );
  recordSums(tgz.path, [
    for (final name in npmNames) tarballName(name, version),
  ]);
  if (channelOf(version) == null) {
    writeFormula(root, version);
  } else {
    // An earlier stable pack's formula is not this release's.
    final stale = File(p.join(root, formulaPath));
    if (stale.existsSync()) stale.deleteSync();
  }
  out('packed ${tgz.path}');
}

/// The tarballs installed in scratch projects and checked as a person gets
/// them. npm refuses a package for another platform unless forced past its
/// os and cpu check, which changes nothing in it, so each other platform
/// package goes into a project of its own.
Future<void> _installed(
  ReleaseRunner runner,
  String root, {
  required String version,
  required List<String> npmNames,
  required Future<void> Function(String binary, String? arch) selftest,
}) async {
  String tgz(String name) =>
      p.join(root, tgzFolder, tarballName(name, version));
  final main = npmNames.last;
  final host = targets.first; // darwin-arm64, this arm64 Mac's
  final scratch = Directory.systemTemp.createTempSync('chord-packages-');
  try {
    Future<bool> install(String cwd, List<String> args) async =>
        (await runner.run('npm', ['init', '-y'], cwd: cwd)).status == 0 &&
        (await runner.run('npm', [
              'install',
              '--no-audit',
              '--no-fund',
              ...args,
            ], cwd: cwd)).status ==
            0;

    if (!await install(scratch.path, [tgz(main), tgz(host.package)])) {
      die('installing the tarballs failed');
    }
    final others = [for (final target in targets.skip(1)) target];
    for (final target in others) {
      final dir = p.join(scratch.path, target.package.split('/').last);
      Directory(dir).createSync();
      if (!await install(dir, ['--force', tgz(target.package)])) {
        die('installing the ${target.package.split('/').last} tarball failed');
      }
    }

    Future<void> check(String installed, Target target) async {
      final built = p.join(root, binaryOf(target));
      if (sha256Of(installed) != sha256Of(built)) {
        die('the installed $installed differs from $built');
      }
      if (target.os != 'darwin') return;
      if ((await runner.run('codesign', [
            '--verify',
            '--strict',
            installed,
          ], loud: true)).status !=
          0) {
        die('the installed $installed does not verify');
      }
      final attributes = await runner.run('xattr', [installed]);
      if (attributes.status != 0) {
        die('xattr $installed failed: ${said(attributes.stderr)}');
      }
      if (attributes.stdout.contains('com.apple.quarantine')) {
        die('npm quarantined $installed');
      }
    }

    // The package's own name is its folder under node_modules.
    String installedIn(String dir, Target target) => p.joinAll([
      dir,
      'node_modules',
      ...target.package.split('/'),
      'bin',
      'chord',
    ]);
    await check(installedIn(scratch.path, host), host);
    for (final target in others) {
      await check(
        installedIn(
          p.join(scratch.path, target.package.split('/').last),
          target,
        ),
        target,
      );
    }
    await selftest(p.join(scratch.path, 'node_modules', '.bin', 'chord'), null);
    final x64 = targets.firstWhere((t) => t.name == 'darwin-x64');
    await selftest(
      installedIn(p.join(scratch.path, x64.package.split('/').last), x64),
      'x86_64',
    );
  } finally {
    scratch.deleteSync(recursive: true);
  }
}
