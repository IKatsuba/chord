/// chord's own MCP server: one per window, on the loopback at a port the
/// system picks, over Streamable HTTP. Every session the window opens gets
/// a token of its own, which says which session calls and so which tools it
/// has; a request without a token chord gave out is refused. From the
/// original's `server/server.ts`, over `mcp_dart` behind our own admission.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:uuid/uuid.dart';

import '../version.dart';
import 'tools.dart';

/// The name chord's server goes to the agent under, beside the user's.
const serverName = 'chord';

/// A session let in: its token, and the server entry that carries it.
typedef Admitted = ({
  String token,

  /// For ACP's `mcpServers`, beside the user's.
  Map<String, Object?> server,
});

/// chord's server, as the host uses it; a test may stand in for it.
abstract interface class ChordServer {
  /// Where it listens.
  String get url;

  /// A token for a session of [caller]'s, until it is revoked.
  Admitted admit(Caller caller);

  /// Refuses [token] from now on, and ends the MCP sessions it opened.
  void revoke(String token);

  /// Ends every MCP session and stops listening.
  Future<void> close();
}

/// An MCP session an agent opened, and the token it opened it with.
final class _Opened {
  _Opened(this.token, this.transport);

  final String token;
  final StreamableHTTPServerTransport transport;
}

const _uuid = Uuid();

/// A JSON-RPC error with no id, as the original's SDK answers one.
Future<void> _refused(HttpRequest request, int status, String message) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode({
        'jsonrpc': '2.0',
        'error': {'code': -32000, 'message': message},
        'id': null,
      }),
    );
  await request.response.close();
}

final _bearer = RegExp(r'^Bearer (.+)$');

String? _tokenOf(HttpRequest request) =>
    _bearer.firstMatch(request.headers.value('authorization') ?? '')?[1];

/// As the original SDK's isInitializeRequest: a JSON-RPC request named
/// `initialize` with the params its schema requires.
bool _isInitializeRequest(Object? body) {
  if (body is! Map) return false;
  if (body['jsonrpc'] != '2.0' || body['method'] != 'initialize') return false;
  final id = body['id'];
  if (id is! String && id is! int) return false;
  final params = body['params'];
  if (params is! Map) return false;
  final info = params['clientInfo'];
  return params['protocolVersion'] is String &&
      params['capabilities'] is Map &&
      info is Map &&
      info['name'] is String &&
      info['version'] is String;
}

/// An empty argument list, as the original's SDK lists a tool with none.
const _noArguments = JsonObject(properties: {});

CallToolResult _result(ToolResult result) => CallToolResult(
  content: [TextContent(text: result.text)],
  isError: result.isError,
  structuredContent: result.structured,
);

/// A token cancelled once the client cancels the request [signal] is for.
CancellationToken _cancelledBy(AbortSignal signal) {
  final token = CancellationToken();
  if (signal.aborted) {
    token.cancel();
  } else {
    signal.onAbort.first.then((_) => token.cancel()).ignore();
  }
  return token;
}

/// A fresh server with [caller]'s tools on it. Every tool list may change
/// as the session's role does, as the original declares.
McpServer _serverFor(Caller caller) {
  final server = McpServer(
    const Implementation(name: serverName, version: version),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(listChanged: true),
      ),
    ),
  );
  for (final tool in toolsOf(caller)) {
    final schema = tool.inputSchema;
    server.registerTool(
      tool.name,
      description: tool.description,
      inputSchema: schema == null ? _noArguments : JsonObject.fromJson(schema),
      callback: (args, extra) async => _result(await switch (tool.until) {
        final until? => until(args, _cancelledBy(extra.signal)),
        null => tool.call(args),
      }),
    );
  }
  return server;
}

/// Starts listening on the loopback; the URL is known when this completes.
/// A bind failure throws.
Future<ChordServer> serveChord() async {
  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // A stream stays open while a tool waits minutes on the person.
  http.idleTimeout = null;
  return _Served(http);
}

final class _Served implements ChordServer {
  _Served(this._http) {
    _http.listen(_answer);
  }

  final HttpServer _http;
  final _callers = <String, Caller>{};
  final _opened = <String, _Opened>{};

  @override
  String get url => 'http://127.0.0.1:${_http.port}/mcp';

  Future<void> _answer(HttpRequest request) async {
    try {
      await _handle(request);
    } on Object {
      try {
        await _refused(request, 500, 'Internal error');
      } on Object {
        // Its answer had begun; there is nothing more to say.
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final token = _tokenOf(request);
    final caller = token == null ? null : _callers[token];
    if (token == null || caller == null) {
      return _refused(request, 401, 'Unknown token');
    }

    final id = request.headers.value('mcp-session-id');
    if (id != null) {
      final session = _opened[id];
      if (session == null) return _refused(request, 404, 'Session not found');
      // A token opens its own sessions alone, so no session speaks as
      // another.
      if (session.token != token) {
        return _refused(request, 403, 'Session opened with another token');
      }
      return session.transport.handleRequest(request);
    }

    Object? body;
    if (request.method == 'POST') {
      try {
        body = jsonDecode(await utf8.decoder.bind(request).join());
      } on FormatException {
        body = null;
      }
    }
    if (!_isInitializeRequest(body)) {
      return _refused(request, 400, 'No session; initialize first');
    }

    late final StreamableHTTPServerTransport transport;
    transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        // Stateful: a stateless transport refuses every request after the
        // first.
        sessionIdGenerator: _uuid.v4,
        onsessioninitialized: (sessionId) {
          _opened[sessionId] = _Opened(token, transport);
        },
      ),
    );
    await _serverFor(caller).connect(transport);
    // mcp_dart has no onsessionclosed, and connect() replaces the
    // transport's onclose with the protocol's own: the session leaves the
    // map through a hook chained after it.
    final protocolClose = transport.onclose;
    transport.onclose = () {
      protocolClose?.call();
      final sessionId = transport.sessionId;
      if (sessionId != null &&
          identical(_opened[sessionId]?.transport, transport)) {
        _opened.remove(sessionId);
      }
    };
    await transport.handleRequest(request, body);
  }

  void _end(String id) {
    final session = _opened.remove(id);
    session?.transport.close().catchError((Object _) {});
  }

  @override
  Admitted admit(Caller caller) {
    final token = _uuid.v4();
    _callers[token] = caller;
    return (
      token: token,
      server: {
        'type': 'http',
        'name': serverName,
        'url': url,
        'headers': [
          {'name': 'Authorization', 'value': 'Bearer $token'},
        ],
      },
    );
  }

  @override
  void revoke(String token) {
    _callers.remove(token);
    for (final MapEntry(:key, :value) in _opened.entries.toList()) {
      if (value.token == token) _end(key);
    }
  }

  @override
  Future<void> close() async {
    _callers.clear();
    for (final id in _opened.keys.toList()) {
      _end(id);
    }
    await _http.close(force: true);
  }
}
