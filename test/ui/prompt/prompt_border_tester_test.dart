import 'package:chord/ui/prompt/named_top.dart';
import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget _prompt(
  TextAreaController controller, {
  PromptAgent? agent,
  bool bash = false,
}) => ChordThemeScope(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PromptInput(
        controller: controller,
        windowRows: 40,
        onSubmit: (_) {},
        onOlder: () {},
        onNewer: () {},
        agent: agent,
        bash: bash,
      ),
    ],
  ),
);

void main() {
  group('tester: prompt border transitions', () {
    testWidgets('ordinary border keeps colour 244 through updates and resize', (
      t,
    ) async {
      final controller = TextAreaController();
      await t.pumpWidget(_prompt(controller), size: const Size(120, 40));
      for (var i = 0; i < 1000; i++) {
        controller.text = 'draft $i';
      }
      await t.pump();
      for (final size in [const Size(80, 24), const Size(120, 40)]) {
        await t.pumpWidget(_prompt(controller), size: size);
        expect(t.screen.lines[2], contains('draft 999'));
        expect(t.screen.styleAt(0, 1), const Style(fg: IndexedColor(244)));
        expect(
          t.screen.styleAt(size.width - 1, 3),
          const Style(fg: IndexedColor(244)),
        );
      }
    });

    testWidgets('main, colourless child and bash restore their own edges', (
      t,
    ) async {
      final controller = TextAreaController(text: 'kept');
      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        await t.pumpWidget(
          _prompt(controller, agent: const PromptAgent('docs')),
          size: size,
        );
        expect(t.screen.styleAt(0, 1), const Style(dim: true));
        expect(t.screen.styleAt(0, 3), const Style(fg: IndexedColor(244)));
        await t.pumpWidget(_prompt(controller, bash: true), size: size);
        expect(t.screen.styleAt(0, 1), chordDark.bash);
        await t.pumpWidget(_prompt(controller), size: size);
        expect(t.screen.styleAt(0, 1), const Style(fg: IndexedColor(244)));
        expect(controller.text, 'kept');
      }
    });
  });
}
