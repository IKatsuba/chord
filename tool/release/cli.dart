/// The release command's arguments, as the original's `bun dev release`
/// declares them in `scripts/dev.ts`: an optional package, so a bare run
/// reaches the release's own words, `--bump`, `--channel`, `--dry-run`,
/// `--skip`, `--only`, `--from` and `--to`, and the RELEASE help.
library;

import 'package:args/args.dart';

import 'select.dart';
import 'version.dart';

/// The command a person types.
const releaseCommand = 'dart run tool/release.dart';

/// The one package the port releases.
const releasePackage = 'chord';

/// chord's release stages, in order, each with what it does.
const releaseStages = [
  (name: 'install', about: 'dart pub get --enforce-lockfile, root and port'),
  (name: 'quality', about: 'dart analyze, the format check and both suites'),
  (name: 'compile', about: 'four binaries, each kind checked'),
  (name: 'sign', about: 'both macOS binaries signed and verified'),
  (name: 'selftest', about: 'each macOS binary on the fake agent'),
  (name: 'notarise', about: "one zip to Apple; cdhashes in Apple's log"),
  (
    name: 'pack',
    about:
        'archives, SHA256SUMS, npm packages and the formula, from the '
        'notarised bytes',
  ),
  (name: 'publish', about: 'npm, the tag and the draft GitHub release'),
];

/// The stage names, in order.
final releaseStageNames = [for (final stage in releaseStages) stage.name];

/// The release's own words, the original's RELEASE adapted to the port.
const releaseText =
    "The release of chord; it runs on the owner's arm64 Mac. With no options "
    'it runs every stage in order, and the last line it prints is the '
    'published version. With no package it releases nothing. Preflight runs '
    'on every run, whatever is skipped. After all eligibility guards, '
    'mandatory npm authentication runs for every invocation, including dry '
    'runs and runs without publish. A successful npm whoami continues '
    'without needing a terminal. If it fails, stdin and stdout must be '
    'terminals: the release runs plain npm login once with inherited stdio, '
    'then rechecks npm whoami. npm may open a browser and save credentials '
    'or registry settings, including during a dry run. Failed, cancelled or '
    'signal-terminated login, or a failed recheck, stops before release '
    'work. Stage selection cannot skip authentication. A run that '
    "publishes, or one at pubspec.yaml's version, keeps the release's state "
    'in .release/chord/state.json as it goes: each stage done with the '
    'sha256 of what it left, each npm name, the tag and the draft. A stopped '
    'release goes on from it: the next run does what is left, past guards '
    'that refuse a changed tree, a moved HEAD while a stage before publish '
    'is left, a changed output, or an npm version or tag the release did '
    'not make. Every refusal a state causes names rm -r .release/chord, '
    'which abandons it. The state is removed once everything is done. The '
    'publish stage hands the terminal to npm, which asks you to authorise '
    'each publish (press Enter, then approve in the browser), and the '
    'release waits for as long as that takes.\n'
    '\n'
    "The version is pubspec.yaml's, or --bump's: pubspec.yaml's own, an "
    'exact version above it, or major, minor, patch or fix (patch) to bump '
    'it. A version with a pre-release label cannot be given, and a new '
    'version needs the stage that puts it into what is published (compile). '
    'Given a new one, the release checks it, writes it into pubspec.yaml, the '
    "framework's pubspec.yaml, pubspec.lock and lib/version.dart and commits "
    'those alone as "chore: chord v<version>" before any stage. A run that '
    "publishes pushes the commit to origin's main first, and its state keeps "
    'it if the push or a later stage fails: rerun without --bump. A dry run, '
    'or a run without publish that makes a new version, keeps no state and '
    'drops the commit at the end, pushing nothing; until then Ctrl+C, SIGTERM and SIGHUP drop it too, and a run '
    'killed otherwise may leave it, to be dropped with git reset --keep '
    "HEAD~1. --bump is refused while chord's state is unfinished, and so is "
    '--dry-run. Publish needs pack done, in this run or the state.\n'
    '\n'
    '--channel <name> releases a pre-release on that channel: '
    "<x.y.z>-<name>.<n>. A bump counts from npm's latest stable version, "
    'and an exact version is taken as written; if pubspec.yaml already holds '
    "that channel's pre-release of it, n goes up by one, otherwise it starts "
    'at 0. So from 0.67.0, --bump major --channel next gives 1.0.0-next.0, '
    'and the same command again 1.0.0-next.1. Without --bump, --channel '
    "finishes pubspec.yaml's version if it is that channel's. The channel is "
    "the version's label, and the rest follows from the version whether or "
    'not --channel is given: a publishing run needs the branch named after '
    'the channel, level with its origin, and pushes there instead of main. '
    "Every package is published with --tag <name>, so npm's latest does not "
    'move, and the draft GitHub release is marked a pre-release. A dry run '
    'on a channel also prints the stages it ran and each package\'s npm '
    'publish arguments, in publish order. A stable version publishes only '
    'from main.';

/// The help's examples, the original's, with what each does. Without
/// notarisation pack cannot run (the pack gate), so the dry run without
/// Apple skips both.
const releaseExamples = [
  ('the whole release', 'chord'),
  ('the next minor version', 'chord --bump minor'),
  ('an exact version', 'chord --bump 1.0.0'),
  (
    "the next pre-release on a channel, from that channel's branch",
    'chord --bump major --channel next',
  ),
  (
    'a dry run of the next patch, pubspec.yaml as it was after',
    'chord --bump patch --dry-run --skip notarise,pack',
  ),
  ('without the checks and tests', 'chord --skip install,quality'),
  ('rerun from the self-test', 'chord --from selftest'),
];

/// What a release command line asks for.
sealed class ReleaseCall {
  const ReleaseCall();
}

/// The help, asked for.
final class ReleaseHelp extends ReleaseCall {
  /// The help.
  const ReleaseHelp();
}

/// No package was named: nothing is released, and [line] says so.
final class ReleaseUnclear extends ReleaseCall {
  /// A bare run, said as [line].
  const ReleaseUnclear(this.line);

  /// What the release says, on stderr.
  final String line;
}

/// A release of [package]'s [stages] with [options], at [bump] if given.
final class ReleaseRun extends ReleaseCall {
  /// The run the command line asks for.
  const ReleaseRun(this.package, this.stages, this.options, this.bump);

  /// The package released.
  final String package;

  /// The stages run, in order.
  final List<String> stages;

  /// The options given.
  final ReleaseOptions options;

  /// `--bump`'s value, or null.
  final String? bump;
}

ArgParser _parser() => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
  ..addOption(
    'bump',
    valueHelp: 'version',
    help:
        "An exact version above chord's pubspec.yaml, or major, minor, "
        'patch or fix.',
  )
  ..addOption(
    'channel',
    valueHelp: 'name',
    help: 'A pre-release on this channel, from the branch of that name.',
  )
  ..addFlag(
    'dry-run',
    negatable: false,
    help:
        'Every stage but publish, so it still submits to Apple. Refused '
        "while chord's state is unfinished.",
  )
  ..addMultiOption(
    'skip',
    valueHelp: 'stages',
    help: "Leave these of chord's stages out (comma-separated).",
  )
  ..addMultiOption(
    'only',
    valueHelp: 'stages',
    help: "Run only these of chord's stages.",
  )
  ..addOption('from', valueHelp: 'stage', help: 'Start at this stage.')
  ..addOption('to', valueHelp: 'stage', help: 'Stop after this stage.');

/// The help: usage, the release's words, its stages and its options.
String releaseHelp() {
  final width = releaseStages
      .map((stage) => stage.name.length)
      .reduce((a, b) => a > b ? a : b);
  return [
    'Usage: $releaseCommand [package] [options]',
    '',
    releaseText,
    '',
    'Stages:',
    for (final stage in releaseStages)
      '  ${stage.name.padRight(width)}  ${stage.about}',
    '',
    'Options:',
    _parser().usage,
    '',
    'Examples:',
    for (final (what, args) in releaseExamples)
      '  $what:\n    $releaseCommand $args',
  ].join('\n');
}

/// What [args] ask for. Refusals of the options themselves come first,
/// as Cliffy's do, then a missing package, then the stage choice.
/// Throws [UsageError].
ReleaseCall parseRelease(List<String> args) {
  final ArgResults parsed;
  try {
    parsed = _parser().parse(args);
  } on FormatException catch (error) {
    throw UsageError(error.message);
  }
  if (parsed.flag('help')) return const ReleaseHelp();

  List<String>? stagesOf(String option) {
    if (!parsed.wasParsed(option)) return null;
    final named = parsed.multiOption(option);
    for (final stage in named) {
      if (!releaseStageNames.contains(stage)) {
        throw UsageError(
          'Option "--$option" must be of type "stage", but got "$stage". '
          'Expected values: ${releaseStageNames.map((s) => '"$s"').join(', ')}',
        );
      }
    }
    return named;
  }

  String? stageOf(String option) {
    final stage = parsed.option(option);
    if (stage != null && !releaseStageNames.contains(stage)) {
      throw UsageError(
        'Option "--$option" must be of type "stage", but got "$stage". '
        'Expected values: ${releaseStageNames.map((s) => '"$s"').join(', ')}',
      );
    }
    return stage;
  }

  if (parsed.wasParsed('only')) {
    for (final other in ['skip', 'from', 'to']) {
      if (parsed.wasParsed(other)) {
        throw UsageError('Option "--only" conflicts with option "--$other".');
      }
    }
  }
  final skip = stagesOf('skip');
  final only = stagesOf('only');
  final from = stageOf('from');
  final to = stageOf('to');
  final bump = parsed.option('bump');
  if (bump != null && !isVersionArgument(bump)) {
    throw UsageError(
      '"$bump" is neither an exact version (1.2.3) nor one of '
      '${Bump.values.map((b) => b.name).join(', ')}.',
    );
  }
  final rest = parsed.rest;
  if (rest.length > 1) {
    throw UsageError('Too many arguments: ${rest.skip(1).join(' ')}');
  }
  if (rest case [final package] when package != releasePackage) {
    throw UsageError(
      'Argument "package" must be of type "package", but got "$package". '
      'Expected values: "$releasePackage"',
    );
  }
  if (rest.isEmpty) {
    return const ReleaseUnclear(
      'release: not clear which package to release: $releaseCommand '
      '<package> ($releasePackage)',
    );
  }
  final options = ReleaseOptions(
    dryRun: parsed.flag('dry-run'),
    skip: skip,
    only: only,
    from: from,
    to: to,
    channel: parsed.option('channel'),
  );
  return ReleaseRun(
    releasePackage,
    selectStages((name: releasePackage, stages: releaseStageNames), options),
    options,
    bump,
  );
}
