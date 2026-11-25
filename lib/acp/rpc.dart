/// JSON-RPC over the agent's stdio: chord's requests through `json_rpc_2`'s
/// [Client], and a dispatcher of ours for the agent's, since `json_rpc_2`'s
/// `Peer` never gives a handler its request's id and the agent withdraws a
/// request by id (`$/cancel_request`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';

import 'plans.dart';
import 'schema.dart';

export 'package:json_rpc_2/json_rpc_2.dart' show RpcException;

/// Writes one message to the agent, through the connection's writer.
typedef Send = void Function(Map<String, Object?> message);

/// Answers a permission request; the token is cancelled once the answer no
/// longer matters, and chord has then answered `cancelled` itself.
typedef PermissionHandler =
    Future<RequestPermissionResponse> Function(
      RequestPermissionRequest request,
      CancellationToken token,
    );

/// Answers an `elicitation/create` with ACP's `CreateElicitationResponse`;
/// the token is cancelled once the answer no longer matters, and chord has
/// then answered `cancel` itself.
typedef ElicitationHandler =
    Future<Map<String, Object?>> Function(
      Map<String, Object?> params,
      CancellationToken token,
    );

/// Answers a plan request in its agent's words, given the request read, or
/// none for one that did not read; the token is cancelled once the answer
/// no longer matters, and chord has then answered `cancelled` itself.
typedef PlanHandler =
    Future<Map<String, Object?>> Function(
      PlanRequest? request,
      CancellationToken token,
    );

/// Registers [turn], a token the session's cancel cancels, while a request
/// of the agent's for session [sessionId] waits on the person; returns what
/// unregisters it.
typedef Hold =
    void Function() Function(String sessionId, CancellationToken turn);

/// Hands each decoded message from the agent, after the tap, to where it
/// belongs: a response to [chord], a request or `$/cancel_request` to
/// [agent]; every other notification, updates included, goes to the
/// traffic alone.
void route(
  Map<String, Object?> message, {
  required ChordRequests chord,
  required AgentRequests agent,
}) {
  if (message.containsKey('id')) {
    if (message.containsKey('method')) {
      agent.request(message);
    } else {
      chord.response(message);
    }
  } else if (message['method'] == cancelRequestMethod) {
    agent.cancelRequest(message);
  }
}

/// Hands each decoded message from the client to where it belongs, as the
/// SDK reads it: a request to [client], a response to [chord],
/// `$/cancel_request` and other notifications to [client]; anything else
/// is answered -32600 with itself as data.
void serve(
  Map<String, Object?> message, {
  required ChordRequests chord,
  required ClientRequests client,
  required Send send,
}) {
  final method = message['method'];
  if (message.containsKey('method')) {
    if (message.containsKey('id')) {
      client.request(message);
      return;
    }
    if (message['jsonrpc'] == '2.0' && method is String) {
      if (method == cancelRequestMethod) {
        client.cancelRequest(message);
      } else {
        client.notify(message);
      }
      return;
    }
  } else if (message.containsKey('id') ||
      message.containsKey('result') ||
      message.containsKey('error')) {
    chord.response(message);
    return;
  }
  send(errorMessage(null, -32600, 'Invalid request', (message,)));
}

/// The notification an agent withdraws one of its requests with.
const cancelRequestMethod = r'$/cancel_request';

/// chord's requests and notifications to the agent, through `json_rpc_2`'s
/// [Client]: it keeps the ids, the waiting requests and their errors, and
/// fails every waiting request once [close] is called.
class ChordRequests {
  /// Requests written through [send]. With [withdraws], a request whose
  /// token is cancelled before its answer is also withdrawn from the other
  /// side with `$/cancel_request`, as the SDK does for an aborted request;
  /// the server's asks to its client do, the window's requests to an
  /// agent do not.
  ChordRequests(Send send, {this._withdraws = false}) {
    _client = Client.withoutJson(
      StreamChannel<Object?>(_responses.stream, _SendSink(send)),
      idGenerator: () => _nextId++,
    )..listen();
  }

  final bool _withdraws;
  final _responses = StreamController<Object?>();
  late final Client _client;
  var _nextId = 0;

  /// The ids of chord's requests the agent has not answered yet.
  final _waiting = <Object?>{};

  /// How many requests wait for an answer, a withdrawn one included until
  /// it is answered or [close] releases it.
  int get waiting => _waiting.length;

  /// Sends [method] with [params] and settles with the agent's `result`, or
  /// fails with its error as an [RpcException]. [token] races the answer:
  /// once it is cancelled the wait ends with its exception, and the answer,
  /// when it comes, is dropped; a token already cancelled sends nothing.
  Future<Object?> request(
    String method,
    Map<String, Object?> params, {
    CancellationToken? token,
  }) {
    if (token != null && token.isCancelled) {
      return Future.error(token.exception!);
    }
    if (_client.isClosed) {
      return Future.error(StateError('The client is closed.'));
    }
    final id = _nextId;
    _waiting.add(id);
    final answer = _client.sendRequest(method, params);
    answer
        .then((_) {}, onError: (_) {})
        .whenComplete(() => _waiting.remove(id));
    if (token == null) return answer;
    final raced = Completer<Object?>();
    final listener = OnCancel((exception) {
      if (raced.isCompleted) return;
      raced.completeError(exception);
      if (_withdraws && _waiting.contains(id) && !_client.isClosed) {
        notify(cancelRequestMethod, {'requestId': id});
      }
    })..listen(token);
    answer.then(
      (value) {
        listener.forget();
        if (!raced.isCompleted) raced.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        listener.forget();
        if (!raced.isCompleted) raced.completeError(error, stack);
      },
    );
    return raced.future;
  }

  /// Sends the notification [method] with [params].
  void notify(String method, Map<String, Object?> params) =>
      _client.sendNotification(method, params);

  /// A response from the agent; one to no waiting request is dropped. A
  /// malformed one to a waiting request fails it with -32600 and the
  /// response as data, as the SDK's `Connection.handleResponse` does,
  /// where `json_rpc_2` would drop it and leave the request waiting.
  void response(Map<String, Object?> message) {
    if (_responses.isClosed) return;
    final id = message['id'];
    if (_waiting.contains(id) && !_wellFormed(message)) {
      _responses.add({
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': -32600,
          'message': 'Invalid request',
          'data': message,
        },
      });
      return;
    }
    _responses.add(_integralCode(message));
  }

  /// [message] with an error code written as an integral double (`1.0`)
  /// read as the integer it is, as the SDK reads every JSON number.
  static Map<String, Object?> _integralCode(Map<String, Object?> message) {
    final error = message['error'];
    if (error is! Map) return message;
    final code = error['code'];
    if (code is! double || !code.isFinite || code != code.truncateToDouble()) {
      return message;
    }
    return {
      ...message,
      'error': {...error, 'code': code.toInt()},
    };
  }

  /// A response [Client] takes: the envelope, exactly one of `result` and
  /// `error`, and an error with an int code and a string message.
  static bool _wellFormed(Map<String, Object?> message) {
    if (message['jsonrpc'] != '2.0') return false;
    final hasResult = message.containsKey('result');
    final hasError = message.containsKey('error');
    if (hasResult == hasError) return false;
    if (hasResult) return true;
    final error = message['error'];
    final code = error is Map ? error['code'] : null;
    final integral =
        code is int ||
        (code is double && code.isFinite && code == code.truncateToDouble());
    return error is Map && integral && error['message'] is String;
  }

  /// Fails every waiting request; nothing more is sent.
  Future<void> close() async {
    await _responses.close();
    await _client.close();
  }
}

/// [Client]'s sink: each message straight to the writer, synchronously, so
/// the tap's order is the wire's.
class _SendSink implements StreamSink<Object?> {
  _SendSink(this._send);

  final Send _send;
  final _done = Completer<void>();

  @override
  void add(Object? message) {
    if (!_done.isCompleted) _send((message as Map).cast<String, Object?>());
  }

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

/// The agent's requests to chord and how each is answered: a handler per
/// method, -32601, -32602 and -32600 as the SDK answers them, and exactly
/// one answer per request, whichever of answer, failure, withdrawal, turn
/// cancel or close comes first.
class AgentRequests {
  /// A dispatcher answering through [send]; [onPermission] answers
  /// permission requests, [closing] is the connection's close, and [hold]
  /// registers each waiting request under its session. [onElicitation]
  /// answers forms and links; without it each is cancelled, as the window
  /// declares none.
  AgentRequests({
    required this._send,
    required this._onPermission,
    required this._closing,
    this._hold,
    this.onElicitation,
  });

  final Send _send;
  final PermissionHandler _onPermission;
  final CancellationToken _closing;
  final Hold? _hold;

  /// Answers forms and links; without it each is cancelled.
  ElicitationHandler? onElicitation;

  /// Answers plan requests; without it each is cancelled. Set once the
  /// session that shows them is there.
  PlanHandler? onPlan;

  late final _incoming = Incoming(_send);

  /// How many of the agent's requests wait for an answer.
  int get running => _incoming.running;

  /// A message from the agent with an id and a method.
  void request(Map<String, Object?> message) {
    if (!_incoming.admits(message)) return;
    final id = message['id'];
    final method = message['method'] as String;
    final params = message['params'];
    switch (method) {
      case 'session/request_permission':
        final invalid = _invalidPermission(params);
        if (invalid != null) {
          _send(errorMessage(id, -32602, 'Invalid params', (invalid,)));
          return;
        }
        final request = RequestPermissionRequest.fromJson(
          params as Map<String, Object?>,
        );
        _answer(
          id,
          request.sessionId,
          RequestPermissionResponse.cancelled().toJson(),
          (token) async {
            final answer = await _onPermission(request, token);
            return _checked(answer, request);
          },
        );
      // Without a handler elicitation is not declared, and the original
      // cancels a mode it does not draw.
      case 'elicitation/create':
        final handler = onElicitation;
        // A mode ACP does not have is cancelled before anyone is asked.
        if (handler == null ||
            params is! Map<String, Object?> ||
            !const {'form', 'url'}.contains(params['mode'])) {
          _send(resultMessage(id, {'action': 'cancel'}));
          return;
        }
        final sessionId = params['sessionId'];
        _answer(id, sessionId is String ? sessionId : null, const {
          'action': 'cancel',
        }, (token) async => _reply(await handler(params, token)));
      // A plan is the person's to take: one that does not read, or that
      // nobody answers, is cancelled, never -32601, which cursor reads as
      // accepted.
      case 'cursor/create_plan' || 'x.ai/exit_plan_mode':
        final handler = onPlan;
        if (handler == null) {
          _send(resultMessage(id, planCancelled));
          return;
        }
        final request = planOf(method, params);
        _answer(
          id,
          request?.sessionId,
          planCancelled,
          (token) => handler(request, token),
        );
      default:
        _send(methodNotFound(id, method));
    }
  }

  /// `$/cancel_request`: withdraws that request; an unknown id, or one
  /// already answered, is ignored.
  void cancelRequest(Map<String, Object?> message) =>
      _incoming.cancelRequest(message);

  /// Runs [handler], answering [fallback] once the answer stops mattering or
  /// the handler fails, whichever comes first; one answer goes out.
  void _answer(
    Object? id,
    String? sessionId,
    Map<String, Object?> fallback,
    Future<Map<String, Object?>> Function(CancellationToken token) handler,
  ) {
    final withdrawn = _incoming.start(id);
    final turn = CancellationToken();
    final token = MergedCancellationToken([withdrawn, turn, _closing]);
    final release = sessionId == null ? null : _hold?.call(sessionId, turn);
    var settled = false;
    late final OnCancel listener;

    void settle(Map<String, Object?> result) {
      if (settled) return;
      settled = true;
      listener.forget();
      _incoming.finish(id, withdrawn);
      release?.call();
      _send(resultMessage(id, result));
    }

    // Enqueued inside the cancel itself, so close's barrier finds this
    // answer ahead of stdin's end.
    listener = OnCancel((_) => settle(fallback));
    if (token.isCancelled) {
      settle(fallback);
      return;
    }
    listener.listen(token);
    Future.sync(
      () => handler(token),
    ).then(settle, onError: (Object _) => settle(fallback));
  }

  /// A form's or a link's answer as it came, or `cancel` for one whose
  /// action ACP does not have.
  static Map<String, Object?> _reply(Map<String, Object?> answer) =>
      switch (answer['action']) {
        'accept' || 'decline' || 'cancel' => answer,
        _ => const {'action': 'cancel'},
      };

  /// [answer] as it goes on the wire, or the fallback for one a wrong
  /// handler made: an option the request did not offer, or no outcome.
  static Map<String, Object?> _checked(
    RequestPermissionResponse answer,
    RequestPermissionRequest request,
  ) {
    final cancelled = RequestPermissionResponse.cancelled().toJson();
    try {
      switch (answer.outcome) {
        case 'cancelled':
          return answer.toJson();
        case 'selected':
          final offered = request.options.any(
            (option) => option.optionId == answer.optionId,
          );
          return offered ? answer.toJson() : cancelled;
        default:
          return cancelled;
      }
    } on TypeError {
      return cancelled;
    }
  }

  /// Why a permission request's params do not hold what chord reads, or
  /// null when they do.
  static String? _invalidPermission(Object? params) {
    if (params is! Map<String, Object?>) return 'params must be an object';
    if (params['sessionId'] is! String) return 'sessionId must be a string';
    final toolCall = params['toolCall'];
    if (toolCall is! Map<String, Object?> ||
        toolCall['toolCallId'] is! String) {
      return 'toolCall.toolCallId must be a string';
    }
    final options = params['options'];
    if (options is! List<Object?>) return 'options must be an array';
    for (final (index, option) in options.indexed) {
      if (option is! Map<String, Object?>) {
        return 'options[$index] must be an object';
      }
      for (final field in const ['optionId', 'name', 'kind']) {
        if (option[field] is! String) {
          return 'options[$index].$field must be a string';
        }
      }
    }
    return null;
  }
}

/// Calls back once a token is cancelled, inside the cancel, or at once for
/// one already cancelled.
class OnCancel with Cancellable {
  /// A listener calling [_callback] with the token's exception.
  OnCancel(this._callback);

  final void Function(Exception exception) _callback;

  /// Starts listening to [token].
  void listen(CancellationToken token) {
    if (token.isCancelled) {
      _callback(token.exception!);
    } else {
      maybeAttach(token);
    }
  }

  /// Stops listening.
  void forget() => detach();

  @override
  void onCancel(Exception cancelException) {
    super.onCancel(cancelException);
    _callback(cancelException);
  }
}

/// What both sides that serve requests share: the envelope and id checks,
/// a token per running request that `$/cancel_request` cancels, and the
/// SDK's answers.
class Incoming {
  /// Requests answered, when they are malformed, through [_send].
  Incoming(this._send);

  final Send _send;

  /// The requests still running, by id. A JSON-RPC id is matched by value
  /// and type, `1` and `"1"` apart, which a Dart map does.
  final _running = <Object?, CancellationToken>{};

  /// How many requests wait for an answer.
  int get running => _running.length;

  /// Whether [message], one with an id and a method, is a request; one
  /// that is not is answered -32600 with itself as data, as the SDK does.
  bool admits(Map<String, Object?> message) {
    if (message['jsonrpc'] == '2.0' &&
        message['method'] is String &&
        isId(message['id'])) {
      return true;
    }
    _send(errorMessage(null, -32600, 'Invalid request', (message,)));
    return false;
  }

  /// The token `$/cancel_request` cancels for the request [id], running from
  /// now until [finish].
  CancellationToken start(Object? id) => _running[id] = CancellationToken();

  /// The request [id], started with [token], is answered.
  void finish(Object? id, CancellationToken token) {
    if (identical(_running[id], token)) _running.remove(id);
  }

  /// Whether the request [id] is still running.
  bool isRunning(Object? id) => _running.containsKey(id);

  /// `$/cancel_request`: cancels that request's token; an unknown id, or
  /// one already answered, is ignored.
  void cancelRequest(Map<String, Object?> message) {
    // As the SDK reads it: outside the envelope it is no notification, and
    // is answered -32600 without withdrawing anything.
    if (message['jsonrpc'] != '2.0') {
      _send(errorMessage(null, -32600, 'Invalid request', (message,)));
      return;
    }
    final params = message['params'];
    // An absent requestId is none, where an explicit null is an id.
    if (params is! Map<String, Object?> || !params.containsKey('requestId')) {
      return;
    }
    final id = params['requestId'];
    if (!isId(id)) return;
    _running[id]?.cancel();
  }

  /// Whether [id] is a JSON-RPC id: null, a string or a finite number.
  static bool isId(Object? id) =>
      id == null || id is String || (id is num && id.isFinite);
}

/// The answer [result] to the request [id].
Map<String, Object?> resultMessage(Object? id, Object? result) => {
  'jsonrpc': '2.0',
  'id': id,
  'result': result,
};

/// The error answer to the request [id]; [data], when given, is its data,
/// null included.
Map<String, Object?> errorMessage(
  Object? id,
  int code,
  String message, [
  (Object?,)? data,
]) => {
  'jsonrpc': '2.0',
  'id': id,
  'error': {
    'code': code,
    'message': message,
    if (data != null) 'data': data.$1,
  },
};

/// The SDK's -32601 for [method], to the request [id].
Map<String, Object?> methodNotFound(Object? id, String method) => errorMessage(
  id,
  -32601,
  '"Method not found": $method',
  ({'method': method},),
);

/// The SDK's `RequestError.internalError` for [error], thrown by a handler
/// that is not an [RpcException]: its message as JSON when it reads as
/// JSON, else as `details`.
RpcException internalError(Object error) {
  final details = switch (error) {
    StateError(:final message) => message,
    ArgumentError(:final message) => '$message',
    FormatException(:final message) => message,
    Exception() => '$error'.replaceFirst(RegExp(r'^\w*Exception: '), ''),
    _ => '$error',
  };
  Object? data;
  try {
    data = details.isEmpty ? <String, Object?>{} : jsonDecode(details);
  } on FormatException {
    data = {'details': details};
  }
  return RpcException(-32603, 'Internal error', data: data);
}

/// The SDK's -32800 for the request [id], withdrawn by the client.
RpcException requestCancelled(Object? id) =>
    RpcException(-32800, 'Request cancelled', data: {'requestId': id});

/// A request from the client, as its handler sees it.
final class Served<P> {
  /// The request [id] with its checked [params] and [token].
  const Served(this.id, this.params, this.token);

  /// The JSON-RPC id, by value and type.
  final Object? id;

  /// The params, checked and read.
  final P params;

  /// Cancelled by `$/cancel_request` naming [id], or by the connection's
  /// close.
  final CancellationToken token;
}

/// Reads a method's params, throwing an [RpcException] (-32602) for ones
/// that do not hold what chord reads.
typedef Check<P> = P Function(Object? params);

/// The client's requests to chord: a checked handler per method, the
/// SDK's -32600 before `initialize` and for malformed requests, -32601 and
/// -32602, and exactly one answer per request, enqueued at the moment it is
/// known.
class ClientRequests {
  /// A dispatcher answering through [send]; [closing] is the connection's
  /// end, which cancels every running request's token; [onNotificationFailed]
  /// hears a notification that failed, for a line on stderr.
  ClientRequests({
    required this._send,
    required this._closing,
    this._onNotificationFailed,
  });

  final Send _send;
  final CancellationToken _closing;
  final void Function(String method, RpcException error)? _onNotificationFailed;
  late final _incoming = Incoming(_send);
  final _requests = <String, void Function(Object? id, Object? params)>{};
  final _notifications = <String, void Function(Object? params)>{};
  var _initialized = false;

  /// The `initialize` requests not answered yet: the first that succeeds
  /// opens the rest, recorded as its answer goes, so the client's next
  /// request is never refused.
  final _initializing = <Object?>{};

  /// How many requests wait for an answer.
  int get running => _incoming.running;

  /// Serves [method] with [handle], whose result, or error, is the answer
  /// as soon as it is known.
  void immediate<P>(
    String method,
    Check<P> check,
    FutureOr<Object?> Function(Served<P> request) handle,
  ) => _requests[method] = (id, params) {
    final served = _served(id, check, params);
    if (served == null) return;
    final FutureOr<Object?> result;
    try {
      result = handle(served);
    } catch (error) {
      fail(id, error);
      return;
    }
    if (result is Future<Object?>) {
      result.then(
        (value) => respond(id, value),
        onError: (Object error) {
          fail(id, error);
        },
      );
    } else {
      respond(id, result);
    }
  };

  /// Serves [method] with [handle], which answers later through [respond]
  /// or [fail]; one it throws at once is the answer.
  void deferred<P>(
    String method,
    Check<P> check,
    void Function(Served<P>) handle,
  ) => _requests[method] = (id, params) {
    final served = _served(id, check, params);
    if (served == null) return;
    try {
      handle(served);
    } catch (error) {
      fail(id, error);
    }
  };

  /// Hears the notification [method]. Params [check] refuses, or a
  /// handler that throws, answer nothing and stop nothing, as the SDK only
  /// logs them: [onNotificationFailed] hears the method and the error as
  /// it would be answered.
  void notification<P>(
    String method,
    Check<P> check,
    void Function(P params) handle,
  ) => _notifications[method] = (params) {
    try {
      handle(check(params ?? const <String, Object?>{}));
    } catch (error) {
      _onNotificationFailed?.call(method, _asRpc(error));
    }
  };

  Served<P>? _served<P>(Object? id, Check<P> check, Object? params) {
    final token = _incoming.start(id);
    final P checked;
    try {
      // As the SDK: absent params are an empty object.
      checked = check(params ?? const <String, Object?>{});
    } catch (error) {
      fail(id, error);
      return null;
    }
    return Served(id, checked, MergedCancellationToken([token, _closing]));
  }

  /// Answers the request [id] with [result], unless it is answered.
  void respond(Object? id, Object? result) {
    if (!_incoming.isRunning(id)) return;
    _incoming.finish(id, _incoming._running[id]!);
    if (_initializing.remove(id)) _initialized = true;
    _send(resultMessage(id, result));
  }

  /// Answers the request [id] with [error]: an [RpcException] as it is, a
  /// cancellation after `$/cancel_request` -32800, anything else -32603.
  void fail(Object? id, Object error) {
    if (!_incoming.isRunning(id)) return;
    final token = _incoming._running[id]!;
    _incoming.finish(id, token);
    _initializing.remove(id);
    final rpc = _asRpc(error, cancelled: token.isCancelled, id: id);
    _send(
      errorMessage(id, rpc.code, rpc.message, switch (rpc.data) {
        null => null,
        final data => (data,),
      }),
    );
  }

  /// [error] as the SDK answers it: an [RpcException] as it is, a
  /// cancellation of a request [cancelled] by the client -32800 naming its
  /// [id], anything else -32603.
  static RpcException _asRpc(
    Object error, {
    bool cancelled = false,
    Object? id,
  }) => switch (error) {
    RpcException() => error,
    CancelledException() when cancelled => requestCancelled(id),
    _ => internalError(error),
  };

  /// A message from the client with an id and a method.
  void request(Map<String, Object?> message) {
    if (!_incoming.admits(message)) return;
    final id = message['id'];
    final method = message['method'] as String;
    if (!_initialized && method != 'initialize') {
      _send(
        errorMessage(
          id,
          -32600,
          "Invalid request: ACP connection must be initialized before "
          "'$method'",
        ),
      );
      return;
    }
    final serve = _requests[method];
    if (serve == null) {
      _send(methodNotFound(id, method));
      return;
    }
    if (method == 'initialize') _initializing.add(id);
    serve(id, message['params']);
  }

  /// A notification from the client other than `$/cancel_request`; one no
  /// handler takes is ignored.
  void notify(Map<String, Object?> message) =>
      _notifications[message['method']]?.call(message['params']);

  /// `$/cancel_request` from the client.
  void cancelRequest(Map<String, Object?> message) =>
      _incoming.cancelRequest(message);
}
