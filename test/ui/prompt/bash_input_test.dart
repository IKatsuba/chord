import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final (i, item) in [
      (ThemeData.dark(), chordDark),
      (ThemeData.light(), chordLight),
      (ThemeData.plain(), chordPlain),
    ].indexed) {
      testWidgets(
        'bash border and first gutter retain multiline cells in theme $i $size',
        (t) async {
          final c = TextAreaController(text: 'first\nsecond');
          addTearDown(c.dispose);
          await t.pumpWidget(
            Theme(
              data: item.$1.copyWith(extensions: [item.$2]),
              child: PromptInput(
                controller: c,
                windowRows: size.height,
                bash: true,
                onSubmit: (_) {},
                onOlder: () {},
                onNewer: () {},
              ),
            ),
            size: size,
          );
          expect(t.screen.lines[2], startsWith('│ ! first'));
          expect(t.screen.lines[3], startsWith('│   second'));
          expect(t.screen.styleAt(0, 1), item.$2.bash);
          expect(t.screen.styleAt(2, 2), item.$2.bash);
          expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
          expect(c.lastLayout!.width, size.width - 6);
        },
      );
    }
  }
}
