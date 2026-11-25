/// chord's release stages, as the original's steps.ts lists them and its
/// `scripts/dev/release/stages.ts` runs them: each with what it does, the
/// machine it needs, what it needs ready before the build, whether it puts
/// the version into what is published, and what it leaves for later ones.
/// The original's natives stage has no counterpart: a Dart binary embeds no
/// library.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../targets.dart';
import 'archive.dart';
import 'build.dart';
import 'cli.dart';
import 'notarise.dart';
import 'notices.dart';
import 'pack.dart';
import 'preflight.dart';
import 'runner.dart';
import 'selftest.dart';
import 'sign.dart';

/// Where a release runs and what it reaches outside itself, so a test runs
/// one against a scratch tree, a recording runner and no waiting.
final class Release {
  /// A release of the tree at [root], its commands through [runner].
  Release({
    required this.root,
    required this.runner,
    required this.out,
    required this.err,
    required this.sleep,
    required this.tty,
    required this.home,
    required this.sdks,
    required this.sdkDir,
    required this.fake,
    required this.platform,
    List<Stage>? stages,
    this.env = const {},
  }) : stages = stages ?? chordStages;

  /// The repository's root.
  final String root;

  /// Every external command goes through it.
  final ReleaseRunner runner;

  /// Says a line on stdout.
  final void Function(String line) out;

  /// Says a line on stderr.
  final void Function(String line) err;

  /// Waits, between polls.
  final Future<void> Function(Duration) sleep;

  /// Whether stdin and stdout are both a terminal, as npm's login needs.
  final bool tty;

  /// The home directory, whose login keychain holds the identity.
  final String home;

  /// The Dart SDKs the binaries are compiled with.
  final Sdks sdks;

  /// The host SDK's folder, whose LICENSE goes into NOTICES.
  final String sdkDir;

  /// The fake agent's command line, for the self-test; dies when it cannot
  /// run here.
  final String Function() fake;

  /// This machine, such as `darwin-arm64`.
  final String platform;

  /// The stages, in order, publish left out: chord's, or a test's.
  final List<Stage> stages;

  /// The environment the release runs in, which gh reads too.
  final Map<String, String> env;

  /// The signing identity, once found before the build.
  String? identity;
}

/// The outputs a stage recorded, by path with their sha256, this run's or
/// the state's.
typedef Recorded = Map<String, String> Function(String stage);

/// One release stage.
final class Stage {
  /// The stage [name], doing [about].
  const Stage({
    required this.name,
    required this.about,
    required this.run,
    this.armMac = false,
    this.versioned = false,
    this.ready,
    this.outputs,
  });

  /// Its name, as `--skip` and the state name it.
  final String name;

  /// What it does, as the help says.
  final String about;

  /// Whether it needs this arm64 Mac's keychain and Rosetta.
  final bool armMac;

  /// Whether it puts the version into what is published.
  final bool versioned;

  /// What it needs found before anything builds.
  final Future<void> Function(Release release)? ready;

  /// What it leaves for later ones, by path from the root, at a version.
  final List<String> Function(String version)? outputs;

  /// Runs it at a version, with what earlier stages recorded.
  final Future<void> Function(
    Release release,
    String version,
    Recorded recorded,
  )
  run;
}

/// The machine signing and notarisation need.
const armMacPlatform = 'darwin-arm64';

/// The framework's package, from the root: its lock is installed and its
/// suite run beside the port's.
const frameworkFolder = 'packages/chord_tui';

Future<void> _loud(Release release, List<String> argv, {String? cwd}) async {
  final [command, ...args] = argv;
  final ran = await release.runner.run(command, args, loud: true, cwd: cwd);
  if (ran.status != 0) die('${argv.join(' ')} failed');
}

/// Whether notarytool reads Apple's credentials from the keychain profile.
Future<void> notary(Release release) async {
  final history = await release.runner.run('xcrun', [
    'notarytool',
    'history',
    '--keychain-profile',
    notaryProfile,
  ]);
  if (history.status != 0) {
    die(
      'xcrun notarytool history --keychain-profile $notaryProfile failed: '
      '${said(history.stdout + history.stderr)}',
    );
  }
}

Future<void> _selftest(
  Release release,
  String binary,
  String version,
  String? arch,
) => selftest(
  release.runner,
  binary: binary,
  version: version,
  fake: release.fake(),
  socket: 'chord-selftest-$pid',
  sleep: release.sleep,
  report: release.out,
  arch: arch,
);

/// chord's stages, in order, publish last; the about texts are the help's.
final List<Stage> chordStages = [
  Stage(
    name: 'install',
    about: _about('install'),
    run: (release, _, _) async {
      await _loud(release, [
        'dart',
        'pub',
        'get',
        '--enforce-lockfile',
      ], cwd: frameworkFolder);
      await _loud(release, ['dart', 'pub', 'get', '--enforce-lockfile']);
    },
  ),
  Stage(
    name: 'quality',
    about: _about('quality'),
    run: (release, _, _) async {
      await _loud(release, ['dart', 'analyze']);
      await _loud(release, [
        'dart',
        'format',
        '--output=none',
        '--set-exit-if-changed',
        '.',
      ]);
      await _loud(release, ['dart', 'test'], cwd: frameworkFolder);
      await _loud(release, ['dart', 'test']);
    },
  ),
  Stage(
    name: 'compile',
    about: _about('compile'),
    versioned: true,
    outputs: (_) => [for (final target in targets) binaryOf(target)],
    run: (release, _, _) => compile(release.runner, release.sdks, release.root),
  ),
  Stage(
    name: 'sign',
    about: _about('sign'),
    armMac: true,
    ready: (release) async =>
        release.identity ??= await identity(release.runner, release.home),
    outputs: (_) => darwinBinaries,
    run: (release, _, _) => sign(
      release.runner,
      release.root,
      release.identity ?? die('no signing identity was found'),
      darwinBinaries,
      out: release.out,
    ),
  ),
  Stage(
    name: 'selftest',
    about: _about('selftest'),
    run: (release, version, _) async {
      await _selftest(
        release,
        p.join(release.root, darwinBinaries[0]),
        version,
        null,
      );
      await _selftest(
        release,
        p.join(release.root, darwinBinaries[1]),
        version,
        'x86_64',
      );
    },
  ),
  Stage(
    name: 'notarise',
    about: _about('notarise'),
    armMac: true,
    ready: notary,
    // The bytes notarised: pack sends nothing else.
    outputs: (_) => darwinBinaries,
    run: (release, _, _) => notarise(
      release.runner,
      release.root,
      p.join('build', 'release', 'notarise'),
      darwinBinaries,
      sleep: release.sleep,
      report: release.out,
    ),
  ),
  Stage(
    name: 'pack',
    about: _about('pack'),
    outputs: (version) => packOutputs(version, npmNames),
    run: (release, version, recorded) => pack(
      release.runner,
      release.root,
      version: version,
      npmNames: npmNames,
      notices: () => collectReleaseNotices(release),
      notarised: recorded('notarise'),
      selftest: (binary, arch) => _selftest(release, binary, version, arch),
      out: release.out,
    ),
  ),
];

/// The publish stage's name; it runs last and is the release's own.
const publishStage = 'publish';

String _about(String name) =>
    releaseStages.firstWhere((stage) => stage.name == name).about;

/// The NOTICES of [release]'s tree, with its SDK's licence.
String collectReleaseNotices(Release release) =>
    collectNotices(root: release.root, sdkDir: release.sdkDir);

/// Refuses at once a stage among [names] that needs an arm64 Mac, anywhere
/// else, naming every stage bound to it.
void onMachine(List<String> names, String platform, [List<Stage>? stages]) {
  final bound = [
    for (final stage in stages ?? chordStages)
      if (stage.armMac) stage.name,
  ];
  if (platform == armMacPlatform || !names.any(bound.contains)) return;
  die(
    '${_listed(bound)} ${bound.length == 1 ? 'runs' : 'run'} only on an '
    'arm64 Mac; this is $platform',
  );
}

/// `a`, `a and b`, `a, b and c`.
String _listed(List<String> names, [String and = 'and']) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} $and ${names.last}';

/// This machine as the release names it: `darwin-arm64`, `linux-x64`.
String hostPlatform() {
  final match = RegExp(r'on "(\w+)_(\w+)"').firstMatch(Platform.version);
  final os = match?[1] == 'macos' ? 'darwin' : match?[1];
  return '$os-${match?[2]}';
}

/// The sums of what [stage] left at [version] in [root], by path; an output
/// it names and did not leave stops the release.
Map<String, String> outputSums(String root, Stage stage, String version) => {
  for (final path in stage.outputs?.call(version) ?? const <String>[])
    path: File(p.join(root, path)).existsSync()
        ? sha256Of(p.join(root, path))
        : die('${stage.name} did not leave $path'),
};
