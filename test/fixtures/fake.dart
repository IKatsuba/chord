// The fake agent: the Dart port under `fake_agent/`, compiled once to a
// kernel snapshot, which every caller starts. No package:test here, so
// `tool/` can import it too.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/which.dart';

/// The port's package directory, wherever the tests or the tool run from;
/// a binary from `dart compile exe` has no package config, so there it is
/// the working directory, as the benchmark's binary is run from the port.
String portPackageDir() {
  final lib = Isolate.resolvePackageUriSync(Uri.parse('package:chord/'));
  return lib == null ? Directory.current.path : p.dirname(lib.toFilePath());
}

// As the port's own lookup: the real PATH alone, none of process_run's
// user env files.
String? _onPath(String command, Map<String, String> env) =>
    whichSync(command, environment: env, includeParentEnvironment: false);

/// The Dart fake's entry point, under the port's package directory.
const dartFakeMain = 'test/fixtures/fake_agent/main.dart';

/// Where compiled snapshots of the Dart fake are kept, under the port.
const dartFakeCache = '.dart_tool/chord_fake_agent';

/// The Dart fake's sources under [packageDir]: its entry point and every
/// file it imports by a relative path, sorted.
List<String> dartFakeSources(String packageDir) {
  final found = <String>{};
  void visit(String path) {
    if (!found.add(path)) return;
    final imports = RegExp(r"^(?:import|export) '([^:']+)'", multiLine: true);
    for (final match in imports.allMatches(File(path).readAsStringSync())) {
      visit(p.normalize(p.join(p.dirname(path), match.group(1)!)));
    }
  }

  visit(p.join(packageDir, dartFakeMain));
  return found.toList()..sort();
}

/// Every source of the port's own the Dart fake, or the entry point
/// [main], is built from, under [packageDir]: [dartFakeSources], and
/// through the app's team file reader the app's and the framework's
/// sources that one imports, sorted. Files of other packages are pinned by
/// pubspec.lock.
List<String> dartFakeBuildSources(
  String packageDir, {
  String main = dartFakeMain,
}) {
  final roots = {
    'package:chord/': p.join(packageDir, 'lib'),
    'package:chord_tui/': p.join(packageDir, 'packages', 'chord_tui', 'lib'),
  };
  final found = <String>{};
  final uses = RegExp(r"^(?:import|export|part) '([^']+)'", multiLine: true);
  void visit(String path) {
    final file = File(path);
    if (!file.existsSync() || !found.add(path)) return;
    for (final match in uses.allMatches(file.readAsStringSync())) {
      final uri = match.group(1)!;
      final root = roots.entries
          .where((entry) => uri.startsWith(entry.key))
          .firstOrNull;
      if (root != null) {
        visit(p.join(root.value, uri.substring(root.key.length)));
      } else if (!uri.contains(':')) {
        visit(p.normalize(p.join(p.dirname(path), uri)));
      }
    }
  }

  visit(p.join(packageDir, main));
  return found.toList()..sort();
}

/// The hash a snapshot of the Dart fake is kept under: its sources, by
/// path and content ([dartFakeBuildSources]), the package versions it was
/// built against, and the
/// SDK that builds and runs it, [sdk] or [dartSdkVersion]'s, whose kernel
/// format another SDK may not read; of the entry point [main] when given.
String dartFakeHash(
  String packageDir, {
  String? sdk,
  String main = dartFakeMain,
}) {
  final parts = <int>[...utf8.encode('${sdk ?? dartSdkVersion()}\n')];
  for (final path in [
    ...dartFakeBuildSources(packageDir, main: main),
    p.join(packageDir, 'pubspec.lock'),
  ]) {
    parts
      ..addAll(utf8.encode('${p.relative(path, from: packageDir)}\n'))
      ..addAll(File(path).readAsBytesSync())
      ..add(0);
  }
  return sha256.convert(parts).toString().substring(0, 16);
}

/// The Dart SDK's `dart`: the one running, or under a compiled binary,
/// the one on PATH.
String dartExecutable() {
  final running = Platform.resolvedExecutable;
  if (p.basenameWithoutExtension(running) == 'dart') return running;
  return _onPath('dart', Platform.environment) ??
      (throw StateError('dart is not on PATH, which the fake agent needs.'));
}

String? _sdkVersion;

/// What [dartExecutable] says of its version: the running VM's own words
/// when it is that dart, else `dart --version`'s.
String dartSdkVersion() => _sdkVersion ??= () {
  final dart = dartExecutable();
  if (dart == Platform.resolvedExecutable) return Platform.version;
  final result = Process.runSync(dart, ['--version']);
  return '${result.stdout}${result.stderr}'.trim();
}();

String? _snapshot;

/// The Dart fake's kernel snapshot under [packageDir], compiled once and
/// kept by [dartFakeHash]: built under the cache's lock, so processes
/// that miss it at once build it once (a POSIX file lock is the process's,
/// so isolates of one process may each build it), and written to a name of
/// its own, then renamed, so none reads half a file.
String dartFakeSnapshot([String? packageDir]) {
  if (packageDir == null && _snapshot != null) return _snapshot!;
  final snapshot = _snapshotOf(
    dartFakeMain,
    packageDir ?? portPackageDir(),
    dartFakeCache,
  );
  if (packageDir == null) _snapshot = snapshot;
  return snapshot;
}

/// Where compiled snapshots of other fixtures are kept, under the port, a
/// folder for each entry point.
const fixtureCache = '.dart_tool/chord_fixtures';

final _fixtureSnapshots = <String, String>{};

/// The kernel snapshot of the port's entry point [main] (a path under the
/// port, as `test/fixtures/crash_window.dart`), compiled and kept as the
/// fake's is, so a test that starts it many times, or many tests at once,
/// do not each compile the app with `dart run`. It is built as `dart run`
/// runs it, not as a product: `dart compile kernel` defines
/// `dart.vm.product`, which would have the app start its process groups
/// through itself, as a compiled binary does, where `dart` is no launcher.
String fixtureSnapshot(String main) => _fixtureSnapshots[main] ??= _snapshotOf(
  main,
  portPackageDir(),
  p.join(fixtureCache, p.basenameWithoutExtension(main)),
  defines: const ['-Ddart.vm.product=false'],
);

/// The argv that starts the port's entry point [main] from its
/// [fixtureSnapshot], then [args].
List<String> fixtureCommand(String main, [List<String> args = const []]) => [
  dartExecutable(),
  fixtureSnapshot(main),
  ...args,
];

/// [main]'s snapshot under [root], in [cacheDir] by [dartFakeHash]: built
/// under the cache's lock, so processes that miss it at once build it
/// once, and written to a name of its own, then renamed, so none reads
/// half a file.
String _snapshotOf(
  String main,
  String root,
  String cacheDir, {
  List<String> defines = const [],
}) {
  final cache = Directory(p.join(root, cacheDir))..createSync(recursive: true);
  final snapshot = p.join(cache.path, '${dartFakeHash(root, main: main)}.dill');
  if (File(snapshot).existsSync()) return snapshot;
  final lock = File(p.join(cache.path, _lock)).openSync(mode: FileMode.append)
    ..lockSync(FileLock.blockingExclusive);
  try {
    if (!File(snapshot).existsSync()) {
      _build(root, main, cache, snapshot, defines);
    }
  } finally {
    lock.closeSync();
  }
  return snapshot;
}

/// The lock a build of the fake holds, in the cache.
const _lock = '.lock';

/// Compiles [main] under [root] to [snapshot] in [cache], with [defines].
void _build(
  String root,
  String main,
  Directory cache,
  String snapshot,
  List<String> defines,
) {
  final partial =
      '$snapshot.$pid.${Random().nextInt(1 << 32).toRadixString(16)}.part';
  final result = Process.runSync(dartExecutable(), [
    'compile',
    'kernel',
    ...defines,
    '--output',
    partial,
    p.join(root, main),
  ], workingDirectory: root);
  if (result.exitCode != 0) {
    final leftover = File(partial);
    if (leftover.existsSync()) leftover.deleteSync();
    throw StateError(
      '$main did not compile:\n${result.stdout}${result.stderr}',
    );
  }
  File(partial).renameSync(snapshot);
  _prune(cache, keep: snapshot);
}

/// Removes snapshots and partial files in [cache] other than [keep] once
/// untouched for ten minutes: the fake's earlier builds, which nothing
/// starting now still runs.
void _prune(Directory cache, {required String keep}) {
  final old = DateTime.now().subtract(const Duration(minutes: 10));
  for (final entry in cache.listSync().whereType<File>()) {
    if (entry.path == keep || p.basename(entry.path) == _lock) continue;
    try {
      if (entry.lastModifiedSync().isBefore(old)) entry.deleteSync();
    } on FileSystemException {
      // Another isolate pruned it first.
    }
  }
}

/// The argv that starts the Dart fake from any working directory: dart and
/// its snapshot, then `--scenario` when [scenario] is given, then [flags].
List<String> dartFakeCommand([
  String? scenario,
  List<String> flags = const [],
]) => [
  dartExecutable(),
  dartFakeSnapshot(),
  if (scenario != null) ...['--scenario', scenario],
  ...flags,
];

/// What looking for the Dart fake found: the [reason] its snapshot could
/// not be built, or none.
final class DartFakeLookup {
  const DartFakeLookup._(this.reason);

  /// Why the Dart fake cannot run here; null when it can.
  final String? reason;
}

/// The fake agent on this machine: the Dart one, its snapshot built once,
/// or why it could not be.
final DartFakeLookup fakeAgent = () {
  try {
    dartFakeSnapshot();
    return const DartFakeLookup._(null);
  } on StateError catch (error) {
    return DartFakeLookup._(error.message);
  } on ProcessException catch (error) {
    return DartFakeLookup._(
      'The Dart fake agent did not compile: ${error.message}',
    );
  }
}();

/// The argv that starts the fake agent, the Dart one, from any working
/// directory, then `--scenario` when [scenario] is given, then [flags],
/// such as `--no-usage`.
List<String> fakeAgentCommand([
  String? scenario,
  List<String> flags = const [],
]) => dartFakeCommand(scenario, flags);

/// [command], started only once the file [gate] exists, so an agent can be
/// kept starting for as long as a test needs. It gives up once [gate]'s
/// directory is gone or after 30 s: an agent chord never let start is not
/// always stopped with the window, and the loop must not outlive the test.
List<String> gatedCommand(String gate, List<String> command) => [
  'sh',
  '-c',
  r'i=0; while [ ! -e "$0" ]; do '
      r'[ -d "${0%/*}" ] && [ "$i" -lt 600 ] || exit 1; '
      r'i=$((i + 1)); sleep 0.05; done; exec "$@"',
  gate,
  ...command,
];
