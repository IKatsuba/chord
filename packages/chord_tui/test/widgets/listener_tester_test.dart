import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent _wheel(int x, int y) => MouseEvent(
  MouseEventKind.wheel,
  position: Offset(x, y),
  scrollDelta: const Offset(0, -1),
);

void main() {
  group('tester: pointer geometry boundaries and removed routes', () {
    testWidgets(
      'zero one cell and unbounded Unicode leaves use current bounds',
      (t) async {
        var calls = 0;
        await t.pumpWidget(
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (_) => calls++,
            child: const SizedBox(),
          ),
          size: const Size(0, 0),
        );
        await t.mouse(_wheel(0, 0));
        expect(calls, 0);
        await t.resize(const Size(1, 1));
        await t.mouse(_wheel(0, 0));
        expect(calls, 1);
        await t.mouse(_wheel(1, 0));
        expect(calls, 1);
        const label = '界👩‍💻e\u0301';
        await t.pumpWidget(
          Row(
            children: [
              Listener(onPointerSignal: (_) => calls++, child: Text(label)),
            ],
          ),
        );
        await t.mouse(_wheel(cellWidth(label) - 1, 0));
        expect(calls, 2);
        await t.mouse(_wheel(cellWidth(label), 0));
        expect(calls, 2);
      },
    );
    testWidgets('disposed sibling is skipped in the snapshotted route', (
      t,
    ) async {
      final visible = ValueNotifier(true);
      final events = <String>[];
      await t.pumpWidget(
        ListenableBuilder(
          listenable: visible,
          builder: (_) => Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (_) => events.add('root'),
            child: Stack(
              children: [
                if (visible.value)
                  Listener(
                    key: const ValueKey('lower'),
                    behavior: HitTestBehavior.opaque,
                    onPointerSignal: (_) => events.add('removed'),
                    child: Text('lower'),
                  ),
                Listener(
                  key: const ValueKey('upper'),
                  behavior: HitTestBehavior.translucent,
                  onPointerSignal: (_) {
                    events.add('upper');
                    visible.value = false;
                    t.host.drawFrame(const Size(80, 24));
                  },
                  child: Text('upper'),
                ),
              ],
            ),
          ),
        ),
      );
      await t.mouse(_wheel(0, 0));
      expect(events, ['upper', 'root']);
      events.clear();
      await t.mouse(_wheel(0, 0));
      expect(events, ['upper', 'root']);
      t.dispose();
      visible.dispose();
    });
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'thousand geometry changes before frame discard old hit bounds at $size',
        (t) async {
          final left = ValueNotifier(0);
          var calls = 0;
          await t.pumpWidget(
            ListenableBuilder(
              listenable: left,
              builder: (_) => Stack(
                children: [
                  Positioned(
                    left: left.value,
                    top: 1,
                    width: 5,
                    height: 2,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerSignal: (_) => calls++,
                      child: Text('界👩‍💻e\u0301'),
                    ),
                  ),
                ],
              ),
            ),
            size: size,
          );
          for (var i = 1; i <= 1000; i++) {
            left.value = i % 17;
          }
          await t.pump();
          await t.mouse(_wheel(0, 1));
          expect(calls, 0);
          await t.mouse(_wheel(1000 % 17, 1));
          expect(calls, 1);
          await t.resize(const Size(0, 0));
          await t.mouse(_wheel(1000 % 17, 1));
          expect(calls, 1);
          await t.resize(size);
          await t.mouse(_wheel(1000 % 17, 1));
          expect(calls, 2);
          t.dispose();
          left.dispose();
        },
      );
    }
  });
}
