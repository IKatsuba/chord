import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent wheel(int rows, {int x = 2, int y = 2}) => MouseEvent(
  MouseEventKind.wheel,
  position: Offset(x, y),
  scrollDelta: Offset(0, rows),
);

Widget list(ScrollController scroll, {required bool wheel}) => ListView.builder(
  controller: scroll,
  scrollsOnWheel: wheel,
  itemCount: 200,
  itemBuilder: (context, i) => Text('item $i'),
);

Widget page(ScrollController scroll, {bool? wheel}) => wheel == null
    ? SingleChildScrollView(
        controller: scroll,
        child: Column(children: [for (var i = 0; i < 200; i++) Text('$i')]),
      )
    : SingleChildScrollView(
        controller: scroll,
        scrollsOnWheel: wheel,
        child: Column(children: [for (var i = 0; i < 200; i++) Text('$i')]),
      );

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('a ListView takes no wheel by default', (t) async {
        final scroll = ScrollController();
        await t.pumpWidget(list(scroll, wheel: false), size: size);
        await t.mouse(wheel(3));
        expect(scroll.offset, 0);
      });

      testWidgets('scrollsOnWheel moves a ListView a row a step, both '
          'ways', (t) async {
        final scroll = ScrollController();
        await t.pumpWidget(list(scroll, wheel: true), size: size);
        await t.mouse(wheel(3));
        expect(scroll.offset, 3);
        await t.mouse(wheel(-1));
        expect(scroll.offset, 2);
        await t.pump();
        expect(t.screen.lines.first, 'item 2');
      });

      testWidgets('a SingleChildScrollView takes the wheel by default, and '
          'not with scrollsOnWheel false', (t) async {
        final scroll = ScrollController();
        await t.pumpWidget(page(scroll), size: size);
        await t.mouse(wheel(2));
        expect(scroll.offset, 2);
        final still = ScrollController();
        await t.pumpWidget(page(still, wheel: false), size: size);
        await t.mouse(wheel(2));
        expect(still.offset, 0);
      });

      testWidgets('an item that absorbs the wheel keeps it', (t) async {
        final scroll = ScrollController();
        var inner = 0;
        await t.pumpWidget(
          ListView.builder(
            controller: scroll,
            scrollsOnWheel: true,
            itemCount: 200,
            itemBuilder: (context, i) => i == 0
                ? Listener(
                    absorbPointerSignal: true,
                    behavior: HitTestBehavior.opaque,
                    onPointerSignal: (_) => inner++,
                    child: Text('a frame'),
                  )
                : Text('item $i'),
          ),
          size: size,
        );
        await t.mouse(wheel(1, y: 0));
        expect(inner, 1);
        expect(scroll.offset, 0, reason: 'the item kept it');
        await t.mouse(wheel(1, y: 5));
        expect(scroll.offset, 1);
      });
    });
  }
}
