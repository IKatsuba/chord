/// chord's own stdout as ACP's writable side, from the original's
/// `acp/stdio.ts`: one queue, one writer, and what it can say of its
/// answers' writes.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'wire.dart';

/// What [Output] writes onto: stdout, or a test's own.
abstract interface class OutputSink {
  /// Buffers [bytes].
  void add(List<int> bytes);

  /// Settles once what was added is written; fails when it cannot be.
  Future<void> flush();

  /// Ends the sink once what was added is written.
  Future<void> close();
}

/// An [IOSink], stdout's kind, as an [OutputSink].
final class IOSinkOutput implements OutputSink {
  /// Writes onto [_sink].
  IOSinkOutput(this._sink);

  final IOSink _sink;

  @override
  void add(List<int> bytes) => _sink.add(bytes);

  @override
  Future<void> flush() => _sink.flush();

  @override
  Future<void> close() => _sink.close();
}

/// The one writer of ACP messages to the client: a FIFO pumped by one
/// `add` of everything queued and one `flush` at a time, never blocking
/// the isolate, so a client that stops reading holds output in memory, as
/// the original's. An answer counts as written once the flush that carried
/// it completes.
class Output {
  /// A writer onto [_sink]; [onFailed] hears the first failed write, the
  /// client gone.
  Output(this._sink, {this._onFailed});

  final OutputSink _sink;
  final void Function(Object error)? _onFailed;

  final _queue = <({Uint8List line, bool answers, Object? id})>[];
  final _expected = <Object?, Completer<void>>{};

  /// Settles once nothing expected is left; a new one begins with the first
  /// answer expected after that, as the original's `seeingWrites`.
  var _settled = Completer<void>()..complete();
  var _flushing = false;
  var _failed = false;
  var _closed = false;

  /// Whether a write failed: the other end is gone.
  bool get failed => _failed;

  /// Queues [message]; dropped once the output failed or closed, as the
  /// original drops a notification to a gone connection.
  void send(Map<String, Object?> message) {
    if (_failed || _closed) return;
    _queue.add((
      line: encodeLine(message),
      answers: message.containsKey('id') && !message.containsKey('method'),
      id: message['id'],
    ));
    _pump();
  }

  /// Settles once the answer to request [id] is written, or once nothing
  /// more can be; [drained] waits for it.
  Future<void> expect(Object? id) {
    if (_failed || _closed) return Future.value();
    if (_expected.isEmpty) _settled = Completer<void>();
    return (_expected[id] ??= Completer<void>()).future;
  }

  /// Settles once every answer expected, now or before it settles, is
  /// written, or none can be.
  Future<void> drained() {
    _settleWhenEmpty();
    return _settled.future;
  }

  void _settleWhenEmpty() {
    if (_expected.isEmpty && !_settled.isCompleted) _settled.complete();
  }

  void _pump() {
    if (_flushing || _failed || _queue.isEmpty) return;
    final batch = [..._queue];
    _queue.clear();
    final Future<void> flushed;
    try {
      // One add for the whole batch: a flood costs one write, not one per
      // line.
      final bytes = BytesBuilder(copy: false);
      for (final each in batch) {
        bytes.add(each.line);
      }
      _sink.add(bytes.takeBytes());
      flushed = _sink.flush();
    } catch (error) {
      // A sink that fails at once fails as one that fails later does.
      _fail(error);
      return;
    }
    _flushing = true;
    flushed.then(
      (_) {
        _flushing = false;
        for (final each in batch) {
          if (each.answers) _expected.remove(each.id)?.complete();
        }
        _settleWhenEmpty();
        if (_closed) {
          _end();
        } else {
          _pump();
        }
      },
      onError: (Object error) {
        _flushing = false;
        _fail(error);
      },
    );
  }

  void _fail(Object error) {
    if (_failed) return;
    _failed = true;
    _queue.clear();
    _giveUp();
    _onFailed?.call(error);
  }

  void _giveUp() {
    final expected = [..._expected.values];
    _expected.clear();
    for (final written in expected) {
      written.complete();
    }
    _settleWhenEmpty();
  }

  /// Takes nothing more, drops what is queued and not yet added, gives up
  /// on every expectation, and closes the sink once the flush in flight, if
  /// any, ends; returns at once, so a client that stopped reading holds
  /// nothing up. The drain before it is the way out's to bound.
  void close() {
    if (_closed) return;
    _closed = true;
    _queue.clear();
    _giveUp();
    if (_failed) return;
    if (!_flushing) _end();
  }

  void _end() => _sink.close().then((_) {}, onError: (Object _) {});
}
