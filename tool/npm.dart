/// Lays out the npm packages from the release's binaries, as the original's
/// `scripts/dev/npm.ts`, the way esbuild and biome ship native code: one
/// package per platform carrying the binary, with `os` and `cpu` so npm
/// installs only the matching one, and `@chorded/chord` depending on all of
/// them optionally and holding a small Node shim as its `bin`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:chord/distribution.dart';
import 'package:path/path.dart' as p;

import 'release/build.dart';
import 'release/runner.dart';
import 'targets.dart';

/// Where the packages are laid out, from the root.
final npmFolder = p.join('build', 'release', 'npm');

/// The `chord` command npm installs, the original's shim as it is.
const shim =
    '''#!/usr/bin/env node
// The `chord` command npm installs: it runs the binary of this machine's
// platform package with the same arguments and stdio, and leaves as the
// binary left. A Node script, because npm runs `bin` with the user's Node
// and the user need not have Bun.
const { spawn } = require("node:child_process");

const pkg = `$npmScope/chord-\${process.platform}-\${process.arch}`;
let bin;
try {
  bin = require.resolve(`\${pkg}/bin/chord`);
} catch {
  process.stderr.write(
    `chord: no \${pkg} is installed. chord runs on macOS and Linux, arm64 and x64; reinstall $npmPackage on one of those, with optional dependencies.\\n`,
  );
  process.exit(1);
}

// spawn, not spawnSync: a blocked event loop cannot forward a signal, and a
// SIGTERM to this process alone would leave the binary running.
const child = spawn(bin, process.argv.slice(2), { stdio: "inherit" });
const forwarded = ["SIGINT", "SIGTERM", "SIGHUP"];
for (const signal of forwarded) {
  process.on(signal, () => child.kill(signal));
}
child.on("error", (error) => {
  process.stderr.write(`chord: \${bin} did not start: \${error.message}\\n`);
  process.exit(1);
});
child.on("exit", (status, signal) => {
  if (signal) {
    // Re-raise the child's signal, so a chord ended by one still ends by it
    // as the shell sees it; the handlers go first, or they would catch it.
    for (const name of forwarded) process.removeAllListeners(name);
    process.kill(process.pid, signal);
    return;
  }
  process.exit(status ?? 1);
});
''';

Map<String, Object?> _common(String version) => {
  'version': version,
  'license': npmLicense,
  'repository': {
    'type': 'git',
    'url': 'git+https://github.com/$githubRepo.git',
  },
  'homepage': 'https://github.com/$githubRepo#readme',
  'bugs': {'url': 'https://github.com/$githubRepo/issues'},
};

/// The package.json of [target]'s platform package at [version].
Map<String, Object?> platformManifest(Target target, String version) => {
  'name': target.package,
  ..._common(version),
  'description': 'The chord binary for ${target.name}.',
  'os': [target.os],
  'cpu': [target.cpu],
  'files': ['bin/', 'NOTICES'],
};

/// The package.json of the main package at [version].
Map<String, Object?> mainManifest(String version) => {
  'name': npmPackage,
  ..._common(version),
  'description': 'A full-screen terminal client for ACP coding agents.',
  'keywords': [
    'acp',
    'agent-client-protocol',
    'claude-code',
    'codex',
    'gemini-cli',
    'coding-agent',
    'terminal',
    'tui',
  ],
  'bin': {'chord': 'bin/chord.js'},
  'files': ['bin/'],
  'optionalDependencies': {
    for (final target in targets) target.package: version,
  },
};

/// [value] as the original writes it: two spaces, a final newline.
String manifestText(Map<String, Object?> value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

/// Writes [npmFolder] in [root] from the binaries in build/release/ at
/// [version], each platform package with LICENSE and [notices]; stops on a
/// missing binary or LICENSE before writing anything.
Future<void> layOutNpm(
  ReleaseRunner runner,
  String root, {
  required String version,
  required String notices,
}) async {
  final missing = [
    for (final target in targets)
      if (!File(p.join(root, binaryOf(target))).existsSync())
        p.join(root, binaryOf(target)),
  ];
  if (missing.isNotEmpty) {
    die('Missing binaries; build them first:\n${missing.join('\n')}');
  }
  final licence = File(p.join(root, 'LICENSE'));
  if (!licence.existsSync()) {
    die('${licence.path} is missing: every package carries the licence');
  }
  if (licence.readAsStringSync().trim().isEmpty) {
    die('${licence.path} is empty: every package carries the licence');
  }
  if (notices.trim().isEmpty) {
    die('NOTICES is empty: every platform package carries the notices');
  }

  final out = Directory(p.join(root, npmFolder));
  if (out.existsSync()) out.deleteSync(recursive: true);

  for (final target in targets) {
    final dir = p.join(
      npmFolder,
      target.package.replaceFirst('$npmScope/', ''),
    );
    Directory(p.join(root, dir, 'bin')).createSync(recursive: true);
    File(
      p.join(root, binaryOf(target)),
    ).copySync(p.join(root, dir, 'bin', 'chord'));
    await _chmod(runner, '755', p.join(dir, 'bin', 'chord'));
    licence.copySync(p.join(root, dir, 'LICENSE'));
    File(p.join(root, dir, 'NOTICES')).writeAsStringSync(notices);
    File(
      p.join(root, dir, 'package.json'),
    ).writeAsStringSync(manifestText(platformManifest(target, version)));
  }

  final main = p.join(npmFolder, 'chord');
  Directory(p.join(root, main, 'bin')).createSync(recursive: true);
  File(p.join(root, 'README.md')).copySync(p.join(root, main, 'README.md'));
  licence.copySync(p.join(root, main, 'LICENSE'));
  File(p.join(root, main, 'bin', 'chord.js')).writeAsStringSync(shim);
  await _chmod(runner, '755', p.join(main, 'bin', 'chord.js'));
  File(
    p.join(root, main, 'package.json'),
  ).writeAsStringSync(manifestText(mainManifest(version)));
}

Future<void> _chmod(ReleaseRunner runner, String mode, String path) async {
  final ran = await runner.run('chmod', [mode, path]);
  if (ran.status != 0) die('chmod $mode $path failed: ${said(ran.stderr)}');
}
