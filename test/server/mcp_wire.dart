// A bare MCP client over loopback HTTP, so a test reads every byte the
// server says: status, refusals, and JSON or SSE answers.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What one request got back.
typedef Reply = ({int status, Object? body, String? session});

/// Sends [message] to [url] as [token], in [session] when given; reads the
/// answer whether it comes as JSON or as an event stream.
Future<Reply> post(
  String url,
  Object? message, {
  String? token,
  String? session,
  String method = 'POST',
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(url));
    request.headers
      ..set('accept', 'application/json, text/event-stream')
      ..set('content-type', 'application/json')
      ..set('mcp-protocol-version', '2025-11-25');
    if (token != null) request.headers.set('authorization', 'Bearer $token');
    if (session != null) request.headers.set('mcp-session-id', session);
    if (message != null) request.write(jsonEncode(message));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    final type = response.headers.contentType?.mimeType;
    Object? body;
    if (type == 'text/event-stream') {
      for (final line in const LineSplitter().convert(text)) {
        if (line.startsWith('data:')) {
          final data = line.substring(5).trim();
          if (data.isNotEmpty) body = jsonDecode(data);
        }
      }
    } else if (text.isNotEmpty) {
      body = jsonDecode(text);
    }
    return (
      status: response.statusCode,
      body: body,
      session: response.headers.value('mcp-session-id'),
    );
  } finally {
    client.close(force: true);
  }
}

var _ids = 0;

/// A JSON-RPC request.
Map<String, Object?> rpc(String method, [Map<String, Object?>? params]) => {
  'jsonrpc': '2.0',
  'id': ++_ids,
  'method': method,
  'params': ?params,
};

/// An `initialize` request as an agent's client sends it.
Map<String, Object?> initialize() => rpc('initialize', {
  'protocolVersion': '2025-11-25',
  'capabilities': <String, Object?>{},
  'clientInfo': {'name': 'test', 'version': '1'},
});

/// An MCP session opened as [token]: its id and the initialize answer.
Future<({String session, Map<String, Object?> result})> open(
  String url,
  String token,
) async {
  final reply = await post(url, initialize(), token: token);
  final session = reply.session!;
  await post(
    url,
    {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
    token: token,
    session: session,
  );
  return (
    session: session,
    result: (reply.body as Map)['result'] as Map<String, Object?>,
  );
}

/// [method]'s result in [session].
Future<Map<String, Object?>> call(
  String url,
  String token,
  String session,
  String method, [
  Map<String, Object?>? params,
]) async {
  final reply = await post(
    url,
    rpc(method, params),
    token: token,
    session: session,
  );
  final body = reply.body as Map;
  if (body['error'] != null) throw StateError('${body['error']}');
  return body['result'] as Map<String, Object?>;
}
