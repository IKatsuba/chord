// A message's arrow and the agent it names take that agent's colour, as
// the original's AgentColours paints them: `← from @lexer` and
// `→ to @lexer` in lexer's, main and chord in none, and a failed or
// pending arrow in its own tone.
import 'package:chord/session/agents_host.dart' show fromMain;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart' show AgentOpened;
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../session/conversation_fake.dart';
import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show show, window;

/// The theme's second agent colour: lexer opens after parser.
final lexerColour = colorOf(agentColour(paletteOf('dark', true), 1)!);

final errorColour = colorOf(paletteOf('dark', true).error!);

/// The window with parser in front, on its session, and lexer opened
/// beside it.
Future<({Conversation parser, ScriptedSession session})> parserBesideLexer(
  WidgetTester t,
  Size size,
) async {
  final w = await window(t, size, EditorTerminal());
  final lexer = ScriptedSession();
  w.connection.agents.openChild(
    ChildInfo(id: 'a2', name: 'lexer', runtime: 'fake', openedAt: 0),
    (emit, key) {
      w.connection.fold.dispatch(AgentOpened(key));
      return Conversation(
        ({required onTraffic, required cancellationToken}) async => lexer,
      )..listen(emit);
    },
  );
  show(w.connection, w.child);
  await settle(t);
  return (
    parser: w.connection.agents.conversationOf(w.child)!,
    session: w.session,
  );
}

/// [conversation]'s `send_message` to lexer, served as [call].
void sendToLexer(
  Conversation conversation,
  ScriptedSession session,
  String id,
  ChordCall call, {
  String status = 'completed',
}) {
  session.say({
    'sessionUpdate': 'tool_call',
    'toolCallId': id,
    'title': 'mcp__chord__send_message',
    'status': status,
    'rawInput': call.input,
  });
  conversation.served(call);
}

/// The row drawn starting with [text].
int rowOf(WidgetTester t, String text) {
  final rows = t.screen.lines;
  final at = rows.indexWhere((row) => row.startsWith(text));
  expect(at, isNonNegative, reason: rows.join('\n'));
  return at;
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('← from @lexer and → to @lexer take lexer\'s colour, at '
        '$size', (t) async {
      final (:parser, :session) = await parserBesideLexer(t, size);
      parser.deliver(
        const MessageFrom('lexer', runtime: 'fake', reachable: true),
        'Tokens are ready.',
      );
      await settle(t);
      const input = {'to': 'lexer', 'text': 'Thanks.'};
      sendToLexer(
        parser,
        session,
        'c1',
        const ChordCall(
          tool: ChordTool.sendMessage,
          input: input,
          answer: {'delivered': 'sent'},
        ),
      );
      await settle(t);

      final came = rowOf(t, ' ← from @lexer · fake');
      expect(t.screen.styleAt(1, came).fg, lexerColour);
      for (var x = 8; x < 14; x++) {
        expect(t.screen.styleAt(x, came).fg, lexerColour, reason: 'col $x');
        expect(t.screen.styleAt(x, came).isBold, isTrue);
      }
      // `from ` and what follows the name stay dim, uncoloured.
      expect(t.screen.styleAt(3, came).fg, isNull);
      expect(t.screen.styleAt(3, came).isDim, isTrue);
      expect(t.screen.styleAt(15, came).fg, isNull);

      final sent = rowOf(t, ' → to @lexer');
      expect(t.screen.styleAt(1, sent).fg, lexerColour);
      expect(t.screen.styleAt(3, sent).fg, isNull);
      expect(t.screen.styleAt(3, sent).isDim, isTrue);
      for (var x = 6; x < 12; x++) {
        expect(t.screen.styleAt(x, sent).fg, lexerColour, reason: 'col $x');
        expect(t.screen.styleAt(x, sent).isBold, isTrue);
      }
    });

    testWidgets('main and chord stay uncoloured beside a coloured lexer, at '
        '$size', (t) async {
      final (:parser, :session) = await parserBesideLexer(t, size);
      // Each turn ends before the next message, so none waits in the
      // queue and all three are drawn in the transcript.
      for (final (from, text) in const [
        (fromMain, 'Run the parser tests.'),
        (MessageFrom('chord'), 'lexer is idle.'),
        (MessageFrom('lexer', reachable: true), 'Done.'),
      ]) {
        parser.deliver(from, text);
        await settle(t);
        session.turns.last.answer();
        await settle(t);
      }

      final lexer = rowOf(t, ' ← from @lexer');
      expect(t.screen.styleAt(1, lexer).fg, lexerColour);
      expect(t.screen.styleAt(8, lexer).fg, lexerColour);

      final main = rowOf(t, ' ← from @main');
      for (var x = 0; x < 13; x++) {
        expect(t.screen.styleAt(x, main).fg, isNull, reason: 'col $x');
      }
      expect(t.screen.styleAt(8, main).isBold, isTrue);
      final chord = rowOf(t, ' ← from chord');
      for (var x = 0; x < 13; x++) {
        expect(t.screen.styleAt(x, chord).fg, isNull, reason: 'col $x');
      }
      expect(t.screen.styleAt(1, chord).isDim, isTrue);
    });

    testWidgets('a failed arrow stays in the error colour, its name in '
        'lexer\'s, at $size', (t) async {
      final (:parser, session: _) = await parserBesideLexer(t, size);
      parser.deliver(
        const MessageFrom('lexer', note: MessageNote.failed, reachable: true),
        'It broke.',
      );
      await settle(t);
      final came = t.screen.lines.indexWhere(
        (row) => row.startsWith(' ← from @lexer'),
      );
      expect(came, isNonNegative, reason: t.screen.text);
      expect(t.screen.styleAt(1, came).fg, errorColour);
      expect(t.screen.styleAt(8, came).fg, lexerColour);
    });

    testWidgets('a refused send\'s arrow stays in the error colour, its '
        'name in lexer\'s, at $size', (t) async {
      final (:parser, :session) = await parserBesideLexer(t, size);
      sendToLexer(
        parser,
        session,
        'c1',
        const ChordCall(
          tool: ChordTool.sendMessage,
          input: {'to': 'lexer', 'text': 'Hello.'},
          error: 'No agent is named lexer.',
        ),
        status: 'failed',
      );
      await settle(t);
      final sent = rowOf(t, ' → to @lexer');
      expect(t.screen.styleAt(1, sent).fg, errorColour);
      expect(t.screen.styleAt(6, sent).fg, lexerColour);
    });

    testWidgets('a pending send\'s arrow stays dim, its name in lexer\'s, at '
        '$size', (t) async {
      final (:parser, :session) = await parserBesideLexer(t, size);
      // Served, so chord's, but still in progress.
      sendToLexer(
        parser,
        session,
        'c1',
        const ChordCall(
          tool: ChordTool.sendMessage,
          input: {'to': 'lexer', 'text': 'Hello.'},
        ),
        status: 'in_progress',
      );
      await settle(t);
      final sent = rowOf(t, ' → to @lexer');
      expect(t.screen.styleAt(1, sent).isDim, isTrue);
      expect(t.screen.styleAt(1, sent).fg, isNull);
      expect(t.screen.styleAt(6, sent).fg, lexerColour);
    });
  }
}
