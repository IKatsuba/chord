// CTUI-35 trial: chord's MCP server admission (../chord/src/server/server.ts)
// in front of mcp_dart's StreamableHTTPServerTransport, behind dart:io.
//
// stdout carries one JSON line, {url, tokens: {main, task}}, and nothing else.
// stdin takes `revoke <token>` lines; each is acknowledged on stderr as
// `revoked <token>` so the runner knows the revocation has happened.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mcp_dart/mcp_dart.dart';

/// Which tools a token's sessions have.
enum Role { main, task }

class Opened {
  Opened(this.token, this.transport);

  final String token;
  final StreamableHTTPServerTransport transport;
}

String uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// A JSON-RPC error with no id, as server.ts answers one.
Future<void> refused(HttpRequest request, int status, String message) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
    ..write(
      jsonEncode({
        'jsonrpc': '2.0',
        'error': {'code': -32000, 'message': message},
        'id': null,
      }),
    );
  await request.response.close();
}

String? bearer(HttpRequest request) {
  final match = RegExp(
    r'^Bearer (.+)$',
  ).firstMatch(request.headers.value('authorization') ?? '');
  return match?.group(1);
}

/// As the TS SDK's isInitializeRequest: a JSON-RPC request named
/// `initialize` with the params InitializeRequestSchema requires.
bool isInitializeRequest(Object? body) {
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

CallToolResult text(String text, [Map<String, dynamic>? structured]) =>
    CallToolResult(
      content: [TextContent(text: text)],
      structuredContent: structured,
    );

void registerTools(McpServer server, Role role) {
  if (role == Role.task) {
    server.registerTool(
      'send_message',
      description: 'Sends a message to the agent that started you.',
      inputSchema: JsonSchema.object(
        properties: {'text': JsonSchema.string(description: 'What to tell it')},
        required: ['text'],
      ),
      callback: (args, extra) => text(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'delivered': 'sent', 'to': 'parser'}),
      ),
    );
    return;
  }
  server.registerTool(
    'send_message',
    description: 'Sends a message to a long-lived agent you opened.',
    inputSchema: JsonSchema.object(
      properties: {
        'to': JsonSchema.string(
          description:
              'The agent, by the id open_agent answered or by its name',
        ),
        'text': JsonSchema.string(description: 'What to tell it'),
      },
      required: ['to', 'text'],
    ),
    callback: (args, extra) => text(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'delivered': 'sent', 'to': 'parser'}),
    ),
  );
  server.registerTool(
    'close_agent',
    description: 'Closes a long-lived agent you opened.',
    inputSchema: JsonSchema.object(
      properties: {
        'to': JsonSchema.string(
          description:
              'The agent, by the id open_agent answered or by its name',
        ),
      },
      required: ['to'],
    ),
    callback: (args, extra) {
      final to = args['to'] as String;
      if (to == 'gone') {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'No agent gone is open in this session; '
                  'list_sessions names them',
            ),
          ],
          isError: true,
        );
      }
      return text('$to has already ended', {'ended': to});
    },
  );
  server.registerTool(
    'clear_agent',
    description: 'Clears a long-lived agent you opened.',
    inputSchema: JsonSchema.object(
      properties: {
        'to': JsonSchema.string(
          description:
              'The agent, by the id open_agent answered or by its name',
        ),
      },
      required: ['to'],
    ),
    callback: (args, extra) {
      final to = args['to'] as String;
      return text(
        '$to (id a1) has a fresh session; it knows nothing of earlier turns.',
        {'cleared': to, 'id': 'a1'},
      );
    },
  );
}

Future<void> main() async {
  final callers = <String, Role>{uuid(): Role.main, uuid(): Role.task};
  final opened = <String, Opened>{};

  void end(String id) {
    final session = opened.remove(id);
    unawaited(session?.transport.close().catchError((_) {}));
  }

  Future<void> handle(HttpRequest request) async {
    final token = bearer(request);
    final caller = token == null ? null : callers[token];
    if (token == null || caller == null) {
      return refused(request, 401, 'Unknown token');
    }

    final id = request.headers.value('mcp-session-id');
    if (id != null) {
      final session = opened[id];
      if (session == null) return refused(request, 404, 'Session not found');
      if (session.token != token) {
        return refused(request, 403, 'Session opened with another token');
      }
      return session.transport.handleRequest(request);
    }

    Object? body;
    if (request.method == 'POST') {
      try {
        body = jsonDecode(await utf8.decoder.bind(request).join());
      } catch (_) {
        body = null;
      }
    }
    if (!isInitializeRequest(body)) {
      return refused(request, 400, 'No session; initialize first');
    }

    late final StreamableHTTPServerTransport transport;
    transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        sessionIdGenerator: uuid,
        onsessioninitialized: (sessionId) {
          opened[sessionId] = Opened(token, transport);
        },
      ),
    );
    final server = McpServer(
      const Implementation(name: 'chord', version: '0.71.0'),
    );
    registerTools(server, caller);
    await server.connect(transport);
    // mcp_dart has no onsessionclosed, and connect() replaces
    // transport.onclose with the protocol's own, so the session is
    // forgotten through a hook chained after connect: a DELETE closes the
    // transport, which calls it.
    final protocolClose = transport.onclose;
    transport.onclose = () {
      protocolClose?.call();
      final sessionId = transport.sessionId;
      if (sessionId != null) opened.remove(sessionId);
    };
    await transport.handleRequest(request, body);
  }

  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  http.listen((request) async {
    try {
      await handle(request);
    } catch (_) {
      try {
        await refused(request, 500, 'Internal error');
      } catch (_) {}
    }
  });

  final tokens = callers.entries.toList();
  stdout.writeln(
    jsonEncode({
      'url': 'http://127.0.0.1:${http.port}/mcp',
      'tokens': {for (final entry in tokens) entry.value.name: entry.key},
    }),
  );
  await stdout.flush();

  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) {
          final parts = line.trim().split(' ');
          if (parts.length == 2 && parts[0] == 'revoke') {
            final token = parts[1];
            callers.remove(token);
            for (final entry in opened.entries.toList()) {
              if (entry.value.token == token) end(entry.key);
            }
            stderr.writeln('revoked $token');
          }
        },
        onDone: () async {
          for (final id in opened.keys.toList()) {
            end(id);
          }
          await http.close(force: true);
          exit(0);
        },
      );
}
