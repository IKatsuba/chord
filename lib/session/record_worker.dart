/// Internal owned record IO operations; not an application scheduler API.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cancellation_token/cancellation_token.dart';

typedef RecordWorkerEntry = void Function(List<Object?> initial);
typedef RecordWorkerJob =
    Future<Object?> Function(RecordWorkerIO io, String path);
typedef RecordWorkerError = Map<String, Object?> Function(Object error);

// The unexported module's test-owned Zone seam never exists in normal calls.
final recordWorkerTestKey = Object();

/// Test controls observe real protocol/IO; they cannot supply cleanup ACKs.
final class RecordWorkerTestHooks {
  const RecordWorkerTestHooks({
    this.events,
    this.gates = const [],
    this.observe,
  });
  final SendPort? events;
  final List<String> gates;
  final void Function(Map<String, Object?> event)? observe;
}

final class _CleanupFailure extends StateError {
  _CleanupFailure(super.message);
}

/// Keeps cleanup/protocol failures above a late public-publication cancellation.
Object recordWorkerPublicationError(Object error, CancellationToken? token) =>
    error is _CleanupFailure ? error : token?.exception ?? error;

var _nextOperation = 0;

/// Runs a private worker, joining its explicit cleanup ACK and SDK exit.
Future<Object?> runRecordWorker(
  RecordWorkerEntry entry,
  String kind,
  String path, {
  CancellationToken? cancellationToken,
  Object Function(Map<String, Object?> error)? decodeError,
}) {
  if (cancellationToken?.isCancelled ?? false) {
    return Future.error(cancellationToken!.exception!);
  }
  final operation = _Operation(kind, path, cancellationToken, decodeError);
  operation.start(entry);
  return operation.future;
}

final class _Operation with Cancellable {
  _Operation(this.kind, this.path, this.token, this.decodeError)
    : id = _nextOperation++,
      hooks = Zone.current[recordWorkerTestKey] as RecordWorkerTestHooks?,
      zone = Zone.current {
    events.handler = receive;
    maybeAttach(token);
  }
  final int id;
  final String kind, path;
  final CancellationToken? token;
  final Object Function(Map<String, Object?>)? decodeError;
  final RecordWorkerTestHooks? hooks;
  final Zone zone;
  final events = RawReceivePort();
  final result = Completer<Object?>();
  Future<Object?> get future => result.future;
  SendPort? control;
  Exception? canceled;
  Map<String, Object?>? terminal;
  List<Object?>? remoteError;
  var settled = false;

  void trace(Map<String, Object?> event) {
    final observer = hooks?.observe;
    if (observer != null) zone.runGuarded(() => observer(event));
  }

  void start(RecordWorkerEntry entry) {
    if (isCancelled || token?.isCancelled == true) {
      finishError(canceled ?? token!.exception!, StackTrace.current);
      return;
    }
    try {
      final spawned = Isolate.spawn(
        entry,
        <Object?>[
          id,
          events.sendPort,
          if (hooks?.events != null)
            {'events': hooks!.events, 'gates': hooks!.gates}
          else
            null,
        ],
        onError: events.sendPort,
        onExit: events.sendPort,
        errorsAreFatal: true,
      );
      trace({'type': 'spawned', 'id': id});
      spawned.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (!settled) finishError(canceled ?? error, stack);
        },
      );
    } catch (error, stack) {
      finishError(canceled ?? error, stack);
    }
  }

  @override
  void onCancel(Exception exception) {
    super.onCancel(exception);
    if (settled) return;
    canceled ??= exception;
    control?.send({'type': 'cancel', 'id': id});
  }

  void receive(Object? message) {
    if (settled) return;
    if (message == null) {
      trace({'type': 'exit', 'id': id});
      final value = terminal;
      if (value != null && value['type'] == 'cleanup-failed') {
        finishError(
          _CleanupFailure('Record worker IO cleanup failed: ${value['cause']}'),
          StackTrace.fromString(value['stack'] as String? ?? ''),
        );
      } else if (value == null || remoteError != null) {
        finishError(
          _CleanupFailure(
            'Record worker exited without acknowledging IO cleanup.',
          ),
          remoteStack,
        );
      } else if (canceled != null) {
        finishError(canceled!, StackTrace.current);
      } else {
        final outcome = value['outcome'] as Map<String, Object?>;
        if (outcome['kind'] == 'success') {
          finish(outcome['value']);
        } else if (outcome['kind'] == 'error') {
          final error = outcome['error'] as Map<String, Object?>;
          finishError(
            decodeError?.call(error) ?? decodeRecordWorkerError(error),
            StackTrace.fromString(outcome['stack'] as String? ?? ''),
          );
        } else {
          finishError(
            StateError('Record worker failed: unexpected cancellation.'),
            StackTrace.current,
          );
        }
      }
      return;
    }
    if (message is List && message.length == 2) {
      remoteError = List<Object?>.from(message);
      trace({'type': 'sdk-error', 'id': id});
      return;
    }
    if (message is! Map || message['id'] != id) return;
    final event = Map<String, Object?>.from(message);
    trace(event);
    switch (event['type']) {
      case 'ready':
        if (control != null || terminal != null) return;
        if (event['control'] is! SendPort) return;
        control = event['control'] as SendPort;
        control!.send(
          canceled != null
              ? {'type': 'cancel', 'id': id}
              : {'type': 'run', 'id': id, 'kind': kind, 'path': path},
        );
      case 'closed':
        if (event['outcome'] is Map<String, Object?>) terminal ??= event;
      case 'cleanup-failed':
        terminal ??= event;
    }
  }

  StackTrace get remoteStack => StackTrace.fromString(
    remoteError == null
        ? ''
        : '${remoteError!.first}\n${remoteError!.elementAtOrNull(1) ?? ''}',
  );

  void release() {
    settled = true;
    events.close();
    control = null;
    terminal = null;
    detach();
  }

  void finish(Object? value) {
    release();
    result.complete(value);
  }

  void finishError(Object error, StackTrace stack) {
    release();
    result.completeError(error, stack);
  }
}

/// The native error envelope preserves filesystem error fields without coercion.
Map<String, Object?> encodeRecordWorkerError(Object error) =>
    error is FileSystemException
    ? {
        'kind': 'filesystem',
        'message': error.message,
        'path': error.path,
        if (error.osError != null)
          'osError': {
            'message': error.osError!.message,
            'code': error.osError!.errorCode,
          },
      }
    : {'kind': 'other', 'message': error.toString()};

/// Reconstructs errors after the worker cleanup/exit barrier has completed.
Object decodeRecordWorkerError(Map<String, Object?> error) {
  if (error['kind'] == 'filesystem') {
    final os = error['osError'] as Map<String, Object?>?;
    return FileSystemException(
      error['message'] as String,
      error['path'] as String,
      os == null ? null : OSError(os['message'] as String, os['code'] as int),
    );
  }
  return StateError('Record worker failed: ${error['message']}');
}

/// Worker-side entry plumbing; the job and error encoder are created locally.
void serveRecordWorker(
  List<Object?> initial,
  String kind,
  RecordWorkerJob job, {
  RecordWorkerError encodeError = encodeRecordWorkerError,
}) {
  final id = initial[0] as int, events = initial[1] as SendPort;
  final io = RecordWorkerIO._(id, initial[2] as Map<String, Object?>?);
  final control = ReceivePort();
  late StreamSubscription<dynamic> listener;
  var admitted = false, finishing = false;
  Future<void> finish(Map<String, Object?> outcome) async {
    if (finishing) return;
    finishing = true;
    Map<String, Object?> terminal;
    try {
      await io.close();
      terminal = {
        'type': 'closed',
        'id': id,
        'outcome': outcome,
        'streams': io.activeStreams,
        'tasks': io.pendingTasks,
      };
    } catch (error, stack) {
      terminal = {
        'type': 'cleanup-failed',
        'id': id,
        'cause': error.toString(),
        'stack': stack.toString(),
      };
    }
    await listener.cancel();
    control.close();
    await io.disposeTest();
    Isolate.exit(events, terminal);
  }

  Future<void> run(String path) async {
    Map<String, Object?> outcome;
    try {
      io.throwIfCancelled();
      final value = await job(io, path);
      io.throwIfCancelled();
      outcome = {'kind': 'success', 'value': value};
    } catch (error, stack) {
      outcome = io.cancelled
          ? {'kind': 'cancelled'}
          : {
              'kind': 'error',
              'error': encodeError(error),
              'stack': stack.toString(),
            };
    }
    await finish(outcome);
  }

  listener = control.listen((dynamic message) {
    if (message is! Map || message['id'] != id) return;
    if (message['type'] == 'cancel') {
      io.cancel();
      if (!admitted) finish({'kind': 'cancelled'});
    } else if (!admitted &&
        !finishing &&
        message['type'] == 'run' &&
        message['kind'] == kind) {
      admitted = true;
      run(message['path'] as String);
    }
  });
  events.send({'type': 'ready', 'id': id, 'control': control.sendPort});
}

final class _WorkerCancelled implements Exception {}

/// Owns each actual subscription and joins its cancellation and consuming task.
final class RecordWorkerIO {
  RecordWorkerIO() : this._(0, null);
  RecordWorkerIO._(int id, Map<String, Object?>? test)
    : _probe = test == null ? null : _WorkerProbe(id, test);
  final _WorkerProbe? _probe;
  final _readers = <_OwnedRead<dynamic>>{};
  final _tasks = <Future<void>>{};
  final _closing = <Future<void>>[];
  (Object, StackTrace)? _cleanupFailure;
  var _cancelled = false, _stopping = false;
  Future<void>? _closed;
  bool get cancelled => _cancelled;
  int get activeStreams => _readers.length;
  int get pendingTasks => _tasks.length;

  void throwIfCancelled() {
    if (_cancelled || _stopping) throw _WorkerCancelled();
  }

  Future<void> checkpoint({String stage = 'cpu'}) async {
    throwIfCancelled();
    await testGate(stage);
    await Future<void>(() {});
    throwIfCancelled();
  }

  Future<void> testGate(String stage, [String? path]) async {
    await _probe?.gate(stage, path);
  }

  Future<void> disposeTest() async {
    await _probe?.close();
  }

  void cancel() {
    _cancelled = true;
    _stopping = true;
    _probe?.release();
    for (final reader in List.of(_readers)) {
      _beginClose(reader);
    }
  }

  Future<void> forEach<T>(
    Stream<T> source,
    FutureOr<void> Function(T value) consume, {
    String stage = 'stream',
    String? path,
  }) {
    Future<void> read() async {
      throwIfCancelled();
      final reader = _OwnedRead<T>(source);
      _readers.add(reader);
      var first = true;
      try {
        while (!_stopping && await reader.iterator.moveNext()) {
          throwIfCancelled();
          if (first) {
            first = false;
            await testGate(stage, path);
          }
          throwIfCancelled();
          await consume(reader.iterator.current);
        }
        throwIfCancelled();
      } finally {
        try {
          await _beginClose(reader);
        } finally {
          _readers.remove(reader);
        }
      }
    }

    final task = read();
    _tasks.add(task);
    task.then<void>(
      (_) => _tasks.remove(task),
      onError: (Object _, StackTrace _) {
        _tasks.remove(task);
      },
    );
    return task;
  }

  Future<void> _beginClose(_OwnedRead<dynamic> reader) {
    final closed = reader.close().then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _cleanupFailure ??= (error, stack);
      },
    );
    _closing.add(closed);
    return closed;
  }

  Future<void> close() => _closed ??= _close();
  Future<void> _close() async {
    _stopping = true;
    _probe?.release();
    while (_readers.isNotEmpty || _tasks.isNotEmpty) {
      for (final reader in List.of(_readers)) {
        _beginClose(reader);
      }
      await Future.wait([
        ..._closing,
        for (final task in List.of(_tasks))
          task.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ]);
    }
    await Future.wait(_closing);
    if (_cleanupFailure case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
  }
}

// Capture the actual subscription even after StreamIterator drops it on error.
// Error cancellation is owned here, so its Future cannot be silently discarded.
final class _CaptureStream<T> extends Stream<T> {
  _CaptureStream(this.source);
  final Stream<T> source;
  StreamSubscription<T>? subscription;
  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => subscription = source.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: false,
  );
}

final class _OwnedRead<T> {
  _OwnedRead(Stream<T> source) {
    captured = _CaptureStream(source);
    iterator = StreamIterator(captured);
  }
  late final _CaptureStream<T> captured;
  late final StreamIterator<T> iterator;
  Future<void>? _closed;
  Future<void> close() => _closed ??= Future<void>.sync(() async {
    final iteratorClose = iterator.cancel();
    final subscriptionClose = captured.subscription?.cancel();
    await Future.wait([iteratorClose, ?subscriptionClose]);
  });
}

// Test gates use their own control port and release on ordinary cancellation.
// Normal operations create no test port and send no progress messages.
final class _WorkerProbe {
  _WorkerProbe(this.id, Map<String, Object?> options)
    : events = options['events'] as SendPort,
      stages = Set<String>.from(options['gates'] as List) {
    listener = control.listen((dynamic message) {
      if (message is int) pending.remove(message)?.complete();
    });
    events.send({'type': 'probe-ready', 'id': id, 'control': control.sendPort});
  }
  final int id;
  final SendPort events;
  final Set<String> stages;
  final control = ReceivePort();
  late final StreamSubscription<dynamic> listener;
  final pending = <int, Completer<void>>{};
  var next = 0, released = false;
  Future<void> gate(String stage, String? path) async {
    if (released || !stages.contains(stage)) return;
    final gate = next++, ready = Completer<void>();
    pending[gate] = ready;
    events.send({
      'type': 'gate',
      'id': id,
      'stage': stage,
      'gate': gate,
      'path': path,
    });
    await ready.future;
  }

  void release() {
    released = true;
    for (final gate in pending.values) {
      gate.complete();
    }
    pending.clear();
  }

  Future<void> close() async {
    release();
    await listener.cancel();
    control.close();
  }
}
