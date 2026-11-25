// A Read result carried as terminal output beside Codex exit bookkeeping.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord_tui/chord_tui.dart';

void main() {
  final relay = enricherRelay(m1Enrichers);
  var state = model.Transcript.empty;
  for (final update in <Message>[
    {
      'sessionUpdate': 'tool_call',
      'toolCallId': 'read',
      'title': 'Read add.py',
      'kind': 'read',
      'status': 'in_progress',
    },
    {
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 'read',
      'status': 'completed',
      'rawOutput': {'exit_code': 0},
      '_meta': {
        'terminal_output': {
          'terminal_id': 'file',
          'data': 'def add(a, b):\n    return a + b',
        },
      },
    },
  ]) {
    for (final message in relay.fromAgent({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {'sessionId': 'session', 'update': update},
    })) {
      state = reduceTranscript(
        state,
        model.UpdateAction(
          'turn',
          acp.SessionUpdate.fromJson(notificationOf(message)!.$2),
        ),
      );
    }
  }
  final call = state.entries.whereType<model.ToolEntry>().single.call;
  runApp(
    Builder(
      builder: (context) => Actions(
        bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
        child: Tool(call, expanded: true),
      ),
    ),
  );
}
