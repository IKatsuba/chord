import 'package:chord/session/transcript/types.dart' show MessageFrom;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'code_pick_window_test.dart' show clickAt;
import 'editor_window_test.dart' show settle;
import 'message_colours_window_test.dart' show parserBesideLexer;
import 'selection_window_test.dart' show cellOf;
import 'wheel_window_test.dart' show wheel;

void main() {
  group('tester: session code controls use the drawn revision', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('copy leaves the prompt empty and run fills it, at $size', (
        t,
      ) async {
        final (:parser, :session) = await parserBesideLexer(t, size);
        session.chordServer = 'chord';
        parser.deliver(const MessageFrom('lexer', reachable: true), 'Code.');
        await settle(t);
        session.chunk('```sh\necho 界👩‍💻e\u0301\n```');
        session.turns.last.answer();
        await settle(t);
        final focus = t.focusManager.primaryFocus;
        await clickAt(t, cellOf(t, '[copy]'));
        await settle(t);
        expect(t.screen, shows("to the terminal's clipboard"));
        expect(t.screen, isNot(shows('! echo')));
        expect(t.focusManager.primaryFocus, same(focus));
        await clickAt(t, cellOf(t, '[run]'));
        await settle(t);
        expect(t.screen, shows('! echo 界👩‍💻e\u0301'));
        expect(session.turns, hasLength(1));
        expect(t.focusManager.primaryFocus, same(focus));
      });

      testWidgets('scrolled code still clicks after a resize at $size', (
        t,
      ) async {
        final (:parser, :session) = await parserBesideLexer(t, size);
        session.chordServer = 'chord';
        parser.deliver(const MessageFrom('lexer', reachable: true), 'Code.');
        await settle(t);
        session.chunk(
          '```sh\necho scrolled\n```\n\n${List.generate(60, (i) => 'After $i.\n').join('\n')}',
        );
        session.turns.last.answer();
        await settle(t);
        expect(t.screen, isNot(shows('[copy]')));
        for (var i = 0; i < 150 && !t.screen.text.contains('[copy]'); i++) {
          await t.mouse(wheel(3, 3));
        }
        expect(t.screen, shows('[copy]'));
        await clickAt(t, cellOf(t, '[copy]'));
        await settle(t);
        expect(t.screen, shows("sent 13 chars to the terminal's clipboard"));
        await t.resize(
          size.width == 120 ? const Size(80, 24) : const Size(120, 40),
        );
        await settle(t);
        await t.press('ctrl+x b esc');
        await settle(t);
        await clickAt(t, cellOf(t, '[run]'));
        await settle(t);
        expect(t.screen, shows('! echo scrolled'));
      });

      for (final ending in ['late', 'cancelled', 'exited']) {
        testWidgets('copy survives a $ending turn at $size', (t) async {
          final (:parser, :session) = await parserBesideLexer(t, size);
          session.chordServer = 'chord';
          parser.deliver(const MessageFrom('lexer', reachable: true), 'Code.');
          await settle(t);
          session.chunk('```sh\necho retained\n```');
          await settle(t);
          // The agent has not answered: the closed fence is already usable.
          await clickAt(t, cellOf(t, '[copy]'));
          await settle(t);
          expect(t.screen, shows("sent 13 chars to the terminal's clipboard"));
          if (ending == 'cancelled') {
            await t.press('esc');
            await settle(t);
            expect(session.cancels, 1);
          }
          if (ending == 'exited') {
            session.exit('Scripted exit');
          } else {
            session.turns.last.answer();
          }
          await settle(t);
          await clickAt(t, cellOf(t, '[copy]'));
          await settle(t);
          expect(t.screen, shows("sent 13 chars to the terminal's clipboard"));
          await t.press('ctrl+x b c');
          await settle(t);
          expect(t.screen, shows("sent 13 chars to the terminal's clipboard"));
        });
      }
    }
  });
}
