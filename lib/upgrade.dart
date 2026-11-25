/// `chord upgrade`, as the original's `src/upgrade.ts` over cliffy's upgrade
/// command: the package manager that installed the running chord, found
/// from the binary's real path, upgrades it, so it upgrades the install it
/// runs from and never puts a second chord elsewhere. The registry read and
/// the manager run sit behind [VersionSource] and [Runner], so the flow is
/// tested without a network or a manager.
library;

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

import 'channel.dart';
import 'distribution.dart';
import 'node_semver.dart' as semver;
import 'platform/process.dart' show Exit;

/// A package manager chord can upgrade itself through.
enum Manager {
  /// npm, under any prefix.
  npm,

  /// bun's global install.
  bun,

  /// pnpm's global store.
  pnpm,

  /// yarn classic's global folder.
  yarn,
}

// The original's ROWS, first match wins. Every row needs a platform
// package's path, so a Bun or a Node that happens to sit under a global
// node_modules never matches.
final List<(RegExp, Manager?)> _rows = [
  // npx and bunx are caches, not installs.
  (RegExp(r'/_npx/[^/]+/node_modules/@chorded/chord-(?:darwin|linux)-'), null),
  (RegExp(r'/bunx-[^/]+/node_modules/@chorded/chord-(?:darwin|linux)-'), null),
  // $BUN_INSTALL (default ~/.bun), the platform package hoisted.
  (
    RegExp(r'/install/global/node_modules/@chorded/chord-(?:darwin|linux)-'),
    Manager.bun,
  ),
  // global/5/… before pnpm 11, global/v11/<hash>-<n>/… from 11.
  (
    RegExp(
      r'/global/[^/]+/(?:[^/]+/)?node_modules/\.pnpm/@chorded\+chord-'
      r'(?:darwin|linux)-',
    ),
    Manager.pnpm,
  ),
  // yarn classic's default global folder.
  (
    RegExp(r'/yarn/global/node_modules/@chorded/chord-(?:darwin|linux)-'),
    Manager.yarn,
  ),
  // npm under any prefix (nvm, Homebrew, fnm, Volta), nested in the main
  // package.
  (
    RegExp(
      r'/lib/node_modules/@chorded/chord/node_modules/@chorded/chord-'
      r'(?:darwin|linux)-',
    ),
    Manager.npm,
  ),
];

/// The manager that installed the binary at [realPath]; null when no
/// supported global install is identified (a copy, a build from source, a
/// local install, npx, bunx), as a guess would install a second chord.
Manager? detectManager(String realPath) {
  for (final (pattern, manager) in _rows) {
    if (pattern.hasMatch(realPath)) return manager;
  }
  return null;
}

/// The manager's own global install of an exact [version]. Never `@*` or
/// `@latest`: `bun add -g pkg@*` leaves an installed version alone and
/// exits 0, so the version is always named.
List<String> installArgv(Manager manager, String version) {
  final spec = '$npmPackage@$version';
  return switch (manager) {
    Manager.npm => ['npm', 'install', '--global', spec],
    Manager.bun => ['bun', 'add', '--global', spec],
    Manager.pnpm => ['pnpm', 'add', '--global', spec],
    Manager.yarn => ['yarn', 'global', 'add', spec],
  };
}

/// Why an external command did not succeed, said as chord says it.
sealed class RunFailure implements Exception {
  const RunFailure(this.argv);

  /// The command as it was run.
  final List<String> argv;

  /// The sentence chord prints for it.
  String get message;

  @override
  String toString() => message;
}

/// The command ran and exited with a status other than 0.
final class RunExited extends RunFailure {
  /// [argv] exited with [status].
  const RunExited(super.argv, this.status);

  /// Its exit status.
  final int status;

  @override
  String get message => '${argv.join(' ')} exited with status $status.';
}

/// The command was ended by a signal.
final class RunKilled extends RunFailure {
  /// [argv] was ended by [signal], named as `SIGTERM`.
  const RunKilled(super.argv, this.signal);

  /// The signal's name.
  final String signal;

  @override
  String get message => '${argv.join(' ')} was killed by $signal.';
}

/// The command is not on the PATH it was looked up on.
final class RunNotFound extends RunFailure {
  /// [argv]'s program was not found.
  const RunNotFound(super.argv);

  @override
  String get message => '${argv.first} is not on PATH.';
}

/// Runs [argv] as a person would type it, looked up on the PATH of the
/// environment given.
abstract interface class Runner {
  /// The terminal's stdio, so progress shows and prompts (an OTP, corepack)
  /// can be answered; no timeout, as an install downloads a large tarball.
  /// Throws [RunFailure].
  Future<void> inherit(List<String> argv, Map<String, String> env);

  /// Its stdout captured, for a short local query. Throws [RunFailure].
  Future<String> capture(List<String> argv, Map<String, String> env);
}

/// The [Runner] over real processes, in exactly the environment given.
class ProcessRunner implements Runner {
  /// The runner.
  const ProcessRunner();

  // No signal handler: Ctrl+C reaches the foreground group, so the manager
  // and chord both get it and chord dies by it.
  Future<Process> _start(
    List<String> argv,
    Map<String, String> env,
    ProcessStartMode mode,
  ) async {
    try {
      return await Process.start(
        argv.first,
        argv.sublist(1),
        environment: env,
        includeParentEnvironment: false,
        mode: mode,
      );
    } on ProcessException catch (error) {
      // ENOENT: nothing of that name on PATH.
      if (error.errorCode == 2) throw RunNotFound(argv);
      rethrow;
    }
  }

  void _check(List<String> argv, int exitCode) {
    final exit = Exit.fromExitCode(exitCode);
    if (exit.signal case final signal?) throw RunKilled(argv, signal);
    if (exit.code != 0) throw RunExited(argv, exit.code);
  }

  @override
  Future<void> inherit(List<String> argv, Map<String, String> env) async {
    final process = await _start(argv, env, ProcessStartMode.inheritStdio);
    _check(argv, await process.exitCode);
  }

  @override
  Future<String> capture(List<String> argv, Map<String, String> env) async {
    final process = await _start(argv, env, ProcessStartMode.normal);
    final out = process.stdout.transform(utf8.decoder).join();
    // Read so a full pipe cannot stall it; a short query's complaints are
    // not what the caller parses.
    final drained = process.stderr.drain<void>();
    final code = await process.exitCode;
    await drained;
    final text = await out;
    _check(argv, code);
    return text;
  }
}

/// The published versions of chord and the one `latest` stands for.
class Versions {
  /// [versions] as the registry lists them, with [latest].
  const Versions({required this.latest, required this.versions});

  /// What `latest` resolves to for the running chord.
  final String latest;

  /// Every published version, newest published first.
  final List<String> versions;
}

/// A registry read that failed, in the words chord prints.
class RegistryError implements Exception {
  /// A failure whose [reason] follows the common prefix.
  RegistryError(String reason)
    : message =
          'chord could not read the versions of $npmPackage from the npm '
          'registry: $reason';

  /// The whole sentence.
  final String message;

  @override
  String toString() => message;
}

/// Where chord's versions are read from; each [read] is one request.
abstract interface class VersionSource {
  /// The versions and `latest`. Throws [RegistryError].
  Future<Versions> read();

  /// Releases what the source holds open.
  void close();
}

/// Opens the [VersionSource] for a chord running [running].
typedef OpenVersions = VersionSource Function(String running);

/// The npm registry's own address.
final Uri npmRegistry = Uri.parse('https://registry.npmjs.org/');

/// The npm registry's package document of [npmPackage], with `latest` npm's
/// `latest` tag on a stable build and the tag of its channel on a
/// pre-release.
class RegistryReader implements VersionSource {
  /// A reader for a chord running [running], through [client] at [base].
  RegistryReader({required this.client, required this.running, Uri? base})
    : base = base ?? npmRegistry;

  /// The production reader: its own client at [npmRegistry].
  factory RegistryReader.open(String running) =>
      RegistryReader(client: http.Client(), running: running);

  /// What sends the request; closed by [close].
  final http.Client client;

  /// The registry's root.
  final Uri base;

  /// The running chord's version, whose channel `latest` follows.
  final String running;

  @override
  Future<Versions> read() async {
    try {
      // Asked here and not at the start, so a version channelOf refuses, in
      // a build whose version was edited by hand, only stops an upgrade.
      final channel = channelOf(running);
      final http.Response response;
      try {
        response = await client.get(base.resolve(npmPackage));
      } on http.ClientException catch (error) {
        throw RegistryError(error.message);
      } on TlsException catch (error) {
        // The client wraps sockets but not TLS: a certificate or handshake
        // failure is the read's failure too.
        throw RegistryError(error.message);
      } on IOException catch (error) {
        throw RegistryError('$error');
      }
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw RegistryError(
          channel == null
              ? "couldn't fetch the latest version - try again after sometime"
              : 'the registry answered ${response.statusCode}',
        );
      }
      final (:tags, :versions) = _document(response.body);
      final tag = channel ?? 'latest';
      final latest = tags[tag];
      if (latest == null) {
        // npm's own document always has latest; one without is no package
        // document of npm's.
        if (channel == null) throw RegistryError(_notADocument);
        throw RegistryError(
          'it has no tag $channel, the channel this chord is on',
        );
      }
      return Versions(latest: latest, versions: versions);
    } on VersionError catch (error) {
      throw RegistryError(error.message);
    }
  }

  @override
  void close() => client.close();
}

const _notADocument = "the registry's answer is not a package document";

/// The dist-tags and versions of a package document, versions reversed as
/// the original takes them; anything else is refused.
({Map<String, String> tags, List<String> versions}) _document(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    throw RegistryError(_notADocument);
  }
  if (json case {
    'dist-tags': final Map<String, Object?> tags,
    'versions': final Map<String, Object?> versions,
  } when tags.values.every((value) => value is String)) {
    return (
      tags: tags.cast<String, String>(),
      versions: versions.keys.toList().reversed.toList(),
    );
  }
  throw RegistryError(_notADocument);
}

// cliffy's Provider.maxListSize and maxCols.
const _maxListSize = 25;
const _maxCols = 8;

/// The versions as cliffy's `printVersions` prints them, without the final
/// newline: newest first by semver, unparseable ones last in string order,
/// [running] marked `* ` and the others indented two spaces; more than 25
/// in cliffy's table, 8 columns filled column by column, each as wide as
/// its widest cell and one space apart. Empty for no versions, which print
/// nothing.
String formatVersions(List<String> versions, String? running) {
  if (versions.isEmpty) return '';
  // Stable, as JavaScript's sort is.
  final sorted = List.of(versions);
  mergeSort(
    sorted,
    compare: (a, b) {
      final aValid = semver.valid(a) != null;
      final bValid = semver.valid(b) != null;
      if (aValid && bValid) return semver.compare(b, a);
      if (aValid) return -1;
      if (bValid) return 1;
      return a.compareTo(b);
    },
  );
  final cells = [
    for (final version in sorted)
      running != null && running == version ? '* $version' : '  $version',
  ];
  if (cells.length <= _maxListSize) return cells.join('\n');

  final rowCount = (cells.length / _maxCols).ceil();
  final colCount = cells.length < _maxCols ? cells.length : _maxCols;
  final rows = List.generate(rowCount, (_) => List.filled(colCount, ''));
  var index = 0;
  for (var col = 0; col < colCount; col++) {
    for (var row = 0; row < rowCount; row++) {
      if (index < cells.length) rows[row][col] = cells[index];
      index++;
    }
  }
  final widths = [
    for (var col = 0; col < colCount; col++)
      rows.map((row) => row[col].length).max,
  ];
  // cliffy's table pads every cell, the last column's too, and puts its
  // padding of one between columns.
  return [
    for (final row in rows)
      [
        for (var col = 0; col < colCount; col++) row[col].padRight(widths[col]),
      ].join(' '),
  ].join('\n');
}

/// Where npm shows the package, or one [version] of it.
String npmPage([String? version]) =>
    'https://npmjs.org/package/$npmPackage${version == null ? '' : '/v/$version'}';

/// Why chord cannot upgrade the binary at [path] to [version] itself, and
/// how a person does, naming every other source chord comes from; a
/// release binary is [machine]'s.
String unidentifiedText(
  String path,
  String version, {
  String machine = 'unknown',
}) {
  final lines = [
    for (final manager in Manager.values)
      installArgv(manager, version).join(' '),
  ];
  // The source-build sentence never names the running path: under
  // `dart run` it is the Dart VM, and compiling over it would overwrite
  // the SDK.
  return 'chord cannot tell which package manager installed $path. If one '
      'did, upgrade with it: ${lines.join(', ')}. Homebrew upgrades with '
      '${homebrewArgv().join(' ')}. ${_releaseBinaryText(machine, version)} '
      'A build from source upgrades with git pull and dart compile exe '
      'bin/chord.dart -o <path of your chord>.';
}

/// The Homebrew formulae chord ships, stable releases only (Q371).
const homebrewFormulae = [homebrewFormula];

final _cellar = RegExp(
  '/Cellar/(${homebrewFormulae.join('|')})/[^/]+/bin/chord\$',
);

/// The formula whose Cellar holds the binary at [realPath], under any
/// prefix; null for none.
String? homebrewFormulaOf(String realPath) => _cellar.firstMatch(realPath)?[1];

/// Homebrew's upgrade of chord's formula; with [force], its reinstall.
List<String> homebrewArgv({bool force = false}) => [
  'brew',
  force ? 'reinstall' : 'upgrade',
  '$homebrewTap/$homebrewFormula',
];

/// Why Homebrew cannot install another version than its formula's; for
/// [list], where the versions are.
String homebrewOnlyText({required bool list, required String version}) {
  final head =
      'Homebrew installs only the version its formula names: '
      '${homebrewArgv().join(' ')}.';
  return list
      ? '$head For the versions there are, run npm view $npmPackage versions '
            'or see https://github.com/$githubRepo/releases.'
      : '$head For another version, install chord with npm (npm install '
            '--global $npmPackage@$version) or from '
            'https://github.com/$githubRepo/releases.';
}

/// Whether this binary was built by the release (`-Dchord.official=true`):
/// one no install row identifies is then a downloaded release binary.
const officialBuild = bool.fromEnvironment('chord.official');

/// The running machine as the release's archives name it, `<os>-<cpu>`:
/// `darwin` or `linux`, `arm64` or `x64`, from the Dart runtime's own
/// `on "macos_arm64"`.
String runningMachine() => machineOf(Platform.version);

/// The `<os>-<cpu>` of a Dart runtime whose `Platform.version` is
/// [platformVersion]; its own words when it names no other.
String machineOf(String platformVersion) {
  final match = RegExp(
    r'on "([a-z]+)_([a-z0-9]+)"',
  ).firstMatch(platformVersion);
  if (match == null) return 'unknown';
  final os = match.group(1) == 'macos' ? 'darwin' : match.group(1)!;
  return '$os-${match.group(2)}';
}

/// Why an official release binary no install row identifies is not
/// upgraded to [version]: chord does not replace itself, so it names npm,
/// then Homebrew, then [machine]'s archive.
String releaseText(String machine, String version) =>
    'Install chord through npm (npm install -g $npmPackage) or Homebrew '
    '(brew install $homebrewTap/$homebrewFormula) and upgrade it there, or '
    'replace this binary by ${_releaseArchive(machine, version)}.';

/// How a release binary for [machine] is replaced by [version], for a
/// refusal that has already named the package managers.
String _releaseBinaryText(String machine, String version) =>
    'A release binary is replaced by ${_releaseArchive(machine, version)}.';

String _releaseArchive(String machine, String version) =>
    'chord-$machine.tar.gz from '
    'https://github.com/$githubRepo/releases/tag/v$version, checked against '
    'its SHA256SUMS';

/// What a call of `chord upgrade` asks for.
class UpgradeRequest {
  /// The request: [to] a version or `latest`.
  const UpgradeRequest({
    this.list = false,
    this.to = 'latest',
    this.force = false,
    this.verbose = false,
  });

  /// `-l`: list the versions instead.
  final bool list;

  /// `--version`, `latest` by default.
  final String to;

  /// `-f`: replace even when not out of date.
  final bool force;

  /// `-v`: say each step.
  final bool verbose;
}

/// Thrown by the flow to end with [message] on stderr.
class _Stop implements Exception {
  _Stop(this.message);
  final String message;
}

/// `chord upgrade` as cliffy's upgrade command runs it over the original's
/// provider, from [running] and the binary at [realPath], read lazily as
/// only the upgrade needs it. Returns the exit code.
Future<int> runUpgrade(
  UpgradeRequest request, {
  required String running,
  required String Function() realPath,
  required Map<String, String> env,
  required Runner runner,
  required VersionSource source,
  required StringSink stdout,
  required StringSink stderr,
  bool official = false,
  String Function() machine = runningMachine,
}) async {
  // Homebrew's install reads no registry: brew knows its formula's version.
  // Resolved once; a binary whose path cannot be resolved is no Homebrew
  // install, and the upgrade says why when it needs the path.
  String? resolved;
  Exception? unresolved;
  try {
    resolved = realPath();
  } on Exception catch (error) {
    unresolved = error;
  }
  final brewFormula = resolved == null || detectManager(resolved) != null
      ? null
      : homebrewFormulaOf(resolved);
  if (brewFormula case final formula?) {
    if (request.list || request.to != 'latest') {
      stderr.writeln(homebrewOnlyText(list: request.list, version: request.to));
      return 1;
    }
    return _brewUpgrade(
      formula,
      request,
      running: running,
      env: env,
      runner: runner,
      stdout: stdout,
      stderr: stderr,
    );
  }
  if (request.list) {
    // The original dies here with an uncaught error and its stack (D6).
    try {
      final text = formatVersions((await source.read()).versions, running);
      if (text.isNotEmpty) stdout.writeln(text);
      return 0;
    } on RegistryError catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }

  // cliffy's logger: log only under -v, info on stdout, warn and error on
  // stderr.
  void log(String line) {
    if (request.verbose) stdout.writeln(line);
  }

  try {
    if (!request.force &&
        !await _isOutdated(source, running, request.to, stderr)) {
      return 0;
    }
    log(
      request.to == 'latest'
          ? 'Upgrading chord to the latest version'
          : 'Upgrading chord to version ${request.to}',
    );
    final to = request.to == 'latest'
        ? (await source.read()).latest
        : request.to;
    log('Upgrading chord:');
    log('  - current version: $running');
    log('  - target version: $to');
    try {
      final path = resolved ?? (throw unresolved!);
      final manager = detectManager(path);
      if (manager == null) {
        throw _Stop(
          official
              ? releaseText(machine(), to)
              : unidentifiedText(path, to, machine: machine()),
        );
      }
      final argv = installArgv(manager, to);
      log('\$ ${argv.join(' ')}');
      try {
        await runner.inherit(argv, env);
      } on RunNotFound {
        throw _Stop(
          '${manager.name} is not on PATH. Install ${manager.name}, or '
          'upgrade chord with the manager that installed it.',
        );
      }
      stdout.writeln(
        'A chord already running keeps $running until it is started again.',
      );
    } on Exception {
      stderr.writeln('Failed to upgrade chord from version $running to $to.');
      rethrow;
    }
    stdout.writeln(
      'Successfully upgraded chord from version $running to $to! '
      '(${npmPage(to)})',
    );
    return 0;
  } on Exception catch (error) {
    // Under -v too the message alone, without a stack (Q370).
    stderr.writeln(_messageOf(error));
    return 1;
  }
}

/// The upgrade through Homebrew: brew upgrades (or with -f reinstalls) the
/// formula with the terminal's stdio, then `brew list --versions` says
/// which version is installed now; brew links the newest after an upgrade.
Future<int> _brewUpgrade(
  String formula,
  UpgradeRequest request, {
  required String running,
  required Map<String, String> env,
  required Runner runner,
  required StringSink stdout,
  required StringSink stderr,
}) async {
  void log(String line) {
    if (request.verbose) stdout.writeln(line);
  }

  final argv = homebrewArgv(force: request.force);
  log('Upgrading chord to the latest version');
  log('\$ ${argv.join(' ')}');
  try {
    await runner.inherit(argv, env);
  } on RunFailure catch (error) {
    stderr
      ..writeln('Failed to upgrade chord from version $running to latest.')
      ..writeln(
        error is RunNotFound
            ? 'brew is not on PATH. Install brew, or upgrade chord with the '
                  'manager that installed it.'
            : error.message,
      );
    return 1;
  }

  final String? installed;
  final String why;
  try {
    final listed = await runner.capture([
      'brew',
      'list',
      '--versions',
      formula,
    ], env);
    // Only the formula's own row says what is installed.
    final row = [
      for (final line in listed.split('\n'))
        if (line.trim().split(RegExp(r'\s+')) case [
          final name,
          ...final versions,
        ] when name == formula)
          (line: line.trim(), versions: versions),
    ].firstOrNull;
    final valid = [
      for (final version in row?.versions ?? const <String>[])
        if (semver.valid(version) != null) version,
    ]..sort(semver.compare);
    installed = valid.lastOrNull;
    why = row == null
        ? 'brew lists no $formula'
        : 'brew listed "${row.line}", which names no version';
  } on RunFailure catch (error) {
    stderr.writeln(_unobserved(formula, error.message));
    return 1;
  }
  if (installed == null) {
    stderr.writeln(_unobserved(formula, why));
    return 1;
  }
  if (installed == running) {
    stderr.writeln(
      "You're already using the latest available version $running of chord.",
    );
    return 0;
  }
  stdout
    ..writeln(
      'A chord already running keeps $running until it is started again.',
    )
    ..writeln(
      'Successfully upgraded chord from version $running to $installed! '
      '(https://github.com/$githubRepo/releases/tag/v$installed)',
    );
  return 0;
}

/// brew finished, but what it installed could not be read, for [reason]:
/// the upgrade may have happened.
String _unobserved(String formula, String reason) =>
    '${homebrewArgv().join(' ')} finished, but chord could not tell which '
    'version is installed now: $reason. Run brew list --versions $formula.';

String _messageOf(Exception error) => switch (error) {
  _Stop(:final message) => message,
  RegistryError(:final message) => message,
  RunFailure(:final message) => message,
  ProcessException(:final executable, :final message) =>
    '$executable: $message',
  FileSystemException(:final message, :final path) =>
    path == null ? message : '$message: $path',
  _ => '$error',
};

/// cliffy's `isOutdated`: false, said on stderr, when there is nothing to
/// do; a version not listed stops the upgrade.
Future<bool> _isOutdated(
  VersionSource source,
  String current,
  String target,
  StringSink stderr,
) async {
  final Versions(:latest, :versions) = await source.read();
  if (target == 'latest') target = latest;
  if (target.isNotEmpty && !versions.contains(target)) {
    throw _Stop(
      'The provided version $target is not found.'
      '${_versionHint(target, versions, latest)}\n\n'
      '    Visit ${npmPage()} for available releases or run again with the '
      '-l or --list-versions command.',
    );
  }
  if (latest.isNotEmpty && latest == current && latest == target) {
    stderr.writeln(
      "You're already using the latest available version $current of chord.",
    );
    return false;
  }
  if (target.isNotEmpty && current == target) {
    stderr.writeln("You're already using version $current of chord.");
    return false;
  }
  return true;
}

String _versionHint(String target, List<String> versions, String latest) {
  final alternative = target.startsWith('v') ? target.substring(1) : 'v$target';
  if (versions.contains(alternative)) return ' Did you mean $alternative?';
  return latest.isNotEmpty && latest != target
      ? ' The latest version is $latest.'
      : '';
}

/// The running binary's real path, links resolved, as the install rows
/// match it.
String resolvedExecutablePath() =>
    File(Platform.resolvedExecutable).resolveSymbolicLinksSync();
