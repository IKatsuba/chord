import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'prompt_keys_test.dart' show read;

void main() {
  group('tester CTUI-182: modified visual history edges', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      for (final mod in ['ctrl', 'alt']) {
        testWidgets('$mod arrows use current soft rows after updates and '
            'resize at $size', (t) async {
          final c = TextAreaController();
          addTearDown(c.dispose);
          var older = 0, newer = 0;
          await t.pumpWidget(
            Column(
              children: [
                PromptInput(
                  controller: c,
                  windowRows: size.height,
                  onSubmit: (_) {},
                  onOlder: () => older++,
                  onNewer: () => newer++,
                ),
              ],
            ),
            size: size,
          );
          for (var i = 0; i < 1000; i++) {
            c.text = '界👩‍💻e\u0301\x1b[31m update $i ' * 30;
          }
          await t.pump();
          for (final next in [size, const Size(20, 12), size]) {
            await t.resize(next);
            final rows = c.lastLayout!.rows;
            c.cursor = rows[1].start;
            await t.pump();
            final cursor = c.cursor, text = c.text;
            await t.press('$mod+up $mod+down');
            expect((older, newer, c.cursor, c.text), (0, 0, cursor, text));
            c.cursor = rows.first.start;
            await t.pump();
            await t.press('$mod+up');
            c.cursor = rows.last.start;
            await t.pump();
            await t.press('$mod+down');
            expect((older, newer), (1, 1));
            older = newer = 0;
          }
          await t.pumpWidget(const SizedBox(), size: size);
          await t.press('$mod+up $mod+down');
          expect((older, newer), (0, 0));
        });
      }
      testWidgets('a bound modified arrow submits instead of recalling at '
          '$size', (t) async {
        final c = TextAreaController(text: 'draft 界🙂e\u0301');
        addTearDown(c.dispose);
        final sent = <String>[];
        var older = 0;
        await t.pumpWidget(
          Column(
            children: [
              PromptInput(
                controller: c,
                windowRows: size.height,
                walking: true,
                keymap: read({'ctrl+up': 'chat:submit'}),
                onSubmit: sent.add,
                onOlder: () => older++,
                onNewer: () {},
              ),
            ],
          ),
          size: size,
        );
        await t.press('ctrl+up');
        expect(sent, ['draft 界🙂e\u0301']);
        expect(older, 0);
      });
    }
  });
}
