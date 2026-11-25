/// One release per checkout at a time, as the original's
/// `scripts/dev/release/lock.ts`: two runs in one clone would move each
/// other's version commits, and nothing in the tree or the branch catches
/// the second. The lock is `<file>.lock`, made by an exclusive create beside
/// a file in git's common directory, so every worktree of the clone shares
/// it. The owner's choice (CHD-623): it never goes stale, so no second run
/// takes over a live one, however long it waits; one a run left behind
/// (SIGKILL, a crash, a reboot) is refused like any other, naming its pid
/// and the path to remove by hand. The original's proper-lockfile takes a
/// directory; an exclusively created file is the same promise here.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'runner.dart';

/// The file the lock is taken beside, in git's common directory of [root].
Future<String> lockFile(ReleaseRunner runner, String root) async {
  final common = await runner.run('git', ['rev-parse', '--git-common-dir']);
  if (common.status != 0) {
    die('git rev-parse --git-common-dir failed: ${said(common.stderr)}');
  }
  final dir = p.normalize(p.join(root, said(common.stdout)));
  // Its real path: git names it relative from a main checkout and absolute
  // from a worktree.
  try {
    return p.join(Directory(dir).resolveSymbolicLinksSync(), 'chord-release');
  } on FileSystemException catch (error) {
    die("git's common directory $dir: ${error.message}");
  }
}

/// Takes the checkout's release lock, or dies naming the run that holds
/// it, and answers its release. [writePid] records the holder's pid; a
/// lock whose pid cannot be written is let go before the error goes on.
Future<Future<void> Function()> holdRelease(
  ReleaseRunner runner,
  String root, {
  void Function(String file)? writePid,
}) async {
  final file = await lockFile(runner, root);
  final lock = File('$file.lock');
  try {
    lock.createSync(exclusive: true);
  } on FileSystemException {
    if (!lock.existsSync()) rethrow;
    die(
      'another release runs in this checkout (pid ${_holder(file)}); if it '
      'was killed, remove ${lock.path}',
    );
  }
  try {
    (writePid ?? (file) => File(file).writeAsStringSync('$pid\n'))(file);
  } catch (_) {
    lock.deleteSync();
    rethrow;
  }
  // Once only: a second call after another run took the lock must not
  // remove that run's.
  var released = false;
  return () async {
    if (released) return;
    released = true;
    if (lock.existsSync()) lock.deleteSync();
  };
}

/// The pid the holding run wrote, if it has yet.
String _holder(String file) {
  try {
    final text = File(file).readAsStringSync().trim();
    return text.isEmpty ? 'unknown' : text;
  } on FileSystemException {
    return 'unknown';
  }
}
