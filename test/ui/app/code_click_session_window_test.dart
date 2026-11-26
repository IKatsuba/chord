// CHD-634: a click on a code block's [copy] or [run] does what its key
// does in a real session, where the session names chord's server and
// another agent has a colour: the code catalog reads the entry as it is
// drawn, so the clicked block's revision is the catalog's.
import 'package:chord/session/transcript/types.dart' show MessageFrom;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'code_pick_window_test.dart' show clickAt;
import 'editor_window_test.dart' show settle;
import 'message_colours_window_test.dart' show parserBesideLexer;
import 'selection_window_test.dart' show cellOf;

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    for (final server in const ['chord', null]) {
      testWidgets('a click on [copy] copies and on [run] runs a block beside '
          'a coloured agent, chord server $server, at $size', (t) async {
        final (:parser, :session) = await parserBesideLexer(t, size);
        session.chordServer = server;
        parser.deliver(
          const MessageFrom('lexer', runtime: 'fake', reachable: true),
          'Print it.',
        );
        await settle(t);
        session.say({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': '```sh\necho clicked\n```'},
        });
        session.turns.last.answer();
        await settle(t);
        expect(t.screen, shows('echo clicked'));

        await clickAt(t, cellOf(t, '[copy]'));
        await settle(t);
        expect(t.screen, shows("sent 12 chars to the terminal's clipboard"));

        await clickAt(t, cellOf(t, '[run]'));
        await settle(t);
        expect(t.screen, shows('! echo clicked'));
      });
    }
  }
}
