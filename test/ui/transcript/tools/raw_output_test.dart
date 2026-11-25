import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final terminal in [false, true]) {
      for (final order in ['before', 'together', 'after']) {
        testWidgets('Read bookkeeping $order terminal=$terminal at $size', (
          t,
        ) async {
          final relay = enricherRelay(m1Enrichers);
          var state = model.Transcript.empty;
          void update(Message fields) {
            for (final message in relay.fromAgent({
              'jsonrpc': '2.0',
              'method': 'session/update',
              'params': {
                'sessionId': 'session',
                'update': {'toolCallId': 'read', ...fields},
              },
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

          const source = 'def add(a, b):\n    return a + b';
          final output = <String, Object?>{
            if (terminal)
              '_meta': {
                'terminal_output': {'terminal_id': 'file', 'data': source},
              }
            else
              'content': [
                {
                  'type': 'content',
                  'content': {'type': 'text', 'text': source},
                },
              ],
          };
          update({
            'sessionUpdate': 'tool_call',
            'title': 'Read add.py',
            'kind': 'read',
            'status': 'in_progress',
          });
          if (order == 'before') {
            update({
              'sessionUpdate': 'tool_call_update',
              'rawOutput': {'exit_code': 0},
            });
          }
          update({
            'sessionUpdate': 'tool_call_update',
            'status': 'completed',
            ...output,
            if (order == 'together') 'rawOutput': {'exit_code': 0},
          });
          if (order == 'after') {
            update({
              'sessionUpdate': 'tool_call_update',
              'rawOutput': {'exit_code': 0},
            });
          }
          final call = state.entries.whereType<model.ToolEntry>().single.call;
          expect(call.rawOutput, {'exit_code': 0});
          for (final expanded in [false, true]) {
            await t.pumpWidget(Tool(call, expanded: expanded), size: size);
            expect(t.screen.lines.take(4), [
              '',
              '⏺ Read(add.py)',
              '  ⎿  def add(a, b):',
              '         return a + b',
            ]);
            expect(t.screen.text, isNot(contains('exit_code')));
          }
        });
      }
    }
  }
}
