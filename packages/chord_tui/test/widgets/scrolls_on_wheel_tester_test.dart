import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent _wheel(int y, {Offset at = const Offset(2, 2), int x = 0}) =>
    MouseEvent(MouseEventKind.wheel, position: at, scrollDelta: Offset(x, y));

void main() {
  group('CHD-638 tester: wheel routing boundaries', () {
    testWidgets(
      'a live list flag change takes effect without duplicate scrolling',
      (t) async {
        final enabled = ValueNotifier(true);
        addTearDown(enabled.dispose);
        final c = ScrollController();
        await t.pumpWidget(
          ListenableBuilder(
            listenable: enabled,
            builder: (_) => ListView.builder(
              controller: c,
              scrollsOnWheel: enabled.value,
              itemCount: 100,
              itemBuilder: (_, i) => Text('row$i'),
            ),
          ),
        );
        await t.mouse(_wheel(3));
        expect(c.offset, 3);
        enabled.value = false;
        await t.pump();
        await t.mouse(_wheel(3));
        expect(c.offset, 3);
        enabled.value = true;
        await t.pump();
        await t.mouse(_wheel(-1));
        expect(c.offset, 2);
        await t.mouse(_wheel(0, x: 5));
        expect(c.offset, 2);
      },
    );

    testWidgets(
      'a retained child absorbs only wheel reports within its bounds',
      (t) async {
        final c = ScrollController();
        var reports = 0;
        await t.pumpWidget(
          SingleChildScrollView(
            controller: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Listener(
                  absorbPointerSignal: true,
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: (_) => reports++,
                  child: Text('frame'),
                ),
                for (var i = 0; i < 100; i++) Text('row$i'),
              ],
            ),
          ),
        );
        await t.mouse(_wheel(3, at: const Offset(1, 0)));
        expect((reports, c.offset), (1, 0));
        await t.mouse(_wheel(3, at: const Offset(1, 2)));
        expect((reports, c.offset), (1, 3));
        await t.mouse(_wheel(-100));
        expect(c.offset, 0);
      },
    );
  });
}
