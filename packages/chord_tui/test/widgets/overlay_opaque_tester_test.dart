import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'markdown_controls_test.dart' show cell, primary, click;
import 'overlay_follower_test.dart' show Page;

void main() {
  group('tester: transparent follower holes and input freshness', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'sparse child keeps its hits while empty interior passes to page $size',
        (t) async {
          final link = LayerLink();
          var pagePress = 0, childPress = 0, pageWheel = 0, childWheel = 0;
          final page = OverlayEntry(
            requestFocus: false,
            builder: (_) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => pagePress++,
              onPointerSignal: (_) => pageWheel++,
              child: Page(link),
            ),
          );
          final layer = OverlayEntry(
            requestFocus: false,
            builder: (_) => CompositedTransformFollower(
              link: link,
              opaque: false,
              followerAnchor: Alignment.bottomLeft,
              child: SizedBox(
                width: 20,
                height: 3,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Listener(
                    onPointerDown: (_) => childPress++,
                    onPointerSignal: (_) => childWheel++,
                    absorbPointerSignal: true,
                    child: Text('界é'),
                  ),
                ),
              ),
            ),
          );
          await t.pumpWidget(
            Overlay(initialEntries: [page, layer]),
            size: size,
          );
          final top = size.height - 7;
          expect(t.screen.lines[top], startsWith('界é#'));
          await click(t, Offset(0, top));
          await t.mouse(
            MouseEvent(
              MouseEventKind.wheel,
              position: Offset(0, top),
              scrollDelta: const Offset(0, 1),
            ),
          );
          expect((childPress, childWheel, pagePress, pageWheel), (1, 1, 0, 0));
          await click(t, Offset(10, top + 1));
          await t.mouse(
            MouseEvent(
              MouseEventKind.wheel,
              position: Offset(10, top + 1),
              scrollDelta: const Offset(0, 1),
            ),
          );
          expect((childPress, childWheel, pagePress, pageWheel), (1, 1, 1, 1));
          expect(t.screen.charAt(10, top + 1), '#');
        },
      );

      testWidgets(
        'same-batch opacity update cancels held run without repaint $size',
        (t) async {
          final link = LayerLink(),
              opaque = ValueNotifier(false),
              controller = SelectionController();
          addTearDown(opaque.dispose);
          addTearDown(controller.dispose);
          var runs = 0;
          final source = SelectionSource.markdown(
            id: 'code',
            revision: 0,
            text: '```custom\nx\n```',
            runCodeBlockLanguages: {'custom'},
          );
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
                  onRunCodeBlock: (_) => runs++,
                ),
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
              controller: controller,
              selectionStyle: Style.inverse,
              child: Overlay(initialEntries: [page, layer]),
            ),
            size: size,
          );
          final at = cell(t, '[run]');
          await t.mouse(primary(MouseEventKind.press, at));
          opaque.value = true;
          final before = t.inputLayoutPasses;
          t.host.handleMouse(primary(MouseEventKind.release, at));
          expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
          expect(controller.visibleCodeBlocks(), isEmpty);
          expect(runs, 0);
          opaque.value = false;
          t.host.handleMouse(primary(MouseEventKind.release, at));
          expect(controller.visibleCodeBlocks(), hasLength(1));
          expect(runs, 0);
          await t.pump();
          await click(t, cell(t, '[run]'));
          expect(runs, 1);
        },
      );
    }
    for (final size in [const Size(0, 0), const Size(1, 1)]) {
      testWidgets('transparent zero-room follower stays inert $size', (
        t,
      ) async {
        final link = LayerLink();
        final page = OverlayEntry(
          builder: (_) =>
              CompositedTransformTarget(link: link, child: Text('base')),
        );
        final layer = OverlayEntry(
          requestFocus: false,
          builder: (_) => CompositedTransformFollower(
            link: link,
            opaque: false,
            child: const SizedBox(width: 0, height: 0),
          ),
        );
        await t.pumpWidget(Overlay(initialEntries: [page, layer]), size: size);
        expect(layer.visible, isFalse);
        await click(t, Offset.zero);
      });
    }
  });
}
