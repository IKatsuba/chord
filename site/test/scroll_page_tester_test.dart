import 'package:chord_site/scroll_page.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CHD-638 tester: poster scroll lifetime and small rooms', () {
    testWidgets('an empty room and one cell recover to a scrolling poster', (
      t,
    ) async {
      final c = ScrollController();
      addTearDown(c.dispose);
      await t.pumpWidget(
        ScrollPage(
          controller: c,
          sections: [for (var i = 0; i < 200; i++) Text('界🙂e\u0301 row $i')],
        ),
        size: Size.zero,
      );
      for (final size in const [
        Size(1, 1),
        Size(52, 52),
        Size(120, 40),
        Size(80, 24),
      ]) {
        await t.resize(size);
      }
      expect(t.screen, shows('界🙂e\u0301 row 0'));
      await t.press('end');
      expect(t.screen, shows('界🙂e\u0301 row 199'));
      await t.press('home');
      expect(c.offset, 0);
    });

    for (final size in const [Size(120, 40), Size(80, 24), Size(52, 52)]) {
      testWidgets('wheel is applied once and removal detaches the view at '
          '$size', (t) async {
        final c = ScrollController();
        addTearDown(c.dispose);
        await t.pumpWidget(
          ScrollPage(
            controller: c,
            sections: [for (var i = 0; i < 200; i++) Text('row $i')],
          ),
          size: size,
        );
        await t.mouse(
          const MouseEvent(
            MouseEventKind.wheel,
            position: Offset(8, 2),
            scrollDelta: Offset(0, 3),
          ),
        );
        expect(c.offset, 3);
        await t.pumpWidget(Text('removed'));
        c.lineDown();
        await t.pump();
        expect(t.screen.text, 'removed');
      });
    }
  });
}
