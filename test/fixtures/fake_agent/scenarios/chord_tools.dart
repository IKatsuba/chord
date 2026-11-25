// chord's own MCP server, called as an agent calls it: through an MCP
// client, on the URL and headers the session was given, as the original's
// scenarios/chord_tools.ts. Here so far the client, the calls, and the
// shape of an MCP call as codex-acp sends one.
import 'package:mcp_dart/mcp_dart.dart' as mcp;

import '../options.dart';
import '../sessions.dart';
import '../turn.dart';

/// An MCP client's failure as the original's SDK words it, its message
/// `MCP error <code>: <message>` with no data, so a reply or a turn's
/// error says what the original's says.
final class McpFailure implements Exception {
  const McpFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// [call], its MCP failure worded as the original's SDK words one.
Future<T> asOriginal<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on mcp.McpError catch (error) {
    throw McpFailure('MCP error ${error.code}: ${error.message}');
  }
}

/// The text of a tool's answer, or what went wrong with it.
String _textOf(mcp.CallToolResult result) {
  final text = [
    for (final block in result.content)
      if (block is mcp.TextContent) block.text else '',
  ].join();
  return result.isError ? 'error: $text' : text;
}

/// A client connected to chord's own server, as the session was given it;
/// null when it was given none.
Future<mcp.McpClient?> chordClient(Turn turn) async {
  // chord's goes after the user's, renamed `chord-<n>` when one of theirs
  // is named `chord`, so the last of those names is chord's.
  Map<Object?, Object?>? chord;
  for (final server in mcpServers[turn.sessionId] ?? const <Object?>[]) {
    if (server is Map &&
        RegExp(r'^chord(-\d+)?$').hasMatch('${server['name']}') &&
        server['type'] == 'http') {
      chord = server;
    }
  }
  final url = chord?['url'];
  if (chord == null || url is! String) return null;

  // The original's MCP client writes nothing on stderr; mcp_dart's would.
  mcp.silenceMcpLogs();
  final client = mcp.McpClient(
    const mcp.Implementation(name: 'chord-fake-agent', version: '0.0.0'),
  );
  final transport = mcp.StreamableHttpClientTransport(
    Uri.parse(url),
    opts: mcp.StreamableHttpClientTransportOptions(
      requestInit: {
        'headers': <String, dynamic>{
          for (final header in (chord['headers'] as List?) ?? const [])
            '${(header as Map)['name']}': '${header['value']}',
        },
      },
    ),
  );
  await asOriginal(() => client.connect(transport));
  return client;
}

/// An MCP call as codex-acp sends one: a command by its dotted name, the
/// arguments wrapped with the server and the tool in `rawInput`.
Map<String, Object?> codexCall(
  String server,
  String tool,
  Map<String, Object?> arguments,
) => {
  'title': 'mcp.$server.$tool',
  'kind': 'execute',
  'rawInput': {'server': server, 'tool': tool, 'arguments': arguments},
  '_meta': {'is_mcp_tool_call': true},
};

/// One of chord's tools called as an agent calls an MCP tool: the call goes
/// out as a `tool_call`, in Claude's adapter's shape or Codex's, then the
/// answer as the call's update. The answer's text, or null when refused.
/// [timeout] in ms, the SDK's 60 s when not said, then cancelled with the
/// turn too.
Future<String?> callChord(
  Turn turn,
  mcp.McpClient client,
  String name,
  Map<String, Object?> arguments, {
  int? timeout,
  String shape = 'claude',
}) async {
  final toolCallId = turn.callId(name);
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'status': 'pending',
    ...(shape == 'claude'
        ? {'title': 'mcp__chord__$name', 'kind': 'other', 'rawInput': arguments}
        : codexCall('chord', name, arguments)),
  });

  mcp.BasicAbortController? abort;
  if (timeout != null) {
    final controller = mcp.BasicAbortController();
    turn.signal.onAbort(() => controller.abort(turn.signal.reason));
    abort = controller;
  }
  final result = await asOriginal(
    () => client.callTool(
      mcp.CallToolRequest(name: name, arguments: arguments),
      options: mcp.RequestOptions(
        timeout: Duration(milliseconds: timeout ?? 60000),
        signal: abort?.signal,
      ),
    ),
  );
  final text = _textOf(result);
  final failed = result.isError;
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': failed ? 'failed' : 'completed',
    'content': [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': failed ? text.substring(7) : text},
      },
    ],
  });
  return failed ? null : text;
}

/// The message `cutcalls` sends main, which its adapter cuts off.
const cutMessage =
    'CHD-393: the owner has a question on Q8, with the options for the '
    'headline:\n'
    '\n'
    '1. Draw the headline whole and wrap it.\n'
    '2. Cut it at the edge, as today.';

/// What `cutcalls` asked `open_agent` for, which its adapter cuts off too.
const cutOpen = <String, Object?>{
  'agent': 'fake',
  'name': 'parser',
  'prompt': 'agentchild',
};

Map<String, Object?> _stoppedText(String text) => {
  'type': 'content',
  'content': {'type': 'text', 'text': text},
};

/// A batch claude-agent-acp 0.93 drops as Claude switches to a steering
/// message, before either call's input has finished streaming (CHD-450).
Future<String> _unfinishedCalls(Turn turn, String status) async {
  const calls = <(String, Map<String, Object?>)>[
    ('send_message', {'to': 'main'}),
    ('open_agent', {}),
  ];
  final ids = [for (final (tool, _) in calls) turn.callId(tool)];
  for (final (index, (tool, input)) in calls.indexed) {
    final name = 'mcp__chord__$tool';
    final meta = {
      'claudeCode': {'toolName': name},
    };
    await turn.send({
      '_meta': meta,
      'toolCallId': ids[index],
      'sessionUpdate': 'tool_call',
      'name': name,
      'rawInput': <String, Object?>{},
      'status': 'pending',
      'title': name,
      'kind': 'other',
      'content': <Object?>[],
    });
    if (input.isNotEmpty) {
      await turn.send({
        '_meta': meta,
        'toolCallId': ids[index],
        'sessionUpdate': 'tool_call_update',
        'rawInput': input,
        'title': name,
        'kind': 'other',
      });
    }
  }
  await pause(turn.signal, stepMs * 20);
  await turn.say(['Read the steer; I will answer that first.']);
  for (final id in ids) {
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': id,
      // ACP v1's types have no `cancelled`; 0.93's v2 sends it.
      'status': status,
      'content': [_stoppedText('Claude stopped this tool call before it ran.')],
    });
  }
  return 'end_turn';
}

final Map<String, Play> chordTools = {
  // As `cutcalls`, with a list_sessions({}) after the two, cut off in the
  // reverse of the order they were made, the send_message's twice.
  'cutcallsback': (turn) async {
    const calls = <(String, Map<String, Object?>)>[
      ('send_message', {'to': 'main', 'text': cutMessage}),
      ('open_agent', cutOpen),
      ('list_sessions', {}),
    ];
    final ids = [for (final (tool, _) in calls) turn.callId(tool)];
    for (final (index, (tool, input)) in calls.indexed) {
      await turn.send({
        'sessionUpdate': 'tool_call',
        'toolCallId': ids[index],
        'title': 'mcp__chord__$tool',
        'kind': 'other',
        'status': 'pending',
        'rawInput': input,
      });
    }
    await pause(turn.signal, stepMs * 20);
    for (final index in const [2, 1, 0, 0]) {
      await turn.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': ids[index],
        'status': 'failed',
        '_meta': {
          'claudeCode': {'nonExecutionKind': 'interrupted'},
        },
      });
    }
    await turn.say(['I have stopped.']);
    return 'end_turn';
  },

  // The batch ended as ACP v1 ends a call that never ran: `failed`.
  'cutcallsunfinished': (turn) => _unfinishedCalls(turn, 'failed'),

  // The same batch ended as 0.93 ends it under the draft ACP v2.
  'cutcallsunfinishedv2': (turn) => _unfinishedCalls(turn, 'cancelled'),

  // A batch Claude's adapter cuts off as a steer interrupts it.
  'cutcalls': (turn) async {
    final calls = [
      (
        id: turn.callId('send_message'),
        tool: 'send_message',
        input: <String, Object?>{'to': 'main', 'text': cutMessage},
      ),
      (id: turn.callId('open_agent'), tool: 'open_agent', input: cutOpen),
    ];
    final bash = turn.callId('bash');
    for (final (:id, :tool, :input) in calls) {
      await turn.send({
        'sessionUpdate': 'tool_call',
        'toolCallId': id,
        'title': 'mcp__chord__$tool',
        'kind': 'other',
        'status': 'pending',
        'rawInput': <String, Object?>{},
      });
      await turn.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': id,
        'rawInput': input,
      });
    }
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': bash,
      'title': '`board show CHD-377`',
      'kind': 'execute',
      'status': 'pending',
    });
    // The batch is in flight a moment before the steer cuts it.
    await pause(turn.signal, stepMs * 20);
    for (final (:id, :tool, input: _) in calls) {
      final error =
          '<tool_use_error>Error calling tool (mcp__chord__$tool): '
          '</tool_use_error>';
      await turn.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': id,
        'status': 'failed',
        'rawOutput': error,
        'content': [_stoppedText(error)],
        '_meta': {
          'claudeCode': {'nonExecutionKind': 'interrupted'},
        },
      });
    }
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': bash,
      'status': 'failed',
      'content': [
        _stoppedText(
          "The user doesn't want to take this action right now. STOP what "
          'you are doing and wait for the user to tell you how to proceed.',
        ),
      ],
      '_meta': {
        'claudeCode': {'nonExecutionKind': 'cancelled'},
      },
    });
    await turn.say(['I have stopped.']);
    return 'end_turn';
  },

  // Calls `list_agents` and `list_sessions` and answers with what came
  // back, each as JSON.
  'chordtools': (turn) async {
    mcp.McpClient? client;
    try {
      client = await chordClient(turn);
      if (client == null) {
        await turn.say(['No chord server in this session.']);
        return 'end_turn';
      }
      final agents = await asOriginal(
        () => client!.callTool(const mcp.CallToolRequest(name: 'list_agents')),
      );
      final sessions = await asOriginal(
        () =>
            client!.callTool(const mcp.CallToolRequest(name: 'list_sessions')),
      );
      await turn.say([
        'list_agents:\n\n```json\n${_textOf(agents)}\n```\n\n',
        'list_sessions:\n\n```json\n${_textOf(sessions)}\n```',
      ]);
    } catch (error) {
      // The original says an Error's message, any other thrown value as
      // a string; an MCP failure's message is the SDK's.
      await turn.say([
        "chord's server failed: ${error is McpFailure ? error.message : error}",
      ]);
    } finally {
      await client?.close();
    }
    return 'end_turn';
  },
};
