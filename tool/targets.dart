/// Every platform chord ships a binary for, as the original's
/// `scripts/targets.ts`: `os` and `cpu` as npm's `os` and `cpu` fields spell
/// them, so the shim finds the package installed beside it from
/// `process.platform` and `process.arch` alone; `dartOs` and `dartArch` as
/// `dart compile exe --target-os` and `--target-arch` take them.
library;

import 'package:chord/distribution.dart';

/// One platform a binary is built for.
final class Target {
  /// The platform [os]/[cpu], built by Dart as [dartOs]/[dartArch].
  const Target({
    required this.os,
    required this.cpu,
    required this.dartOs,
    required this.dartArch,
  });

  /// npm's `os`: `darwin` or `linux`.
  final String os;

  /// npm's `cpu`: `arm64` or `x64`.
  final String cpu;

  /// Dart's target OS: `macos` or `linux`.
  final String dartOs;

  /// Dart's target architecture: `arm64` or `x64`.
  final String dartArch;

  /// `<os>-<cpu>`, the archive's and the build folder's name.
  String get name => '$os-$cpu';

  /// The npm package holding this target's binary.
  String get package => platformPackage(os, cpu);

  /// The archive of this target on a release.
  String get archive => 'chord-$name.tar.gz';

  @override
  String toString() => name;
}

/// Every target, in the original's order.
const targets = [
  Target(os: 'darwin', cpu: 'arm64', dartOs: 'macos', dartArch: 'arm64'),
  Target(os: 'darwin', cpu: 'x64', dartOs: 'macos', dartArch: 'x64'),
  Target(os: 'linux', cpu: 'x64', dartOs: 'linux', dartArch: 'x64'),
  Target(os: 'linux', cpu: 'arm64', dartOs: 'linux', dartArch: 'arm64'),
];
