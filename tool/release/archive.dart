/// The release's archives, one per target, as the archive contract says
/// (docs/decisions.md): `chord-<os>-<cpu>.tar.gz` holding `chord` (0755),
/// `LICENSE` and `NOTICES` at the top, and SHA256SUMS beside them in
/// sha256sum's format, as the original's `sums.ts` records its tarballs.
/// Only a darwin binary that verifies and whose notarisation the release
/// recorded, and a Linux binary of its target's kind, is archived.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../targets.dart';
import 'build.dart';
import 'runner.dart';

/// The file the sums are recorded in.
const sums = 'SHA256SUMS';

/// Where the archives and their sums are written, from the root.
final archivesFolder = p.join('build', 'release', 'archives');

/// The members of every archive, in order.
const members = ['chord', 'LICENSE', 'NOTICES'];

/// The hex sha256 of the file at [path].
String sha256Of(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

/// Writes SHA256SUMS in [dir] for [files], each a name in [dir].
void recordSums(String dir, List<String> files) {
  File(p.join(dir, sums)).writeAsStringSync(
    files.map((file) => '${sha256Of(p.join(dir, file))}  $file\n').join(),
  );
}

final _sumLine = RegExp(r'^([0-9a-f]{64}) [ *](.+)$');

/// Stops unless SHA256SUMS beside [file] records its sum as it is.
void checkSum(String file) {
  final path = p.join(p.dirname(file), sums);
  final found = switch (File(path)) {
    final sumsFile when sumsFile.existsSync() => [
      for (final line in sumsFile.readAsLinesSync())
        if (_sumLine.firstMatch(line) case final match?
            when match[2] == p.basename(file))
          match[1]!,
    ],
    _ => const <String>[],
  };
  if (found.isEmpty) die('$path has no sum for $file');
  // Two sums for one name leave which was meant a guess.
  if (found.length > 1) die('$path records $file more than once');
  final recorded = found.single;
  final actual = sha256Of(file);
  if (actual != recorded) {
    die('$file has sha256 $actual; $sums recorded $recorded');
  }
}

/// Refuses [target]'s binary unless it may be shipped: of its kind, and for
/// darwin verifying under `codesign --verify --strict` and among
/// [notarised], the targets whose notarisation the release recorded.
Future<void> checkPackable(
  ReleaseRunner runner,
  Target target,
  Set<String> notarised,
) async {
  await checkKind(runner, target);
  if (target.os != 'darwin') return;
  final binary = binaryOf(target);
  final verified = await runner.run('codesign', [
    '--verify',
    '--strict',
    binary,
  ]);
  if (verified.status != 0) {
    die('$binary does not verify: ${said(verified.stderr)}');
  }
  if (!notarised.contains(target.name)) {
    die('$binary is not notarised: the release records no notarisation');
  }
}

/// Every target's archive and SHA256SUMS written into [archivesFolder] of
/// [root], NOTICES holding [notices]; nothing is written unless every
/// binary may be shipped.
Future<void> archive(
  ReleaseRunner runner,
  String root, {
  required String notices,
  required Set<String> notarised,
}) async {
  final licence = File(p.join(root, 'LICENSE'));
  if (!licence.existsSync()) {
    die('${licence.path} is missing: every archive carries the licence');
  }
  if (licence.readAsStringSync().trim().isEmpty) {
    die('${licence.path} is empty: every archive carries the licence');
  }
  if (notices.trim().isEmpty) {
    die('NOTICES is empty: every archive carries the notices');
  }
  for (final target in targets) {
    await checkPackable(runner, target, notarised);
  }

  final out = Directory(p.join(root, archivesFolder));
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);
  final staging = p.join('build', 'release', 'staging');
  TarFlavour? flavour;
  for (final target in targets) {
    final stage = p.join(staging, target.name);
    final at = Directory(p.join(root, stage));
    if (at.existsSync()) at.deleteSync(recursive: true);
    at.createSync(recursive: true);
    File(p.join(root, binaryOf(target))).copySync(p.join(at.path, 'chord'));
    licence.copySync(p.join(at.path, 'LICENSE'));
    File(p.join(at.path, 'NOTICES')).writeAsStringSync(notices);
    await _run(runner, 'chmod', ['755', p.join(stage, 'chord')]);
    await _run(runner, 'chmod', [
      '644',
      p.join(stage, 'LICENSE'),
      p.join(stage, 'NOTICES'),
    ]);
    // Asked once, at the first archive: a refused chmod runs no tar.
    flavour ??= await tarFlavourOf(runner);
    await _run(
      runner,
      'tar',
      tarArgs(flavour, p.join(archivesFolder, target.archive), stage),
    );
  }
  recordSums(out.path, [for (final target in targets) target.archive]);
}

/// The tar the host has: macOS ships bsdtar, Linux GNU tar, and they spell
/// the same archive with different flags.
enum TarFlavour {
  /// libarchive's bsdtar, macOS's tar.
  bsd,

  /// GNU tar, Linux's.
  gnu,
}

/// The flavour [version], the output of `tar --version`, names.
TarFlavour tarFlavourIn(String version) {
  if (version.startsWith('bsdtar ')) return TarFlavour.bsd;
  if (version.startsWith('tar (GNU tar) ')) return TarFlavour.gnu;
  die('tar is neither bsdtar nor GNU tar: ${said(version)}');
}

/// The host tar's flavour, asked through [runner].
Future<TarFlavour> tarFlavourOf(ReleaseRunner runner) async {
  final ran = await runner.run('tar', ['--version']);
  if (ran.status != 0) die('tar --version failed: ${said(ran.stderr)}');
  return tarFlavourIn(ran.stdout);
}

/// The tar arguments that write [archive] from [members] in [stage], the
/// same archive for either [flavour]: ustar members owned by root (0:0),
/// with no pax header and no extended attribute.
List<String> tarArgs(TarFlavour flavour, String archive, String stage) => [
  ...switch (flavour) {
    // No owner of this machine and no macOS metadata in what is shipped:
    // without --no-xattrs bsdtar gives each member a pax header carrying
    // com.apple.provenance, as npm pack's tarballs never do.
    TarFlavour.bsd => [
      '--uid',
      '0',
      '--gid',
      '0',
      '--uname',
      'root',
      '--gname',
      'root',
      '--no-mac-metadata',
      '--no-xattrs',
    ],
    // GNU tar has no --uid or --no-mac-metadata; NAME:ID sets both, and
    // ustar keeps out the GNU long-name and pax headers.
    TarFlavour.gnu => [
      '--owner=root:0',
      '--group=root:0',
      '--format=ustar',
      '--no-xattrs',
    ],
  },
  '-czf',
  archive,
  '-C',
  stage,
  ...members,
];

Future<void> _run(
  ReleaseRunner runner,
  String command,
  List<String> args,
) async {
  final ran = await runner.run(command, args);
  if (ran.status != 0) {
    die('$command ${args.join(' ')} failed: ${said(ran.stderr)}');
  }
}
