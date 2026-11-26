import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CHD-638 tester: live frame title styles', () {
    for (final decorated in [false, true]) {
      testWidgets(
        '${decorated ? 'DecoratedBox' : 'Box'} updates and restores fallback',
        (t) async {
          final custom = Style(fg: RgbColor.hex('#8d919c'));
          final style = ValueNotifier<Style?>(custom);
          addTearDown(style.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: style,
              builder: (_) => Align(
                alignment: Alignment.topLeft,
                child: decorated
                    ? DecoratedBox(
                        border: Border.single,
                        title: 'Title',
                        titleStyle: style.value,
                        child: const SizedBox(width: 18, height: 1),
                      )
                    : Box(
                        width: 20,
                        height: 3,
                        title: 'Title',
                        titleStyle: style.value,
                      ),
              ),
            ),
          );
          expect(t.screen.styleAt(2, 0), custom);
          for (var i = 0; i < 1000; i++) {
            style.value = i.isEven ? null : Style.bold;
          }
          style.value = null;
          await t.pump();
          expect(
            t.screen.styleAt(2, 0),
            ThemeData.dark().border.merge(Style.bold),
          );
          style.value = custom;
          await t.pump();
          expect(t.screen.styleAt(2, 0), custom);
          expect(t.screen.styleAt(19, 0), ThemeData.dark().border);
        },
      );
    }

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('wide and escaped title clips inside corners at $size', (
        t,
      ) async {
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: Box(
              title: '\x1b[31m界👩‍💻e\u0301\x1b[0m',
              titleStyle: Style.underline,
              width: size.width,
              height: 3,
            ),
          ),
          size: size,
        );
        for (final width in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, size.width]) {
          await t.resize(Size(width, size.height));
          expect(
            t.screen.lines.every((line) => cellWidth(line) <= width),
            isTrue,
          );
          expect(t.screen.text, isNot(contains('\x1b')));
          if (width >= 2) expect(t.screen.charAt(width - 1, 0), '┐');
        }
        expect(t.screen, shows('界👩‍💻e\u0301'));
      });
    }

    testWidgets('an unbounded frame keeps its title distinct from its border', (
      t,
    ) async {
      await t.pumpWidget(
        Row(
          children: [
            Box(
              title: 'Title',
              titleStyle: Style.underline,
              child: Text('a sufficiently wide child'),
            ),
          ],
        ),
      );
      expect(t.screen, shows('Title'));
      expect(t.screen.styleAt(2, 0).isUnderline, isTrue);
      expect(t.screen.styleAt(0, 0).isUnderline, isFalse);
    });
  });
}
