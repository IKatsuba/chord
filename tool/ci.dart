/// The CI check of one target (docs/design/CTUI-102.md, U8; CTUI-146): on
/// its own native runner the binary compiled, checked to be its target's
/// kind, and run for `--version`; a Linux target on a Linux runner of
/// another CPU cross-compiled and checked to be its kind, not run. It
/// releases nothing: its runner lets through only dart, file and tar, and
/// the binary it built, and fails on anything else, so the workflow cannot
/// reach a signing, a registry or a release.
///
///     dart run tool/ci.dart <os>-<cpu>
library;

import 'dart:io';

import 'package:chord/version.dart';
import 'package:path/path.dart' as p;

import 'release/build.dart';
import 'release/runner.dart';
import 'targets.dart';

/// The commands a CI check may run, besides the binary it built.
const ciCommands = {'dart', 'file', 'tar'};

/// A runner that runs only [ciCommands] and [binary] through [inner].
final class CiRunner implements ReleaseRunner {
  /// Lets [inner] run [ciCommands] and [binary], and nothing else.
  const CiRunner(this.inner, {required this.binary});

  /// The runner that runs what is let through.
  final ReleaseRunner inner;

  /// The built binary, by its absolute path.
  final String binary;

  void _check(String command) {
    if (command != binary && !ciCommands.contains(p.basename(command))) {
      die('CI runs only ${ciCommands.join(', ')} and $binary, not $command');
    }
  }

  @override
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    _check(command);
    return inner.run(command, args, loud: loud, cwd: cwd, env: env);
  }

  @override
  Future<Started> start(
    String command,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    _check(command);
    return inner.start(command, args, cwd: cwd, env: env);
  }
}

/// The target this machine is, from the running Dart's platform such as
/// `macos_arm64`.
Target hostTarget(String platformVersion) {
  final platform = RegExp(r'on "(\w+)_(\w+)"').firstMatch(platformVersion);
  return targets.firstWhere(
    (t) => t.dartOs == platform?[1] && t.dartArch == platform?[2],
    orElse: () => die('no target is $platformVersion'),
  );
}

/// Checks [target]: on its own runner compiled natively with [dart], of its
/// kind, and saying [version]; a Linux target on a Linux [host] of another
/// CPU cross-compiled, of its kind, and not run, as Dart cross-compiles to
/// Linux alone.
Future<void> check(
  ReleaseRunner runner,
  Target target, {
  required Target host,
  required String dart,
  required String root,
  required void Function(String line) report,
}) async {
  final native = target.name == host.name;
  if (!native && (target.os != 'linux' || host.os != 'linux')) {
    die('$target is checked on its own runner, not on $host');
  }
  final binary = binaryOf(target);
  Directory(p.join(root, p.dirname(binary))).createSync(recursive: true);
  final built = await runner.run(dart, [
    'compile',
    'exe',
    if (!native) ...[
      '--target-os=${target.dartOs}',
      '--target-arch=${target.dartArch}',
    ],
    entry,
    '-o',
    binary,
  ], loud: true);
  if (built.status != 0) die('compile of $target failed');
  await checkKind(runner, target);
  if (!native) {
    report('$target: ${kinds[target.name]}, cross-compiled on $host, not run');
    return;
  }
  // By its absolute path: a relative one is not looked up from the root.
  final shown = await runner.run(p.join(root, binary), ['--version']);
  if (shown.status != 0 || said(shown.stdout) != 'chord $version') {
    die('$binary --version said ${said(shown.stdout + shown.stderr)}');
  }
  report('$target: ${kinds[target.name]}, chord $version');
}

Future<void> main(List<String> args) async {
  try {
    if (args.length != 1) {
      die('usage: dart run tool/ci.dart <os>-<cpu>');
    }
    final target = targets.firstWhere(
      (t) => t.name == args.single,
      orElse: () => die('no target ${args.single}; the targets are $targets'),
    );
    final root = p.normalize(
      p.join(p.dirname(Platform.script.toFilePath()), '..'),
    );
    await check(
      CiRunner(
        ProcessReleaseRunner(root: root, env: Platform.environment),
        binary: p.join(root, binaryOf(target)),
      ),
      target,
      host: hostTarget(Platform.version),
      dart: Platform.resolvedExecutable,
      root: root,
      report: print,
    );
  } on ReleaseError catch (error) {
    stderr.writeln('ci: $error');
    exitCode = 1;
  }
}
