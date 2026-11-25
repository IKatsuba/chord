/// A look inside chord's heap while it runs, from the original's
/// `platform/heap.ts`: on [heapSignal], a snapshot of the heap in the Dart
/// VM's own format, which Dart DevTools' memory view opens, and the
/// process's memory beside it. A compiled chord cannot take a snapshot
/// (the VM supports them only outside product mode); it still writes the
/// memory, and says why the snapshot is missing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The signal that has a running chord write a snapshot.
const heapSignal = ProcessSignal.sigusr2;

/// The files one snapshot leaves: the snapshot, when one could be taken,
/// and the memory, always.
typedef HeapFiles = ({String? snapshot, String stats});

/// The process's memory as the system sees it, now.
Map<String, Object?> heapNow(DateTime now) => {
  'pid': pid,
  'at': now.toUtc().toIso8601String(),
  'currentRss': ProcessInfo.currentRss,
  'maxRss': ProcessInfo.maxRss,
  'buildId': NativeRuntime.buildId,
};

/// Writes the VM's snapshot of the heap to the path given.
typedef SnapshotWriter = void Function(String path);

/// The VM's own heap snapshot writer.
void writeVmSnapshot(String path) =>
    NativeRuntime.writeHeapSnapshotToFile(path);

/// Writes a snapshot of the heap and the process's memory into [dir],
/// named by the pid and the time, so one chord's sort in the order they
/// were taken and two chords' never meet. Each file is written beside its
/// name and renamed onto it, so a file under its name is whole. The
/// snapshot is taken first, as the original's; one that cannot be taken
/// leaves the memory written all the same, and then throws why.
Future<HeapFiles> writeHeapSnapshot(
  String dir, {
  DateTime Function() now = DateTime.now,
  SnapshotWriter snapshot = writeVmSnapshot,
  Map<String, Object?> Function(DateTime now) stats = heapNow,
}) async {
  final at = now().toUtc().toIso8601String().replaceAll(RegExp('[:.]'), '-');
  final base = p.join(dir, 'chord-$pid-$at');
  final files = (snapshot: '$base.heapsnapshot', stats: '$base.json');
  await Directory(dir).create(recursive: true);
  Object? failed;
  StackTrace? trace;
  try {
    snapshot('${files.snapshot}.part');
    await File('${files.snapshot}.part').rename(files.snapshot);
  } catch (error, stack) {
    failed = error;
    trace = stack;
    // A half-written snapshot is no snapshot.
    final part = File('${files.snapshot}.part');
    if (await part.exists()) await part.delete();
  }
  final memory = File('${files.stats}.part');
  await memory.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(stats(now()))}\n',
  );
  await memory.rename(files.stats);
  if (failed != null) Error.throwWithStackTrace(failed, trace!);
  return files;
}

/// Has [heapSignal] write a snapshot into the directory [dir] names, asked
/// for each time so a missing home fails the snapshot and not chord's
/// start. Nothing is written to the terminal, which the window owns: a
/// failure is left as `heap-error.txt` in that directory, or nowhere when
/// there is none. A signal while a snapshot is being written is dropped,
/// as the one under way already has what it would. Without the handler,
/// the signal's default action would kill chord. Returns the function
/// that takes it off.
void Function() snapshotOnSignal(
  String Function() dir, {
  void Function(HeapFiles files)? written,
  Stream<ProcessSignal>? signals,
  Future<HeapFiles> Function(String dir) write = writeHeapSnapshot,
  DateTime Function() now = DateTime.now,
}) {
  var writing = false;
  final subscription = (signals ?? heapSignal.watch()).listen((_) async {
    if (writing) return;
    writing = true;
    String? into;
    try {
      into = dir();
      // Taken whether or not anyone hears of it: `?.` would skip it.
      final files = await write(into);
      written?.call(files);
    } catch (error, stack) {
      if (into != null) {
        await File(p.join(into, 'heap-error.txt'))
            .writeAsString(
              '${now().toUtc().toIso8601String()} $error\n$stack\n',
            )
            .then((_) {}, onError: (_) {});
      }
    } finally {
      writing = false;
    }
  });
  return () => unawaited(subscription.cancel());
}
