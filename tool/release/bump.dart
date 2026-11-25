/// The commit a release given a new version makes before any stage, as the
/// original's `scripts/dev/release/bump.ts`: pubspec.yaml's version, the
/// framework's pubspec.yaml beside it (Q375), the port's pubspec.lock that
/// records it, and the held lib/version.dart written and committed alone
/// (Q359), so every stage builds that version and the install stage's
/// enforced lockfile still holds, as the original commits bun.lock. A run that publishes pushes it to origin's main, or
/// its channel's branch; any other run drops it at the end, leaving the
/// branch as it found it. Until it is pushed or dropped, Ctrl+C, SIGTERM
/// and SIGHUP drop it too; SIGKILL cannot be caught, and leaves it.
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/channel.dart';
import 'package:chord/platform/signals.dart';
import 'package:path/path.dart' as p;

import 'archive.dart';
import 'continue.dart';
import 'runner.dart';
import 'version.dart';

/// The held version, from the root.
const heldVersionPath = 'lib/version.dart';

/// The framework's manifest, which carries the port's version (Q375),
/// from the root.
const frameworkManifestPath = 'packages/chord_tui/pubspec.yaml';

/// The port's lockfile, which records the framework's version, from the
/// root. The root pubspec.lock records nothing of the root package.
const lockPath = 'pubspec.lock';

/// The files the version commit holds, from the root.
const versionFiles = [
  manifestPath,
  frameworkManifestPath,
  lockPath,
  heldVersionPath,
];

/// Commits [version] into both pubspec.yaml files, the port's pubspec.lock
/// and lib/version.dart,
/// telling [committing] what the commit will hold, by path with its sha256,
/// before it is made; answers the commit it was made on. Anything that
/// fails before the commit is made puts every file back first; [write] is a
/// test's way to fail a write.
Future<String> commitVersion(
  ReleaseRunner runner,
  String root,
  String version, {
  void Function(Map<String, String> files)? committing,
  void Function(String path, String text)? write,
}) async {
  final head = await runner.run('git', ['rev-parse', 'HEAD']);
  if (head.status != 0) die('git rev-parse HEAD failed: ${said(head.stderr)}');
  final base = said(head.stdout);

  final before = {
    for (final path in versionFiles)
      path: File(p.join(root, path)).readAsStringSync(),
  };
  final after = {
    manifestPath:
        withVersion(before[manifestPath]!, version) ??
        die('$manifestPath has no version line'),
    frameworkManifestPath:
        withVersion(before[frameworkManifestPath]!, version) ??
        die('$frameworkManifestPath has no version line'),
    lockPath:
        withLockedVersion(before[lockPath]!, version) ??
        die('$lockPath locks no chord_tui'),
    heldVersionPath:
        withHeldVersion(before[heldVersionPath]!, version) ??
        die('$heldVersionPath holds no version'),
  };
  void undo() => before.forEach(
    (path, text) => File(p.join(root, path)).writeAsStringSync(text),
  );

  final Ran committed;
  try {
    after.forEach(
      write ?? (path, text) => File(p.join(root, path)).writeAsStringSync(text),
    );
    committing?.call({
      for (final path in versionFiles) path: sha256Of(p.join(root, path)),
    });
    committed = await runner.run('git', [
      'commit',
      '-q',
      '-m',
      'chore: chord v$version',
      '--',
      ...versionFiles,
    ]);
  } catch (_) {
    // Put back only what no commit holds: one that went through keeps
    // its bytes, for the state to recover from.
    final now = await runner.run('git', ['rev-parse', 'HEAD']);
    if (now.status != 0 || said(now.stdout) == base) undo();
    rethrow;
  }
  if (committed.status != 0) {
    undo();
    die(
      'git commit of ${versionFiles.join(', ')} failed: '
      '${said(committed.stderr)}',
    );
  }
  return base;
}

/// A local version commit, dropped once, or kept once pushed.
abstract interface class Held {
  /// Drops the commit, if it is still held, and stops watching signals.
  Future<void> drop();

  /// Keeps the commit, pushed, and stops watching signals.
  void keep();
}

/// Holds the version commit made on [head]: a signal while it is held
/// drops it, then raises the signal again with no handler left, so the run
/// ends by it ([watch] and [raise] are a test's way in). A drop and a
/// signal share one rollback, and the handlers stay until it has ended.
Held holdVersion(
  ReleaseRunner runner,
  String head, {
  required void Function(String line) err,
  Stream<ProcessSignal> Function(ProcessSignal signal)? watch,
  void Function(ProcessSignal signal) raise = raiseSignal,
}) {
  var kept = false;
  Future<void>? rolling;
  Future<void> rollback() => rolling ??= dropVersion(runner, head);
  late final void Function() off;
  off = dieBySignal(
    () async {
      if (kept) return;
      try {
        await rollback();
      } on ReleaseError catch (error) {
        err('release: ${error.message}');
      }
    },
    watch: watch,
    raise: raise,
  );
  return _Held(
    () async {
      if (kept) return;
      try {
        await rollback();
      } finally {
        // The handlers outlive the rollback by a turn of the event loop: a
        // signal that failed the stage must still end the run by itself.
        Timer.run(off);
      }
    },
    () {
      kept = true;
      off();
    },
  );
}

final class _Held implements Held {
  _Held(this._drop, this._keep);

  final Future<void> Function() _drop;
  final void Function() _keep;

  @override
  Future<void> drop() => _drop();

  @override
  void keep() => _keep();
}

/// The version's branch, main or its channel's, pushed to origin with the
/// version commit. A held commit (a run without a state) is dropped if the
/// push fails; one a state records stays, and the next run pushes it.
Future<void> pushVersion(
  ReleaseRunner runner,
  String version, {
  Held? held,
}) async {
  final branch = channelOf(version) ?? 'main';
  final pushed = await runner.run('git', ['push', '-q', 'origin', branch]);
  if (pushed.status != 0) {
    if (held == null) {
      die(
        'git push origin $branch failed; chore: chord v$version stays '
        'committed, and `$continueCommandText` pushes it: '
        '${said(pushed.stderr)}',
      );
    }
    await held.drop();
    die(
      'git push origin $branch failed, so chore: chord v$version is '
      'dropped: ${said(pushed.stderr)}',
    );
  }
  held?.keep();
}

/// How a refusal names the run that continues.
const continueCommandText = 'dart run tool/release.dart chord';

/// The version commit dropped: the branch back at [head]. `--keep`, so a
/// change a stage left in a tracked file is never thrown away with it.
Future<void> dropVersion(ReleaseRunner runner, String head) async {
  final reset = await runner.run('git', ['reset', '-q', '--keep', head]);
  if (reset.status != 0) {
    die(
      'git reset --keep $head failed, so the version commit is still on the '
      'branch: ${said(reset.stderr)}',
    );
  }
}
