import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'markdown_controls_test.dart' show cell, primary, click;
import 'overlay_follower_test.dart' show Page;

class _Unknown extends SingleChildRenderObjectWidget {
  const _Unknown({required super.child});
  @override
  RenderBox createRenderObject(BuildContext context) => _UnknownBox();
}

class _UnknownBox extends RenderProxyBox {}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'nonopaque empty follower preserves paint, pointers, wheel and raw visibility $size',
      (t) async {
        final link = LayerLink(), opaque = ValueNotifier(false);
        addTearDown(opaque.dispose);
        var presses = 0, wheels = 0;
        final page = OverlayEntry(
          requestFocus: false,
          builder: (_) => Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => presses++,
            onPointerSignal: (_) => wheels++,
            child: Page(link),
          ),
        );
        final layer = OverlayEntry(
          requestFocus: false,
          builder: (_) => ListenableBuilder(
            listenable: opaque,
            builder: (_) => CompositedTransformFollower(
              link: link,
              opaque: opaque.value,
              followerAnchor: Alignment.bottomLeft,
              child: SizedBox(width: size.width, height: 1),
            ),
          ),
        );
        await t.pumpWidget(Overlay(initialEntries: [page, layer]), size: size);
        final y = size.height - 5;
        expect(layer.visible, isTrue);
        expect(t.screen.lines[y], '#' * size.width);
        expect(
          t.screen.styleAt(2, y),
          const Style(fg: Colors.green, bg: Colors.blue),
        );
        await click(t, Offset(2, y));
        await t.mouse(
          MouseEvent(
            MouseEventKind.wheel,
            position: Offset(2, y),
            scrollDelta: const Offset(0, 1),
          ),
        );
        expect((presses, wheels), (1, 1));
        opaque.value = true;
        await t.pump();
        expect(layer.visible, isTrue);
        expect(t.screen.lines[y], isEmpty);
        await click(t, Offset(2, y));
        await t.mouse(
          MouseEvent(
            MouseEventKind.wheel,
            position: Offset(2, y),
            scrollDelta: const Offset(0, 1),
          ),
        );
        expect((presses, wheels), (1, 1));
        opaque.value = false;
        await t.pump();
        expect(t.screen.lines[y], '#' * size.width);
        await t.resize(Size(size.width, 4));
        expect(layer.visible, isFalse);
        await t.resize(size);
        expect(layer.visible, isTrue);
      },
    );
    testWidgets('child paint and hits remain with opacity disabled $size', (
      t,
    ) async {
      final link = LayerLink();
      var childPresses = 0, pagePresses = 0;
      final page = OverlayEntry(
        builder: (_) => Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => pagePresses++,
          child: Page(link),
        ),
      );
      final layer = OverlayEntry(
        requestFocus: false,
        builder: (_) => CompositedTransformFollower(
          link: link,
          opaque: false,
          followerAnchor: Alignment.bottomLeft,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => childPresses++,
            child: SizedBox(width: 12, height: 2, child: Text('child')),
          ),
        ),
      );
      await t.pumpWidget(Overlay(initialEntries: [page, layer]), size: size);
      final y = size.height - 6;
      expect(t.screen.lines[y], startsWith('child#'));
      await click(t, Offset(2, y));
      expect((childPresses, pagePresses), (1, 0));
      await click(t, Offset(20, y));
      expect((childPresses, pagePresses), (1, 1));
    });
    testWidgets(
      'same geometry opacity toggles current selection/code exposure and cancels stale copy $size',
      (t) async {
        final link = LayerLink(),
            opaque = ValueNotifier(false),
            controller = SelectionController();
        addTearDown(opaque.dispose);
        addTearDown(controller.dispose);
        final source = SelectionSource.markdown(
          id: 'code',
          revision: 0,
          text: '```sh\nunder\n```',
          copyCodeBlocks: true,
        );
        var copies = 0;
        final page = OverlayEntry(
          requestFocus: false,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CompositedTransformTarget(
                link: link,
                child: const SizedBox(height: 0),
              ),
              Markdown.fromSelectionSource(
                source,
                onCopyCodeBlock: (_) => copies++,
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        );
        final layer = OverlayEntry(
          requestFocus: false,
          builder: (_) => ListenableBuilder(
            listenable: opaque,
            builder: (_) => CompositedTransformFollower(
              link: link,
              opaque: opaque.value,
              child: SizedBox(width: size.width, height: 3),
            ),
          ),
        );
        await t.pumpWidget(
          SelectionArea(
            selectionStyle: const Style(inverse: true),
            controller: controller,
            child: Overlay(initialEntries: [page, layer]),
          ),
          size: size,
        );
        expect(controller.visibleCodeBlocks().single.block.text, 'under');
        final word = cell(t, 'under');
        await t.mouse(primary(MouseEventKind.press, word));
        await t.mouse(primary(MouseEventKind.move, Offset(word.x + 4, word.y)));
        await t.mouse(
          primary(MouseEventKind.release, Offset(word.x + 4, word.y)),
        );
        expect(controller.snapshot()!.text, 'under');
        controller.clear();
        final at = cell(t, '[copy]');
        await t.mouse(primary(MouseEventKind.press, at));
        opaque.value = true;
        await t.pump();
        expect(controller.visibleCodeBlocks(), isEmpty);
        await t.mouse(primary(MouseEventKind.release, at));
        expect(copies, 0);
        opaque.value = false;
        await t.pump();
        expect(controller.visibleCodeBlocks().single.block.text, 'under');
        await click(t, cell(t, '[copy]'));
        expect(copies, 1);
      },
    );
    testWidgets(
      'nonopaque unknown child remains fail closed and unlink policy is independent $size',
      (t) async {
        final link = LayerLink(), controller = SelectionController();
        addTearDown(controller.dispose);
        var target = true, fallback = false, unknown = true;
        final source = SelectionSource.markdown(
          id: 'code',
          revision: 0,
          text: '```sh\nunder\n```',
        );
        final page = OverlayEntry(
          builder: (_) => Column(
            children: [
              if (target)
                CompositedTransformTarget(
                  link: link,
                  child: const SizedBox(height: 0),
                ),
              Markdown.fromSelectionSource(source),
            ],
          ),
        );
        final layer = OverlayEntry(
          requestFocus: false,
          builder: (_) => CompositedTransformFollower(
            link: link,
            opaque: false,
            showWhenUnlinked: fallback,
            child: unknown
                ? const _Unknown(child: SizedBox(width: 8, height: 1))
                : const SizedBox(width: 8, height: 1),
          ),
        );
        await t.pumpWidget(
          SelectionArea(
            selectionStyle: const Style(inverse: true),
            controller: controller,
            child: Overlay(initialEntries: [page, layer]),
          ),
          size: size,
        );
        expect(layer.visible, isTrue);
        expect(controller.visibleCodeBlocks(), isEmpty);
        unknown = false;
        layer.markNeedsBuild();
        await t.pump();
        expect(controller.visibleCodeBlocks(), hasLength(1));
        target = false;
        page.markNeedsBuild();
        await t.pump();
        expect(layer.visible, isFalse);
        fallback = true;
        layer.markNeedsBuild();
        await t.pump();
        expect(layer.visible, isTrue);
        await t.pumpWidget(const SizedBox());
        expect(layer.visible, isFalse);
      },
    );
  }
}
