import 'package:chord_site/live_plate.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CHD-638 tester: live plate controller lifetime', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('controller replacement and removal detach stale handles '
          'at $size', (t) async {
        final first = LivePlateController();
        final second = LivePlateController();
        final selected = ValueNotifier(first);
        final live = ValueNotifier(false);
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        addTearDown(selected.dispose);
        addTearDown(live.dispose);
        await t.pumpWidget(
          LiveScope(
            entered: live,
            child: Focus(
              autofocus: true,
              child: ListenableBuilder(
                listenable: selected,
                builder: (_) => LivePlate(
                  controller: selected.value,
                  figure: 1,
                  title: 'field',
                  rows: 3,
                  home: () {},
                  child: (_) => Focus(autofocus: true, child: Text('field')),
                ),
              ),
            ),
          ),
          size: size,
        );
        first.enter();
        await t.pump();
        expect(live.value, isTrue);
        selected.value = second;
        await t.pump();
        expect(first.entered, isFalse);
        expect(second.entered, isTrue);
        first.leave();
        expect(live.value, isTrue);
        second.leave();
        await t.pump();
        expect(live.value, isFalse);
        second.enter();
        await t.pumpWidget(Text('removed'));
        expect(live.value, isFalse);
        for (final controller in [first, second]) {
          controller.enter();
          controller.leave();
          expect(controller.entered, isFalse);
        }
        await t.pump();
        expect(t.screen.text, 'removed');
      });
    }
  });

  group('CHD-638 tester: entered wheel isolation', () {
    for (final size in const [Size(120, 40), Size(80, 24), Size(55, 52)]) {
      testWidgets('1000 reports stay in the entered room and scroll its page '
          'again after leaving at $size', (t) async {
        final controller = LivePlateController();
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        var reports = 0;
        await t.pumpWidget(
          Focus(
            autofocus: true,
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  LivePlate(
                    controller: controller,
                    figure: 1,
                    title: 'room',
                    rows: 3,
                    home: () {},
                    child: (_) => Focus(
                      autofocus: true,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerSignal: (_) => reports++,
                        child: Text('room'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 200),
                ],
              ),
            ),
          ),
          size: size,
        );
        final y = t.screen.lines.indexWhere((line) => line.trim() == 'room');
        expect(y, greaterThanOrEqualTo(0));
        final wheel = MouseEvent(
          MouseEventKind.wheel,
          position: Offset(4, y),
          scrollDelta: const Offset(0, 1),
        );
        await t.mouse(wheel);
        expect(scroll.offset, 1);
        scroll.toTop();
        controller.enter();
        await t.pump();
        for (var i = 0; i < 1000; i++) {
          t.host.handleMouse(wheel);
        }
        await t.pump();
        expect(scroll.offset, 0);
        expect(reports, 1001);
        controller.leave();
        await t.pump();
        await t.mouse(wheel);
        expect(scroll.offset, 1);
        expect(reports, 1002);
      });
    }
  });
}
