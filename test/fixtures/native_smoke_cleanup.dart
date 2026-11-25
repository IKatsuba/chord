import 'dart:io';

/// The tracked groups still present, including any orphaned group members.
Future<Set<int>> nativeSmokeGroups(Set<int> owned) async {
  final result = await Process.run('ps', ['-A', '-o', 'pgid=']);
  if (result.exitCode != 0) {
    throw StateError('Cannot inspect native smoke groups: ${result.stderr}');
  }
  return {
    for (final line in result.stdout.toString().split('\n'))
      if (int.tryParse(line.trim()) case final group?
          when owned.contains(group))
        group,
  };
}

Future<Set<int>> _waitForGroups(Set<int> owned, Duration bound) async {
  final watch = Stopwatch()..start();
  var alive = await nativeSmokeGroups(owned);
  while (alive.isNotEmpty && watch.elapsed < bound) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    alive = await nativeSmokeGroups(owned);
  }
  return alive;
}

/// Reaps the driver and verifies every recorded group is gone, even after
/// an early driver exit. Register with addTearDown so a cleanup failure is
/// reported alongside, rather than replacing, the primary assertion failure.
Future<void> cleanupNativeSmoke({
  required Process driver,
  required Iterable<int> Function() groupIds,
  Duration termBound = const Duration(seconds: 2),
  Duration killBound = const Duration(seconds: 3),
}) async {
  Object? driverFailure;
  StackTrace? driverStack;
  try {
    driver.kill(ProcessSignal.sigterm);
    try {
      await driver.exitCode.timeout(termBound);
    } on Object {
      driver.kill(ProcessSignal.sigkill);
      await driver.exitCode.timeout(killBound);
    }
  } catch (error, stack) {
    driverFailure = error;
    driverStack = stack;
  }

  final owned = groupIds().where((group) => group > 0).toSet();
  try {
    for (final group in owned) {
      Process.killPid(-group, ProcessSignal.sigterm);
    }
    var alive = await _waitForGroups(owned, termBound);
    for (final group in alive) {
      Process.killPid(-group, ProcessSignal.sigkill);
    }
    alive = await _waitForGroups(owned, killBound);
    if (alive.isNotEmpty) {
      throw StateError('Native smoke process groups survived SIGKILL: $alive');
    }
  } on Object {
    // Even a failed process inspection must not leave an owned group running.
    for (final group in owned) {
      Process.killPid(-group, ProcessSignal.sigkill);
    }
    rethrow;
  }
  if (driverFailure != null) {
    Error.throwWithStackTrace(driverFailure, driverStack!);
  }
}
