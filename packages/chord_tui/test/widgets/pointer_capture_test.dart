import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent _pointer(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

Widget _receiver(
  PointerCaptureController controller,
  List<String> log, {
  void Function(MouseEvent)? down,
  void Function(MouseEvent)? up,
  void Function(MouseEvent)? cancel,
}) => Listener(
  captureController: controller,
  behavior: HitTestBehavior.opaque,
  onPointerDown: down ?? (_) => controller.capture(),
  onPointerMove: (e) => log.add('move ${e.position}'),
  onPointerUp: up ?? (_) => log.add('up ${controller.isCaptured}'),
  onPointerCancel: cancel ?? (_) => log.add('cancel ${controller.isCaptured}'),
  child: const SizedBox(width: 4, height: 2),
);

void main() {
  testWidgets(
    'nested wheel preserves the current primary-down capture context',
    (t) async {
      final controller = PointerCaptureController();
      var wheels = 0;
      await t.pumpWidget(
        Listener(
          captureController: controller,
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            t.host.handleMouse(
              const MouseEvent(
                MouseEventKind.wheel,
                position: Offset.zero,
                scrollDelta: Offset(0, -1),
              ),
            );
            controller.capture();
          },
          onPointerSignal: (_) => wheels++,
          child: Text('target'),
        ),
      );
      t.host.handleMouse(_pointer(MouseEventKind.press, 0, 0));
      expect(wheels, 1);
      expect(controller.isCaptured, isTrue);
      t.dispose();
      controller.dispose();
    },
  );

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('capture outside, fresh absorbed wheel and release at $size', (
      t,
    ) async {
      final child = PointerCaptureController();
      final parent = PointerCaptureController();
      final log = <String>[];
      await t.pumpWidget(
        Listener(
          captureController: parent,
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            parent.capture();
            log.add('parent ${parent.isCaptured}');
          },
          onPointerMove: (_) => log.add('parent move'),
          onPointerUp: (_) => log.add('parent up'),
          onPointerSignal: (_) => log.add('parent wheel'),
          child: Stack(
            children: [
              Positioned(left: 0, top: 0, child: _receiver(child, log)),
              Positioned(
                left: 10,
                top: 0,
                width: 4,
                height: 2,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  absorbPointerSignal: true,
                  onPointerMove: (_) => log.add('wrong move'),
                  onPointerUp: (_) => log.add('wrong up'),
                  onPointerSignal: (_) => log.add('fresh wheel'),
                  child: const SizedBox(),
                ),
              ),
            ],
          ),
        ),
        size: size,
      );
      t.host.handleMouse(_pointer(MouseEventKind.press, 0, 0));
      expect(log, ['parent false']);
      expect(child.isCaptured, isTrue);
      t.host.handleMouse(_pointer(MouseEventKind.move, 11, 0));
      t.host.handleMouse(
        const MouseEvent(
          MouseEventKind.wheel,
          position: Offset(11, 0),
          scrollDelta: Offset(0, -1),
        ),
      );
      t.host.handleMouse(_pointer(MouseEventKind.move, -5, size.height + 3));
      t.host.handleMouse(_pointer(MouseEventKind.release, 11, 0));
      expect(log, [
        'parent false',
        'move Offset(11, 0)',
        'parent move',
        'fresh wheel',
        'move Offset(-5, ${size.height + 3})',
        'parent move',
        'up false',
        'parent up',
      ]);
      expect(child.isCaptured, isFalse);
      expect(() => child.capture(), throwsStateError);
      t.dispose();
      child.dispose();
      parent.dispose();
    });
  }

  testWidgets('capture excludes translucent siblings and unrelated buttons', (
    t,
  ) async {
    final controller = PointerCaptureController();
    final log = <String>[];
    await t.pumpWidget(
      Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerMove: (_) => log.add('sibling move'),
            onPointerUp: (_) => log.add('sibling up'),
            child: Text('lower'),
          ),
          Listener(
            behavior: HitTestBehavior.translucent,
            captureController: controller,
            onPointerDown: (_) => controller.capture(),
            onPointerMove: (_) => log.add('captured move'),
            onPointerUp: (_) => log.add('captured up'),
            child: Text('upper'),
          ),
        ],
      ),
    );
    t.host.handleMouse(_pointer(MouseEventKind.press, 0, 0));
    t.host.handleMouse(_pointer(MouseEventKind.move, 50, 10));
    t.host.handleMouse(
      const MouseEvent(
        MouseEventKind.release,
        position: Offset(50, 10),
        button: MouseButton.secondary,
      ),
    );
    expect(controller.isCaptured, isTrue);
    t.host.handleMouse(_pointer(MouseEventKind.release, 50, 10));
    expect(log, ['captured move', 'captured up']);
    t.dispose();
    controller.dispose();
  });

  testWidgets('explicit release and superseding down cancel only once', (
    t,
  ) async {
    final controller = PointerCaptureController();
    final log = <String>[];
    await t.pumpWidget(_receiver(controller, log));
    t.host.handleMouse(_pointer(MouseEventKind.press, 0, 0));
    controller.release();
    controller.release();
    expect(log, ['cancel false']);
    t.host.handleMouse(_pointer(MouseEventKind.press, 0, 0));
    t.host.handleMouse(_pointer(MouseEventKind.press, 1, 0));
    expect(log, ['cancel false', 'cancel false']);
    expect(controller.isCaptured, isTrue);
    t.host.cancelPointerCapture();
    expect(log, ['cancel false', 'cancel false', 'cancel false']);
    t.dispose();
    controller.dispose();
  });

  testWidgets('old-up cleanup leaves a reentrant new capture alive', (t) async {
    final controller = PointerCaptureController();
    final log = <String>[];
    await t.pumpWidget(
      _receiver(
        controller,
        log,
        up: (_) {
          expect(controller.isCaptured, isFalse);
          t.host.handleMouse(_pointer(MouseEventKind.press, 1, 0));
        },
      ),
    );
    t.host.handleMouse(_pointer(MouseEventKind.press, 0, 0));
    t.host.handleMouse(_pointer(MouseEventKind.release, 50, 10));
    expect(controller.isCaptured, isTrue);
    t.host.handleMouse(_pointer(MouseEventKind.move, 50, 10));
    expect(log, ['move Offset(50, 10)']);
    t.dispose();
    expect(log.last, 'cancel false');
    controller.dispose();
  });

  testWidgets('reentrant down during cancellation wins the outer down', (
    t,
  ) async {
    final controller = PointerCaptureController();
    final log = <String>[];
    var starts = 0;
    await t.pumpWidget(
      _receiver(
        controller,
        log,
        down: (_) {
          starts++;
          controller.capture();
        },
        cancel: (_) {
          log.add('cancel');
          if (log.length == 1) {
            t.host.handleMouse(_pointer(MouseEventKind.press, 1, 0));
          }
        },
      ),
    );
    t.host.handleMouse(_pointer(MouseEventKind.press, 0, 0));
    t.host.handleMouse(_pointer(MouseEventKind.press, 2, 0));
    expect(starts, 2);
    expect(controller.isCaptured, isTrue);
    t.dispose();
    controller.dispose();
  });

  testWidgets('detached owner is skipped while ancestors receive cancel', (
    t,
  ) async {
    final show = ValueNotifier(true);
    final controller = PointerCaptureController();
    final log = <String>[];
    await t.pumpWidget(
      Listener(
        onPointerCancel: (_) => log.add('ancestor cancel'),
        child: ListenableBuilder(
          listenable: show,
          builder: (_) =>
              show.value ? _receiver(controller, log) : const SizedBox(),
        ),
      ),
    );
    t.host.handleMouse(_pointer(MouseEventKind.press, 0, 0));
    show.value = false;
    t.host.handleMouse(_pointer(MouseEventKind.move, 10, 10));
    expect(controller.isCaptured, isFalse);
    expect(log, ['ancestor cancel']);
    t.dispose();
    controller.dispose();
    show.dispose();
  });

  testWidgets(
    'controller disposal releases before callbacks and host teardown',
    (t) async {
      final controller = PointerCaptureController();
      final log = <String>[];
      await t.pumpWidget(_receiver(controller, log));
      t.host.handleMouse(_pointer(MouseEventKind.press, 0, 0));
      controller.dispose();
      expect(log, ['cancel false']);
      expect(controller.isCaptured, isFalse);
      expect(() => controller.capture(), throwsStateError);
      t.dispose();
      expect(log, ['cancel false']);
    },
  );

  testWidgets('throwing cancel still unmounts the host and releases capture', (
    t,
  ) async {
    final controller = PointerCaptureController();
    late BuildContext context;
    await t.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return _receiver(
            controller,
            [],
            cancel: (_) => throw StateError('cancel failed'),
          );
        },
      ),
    );
    t.host.handleMouse(_pointer(MouseEventKind.press, 0, 0));
    expect(t.host.dispose, throwsStateError);
    expect(context.mounted, isFalse);
    expect(controller.isCaptured, isFalse);
    t.dispose();
    controller.dispose();
  });

  testWidgets('only the current primary-down receiver may claim capture', (
    t,
  ) async {
    final controller = PointerCaptureController();
    await t.pumpWidget(
      Listener(
        captureController: controller,
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => expect(controller.capture, throwsStateError),
        onPointerMove: (_) => expect(controller.capture, throwsStateError),
        child: Text('target'),
      ),
    );
    t.host.handleMouse(
      const MouseEvent(
        MouseEventKind.press,
        position: Offset.zero,
        button: MouseButton.secondary,
      ),
    );
    t.host.handleMouse(_pointer(MouseEventKind.move, 0, 0));
    t.dispose();
    controller.dispose();
  });
}
