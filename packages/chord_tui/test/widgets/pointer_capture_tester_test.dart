import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent _primary(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

void main() {
  group('tester: captured pointer boundaries and callback snapshots', () {
    testWidgets('zero room cannot capture; one cell captures outside', (
      t,
    ) async {
      final capture = PointerCaptureController();
      var moves = 0;
      await t.pumpWidget(
        Listener(
          captureController: capture,
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => capture.capture(),
          onPointerMove: (_) => moves++,
          child: const SizedBox(),
        ),
        size: Size.zero,
      );
      await t.mouse(_primary(MouseEventKind.press, 0, 0));
      expect(capture.isCaptured, isFalse);
      await t.resize(const Size(1, 1));
      await t.mouse(_primary(MouseEventKind.press, 0, 0));
      expect(capture.isCaptured, isTrue);
      await t.resize(Size.zero);
      await t.mouse(_primary(MouseEventKind.move, -1, 2));
      expect(moves, 1);
      await t.mouse(_primary(MouseEventKind.release, 100, 100));
      expect(capture.isCaptured, isFalse);
      t.dispose();
      capture.dispose();
    });

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('unbounded Unicode leaf captures each exposed edge $size', (
        t,
      ) async {
        final capture = PointerCaptureController();
        var downs = 0, ups = 0;
        const text = '界👩‍💻e\u0301\x1b[31mZ\x1b[0m';
        await t.pumpWidget(
          Row(
            children: [
              Listener(
                captureController: capture,
                onPointerDown: (_) {
                  downs++;
                  capture.capture();
                },
                onPointerUp: (_) => ups++,
                child: Text(text),
              ),
            ],
          ),
          size: size,
        );
        for (var x = 0; x < cellWidth(text); x++) {
          await t.mouse(_primary(MouseEventKind.press, x, 0));
          expect(capture.isCaptured, isTrue, reason: 'cell $x');
          await t.mouse(_primary(MouseEventKind.release, size.width, 0));
        }
        await t.mouse(_primary(MouseEventKind.press, cellWidth(text), 0));
        expect(capture.isCaptured, isFalse);
        expect(downs, cellWidth(text));
        expect(ups, downs);
        t.dispose();
        capture.dispose();
      });

      testWidgets('focus round trip and resize preserve held route $size', (
        t,
      ) async {
        final capture = PointerCaptureController();
        final first = FocusNode(), second = FocusNode();
        final log = <String>[];
        await t.pumpWidget(
          Listener(
            captureController: capture,
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => capture.capture(),
            onPointerMove: (_) => log.add('move'),
            onPointerUp: (_) => log.add('up'),
            child: Column(
              children: [
                Focus(focusNode: first, autofocus: true, child: Text('first')),
                Focus(focusNode: second, child: Text('second')),
              ],
            ),
          ),
          size: size,
        );
        await t.mouse(_primary(MouseEventKind.press, 0, 0));
        second.requestFocus();
        await t.press('a');
        expect(second.hasFocus, isTrue);
        first.requestFocus();
        await t.press('left');
        expect(first.hasFocus, isTrue);
        await t.resize(
          size.width == 120 ? const Size(80, 24) : const Size(120, 40),
        );
        await t.mouse(_primary(MouseEventKind.move, -3, -2));
        await t.mouse(_primary(MouseEventKind.release, -3, -2));
        expect(log, ['move', 'up']);
        expect(first.hasFocus, isTrue);
        t.dispose();
        capture.dispose();
        first.dispose();
        second.dispose();
      });
    }

    testWidgets(
      'rebuild during motion keeps ancestor callback for this event',
      (t) async {
        final capture = PointerCaptureController();
        final revision = ValueNotifier(0);
        final log = <String>[];
        await t.pumpWidget(
          ListenableBuilder(
            listenable: revision,
            builder: (_) {
              final current = revision.value;
              return Listener(
                onPointerMove: (_) => log.add('ancestor $current'),
                child: Listener(
                  captureController: capture,
                  onPointerDown: (_) => capture.capture(),
                  onPointerMove: (_) {
                    log.add('child');
                    revision.value++;
                    t.host.drawFrame(t.size);
                  },
                  child: Text('target'),
                ),
              );
            },
          ),
        );
        await t.mouse(_primary(MouseEventKind.press, 0, 0));
        await t.mouse(_primary(MouseEventKind.move, 100, 100));
        await t.mouse(_primary(MouseEventKind.move, 100, 100));
        expect(log, ['child', 'ancestor 0', 'child', 'ancestor 1']);
        t.dispose();
        capture.dispose();
        revision.dispose();
      },
    );

    testWidgets('thousand reports before frame release exactly once', (
      t,
    ) async {
      final capture = PointerCaptureController();
      var moves = 0, ups = 0, cancels = 0;
      await t.pumpWidget(
        Listener(
          captureController: capture,
          onPointerDown: (_) => capture.capture(),
          onPointerMove: (_) => moves++,
          onPointerUp: (_) => ups++,
          onPointerCancel: (_) => cancels++,
          child: Text('target'),
        ),
      );
      t.host.handleMouse(_primary(MouseEventKind.press, 0, 0));
      for (var i = 0; i < 1000; i++) {
        t.host.handleMouse(_primary(MouseEventKind.move, i - 500, i));
      }
      expect(moves, 1000);
      expect(capture.isCaptured, isTrue);
      t.host.handleMouse(_primary(MouseEventKind.release, -1, -1));
      await t.pump();
      expect(ups, 1);
      expect(cancels, 0);
      expect(capture.isCaptured, isFalse);
      t.dispose();
      expect(cancels, 0);
      capture.dispose();
    });
  });
}
