import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester CTUI-179: command history visual edges', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('soft rows and resize gate both command arrows at $size', (
        t,
      ) async {
        final c = TextAreaController(text: '界🙂e\u0301 ' * 80);
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
        for (final width in [size, const Size(20, 12), size]) {
          await t.resize(width);
          final rows = c.lastLayout!.rows;
          expect(rows.length, greaterThan(2));
          c.cursor = rows[1].start;
          await t.pump();
          final cursor = c.cursor;
          await t.press('super+up super+down');
          expect((older, newer, c.cursor), (0, 0, cursor));
          c.cursor = rows.first.end - 1;
          await t.pump();
          await t.press('super+up');
          expect(older, 1);
          c.cursor = rows.last.start;
          await t.pump();
          await t.press('super+down');
          expect(newer, 1);
          older = newer = 0;
        }
      });

      testWidgets('latest burst layout owns command edges at $size', (t) async {
        final c = TextAreaController(text: 'initial');
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
          c.text = '界🙂e\u0301\x1b[31m update $i ' * 30;
        }
        await t.pump();
        c.cursor = c.lastLayout!.rows[1].start;
        await t.pump();
        final cursor = c.cursor, text = c.text;
        await t.press('super+up super+down');
        expect((older, newer, c.cursor, c.text), (0, 0, cursor, text));
        c.text = '界🙂e\u0301';
        await t.pump();
        await t.press('super+up super+down');
        expect((older, newer), (1, 1));
      });
    }
  });
}
