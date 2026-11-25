// Messages between agents in the window: what came in is drawn `←` in the
// recipient's transcript, and a send_message call chord served is drawn
// `→`, never as `chord - send_message (MCP)(…)`.
import 'package:chord/session/agents_host.dart' show fromMain;
import 'package:chord/session/transcript/types.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show show, window;

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a message comes in as ← from @main and one sent goes out as '
        '→ to @main · queued, at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      show(w.connection, w.child);
      await t.pump();
      final conversation = w.connection.agents.conversationOf(w.child)!;
      conversation.deliver(fromMain, 'Run the parser tests now.');
      await settle(t);
      const input = {'text': 'Ran them: 2 failures.'};
      w.session.say({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'c1',
        'title': 'mcp__chord__send_message',
        'status': 'in_progress',
        'rawInput': input,
      });
      conversation.served(
        const ChordCall(
          tool: ChordTool.sendMessage,
          input: input,
          answer: {'delivered': 'queued'},
          queued: true,
        ),
      );
      await settle(t);
      final rows = [for (final row in t.screen.lines) row.trimRight()];
      final came = rows.indexOf(' ← from @main');
      expect(came, isNonNegative, reason: rows.join('\n'));
      expect(rows[came + 1], '   ⎿  Run the parser tests now.');
      final sent = rows.indexOf(' → to @main · queued');
      expect(sent, greaterThan(came), reason: rows.join('\n'));
      expect(rows[sent + 1], '   ⎿  Ran them: 2 failures.');
      expect(t.screen.text, isNot(contains('(MCP)')));
      expect(t.screen.text, isNot(contains('› Run the parser')));
      // `from ` dim, `@main` bold.
      expect(t.screen.styleAt(3, came).isDim, isTrue);
      expect(t.screen.styleAt(8, came).isBold, isTrue);
      expect(t.screen.styleAt(7, sent).isBold, isTrue);
    });
  }
}
