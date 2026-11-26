@Tags(['compile'])
library;

import 'dart:io';

import 'package:chord/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/build.dart';
import '../../../tool/release/runner.dart';
import '../../../tool/targets.dart';

/// The repository's root; the builds go to its ignored build/release/.
final root = p.normalize(p.absolute('.'));

final runner = ProcessReleaseRunner(root: root, env: Platform.environment);

final sdks = Sdks.of(const {}, '');

final hostIsArmMac =
    Platform.isMacOS && Platform.version.contains('macos_arm64');

Future<void> build(Target target) async {
  final [command, ...args] = compileArgv(target, sdks);
  final folder = Directory(p.join(root, p.dirname(binaryOf(target))));
  // The test owns this target's output, and removes it even on failure.
  addTearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });
  folder.createSync(recursive: true);
  final ran = await runner.run(command, args);
  expect(ran.status, 0, reason: '${ran.stdout}${ran.stderr}');
  await checkKind(runner, target);
}

Target named(String name) => targets.firstWhere((t) => t.name == name);

void main() {
  for (final name in ['linux-x64', 'linux-arm64']) {
    test('$name is built and of its kind', () async {
      await build(named(name));
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  test('darwin-arm64 is built, of its kind, and runs signed with the hardened '
      "runtime and chord's entitlements", () async {
    // In the body: the compile tag runs with --run-skipped, which
    // overrides skip:, and codesign and a darwin-arm64 run need that Mac.
    if (!hostIsArmMac) {
      markTestSkipped('builds darwin-arm64 only on an arm64 Mac');
      return;
    }
    final target = named('darwin-arm64');
    await build(target);
    final temp = Directory.systemTemp.createTempSync('build_compile');
    addTearDown(() => temp.deleteSync(recursive: true));
    final signed = p.join(temp.path, 'chord');
    File(p.join(root, binaryOf(target))).copySync(signed);
    final sign = await Process.run('codesign', [
      '--sign',
      '-',
      '--force',
      '--options',
      'runtime',
      '--entitlements',
      p.join(root, 'tool/macos/chord.entitlements'),
      signed,
    ]);
    expect(sign.exitCode, 0, reason: '${sign.stderr}');
    // Without allow-unsigned-executable-memory the kernel kills it here.
    final ran = await Process.run(signed, ['--version']);
    expect((ran.exitCode, ran.stdout), (0, 'chord $version\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
