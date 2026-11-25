/// A limits reader's process: started leading a group of its own, bounded,
/// and on every way out closed down the ladder (its library closed and its
/// stdin ended, then SIGTERM, then SIGKILL) until the whole group is seen
/// gone. No request's failure, direct child's exit or library close alone
/// proves the cleanup. From the original's `platform/resource_process.ts`.
library;

import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;

import 'process.dart';

/// A reader's failure in words the answer may carry; any other failure
/// reads as a plain one. A `cleanup` one is the reader's process group not
/// seen gone, which the window's close reports.
final class ResourceReadError implements Exception {
  /// A failure of [kind], said as [message].
  const ResourceReadError(this.kind, this.message);

  /// `timeout`, `cancelled`, `startup`, `authentication`, `rate-limit`,
  /// `protocol` or `cleanup`.
  final String kind;
  final String message;

  @override
  String toString() => message;
}

/// How long a reader's process and its steps may take, and each rung of
/// its close.
typedef CollectorBounds = ({
  Duration total,
  Duration initialize,
  Duration request,
  Duration close,
  Duration term,
  Duration kill,
});

/// The bounds every official reader runs under.
const CollectorBounds collectorBounds = (
  total: Duration(seconds: 20),
  initialize: Duration(seconds: 8),
  request: Duration(seconds: 3),
  close: Duration(milliseconds: 500),
  term: Duration(milliseconds: 500),
  kill: Duration(milliseconds: 500),
);

/// [step] bounded by [limit] and by [cancelled]: a step past its limit is a
/// [TimeoutException], which reads as the read's timeout.
Future<T> resourceStep<T>(
  Future<T> step,
  CancellationToken cancelled,
  Duration limit,
) => step.timeout(limit).asCancellable(cancelled);

/// Whether nothing is left once [alive] says so, looked at every 10 ms
/// within [limit] measured on [watch], a monotonic clock, so a wall clock
/// set back while a rung waits never stretches the ladder past its bounds.
Future<bool> goneWithin(
  bool Function() alive,
  Duration limit, {
  Stopwatch Function() watch = Stopwatch.new,
}) async {
  final elapsed = watch()..start();
  while (alive() && elapsed.elapsed < limit) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return !alive();
}

Future<bool> _gone(GroupProcess group, Duration limit) =>
    goneWithin(group.alive, limit);

/// Closes [group]'s reader down the ladder; throws a `cleanup`
/// [ResourceReadError] when its group is not seen gone, or its exit never
/// seen.
Future<void> _closeGroup(
  GroupProcess group,
  Future<void> Function() close,
  CollectorBounds bounds,
  bool Function() exited,
  List<StreamSubscription<Object?>> listening,
) async {
  await Future.wait([
    Future(close).catchError((Object _) {}),
    group.stdin.close().catchError((Object _) {}),
    _gone(group, bounds.close),
  ]).timeout(bounds.close, onTimeout: () => const []);
  if (!await _gone(group, Duration.zero)) {
    group.signal(ProcessSignal.sigterm);
    if (!await _gone(group, bounds.term)) {
      group.signal(ProcessSignal.sigkill);
      await _gone(group, bounds.kill);
    }
  }
  // The group is seen gone once the VM reaps it, but the VM tells of the
  // exit later, over its own port, a delay load stretches: a group seen
  // gone gets the kill rung to be heard exiting, and no more.
  if (!group.alive() && !exited()) {
    await group.exit
        .then<void>((_) {}, onError: (Object _) {})
        .timeout(bounds.kill, onTimeout: () {});
  }
  for (final subscription in listening) {
    subscription.cancel().ignore();
  }
  if (group.alive() || !exited()) {
    throw const ResourceReadError(
      'cleanup',
      'Collector cleanup could not verify process-group exit.',
    );
  }
}

/// What a reader reads from its process: [group], bounded by [cancelled],
/// which also carries the read's total; [onClose] names how its library
/// closes, the ladder's first rung.
typedef ResourceRead<T> =
    Future<T> Function(
      GroupProcess group,
      CancellationToken cancelled,
      void Function(Future<void> Function() close) onClose,
    );

/// Runs [command] in [cwd] leading a group of its own and reads it with
/// [read], within [bounds]' total and [cancelled]; on every way out the
/// group is closed down the ladder. A failure is a [ResourceReadError] in
/// the original's words; a cancel or the total past ahead of a read that
/// answered still revokes its answer. [env] is laid over chord's, or, with
/// [ownEnvironment], is the environment whole. Tests give their own [kill].
Future<T> withResourceProcess<T>(
  List<String> command, {
  required String cwd,
  required CancellationToken cancelled,
  required ResourceRead<T> read,
  CollectorBounds bounds = collectorBounds,
  Map<String, String>? env,
  bool ownEnvironment = false,
  Kill? kill,
}) async {
  final deadline = CancellationToken();
  final timer = Timer(
    bounds.total,
    () => deadline.cancel(TimeoutException('the read took too long')),
  );
  final within = MergedCancellationToken([cancelled, deadline]);
  try {
    if (within.isCancelled) {
      throw const ResourceReadError(
        'cancelled',
        'Resource read cancelled before startup.',
      );
    }
    final GroupProcess group;
    try {
      group = await spawnGroup(
        command.first,
        command.sublist(1),
        cwd: cwd,
        env: env,
        ownEnvironment: ownEnvironment,
        kill: kill,
      );
    } on CannotStart {
      throw const ResourceReadError(
        'startup',
        'The collector process failed to start.',
      );
    }
    var exited = false;
    group.exit.then<void>((_) => exited = true, onError: (_) => exited = true);
    // What it says on stderr is no one's to see.
    final listening = <StreamSubscription<Object?>>[
      group.stderr.listen((_) {}, onError: (_) {}),
    ];
    Future<void> Function() close = () async {};
    final T result;
    try {
      try {
        await group.started.asCancellable(within);
      } on Object {
        if (within.isCancelled) rethrow;
        throw const ResourceReadError(
          'startup',
          'The collector process failed to start.',
        );
      }
      result = await read(
        group,
        within,
        (callback) => close = callback,
      ).asCancellable(within);
    } on ResourceReadError {
      rethrow;
    } on Object catch (error) {
      if (deadline.isCancelled || error is TimeoutException) {
        throw const ResourceReadError(
          'timeout',
          'Resource acquisition exceeded its deadline.',
        );
      }
      if (cancelled.isCancelled) {
        throw const ResourceReadError('cancelled', 'Resource read cancelled.');
      }
      final status = error is RpcException
          ? error.code
          : error is ResourceStatus
          ? error.status
          : null;
      throw status == 401 || status == 403
          ? const ResourceReadError(
              'authentication',
              'The provider refused the existing authentication.',
            )
          : status == 429
          ? const ResourceReadError(
              'rate-limit',
              'The provider rate-limited the resource read.',
            )
          : const ResourceReadError(
              'protocol',
              'The collector failed to return supported resource facts.',
            );
    } finally {
      await _closeGroup(group, close, bounds, () => exited, listening);
    }
    if (cancelled.isCancelled) {
      throw const ResourceReadError('cancelled', 'Resource read cancelled.');
    }
    if (deadline.isCancelled) {
      throw const ResourceReadError(
        'timeout',
        'Resource acquisition exceeded its deadline.',
      );
    }
    return result;
  } finally {
    timer.cancel();
  }
}

/// A failure that carries an HTTP-like status, which says authentication or
/// rate limiting.
abstract interface class ResourceStatus {
  /// The status, as 401, 403 or 429.
  int get status;
}
