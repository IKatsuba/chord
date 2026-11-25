// cmd+← and cmd+→ in the prompt go to the shown row's start or end, wrapped
// or not, as the original's OpenTUI textarea (docs/guide.md 259-262);
// ctrl+a and ctrl+e keep the logical line.
import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('CTUI-163: cmd+left/right in a wrapped prompt row, ctrl+a/e '
        'on its line, at $size', (t) async {
      final c = TextAreaController();
      await t.pumpWidget(
        Column(
          children: [
            PromptInput(
              controller: c,
              windowRows: size.height,
              onSubmit: (_) {},
              onOlder: () {},
              onNewer: () {},
            ),
          ],
        ),
        size: size,
      );
      final text = List.generate(90, (i) => 'w$i').join(' ');
      await t.type(text);
      await t.pump();
      final rows = c.lastLayout!.rows;
      expect(rows.length, greaterThan(2));
      c.cursor = rows[1].start + 2;
      await t.pump();
      await t.press('cmd+left');
      expect(c.cursor, rows[1].start);
      await t.type('[');
      expect(
        t.screen,
        shows('[${text.substring(rows[1].start, rows[1].start + 8)}'),
      );
      await t.press('backspace');
      await t.press('cmd+right');
      final row = c.lastLayout!.rows[1];
      expect(c.cursor, row.end - 1);
      expect(c.lastLayout!.cursorRow, 1);
      await t.press('ctrl+a');
      expect(c.cursor, 0);
      await t.press('ctrl+e');
      expect(c.cursor, text.length);
    });
  }
}
