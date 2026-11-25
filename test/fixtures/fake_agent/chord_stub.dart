// A stand-in for chord's MCP server on the loopback, for the parity test:
// both fakes call the same tools on it and get the same answers, so what
// each says of them can be compared. Each tool answers with its name and
// arguments as JSON; a `max` effort is refused, as chord refuses an effort
// the agent does not offer.
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:uuid/uuid.dart';

/// The tools the stand-in serves.
const chordStubTools = [
  'clear_agent',
  'close_agent',
  'get_budgets',
  'list_agents',
  'list_sessions',
  'list_teams',
  'monitor',
  'open_agent',
  'propose_team',
  'run_team',
  'send_message',
  'settings',
  'spawn_task',
];

/// What the stand-in answers [name] called with [arguments].
CallToolResult chordStubAnswer(String name, Map<String, dynamic> arguments) {
  // The saved teams as chord's teamsAnswer lays them out: one, `fixture`.
  if (name == 'list_teams') {
    return CallToolResult(
      content: [
        TextContent(
          text: jsonEncode({
            'runs': <Object?>[],
            'teams': [
              {
                'name': 'fixture',
                'description': 'A team the parity test saves',
                'body': 'Fix what the job names.',
                'lead': {'agent': 'fake', 'model': 'fake-large'},
                'members': [
                  {
                    'name': 'tester',
                    'role': 'Writes the failing test',
                    'instructions': 'Write the test first.',
                    'agent': 'codex',
                  },
                ],
                'runs': <Object?>[],
              },
            ],
          }),
        ),
      ],
    );
  }
  if (arguments['effort'] == 'max') {
    return const CallToolResult(
      content: [TextContent(text: 'The agent offers no effort max.')],
      isError: true,
    );
  }
  return CallToolResult(
    content: [
      TextContent(
        text: jsonEncode({
          'tool': name,
          'arguments': arguments,
          if (arguments['effort'] != null) 'effort': arguments['effort'],
          if (arguments['effort'] != null) 'note': 'Started as asked',
        }),
      ),
    ],
  );
}

/// The stand-in, serving until [close].
final class ChordStub {
  ChordStub._(this._http, this._tools) {
    _http.listen(_answer);
  }

  /// Starts it on the loopback, serving [tools]: with none, every call is
  /// refused as a tool the server does not have.
  static Future<ChordStub> start({List<String> tools = chordStubTools}) async =>
      ChordStub._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        tools,
      );

  final HttpServer _http;
  final List<String> _tools;
  final _sessions = <String, StreamableHTTPServerTransport>{};

  /// Where an MCP client reaches it.
  String get url => 'http://127.0.0.1:${_http.port}/mcp';

  Future<void> _answer(HttpRequest request) async {
    final id = request.headers.value('mcp-session-id');
    final open = id == null ? null : _sessions[id];
    if (open != null) return open.handleRequest(request);

    Object? body;
    if (request.method == 'POST') {
      body = jsonDecode(await utf8.decoder.bind(request).join());
    }
    late final StreamableHTTPServerTransport transport;
    transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        sessionIdGenerator: const Uuid().v4,
        onsessioninitialized: (sessionId) => _sessions[sessionId] = transport,
      ),
    );
    final server = McpServer(
      const Implementation(name: 'chord', version: '0.0.0'),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );
    for (final name in _tools) {
      server.registerTool(
        name,
        description: name,
        inputSchema: const JsonObject(properties: {}),
        callback: (arguments, _) async => chordStubAnswer(name, arguments),
      );
    }
    await server.connect(transport);
    await transport.handleRequest(request, body);
  }

  /// Stops serving: the sessions' streams are let go for at most a second,
  /// as one whose client has gone may never close, then the server goes.
  Future<void> close() async {
    await Future.wait([
      for (final transport in _sessions.values)
        transport.close().catchError((Object _) {}),
    ]).timeout(const Duration(seconds: 1), onTimeout: () => []);
    await _http.close(force: true);
  }
}
