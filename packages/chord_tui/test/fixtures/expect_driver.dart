// An expect driver the test owns: started with Process.start, never
// Process.run, so a case that times out under load still kills it and
// what it spawned at teardown instead of leaving them with PPID 1. What
// it spawned is also written down as it spawns, since a spawned program
// has a session of its own and outlives a driver that dies abnormally,
// out of its tree and its process group.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

/// Every process under [pid], children before their own, read from `ps`.
Future<List<int>> descendantsOf(int pid) async {
  final listed = await Process.run('ps', ['-A', '-o', 'pid=,ppid=']);
  final children = <int, List<int>>{};
  for (final line in const LineSplitter().convert('${listed.stdout}')) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length != 2) continue;
    final child = int.tryParse(fields[0]);
    final parent = int.tryParse(fields[1]);
    if (child == null || parent == null) continue;
    (children[parent] ??= []).add(child);
  }
  final found = <int>[];
  void walk(int parent) {
    for (final child in children[parent] ?? const <int>[]) {
      found.add(child);
      walk(child);
    }
  }

  walk(pid);
  return found;
}

/// Kills [pid] and everything under it, the tree read before the first
/// kill so nothing is reparented away from it.
Future<void> killTree(int pid) async {
  final tree = [pid, ...await descendantsOf(pid)];
  for (final each in tree.reversed) {
    Process.killPid(each, ProcessSignal.sigkill);
  }
}

// A spawn is told from a later process given its pid by an identity read
// when it is recorded and again at teardown. On Linux that is the start
// time /proc gives in clock ticks since boot, compared for equality: a
// reused pid would have to be freed and handed out again within one tick.
// On macOS no such number is in reach of the Tcl hook, so it records the
// wall clock in microseconds after the spawn returns, and teardown asks the
// kernel for the process's start in microseconds: a process started after
// the record is not the spawn. Left open there: a pid freed and reused
// between the fork and the record, a window of microseconds, and a wall
// clock stepped back between the spawn and the teardown.

/// The identity of the process [pid] for [spawnedAs]: on Linux its start
/// in clock ticks since boot, on macOS its start in microseconds since the
/// epoch; null once it is gone or elsewhere.
int? spawnIdentity(int pid) {
  if (Platform.isLinux) {
    try {
      return _linuxStart(File('/proc/$pid/stat').readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }
  if (Platform.isMacOS) return _macStart(pid);
  return null;
}

/// Whether a process of [identity] is the one spawned and recorded as
/// [recorded] by the driver's spawn hook.
bool spawnedAs(int identity, int recorded) =>
    Platform.isLinux ? identity == recorded : identity <= recorded;

// The 22nd field of /proc/<pid>/stat, counted after the command, which is
// in parentheses and may hold spaces and parentheses of its own.
int? _linuxStart(String stat) {
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  return fields.length > 19 ? int.tryParse(fields[19]) : null;
}

// kinfo_proc from sysctl kern.proc.pid.<pid>: its first field, the start
// time, is a timeval.
int? _macStart(int pid) {
  final sysctl = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(
          Pointer<Int32>,
          Uint32,
          Pointer<Void>,
          Pointer<Size>,
          Pointer<Void>,
          Size,
        ),
        int Function(
          Pointer<Int32>,
          int,
          Pointer<Void>,
          Pointer<Size>,
          Pointer<Void>,
          int,
        )
      >('sysctl');
  const kinfoProcSize = 648;
  return using((arena) {
    final name = arena<Int32>(4);
    name.asTypedList(4).setAll(0, [1, 14, 1, pid]); // kern.proc.pid
    final info = arena<Uint8>(kinfoProcSize);
    final size = arena<Size>()..value = kinfoProcSize;
    if (sysctl(name, 4, info.cast(), size, nullptr, 0) != 0) return null;
    if (size.value != kinfoProcSize) return null;
    final seconds = info.cast<Int64>().value;
    final micros = (info + 8).cast<Int32>().value;
    return seconds * 1000000 + micros;
  });
}

// Every spawn the driver makes appends its pid and its identity to the
// file the environment names: on Linux the start /proc gives, elsewhere the
// wall clock in microseconds once it is made.
const _spawnedVariable = 'EXPECT_DRIVER_SPAWNED';
const _recordSpawns = r'''
rename spawn _expect_driver_spawn
proc _expect_driver_identity pid {
  if {[catch {open /proc/$pid/stat} stat]} {return [clock microseconds]}
  set line [read $stat]
  close $stat
  return [lindex [split [string range $line [string last ")" $line]+2 end]] 19]
}
proc spawn args {
  set pid [uplevel 1 [linsert $args 0 _expect_driver_spawn]]
  if {$pid > 0} {
    set identity [_expect_driver_identity $pid]
    set file [open $::env(EXPECT_DRIVER_SPAWNED) a]
    puts $file "$pid $identity"
    close $file
  }
  return $pid
}
''';

/// How long [runExpect] reads the output of a driver that has exited.
const expectDrain = Duration(seconds: 2);

/// The directory where [runExpect] last recorded its driver's spawns,
/// removed at the test's teardown, or at once if the driver failed to start.
Directory? lastExpectSpawns;

/// The pid of the expect driver [runExpect] last started.
int? lastExpectPid;

/// Runs `expect` with [arguments] as `Process.run` would and gives its
/// result, the driver and its tree killed at the test's teardown if it
/// has not ended; an ended one's pid may be another process's by then.
/// Each program it spawned that is still running then is killed with its
/// tree too, however the driver ended, unless its pid now names another
/// process, as [spawnIdentity] tells. It returns once the driver exits, its output
/// drained for at most [expectDrain]: an orphan it spawned may hold its
/// output open until that teardown.
Future<ProcessResult> runExpect(
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final spawns = Directory.systemTemp.createTempSync('expect-driver-');
  lastExpectSpawns = spawns;
  final spawned = File('${spawns.path}/spawned')..createSync();
  final Process process;
  try {
    process = await Process.start(
      'expect',
      ['-c', _recordSpawns, ...arguments],
      workingDirectory: workingDirectory,
      environment: {...?environment, _spawnedVariable: spawned.path},
    );
  } catch (_) {
    // No driver started, so no teardown is there to remove it.
    spawns.deleteSync(recursive: true);
    rethrow;
  }
  lastExpectPid = process.pid;
  var ended = false;
  addTearDown(() async {
    if (!ended) await killTree(process.pid);
    for (final line in spawned.readAsLinesSync()) {
      final [pid, recorded] = line.split(' ').map(int.parse).toList();
      final identity = spawnIdentity(pid);
      if (identity != null && spawnedAs(identity, recorded)) {
        await killTree(pid);
      }
    }
    spawns.deleteSync(recursive: true);
  });
  final out = StringBuffer();
  final err = StringBuffer();
  final reads = <StreamSubscription<String>>[];
  final drained = <Future<void>>[];
  // A read or decoding failure fails the run, as a joined stream would,
  // once both streams are drained or given up on.
  (Object, StackTrace)? failure;
  for (final (stream, into) in [(process.stdout, out), (process.stderr, err)]) {
    final done = Completer<void>();
    reads.add(
      stream
          .transform(systemEncoding.decoder)
          .listen(
            into.write,
            onDone: done.complete,
            onError: (Object error, StackTrace stack) =>
                failure ??= (error, stack),
          ),
    );
    drained.add(done.future);
  }
  final code = await process.exitCode;
  ended = true;
  await Future.wait(drained).timeout(expectDrain, onTimeout: () => []);
  for (final read in reads) {
    await read.cancel();
  }
  if (failure case (final error, final stack)) {
    Error.throwWithStackTrace(error, stack);
  }
  return ProcessResult(process.pid, code, '$out', '$err');
}
