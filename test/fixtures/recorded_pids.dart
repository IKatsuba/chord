// What a provider fixture of the original's recorded of its processes,
// killed when a test leaves them behind.
import 'dart:convert';
import 'dart:io';

/// Whether process [pid] works in [dir], a folder of this run's alone,
/// which what it starts inherits: `/proc` on Linux, `lsof` elsewhere.
bool worksIn(int pid, String dir) {
  final want = Directory(dir).resolveSymbolicLinksSync();
  if (Platform.isLinux) {
    try {
      return Link('/proc/$pid/cwd').resolveSymbolicLinksSync() == want;
    } on FileSystemException {
      return false;
    }
  }
  final shown =
      Process.runSync('lsof', ['-a', '-p', '$pid', '-d', 'cwd', '-Fn']).stdout
          as String;
  return shown.split('\n').contains('n$want');
}

/// Kills the processes a provider fixture recorded in [record] (its `pid`
/// and `descendant` entries) that still work in [dir], a folder unique to
/// this run, each with its process group, and waits up to [within] for
/// them to go; throws naming those still there.
///
/// A test that times out is abandoned with its read's cleanup still to
/// come, which the suite's end then cuts off: a provider that ignores
/// SIGTERM would outlive the run. Only a process this run started works in
/// [dir], so a reused pid, another run's included, is left alone.
/// Tests give their own [kill].
Future<void> killRecordedProviders(
  File record,
  String dir, {
  void Function(int pid)? kill,
  Duration within = const Duration(seconds: 5),
}) async {
  if (!record.existsSync()) return;
  final pids = <int>{};
  for (final line in record.readAsLinesSync()) {
    try {
      final entry = jsonDecode(line);
      if (entry is! Map) continue;
      for (final key in ['pid', 'descendant']) {
        if (entry[key] case final int pid) pids.add(pid);
      }
    } on FormatException {
      // A line cut off as the provider was killed.
    }
  }
  if (!Directory(dir).existsSync()) return;
  bool ours(int pid) => worksIn(pid, dir);
  final left = pids.where(ours).toList();
  for (final pid in left) {
    (kill ??
        (pid) {
          Process.runSync('kill', ['-KILL', '--', '-$pid']);
          Process.killPid(pid, ProcessSignal.sigkill);
        })(pid);
  }
  final until = DateTime.now().add(within);
  while (left.any(ours) && DateTime.now().isBefore(until)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final surviving = left.where(ours).toList();
  if (surviving.isNotEmpty) {
    throw StateError(
      'Recorded providers outlived their kill: ${surviving.join(', ')}',
    );
  }
}
