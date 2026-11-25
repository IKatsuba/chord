import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

MouseEvent _mouse(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe(this.counts, {required super.child});
  final _Counts counts;
  @override
  RenderBox createRenderObject(BuildContext context) =>
      _RenderProbe(context.owner, counts);
}

class _Counts {
  var layouts = 0, paints = 0;
  bool churn = false, failPaint = false, checkGuard = false;
}

class _RenderProbe extends RenderProxyBox {
  _RenderProbe(this.owner, this.counts);
  final BuildOwner owner;
  final _Counts counts;
  @override
  void performLayout() {
    counts.layouts++;
    if (counts.checkGuard) {
      expect(owner.ensureCurrentInputGeometry, throwsStateError);
    }
    super.performLayout();
    if (counts.churn) owner.afterLayout(owner.requestFrame);
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    counts.paints++;
    if (counts.checkGuard) {
      expect(owner.ensureCurrentInputGeometry, throwsStateError);
    }
    if (counts.failPaint) throw StateError('fixture paint failed');
    super.paint(canvas, origin);
  }
}

void main() {
  test(
    'virtual-detach cancel may start a new capture after settlement unwinds',
    () {
      final childCapture = PointerCaptureController();
      final ancestorCapture = PointerCaptureController();
      final scroll = ScrollController();
      var cancels = 0, ancestorMoves = 0;
      var startAncestor = false;
      late AppHost host;
      host = AppHost(
        Listener(
          captureController: ancestorCapture,
          onPointerMove: (_) => ancestorMoves++,
          onPointerDown: (_) {
            if (startAncestor) ancestorCapture.capture();
          },
          onPointerCancel: (_) {
            cancels++;
            expect(host.owner.doingLayoutOrPaint, isFalse);
            if (cancels == 1) {
              startAncestor = true;
              host.handleMouse(_mouse(MouseEventKind.press, 0, 0));
            }
          },
          child: ListView.builder(
            controller: scroll,
            itemCount: 20,
            itemVersion: (i) => i,
            itemBuilder: (_, i) => Listener(
              captureController: i == 0 ? childCapture : null,
              onPointerDown: i == 0 ? (_) => childCapture.capture() : null,
              child: Text('item $i'),
            ),
          ),
        ),
      );
      addTearDown(host.dispose);
      addTearDown(childCapture.dispose);
      addTearDown(ancestorCapture.dispose);
      addTearDown(scroll.dispose);
      host.drawFrame(const Size(20, 3));
      host.handleMouse(_mouse(MouseEventKind.press, 0, 0));
      scroll.jumpTo(10);
      host.handleMouse(_mouse(MouseEventKind.move, 0, 1));
      expect(cancels, 1);
      expect(childCapture.isCaptured, isFalse);
      expect(ancestorCapture.isCaptured, isTrue);
      expect(ancestorMoves, 0);
    },
  );

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    test(
      'same-batch source/tree updates route current bounds without paint $size',
      () {
        final left = ValueNotifier(0);
        final counts = _Counts();
        var hits = 0;
        final host = AppHost(
          _Probe(
            counts,
            child: ListenableBuilder(
              listenable: left,
              builder: (_) => Stack(
                children: [
                  Positioned(
                    left: left.value,
                    top: 0,
                    width: 4,
                    height: 2,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => hits++,
                      child: Text('here'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        addTearDown(host.dispose);
        addTearDown(left.dispose);
        host.drawFrame(size);
        final paints = counts.paints;
        for (var i = 0; i < 1000; i++) {
          left.value = 5 + i % 10;
        }
        expect(host.handleMouse(_mouse(MouseEventKind.press, 0, 0)), isFalse);
        expect(host.handleMouse(_mouse(MouseEventKind.press, 14, 0)), isTrue);
        expect(hits, 1);
        expect(counts.paints, paints);
      },
    );
  }

  test(
    'same-batch wheel and scroll mutations refresh geometry before next input',
    () {
      final scroll = ScrollController();
      final hits = <int>[];
      final host = AppHost(
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (_) => scroll.lineDown(),
          child: ListView.builder(
            controller: scroll,
            itemCount: 20,
            itemVersion: (i) => i,
            itemBuilder: (_, i) => Listener(
              onPointerUp: (_) => hits.add(i),
              child: Text('item $i'),
            ),
          ),
        ),
      );
      addTearDown(host.dispose);
      addTearDown(scroll.dispose);
      host.drawFrame(const Size(20, 3));
      host.handleMouse(
        const MouseEvent(
          MouseEventKind.wheel,
          position: Offset.zero,
          scrollDelta: Offset(0, 1),
        ),
      );
      host.handleMouse(_mouse(MouseEventKind.release, 0, 0));
      scroll.jumpTo(9);
      host.handleMouse(_mouse(MouseEventKind.release, 0, 0));
      expect(hits, [1, 9]);
    },
  );

  test('resize refreshes lazy layout before a mouse report or key', () {
    final widths = <int>[];
    final host = AppHost(
      LayoutBuilder(
        builder: (_, constraints) => Actions(
          bindings: [
            Binding(
              'a',
              'Record width',
              () => widths.add(constraints.maxWidth),
            ),
          ],
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => widths.add(constraints.maxWidth),
            child: Text('current'),
          ),
        ),
      ),
    );
    addTearDown(host.dispose);
    host.drawFrame(const Size(120, 40));
    host.updateSize(const Size(80, 24));
    host.handleMouse(_mouse(MouseEventKind.press, 79, 23));
    host.handleKey(const KeyEvent('a'));
    expect(widths, [80, 80]);
  });

  test(
    'unsettled geometry stops after two passes, cancels and never paints',
    () {
      final capture = PointerCaptureController();
      final counts = _Counts();
      var cancels = 0, moves = 0;
      final host = AppHost(
        _Probe(
          counts,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            captureController: capture,
            onPointerDown: (_) => capture.capture(),
            onPointerMove: (_) => moves++,
            onPointerCancel: (_) => cancels++,
            child: Text('target'),
          ),
        ),
      );
      addTearDown(host.dispose);
      addTearDown(capture.dispose);
      host.drawFrame(const Size(20, 6));
      host.handleMouse(_mouse(MouseEventKind.press, 0, 0));
      counts.churn = true;
      host.owner.requestFrame();
      final layouts = counts.layouts, paints = counts.paints;
      expect(host.handleMouse(_mouse(MouseEventKind.move, 1, 0)), isFalse);
      expect(counts.layouts - layouts, 2);
      expect(counts.paints, paints);
      expect(cancels, 1);
      expect(moves, 0);
      expect(capture.isCaptured, isFalse);
      counts.churn = false;
      expect(host.handleMouse(_mouse(MouseEventKind.press, 0, 0)), isTrue);
      expect(capture.isCaptured, isTrue);
    },
  );

  test(
    'virtual detach releases immediately but notifies only after layout',
    () {
      final capture = PointerCaptureController();
      final scroll = ScrollController();
      var cancels = 0;
      late AppHost host;
      host = AppHost(
        Listener(
          onPointerCancel: (_) {
            expect(host.owner.doingLayoutOrPaint, isFalse);
            expect(capture.isCaptured, isFalse);
            cancels++;
          },
          child: ListView.builder(
            controller: scroll,
            itemCount: 20,
            itemVersion: (i) => i,
            itemBuilder: (_, i) => Listener(
              captureController: i == 0 ? capture : null,
              onPointerDown: i == 0 ? (_) => capture.capture() : null,
              child: Text('item $i'),
            ),
          ),
        ),
      );
      addTearDown(host.dispose);
      addTearDown(capture.dispose);
      addTearDown(scroll.dispose);
      host.drawFrame(const Size(20, 3));
      host.handleMouse(_mouse(MouseEventKind.press, 0, 0));
      scroll.jumpTo(10);
      host.handleMouse(_mouse(MouseEventKind.move, 0, 1));
      expect(cancels, 1);
    },
  );

  test(
    'synchronized query during layout or paint throws without recursion',
    () {
      final counts = _Counts()..checkGuard = true;
      final host = AppHost(_Probe(counts, child: Text('guard')));
      addTearDown(host.dispose);
      host.drawFrame(const Size(20, 6));
      expect(counts.layouts, 1);
      expect(counts.paints, 1);
    },
  );

  test('drawing crash cancels capture outside the recovered boundary once', () {
    final capture = PointerCaptureController();
    final counts = _Counts();
    var cancels = 0;
    final host = AppHost(
      Listener(
        behavior: HitTestBehavior.opaque,
        captureController: capture,
        onPointerDown: (_) => capture.capture(),
        onPointerCancel: (_) => cancels++,
        child: ErrorBoundary(
          errorBuilder: (_, _, _) => Text('recovered'),
          child: _Probe(counts, child: Text('target')),
        ),
      ),
    );
    addTearDown(host.dispose);
    addTearDown(capture.dispose);
    host.drawFrame(const Size(20, 6));
    host.handleMouse(_mouse(MouseEventKind.press, 0, 0));
    counts.failPaint = true;
    host.drawFrame(const Size(20, 6));
    expect(cancels, 1);
    expect(capture.isCaptured, isFalse);
  });
}
