import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent pointer(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

// An application policy bound only through public APIs; production port policy
// belongs to S5. The framework owns the range, capture and held scroll state.
class _Binding {
  _Binding(this.scroll);
  final ScrollController scroll;
  bool dragging = false, wasFollowing = false, moved = false;
  void selectionChanged(SelectionValue value) {
    if (value.phase == SelectionPhase.changing && !dragging) {
      wasFollowing = scroll.isFollowing;
      moved = false;
      dragging = true;
      scroll.hold();
    } else if (value.phase != SelectionPhase.changing && dragging) {
      dragging = false;
      scroll.release();
      if (wasFollowing && !moved) scroll.toBottom();
    }
  }

  void explicitScroll(void Function() action) {
    if (dragging) moved = true;
    action();
  }
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final wheel in ['none', 'transcript clamped', 'child consumed']) {
      testWidgets('fit-to-overflow drag wheel=$wheel $size', (t) async {
        final selection = SelectionController();
        final scroll = ScrollController(follow: Follow.bottom);
        final binding = _Binding(scroll);
        final changed = ValueNotifier(0);
        final sources = [
          for (var i = 0; i < 2; i++)
            SelectionSource.text(id: i, revision: 0, text: TextSpan('row$i')),
        ];
        var childWheels = 0, finalizations = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: changed,
            builder: (_) {
              final delegate = SelectionChildDelegate(
                itemCount: sources.length,
                idAt: (i) => i,
                indexOfId: (id) =>
                    id is int && id >= 0 && id < sources.length ? id : null,
                sourceAt: (i) => sources[i],
              );
              return SelectionArea(
                controller: selection,
                selectionStyle: Style.inverse,
                onSelectionChanged: binding.selectionChanged,
                onSelectionFinalized: (_) {
                  finalizations++;
                  expect(scroll.state.held, isFalse);
                },
                child: Column(
                  children: [
                    SizedBox(
                      height: 3,
                      child: Listener(
                        onPointerSignal: (_) =>
                            binding.explicitScroll(scroll.lineDown),
                        child: ListView.builder(
                          controller: scroll,
                          selectionDelegate: delegate,
                          itemCount: sources.length,
                          itemVersion: (i) => sources[i].revision,
                          itemBuilder: (_, i) => Listener(
                            absorbPointerSignal: wheel == 'child consumed',
                            onPointerSignal: wheel == 'child consumed'
                                ? (_) => childWheels++
                                : null,
                            child: Text.fromSelectionSource(sources[i]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          size: size,
        );
        expect(scroll.isFollowing, isTrue);
        await t.mouse(pointer(MouseEventKind.press, 0, 0));
        await t.mouse(pointer(MouseEventKind.move, 3, 0));
        expect(
          (scroll.state.held, scroll.isFollowing, scroll.offset),
          (true, false, 0),
        );
        if (wheel != 'none') {
          await t.mouse(
            const MouseEvent(
              MouseEventKind.wheel,
              position: Offset(1, 0),
              scrollDelta: Offset(0, 1),
            ),
          );
        }
        expect(binding.moved, wheel == 'transcript clamped');
        expect(childWheels, wheel == 'child consumed' ? 1 : 0);
        sources.addAll([
          for (var i = 2; i < 6; i++)
            SelectionSource.text(id: i, revision: 0, text: TextSpan('row$i')),
        ]);
        changed.value++;
        scroll.markNews();
        expect(selection.snapshot()!.text, 'row0');
        expect(
          (scroll.state.held, scroll.isFollowing, scroll.offset),
          (true, false, 0),
        );
        await t.mouse(pointer(MouseEventKind.release, 40, 20));
        expect(scroll.state.held, isFalse);
        expect(scroll.isFollowing, wheel != 'transcript clamped');
        expect(scroll.offset, wheel == 'transcript clamped' ? 0 : 3);
        expect(selection.snapshot()!.text, 'row0');
        expect(finalizations, 1);
        var frames = 0;
        t.host.owner.onNeedsFrame = () => frames++;
        await t.pump();
        expect(frames, 0);
        selection.dispose();
        scroll.dispose();
        changed.dispose();
      });
    }
  }

  testWidgets(
    'held explicit scroll reprojects stationary focus and release retains logical range',
    (t) async {
      final selection = SelectionController();
      final scroll = ScrollController();
      final binding = _Binding(scroll);
      final sources = [
        for (var i = 0; i < 8; i++)
          SelectionSource.text(id: i, revision: 0, text: TextSpan('row$i')),
      ];
      final delegate = SelectionChildDelegate(
        itemCount: 8,
        idAt: (i) => i,
        indexOfId: (id) => id is int && id >= 0 && id < 8 ? id : null,
        sourceAt: (i) => sources[i],
      );
      await t.pumpWidget(
        SelectionArea(
          controller: selection,
          selectionStyle: Style.inverse,
          onSelectionChanged: binding.selectionChanged,
          child: Column(
            children: [
              SizedBox(
                height: 2,
                child: ListView.builder(
                  controller: scroll,
                  itemCount: 8,
                  selectionDelegate: delegate,
                  itemVersion: (_) => 0,
                  itemBuilder: (_, i) => Text.fromSelectionSource(sources[i]),
                ),
              ),
            ],
          ),
        ),
      );
      t.host.handleMouse(pointer(MouseEventKind.press, 0, 0));
      t.host.handleMouse(pointer(MouseEventKind.move, 3, 1));
      binding.explicitScroll(scroll.lineDown);
      expect(selection.snapshot()!.text, 'row0\nrow1\nrow2');
      expect(
        (scroll.state.held, scroll.offset, scroll.isFollowing),
        (true, 1, false),
      );
      t.host.handleMouse(pointer(MouseEventKind.release, 0, 0));
      expect(scroll.state.held, isFalse);
      expect(scroll.offset, 1);
      expect(selection.snapshot()!.text, 'row0\nrow1\nrow2');
      scroll.toBottom();
      expect(selection.snapshot()!.text, 'row0\nrow1\nrow2');
      selection.dispose();
      scroll.dispose();
    },
  );

  testWidgets(
    'clear cancels the gesture and releases its scroll hold without finalizing',
    (t) async {
      final selection = SelectionController();
      final scroll = ScrollController(follow: Follow.bottom);
      final binding = _Binding(scroll);
      var finalizations = 0;
      await t.pumpWidget(
        SelectionArea(
          controller: selection,
          selectionStyle: Style.inverse,
          onSelectionChanged: binding.selectionChanged,
          onSelectionFinalized: (_) => finalizations++,
          child: Column(
            children: [
              SizedBox(
                height: 2,
                child: ListView.builder(
                  controller: scroll,
                  itemCount: 3,
                  itemVersion: (_) => 0,
                  itemBuilder: (_, i) => Text('row$i'),
                ),
              ),
            ],
          ),
        ),
      );
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 3, 0));
      expect(scroll.state.held, isTrue);
      selection.clear();
      expect(scroll.state.held, isFalse);
      expect(scroll.isFollowing, isTrue);
      await t.mouse(pointer(MouseEventKind.release, 3, 0));
      expect(finalizations, 0);
      selection.dispose();
      scroll.dispose();
    },
  );
}
