// Test-owned own-process FD proof for the real public record operations.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/record_worker.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sessions.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final class Gates {
  Gates() {
    subscription = port.listen((dynamic message) {
      final event = Map<String, Object?>.from(message as Map);
      events.add(event);
      for (final waiter in List.of(waiters)) {
        if (waiter.$1(event)) {
          waiters.remove(waiter);
          waiter.$2.complete(event);
        }
      }
    });
  }
  final port = ReceivePort();
  late final StreamSubscription<dynamic> subscription;
  final events = <Map<String, Object?>>[];
  final waiters =
      <
        (bool Function(Map<String, Object?>), Completer<Map<String, Object?>>)
      >[];

  Future<Map<String, Object?>> next(
    bool Function(Map<String, Object?>) matches,
  ) {
    for (final event in events) {
      if (matches(event)) return Future.value(event);
    }
    final ready = Completer<Map<String, Object?>>();
    waiters.add((matches, ready));
    return ready.future;
  }

  Future<void> close() async {
    await subscription.cancel();
    port.close();
  }
}

Future<List<Map<String, String>>> descriptors(String root) async =>
    Platform.isLinux ? procDescriptors(root) : lsofDescriptors(root);

/// The own descriptors under [root], read from /proc/self/fd as lsof's
/// would list them: a descriptor's path is its link, less the
/// " (deleted)" Linux adds once the file is gone, and its type is lsof's
/// REG or DIR for what the descriptor holds.
List<Map<String, String>> procDescriptors(String root) {
  final found = <Map<String, String>>[];
  final listed = Directory('/proc/self/fd').listSync(followLinks: false);
  for (final entry in listed) {
    final String target;
    try {
      target = Link(entry.path).targetSync();
    } on FileSystemException {
      // The listing's own descriptor, closed by now.
      continue;
    }
    final path = target.endsWith(' (deleted)')
        ? target.substring(0, target.length - ' (deleted)'.length)
        : target;
    if (path != root && !path.startsWith('$root/')) continue;
    final type = switch (FileStat.statSync(entry.path).type) {
      FileSystemEntityType.file => 'REG',
      FileSystemEntityType.directory => 'DIR',
      final other => '$other',
    };
    found.add({
      'descriptor': entry.uri.pathSegments.last,
      'type': type,
      'path': path == root ? '.' : path.substring(root.length + 1),
    });
  }
  return found;
}

Future<List<Map<String, String>>> lsofDescriptors(String root) async {
  final result = await Process.run('/usr/sbin/lsof', [
    '-a',
    '-p',
    '$pid',
    '-Fftn',
  ]);
  check(result.exitCode == 0, 'Own-process lsof snapshot unavailable.');
  final found = <Map<String, String>>[];
  var descriptor = '', type = '';
  for (final line in result.stdout.toString().split('\n')) {
    if (line.startsWith('f')) descriptor = line.substring(1);
    if (line.startsWith('t')) type = line.substring(1);
    if (line.startsWith('n$root/')) {
      found.add({
        'descriptor': descriptor,
        'type': type,
        'path': line.substring(root.length + 2),
      });
    } else if (line == 'n$root') {
      found.add({'descriptor': descriptor, 'type': type, 'path': '.'});
    }
  }
  return found;
}

Map<String, Object?> header(String id) => {
  'type': 'session',
  'version': 1,
  'sessionId': id,
  'agent': 'fake',
  'cwd': '.',
  'at': 1.25,
};
Map<String, Object?> prompt(int index) => {
  'type': 'prompt',
  'turnId': 'turn-$index',
  'prompt': 'Saved request $index 界😀',
  'images': 0,
  'at': 2.75,
};

Future<void> seed(Directory root) async {
  final records = Directory(recordsDir(root.path));
  await records.create();
  final padding = encodeRecord({
    'type': 'future',
    'ignored': 'x' * (256 * 1024),
  });
  for (var i = 0; i < 16; i++) {
    await File('${records.path}/$i.jsonl').writeAsString(
      '${encodeRecord(header('id-$i'))}${encodeRecord(prompt(i))}$padding',
    );
  }
  await File('${root.path}/selected.jsonl').writeAsString(
    [
          header('selected'),
          for (var i = 0; i < 256; i++) prompt(i),
        ].map(encodeRecord).join() +
        padding,
  );
  await File(
    '${root.path}/unsupported.jsonl',
  ).writeAsString(encodeRecord({...header('unsupported'), 'version': 2.75}));
}

Future<Map<String, Object?>> operation(
  String name,
  Future<Object?> Function(Directory root, CancellationToken token) body, {
  String? stage,
  int gates = 1,
  int activeFiles = 0,
  int activeDirectories = 0,
  Type? errorType,
  bool scanResult = false,
}) async {
  final allocated = await Directory.systemTemp.createTemp(
    'record-handles-$name-',
  );
  final root = Directory(await allocated.resolveSymbolicLinks());
  final probe = Gates(), token = CancellationToken();
  final trace = <Map<String, Object?>>[];
  var pending = 0;
  Future<Object?>? active;
  final report = <String, Object?>{'name': name};
  try {
    await seed(root);
    if (activeDirectories > 0) {
      // Exceed native enumeration batches so the first-event gate holds real DIR IO.
      for (var i = 0; i < 2048; i++) {
        await File('${recordsDir(root.path)}/ignored-$i.txt').writeAsString('');
      }
    }
    pending++;
    final pendingResult = runZoned(
      () async {
        try {
          final value = await body(root, token);
          return (value: value, error: null);
        } catch (error) {
          return (value: null, error: error);
        } finally {
          pending--;
        }
      },
      zoneValues: {
        recordWorkerTestKey: RecordWorkerTestHooks(
          events: probe.port.sendPort,
          gates: [?stage],
          observe: trace.add,
        ),
      },
    );
    active = pendingResult;
    if (stage != null) {
      final paths = <Object?>{};
      for (var i = 0; i < gates; i++) {
        final event = await probe.next(
          (event) =>
              event['type'] == 'gate' &&
              event['stage'] == stage &&
              !paths.contains(event['path']),
        );
        paths.add(event['path']);
      }
      final before = await descriptors(root.path);
      report['whileGated'] = before;
      check(
        before.where((fd) => fd['type'] == 'REG').length >= activeFiles,
        '$name did not expose $activeFiles active real files.',
      );
      check(
        before.where((fd) => fd['type'] == 'DIR').length >= activeDirectories,
        '$name did not expose $activeDirectories active real directories.',
      );
      report['observedRealIoGates'] = paths.length;
      token.cancelWithReason(name);
    }
    final outcome = await pendingResult;
    // Exactly one immediate snapshot: no retries, zero polling or grace period.
    final after = await descriptors(root.path);
    report['immediatelyAfterFuture'] = after;
    check(after.isEmpty, '$name retained owned descriptors after its Future.');
    check(
      pending == 0 && !token.hasCancellables,
      '$name retained pending work.',
    );
    check(trace.last['type'] == 'exit', '$name did not join SDK exit.');
    final closed = trace.singleWhere((event) => event['type'] == 'closed');
    check(
      closed['streams'] == 0 && closed['tasks'] == 0,
      '$name did not join owned streams/tasks.',
    );
    if (stage != null) {
      check(
        identical(outcome.error, token.exception),
        '$name lost cancel identity.',
      );
    } else if (errorType != null) {
      check(
        (errorType == FileSystemException &&
                outcome.error is FileSystemException) ||
            (errorType == UnsupportedRecordVersion &&
                outcome.error is UnsupportedRecordVersion),
        '$name lost domain error type.',
      );
    } else {
      check(outcome.error == null, '$name did not succeed.');
      if (scanResult) {
        final records = outcome.value as List<SessionRecord>;
        check(
          records.length == 16 && records.every((r) => r.lastUsedAt == 2.75),
          '$name lost summaries or fractional values.',
        );
      } else {
        final history = outcome.value as PreparedHistory;
        check(
          history.actions.length == 512 && history.rawHasPast,
          '$name lost selected projection.',
        );
      }
    }
    report.addAll({
      'outcome': stage != null
          ? 'cancelled'
          : errorType == null
          ? 'success'
          : 'caught-error',
      'closedStreams': closed['streams'],
      'closedTasks': closed['tasks'],
      'sdkExitJoined': trace.last['type'] == 'exit',
      'pendingFutures': pending,
    });
    await root.delete(recursive: true);
    check(!await root.exists(), '$name root was recreated.');
    final removed = await descriptors(root.path);
    report['afterRootDeletion'] = removed;
    report['rootRemoved'] = !await root.exists();
    check(
      removed.isEmpty && !await root.exists(),
      '$name retained/recreated its root.',
    );
    return report;
  } catch (_) {
    stderr.writeln(jsonEncode({...report, 'failed': true}));
    rethrow;
  } finally {
    token.cancel();
    await active;
    await probe.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<void> main() async {
  // A watchdog only bounds failure; it cannot make any cleanup assertion pass.
  final watchdog = Timer(const Duration(minutes: 2), () {
    stderr.writeln('Record handle proof watchdog expired.');
    exit(1);
  });
  try {
    final reports = <Map<String, Object?>>[];
    Future<Object?> scan(Directory root, CancellationToken token) =>
        readRecords(root.path, cancellationToken: token);
    Future<Object?> selected(Directory root, CancellationToken token) =>
        readRecordedHistory(
          '${root.path}/selected.jsonl',
          cancellationToken: token,
        );
    reports.add(
      await operation(
        'directory-cancel',
        scan,
        stage: 'directory',
        activeDirectories: 1,
      ),
    );
    reports.add(
      await operation(
        'eight-files-cancel',
        scan,
        stage: 'file',
        gates: 8,
        activeFiles: 8,
      ),
    );
    reports.add(
      await operation(
        'selected-cancel',
        selected,
        stage: 'selected',
        activeFiles: 1,
      ),
    );
    reports.add(
      await operation('projection-cancel', selected, stage: 'projection'),
    );
    reports.add(await operation('scan-success', scan, scanResult: true));
    reports.add(await operation('selected-success', selected));
    reports.add(
      await operation('directory-error', (root, token) async {
        await Directory(recordsDir(root.path)).delete(recursive: true);
        await File(recordsDir(root.path)).writeAsString('not a directory');
        return readRecords(root.path, cancellationToken: token);
      }, errorType: FileSystemException),
    );
    reports.add(
      await operation(
        'version-error',
        (root, token) => readRecordedHistory(
          '${root.path}/unsupported.jsonl',
          cancellationToken: token,
        ),
        errorType: UnsupportedRecordVersion,
      ),
    );
    stdout.writeln(
      jsonEncode({
        'runtime': Platform.version.split(' ').first,
        'mode': const bool.fromEnvironment('dart.vm.product') ? 'AOT' : 'JIT',
        'pathMatching': 'Canonical owned root; relative descriptor names only.',
        'snapshotPolicy':
            'Immediate single descriptor snapshot after public Future; no polling.',
        'physicalIsolateCount': null,
        'physicalExitLatency': null,
        'operations': reports,
      }),
    );
  } finally {
    watchdog.cancel();
  }
}
