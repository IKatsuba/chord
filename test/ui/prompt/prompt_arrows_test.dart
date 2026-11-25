// The original's press reads ↑ and ↓ with any modifier but shift as ↑ and
// ↓ (src/ui/shortcuts/press.ts, src/ui/prompt/Prompt.tsx): ctrl and alt
// arrows walk history where the plain arrows do (CTUI-182).
import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final mod in ['ctrl', 'alt', 'ctrl+alt', 'meta']) {
      for (final walking in [false, true]) {
        testWidgets('$mod arrows walk as arrows, walking $walking, at $size', (
          t,
        ) async {
          final c = TextAreaController(text: 'one\ntwo\nthree')..cursor = 5;
          addTearDown(c.dispose);
          var older = 0;
          var newer = 0;
          await t.pumpWidget(
            Column(
              children: [
                PromptInput(
                  controller: c,
                  windowRows: size.height,
                  walking: walking,
                  onSubmit: (_) {},
                  onOlder: () => older++,
                  onNewer: () => newer++,
                ),
              ],
            ),
            size: size,
          );
          // An interior row: history's only while walking; the cursor and
          // text stay.
          await t.press('$mod+up $mod+down');
          expect(
            (older, newer, c.cursor, c.text),
            (walking ? 1 : 0, walking ? 1 : 0, 5, 'one\ntwo\nthree'),
          );
          if (walking) return;
          // The first and last rows: history's.
          c.cursor = 0;
          await t.pump();
          await t.press('$mod+up');
          c.cursor = c.text.length;
          await t.pump();
          await t.press('$mod+down');
          expect((older, newer, c.text), (1, 1, 'one\ntwo\nthree'));
          // Shift is the transcript's, never history's.
          await t.press('shift+$mod+down');
          c.cursor = 0;
          await t.pump();
          await t.press('shift+$mod+up');
          expect((older, newer), (1, 1));
        });
      }
    }
  }
}
