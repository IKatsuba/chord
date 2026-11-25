// The agent side of ACP over stdio, as the original's SDK serves it: lines of
// JSON, the SDK's error words, and `initialize` before anything else. The
// fake's own requests to the client go through json_rpc_2's Client, as the
// app's do; its dispatcher of incoming requests is its own, as the app's is
// (docs/decisions.md, CTUI-56), and imports nothing of the app.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';

import 'signals.dart';

/// A JSON-RPC error, with the SDK's words for each kind.
final class RequestError implements Exception {
  RequestError(this.code, this.message, [this.data]);

  /// Invalid JSON.
  factory RequestError.parseError([Object? data, String? more]) =>
      RequestError(-32700, 'Parse error${more == null ? '' : ': $more'}', data);

  /// Not a valid request.
  factory RequestError.invalidRequest([Object? data, String? more]) =>
      RequestError(
        -32600,
        'Invalid request${more == null ? '' : ': $more'}',
        data,
      );

  /// No such method.
  factory RequestError.methodNotFound(String method) =>
      RequestError(-32601, '"Method not found": $method', {'method': method});

  /// Params that do not fit the method.
  factory RequestError.invalidParams([Object? data, String? more]) =>
      RequestError(
        -32602,
        'Invalid params${more == null ? '' : ': $more'}',
        data,
      );

  /// The agent failed.
  factory RequestError.internalError([Object? data, String? more]) =>
      RequestError(
        -32603,
        'Internal error${more == null ? '' : ': $more'}',
        data,
      );

  /// Nobody is signed in.
  factory RequestError.authRequired([Object? data, String? more]) =>
      RequestError(
        -32000,
        'Authentication required${more == null ? '' : ': $more'}',
        data,
      );

  /// No such resource, a session among them.
  factory RequestError.resourceNotFound([String? uri]) => RequestError(
    -32002,
    'Resource not found${uri == null || uri.isEmpty ? '' : ': $uri'}',
    uri == null || uri.isEmpty ? null : {'uri': uri},
  );

  final int code;
  final String message;
  final Object? data;

  /// The `error` member of a response.
  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };

  @override
  String toString() => 'RequestError($code, $message)';
}

/// The SDK's line limit.
const maxMessageBytes = 32 * 1024 * 1024;

/// [value] as JavaScript writes it: a whole double is an integer.
Object? jsValue(Object? value) => switch (value) {
  double() when value.isFinite && value == value.truncateToDouble() =>
    value.toInt(),
  Map() => {
    for (final entry in value.entries)
      entry.key as String: jsValue(entry.value),
  },
  List() => [for (final each in value) jsValue(each)],
  _ => value,
};

/// `JSON.stringify(value)`, or with [indent] spaces.
String stringify(Object? value, [int indent = 0]) => indent == 0
    ? jsonEncode(jsValue(value))
    : JsonEncoder.withIndent(' ' * indent).convert(jsValue(value));

/// What a request's handler is given.
final class RequestContext {
  RequestContext(this.params, this.requestId, this.client);

  final Map<String, Object?> params;
  final Object? requestId;
  final Client client;
}

/// A request's handler, its params read by [parse] first; [empty] answers
/// `{}` for nothing, as the SDK does for some methods.
final class RequestSpec {
  const RequestSpec(this.handle, {this.parse, this.empty = false});

  final FutureOr<Object?> Function(RequestContext context) handle;
  final Map<String, Object?> Function(Object? params)? parse;
  final bool empty;
}

/// A notification's handler.
final class NotificationSpec {
  const NotificationSpec(this.handle, {this.parse});

  final FutureOr<void> Function(Map<String, Object?> params, Client client)
  handle;
  final Map<String, Object?> Function(Object? params)? parse;
}

/// The client, as the fake calls it.
final class Client {
  Client._(this._connection);

  final Connection _connection;

  /// Sends a notification; completes once it is written.
  Future<void> notify(String method, Object? params) =>
      _connection._send({'jsonrpc': '2.0', 'method': method, 'params': params});

  /// Sends a request; completes with its result, or fails with a
  /// [RequestError] of its error. Once [cancellation] aborts, the client is
  /// told `$/cancel_request` with its id, and its answer still awaited, as
  /// the SDK does.
  ///
  /// Its failure counts as handled at once, as [requestAny]'s does.
  Future<Map<String, Object?>> request(
    String method,
    Object? params, {
    Signal? cancellation,
  }) {
    final answer = requestAny(method, params, cancellation: cancellation).then(
      (result) =>
          result is Map ? result.cast<String, Object?>() : <String, Object?>{},
    );
    answer.ignore();
    return answer;
  }

  /// As [request], its result as the client sent it, of any shape. Its
  /// failure counts as handled at once, as the SDK's does, so a play that
  /// awaits it later sees it and none that never does fails the process.
  Future<Object?> requestAny(
    String method,
    Object? params, {
    Signal? cancellation,
  }) {
    final answer = _requestAny(method, params, cancellation: cancellation);
    answer.ignore();
    return answer;
  }

  Future<Object?> _requestAny(
    String method,
    Object? params, {
    Signal? cancellation,
  }) async {
    if (_connection.isClosed) throw StateError('ACP connection closed');
    final answer = _connection._requests.sendRequest(method, params);
    final id = _connection._lastRequestId;
    final stop = cancellation?.onAbort(
      () => notify(r'$/cancel_request', {'requestId': id}).ignore(),
    );
    try {
      return await answer;
    } on rpc.RpcException catch (error) {
      throw RequestError(error.code, error.message, error.data);
    } finally {
      stop?.call();
    }
  }
}

/// One served connection.
final class Connection {
  Connection._(this._output, this._requestSpecs, this._notificationSpecs) {
    client = Client._(this);
    _requests = rpc.Client.withoutJson(
      StreamChannel<Object?>(
        _responses.stream,
        _SendSink((message) {
          final request = message as Map<String, Object?>;
          _lastRequestId = request['id'];
          _send(request).ignore();
        }),
      ),
    );
    unawaited(_requests.listen());
  }

  /// Serves [input] and writes to [output], with these handlers.
  static Connection serve(
    Stream<List<int>> input,
    void Function(List<int> bytes) output,
    Future<void> Function() flush, {
    required Map<String, RequestSpec> requests,
    required Map<String, NotificationSpec> notifications,
  }) {
    final connection = Connection._(output, requests, notifications)
      .._flush = flush;
    connection._read(input);
    return connection;
  }

  final void Function(List<int> bytes) _output;
  late final Future<void> Function() _flush;
  final Map<String, RequestSpec> _requestSpecs;
  final Map<String, NotificationSpec> _notificationSpecs;
  late final Client client;
  late final rpc.Client _requests;
  final _responses = StreamController<Object?>();
  final _closed = Completer<void>();
  bool _initialized = false;

  /// The id of the last request json_rpc_2's Client sent, which it sends
  /// as it is asked.
  Object? _lastRequestId;
  Future<void> _writes = Future.value();

  bool get isClosed => _closed.isCompleted;

  /// Completes once the client has gone.
  Future<void> get closed => _closed.future;

  Future<void> _send(Map<String, Object?> message) {
    if (isClosed) return Future.error(StateError('ACP connection closed'));
    final line = utf8.encode('${stringify(message)}\n');
    final write = _writes.then((_) {
      if (isClosed) throw StateError('ACP connection closed');
      _output(line);
      return _flush();
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  void close() {
    if (isClosed) return;
    _closed.complete();
    unawaited(_responses.close());
    unawaited(_requests.close());
  }

  void _read(Stream<List<int>> input) {
    final pending = BytesBuilder(copy: false);
    var queue = Future<void>.value();
    late final StreamSubscription<List<int>> subscription;
    subscription = input.listen(
      (chunk) {
        var start = 0;
        for (var i = 0; i < chunk.length; i++) {
          if (chunk[i] != 0x0a) continue;
          pending.add(chunk.sublist(start, i));
          start = i + 1;
          final line = pending.takeBytes();
          queue = queue.then((_) => _line(line));
        }
        if (start < chunk.length) pending.add(chunk.sublist(start));
        if (pending.length > maxMessageBytes) {
          unawaited(subscription.cancel());
          close();
        }
      },
      onDone: () {
        final rest = pending.takeBytes();
        queue = queue
            .then((_) => rest.isEmpty ? null : _line(rest))
            .whenComplete(close);
      },
      onError: (Object _) => close(),
    );
  }

  Future<void> _line(Uint8List bytes) async {
    if (isClosed) return;
    var end = bytes.length;
    if (end > 0 && bytes[end - 1] == 0x0d) end--;
    final text = utf8.decode(bytes.sublist(0, end), allowMalformed: true);
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    Object? message;
    try {
      message = jsonDecode(trimmed);
    } on FormatException {
      await _protocolError(RequestError.parseError());
      return;
    }
    if (message is List) {
      await _protocolError(
        RequestError.invalidRequest(null, 'JSON-RPC batches are not supported'),
      );
    } else if (message is Map) {
      _receive(message.cast<String, Object?>());
    } else {
      await _protocolError(RequestError.invalidRequest(message));
    }
  }

  Future<void> _protocolError(RequestError error) => _send({
    'jsonrpc': '2.0',
    'id': null,
    'error': error.toJson(),
  }).catchError((Object _) {});

  static bool _isId(Object? id) =>
      id == null || id is String || (id is num && id.isFinite);

  void _receive(Map<String, Object?> message) {
    final envelope = message['jsonrpc'] == '2.0';
    final method = message['method'];
    final isRequest =
        envelope &&
        message.containsKey('id') &&
        method is String &&
        _isId(message['id']);
    final isNotification =
        envelope && !message.containsKey('id') && method is String;
    final responseShaped =
        !message.containsKey('method') &&
        (message.containsKey('id') ||
            message.containsKey('result') ||
            message.containsKey('error'));
    if (!isRequest && !isNotification && !responseShaped) {
      unawaited(_protocolError(RequestError.invalidRequest(message)));
      return;
    }
    if (message.containsKey('method')) {
      if (message.containsKey('id')) {
        unawaited(_request(method as String, message['id'], message['params']));
      } else {
        unawaited(_notification(method as String, message['params']));
      }
    } else if (message.containsKey('id')) {
      _responses.add(message);
    }
  }

  Future<void> _respond(Object? id, Map<String, Object?> result) =>
      _send({'jsonrpc': '2.0', 'id': id, ...result}).catchError((Object _) {});

  Future<void> _request(String method, Object? id, Object? params) async {
    if (!_initialized && method != 'initialize') {
      await _respond(id, {
        'error': RequestError.invalidRequest(
          null,
          "ACP connection must be initialized before '$method'",
        ).toJson(),
      });
      return;
    }
    final spec = _requestSpecs[method];
    if (spec == null) {
      await _respond(id, {
        'error': RequestError.methodNotFound(method).toJson(),
      });
      return;
    }
    Object? result;
    try {
      final read = spec.parse == null
          ? (params is Map
                ? params.cast<String, Object?>()
                : <String, Object?>{})
          : spec.parse!(params ?? <String, Object?>{});
      result = await spec.handle(RequestContext(read, id, client));
    } catch (error) {
      if (isClosed) return;
      await _respond(id, {'error': _errorOf(error).toJson()});
      return;
    }
    if (method == 'initialize') _initialized = true;
    await _respond(id, {'result': result ?? (spec.empty ? {} : null)});
  }

  Future<void> _notification(String method, Object? params) async {
    final spec = _notificationSpecs[method];
    if (spec == null) return;
    try {
      final read = spec.parse == null
          ? (params is Map
                ? params.cast<String, Object?>()
                : <String, Object?>{})
          : spec.parse!(params);
      await spec.handle(read, client);
    } catch (_) {
      // The SDK logs a failed notification and answers nothing.
    }
  }

  static RequestError _errorOf(Object error) {
    if (error is RequestError) return error;
    final details = error is StateError ? error.message : '$error';
    try {
      return RequestError.internalError(jsonDecode(details));
    } on FormatException {
      return RequestError.internalError({'details': details});
    }
  }
}

final class _SendSink implements StreamSink<Object?> {
  _SendSink(this._send);

  final void Function(Object? message) _send;
  final _done = Completer<void>();

  @override
  void add(Object? event) => _send(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) => stream.forEach(add);

  @override
  Future<void> close() {
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
