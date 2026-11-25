import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/foundation/selection_controller.dart'
    show selectionDiagnostics, SelectionClient;
import 'package:chord_tui/src/foundation/selection_diagnostics.dart';
import 'package:chord_tui/src/text/markdown.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'package:fake_async/fake_async.dart';

void main() {
  test(
    'parser diagnostics distinguish real work and never retain parser state',
    () {
      final parser = MarkdownParser();
      resetMarkdownParseDiagnostics();
      final blocks = parser.update('unchanged paragraph');
      parser.update('unchanged paragraph');
      expect(markdownParseDiagnostics, (
        updates: 2,
        changedUpdates: 1,
        tailParses: 1,
      ));
      resetMarkdownParseDiagnostics();
      expect(markdownParseDiagnostics, (
        updates: 0,
        changedUpdates: 0,
        tailParses: 0,
      ));
      expect(parser.blocks, same(blocks));
      parser.update('unchanged paragraph');
      expect(markdownParseDiagnostics, (
        updates: 1,
        changedUpdates: 0,
        tailParses: 0,
      ));
    },
  );
  testWidgets('cleared scene refreshes current code geometry and reveal', (
    t,
  ) async {
    final controller = SelectionController();
    final source = SelectionSource.markdown(
      id: 'code',
      revision: 0,
      text: '```dart\nvalue\n```',
    );
    await t.pumpWidget(
      SelectionArea(
        controller: controller,
        selectionStyle: Style.inverse,
        child: Markdown.fromSelectionSource(source),
      ),
    );
    final id = source.codeBlocks.single.id;
    expect(controller.codeBlockGeometry(id), isNotNull);
    controller.clear();
    expect(selectionDiagnostics(controller).resolvedRoots, 0);
    expect(controller.codeBlockGeometry(id), isNotNull);
    expect(controller.revealCodeBlock(id), isTrue);
    expect(controller.snapshot()!.phase, SelectionPhase.none);
    controller.dispose();
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    test(
      'stationary held pointer schedules no periodic frame or parser work $size',
      () {
        fakeAsync((clock) {
          final t = WidgetTester(), controller = SelectionController();
          void settle(Future<void> future) {
            var done = false;
            future.then((_) => done = true);
            clock.elapse(Duration.zero);
            expect(done, isTrue);
          }

          settle(
            t.pumpWidget(
              SelectionArea(
                controller: controller,
                selectionStyle: Style.inverse,
                child: Text('stationary pointer'),
              ),
              size: size,
            ),
          );
          settle(
            t.mouse(
              const MouseEvent(
                MouseEventKind.press,
                position: Offset(0, 0),
                button: MouseButton.primary,
              ),
            ),
          );
          settle(
            t.mouse(
              const MouseEvent(
                MouseEventKind.move,
                position: Offset(3, 0),
                button: MouseButton.primary,
              ),
            ),
          );
          var requests = 0;
          t.host.owner.onNeedsFrame = () => requests++;
          final passes = t.inputLayoutPasses, parses = markdownParseDiagnostics;
          clock.elapse(const Duration(seconds: 10));
          expect(requests, 0);
          expect(t.inputLayoutPasses, passes);
          expect(markdownParseDiagnostics, parses);
          expect(clock.pendingTimers, isEmpty);
          expect(controller.value.phase, SelectionPhase.changing);
          t.dispose();
          controller.dispose();
        });
      },
    );
  }
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'cached scene sees notifier sources, editor and owner replacement without setState $size',
      (t) async {
        final first = SelectionController(), second = SelectionController();
        final owner = ValueNotifier(first);
        final source = ValueNotifier(
          SelectionSource.text(
            id: 'body',
            revision: 0,
            text: const TextSpan('abcdef'),
          ),
        );
        final editor = TextAreaController(text: 'draft');
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        addTearDown(owner.dispose);
        addTearDown(source.dispose);
        addTearDown(editor.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: owner,
            builder: (_) => ListenableBuilder(
              listenable: source,
              builder: (_) => SelectionArea(
                controller: owner.value,
                selectionStyle: Style.inverse,
                child: Column(
                  children: [
                    Text.fromSelectionSource(source.value),
                    TextArea(controller: editor),
                  ],
                ),
              ),
            ),
          ),
          size: size,
        );
        MouseEvent at(MouseEventKind kind, int x, int y) => MouseEvent(
          kind,
          position: Offset(x, y),
          button: MouseButton.primary,
        );
        await t.mouse(at(MouseEventKind.press, 0, 0));
        await t.mouse(at(MouseEventKind.move, 3, 0));
        source.value = SelectionSource.text(
          id: 'body',
          revision: 1,
          text: const TextSpan('abXYef'),
          previous: source.value,
        );
        expect(first.snapshot()!.text, 'abXY');
        await t.mouse(at(MouseEventKind.release, 3, 0));
        expect(first.snapshot()!.text, 'abXY');
        await t.mouse(at(MouseEventKind.press, 0, 1));
        await t.mouse(at(MouseEventKind.move, 2, 1));
        editor.text = 'newer';
        expect(first.snapshot()!.text, 'new');
        await t.mouse(at(MouseEventKind.release, 2, 1));
        expect(first.snapshot()!.text, 'new');
        owner.value = second;
        expect(second.snapshot(), isNull);
        await t.pump();
        expect(second.snapshot()!.phase, SelectionPhase.none);
        expect(first.snapshot(), isNull);
        expect(selectionDiagnostics(first).logicalSlots, 0);
        await t.mouse(at(MouseEventKind.press, 0, 0));
        await t.mouse(at(MouseEventKind.move, 1, 0));
        await t.mouse(at(MouseEventKind.release, 1, 0));
        expect(second.snapshot()!.text, 'ab');
      },
    );
  }
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'clear drops crossed lazy caches immediately and after a frame $size',
      (t) async {
        final selection = SelectionController();
        final scroll = ScrollController();
        addTearDown(selection.dispose);
        addTearDown(scroll.dispose);
        final sources = [
          for (var i = 0; i < 100; i++)
            SelectionSource.markdown(
              id: i,
              revision: 0,
              text: 'Record $i\n\nbody $i',
            ),
        ];
        var resolutions = 0;
        final delegate = SelectionChildDelegate(
          itemCount: sources.length,
          idAt: (i) => i,
          indexOfId: (id) =>
              id is int && id >= 0 && id < sources.length ? id : null,
          sourceAt: (i) {
            resolutions++;
            return sources[i];
          },
        );
        resetSelectionWorkDiagnostics();
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: Style.inverse,
            child: Column(
              children: [
                Text('header'),
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    itemCount: sources.length,
                    selectionDelegate: delegate,
                    itemBuilder: (_, i) =>
                        Markdown.fromSelectionSource(sources[i]),
                  ),
                ),
                Text('footer'),
              ],
            ),
          ),
          size: size,
        );
        final before = selectionDiagnostics(selection);
        expect(selectionWorkDiagnostics.sceneCollections, greaterThan(0));
        expect(selectionWorkDiagnostics.rangeCompositions, 0);
        expect(before.offscreenResolvedRoots, 0);
        final calls = resolutions,
            parses = markdownParseDiagnostics,
            work = selectionWorkDiagnostics;
        for (var i = 0; i < 10; i++) {
          expect(
            selectionDiagnostics(selection).resolvedRoots,
            before.resolvedRoots,
          );
        }
        expect(resolutions, calls);
        expect(markdownParseDiagnostics, parses);
        expect(selectionWorkDiagnostics, work);
        MouseEvent at(MouseEventKind kind, int y) => MouseEvent(
          kind,
          position: Offset(0, y),
          button: MouseButton.primary,
        );
        await t.mouse(at(MouseEventKind.press, 0));
        await t.mouse(at(MouseEventKind.move, size.height - 1));
        expect(selectionWorkDiagnostics.rangeCompositions, greaterThan(0));
        final heldValue = selection.value;
        resetSelectionWorkDiagnostics();
        expect(selection.value, same(heldValue));
        final heldCalls = resolutions, heldParses = markdownParseDiagnostics;
        for (var i = 0; i < 5; i++) {
          t.host.drawFrame(size);
        }
        expect(
          resolutions,
          heldCalls,
          reason: 'unchanged held frames must not flatten history',
        );
        expect(markdownParseDiagnostics, heldParses);
        expect(selectionWorkDiagnostics, (
          sceneCollections: 0,
          rangeCompositions: 0,
        ));
        await t.mouse(at(MouseEventKind.release, size.height - 1));
        final crossed = selectionDiagnostics(selection);
        expect(crossed.selectedRoots, 102);
        expect(crossed.selectedRanges, greaterThan(crossed.selectedRoots));
        expect(crossed.offscreenResolvedRoots, greaterThan(0));
        resetSelectionWorkDiagnostics();
        final steadyCalls = resolutions,
            steadyParses = markdownParseDiagnostics;
        for (var i = 0; i < 5; i++) {
          t.host.drawFrame(size);
          expect(
            selectionDiagnostics(selection).selectedRanges,
            crossed.selectedRanges,
          );
        }
        expect(
          resolutions,
          steadyCalls,
          reason: 'unchanged shown frames must not flatten history',
        );
        expect(markdownParseDiagnostics, steadyParses);
        expect(selectionWorkDiagnostics, (
          sceneCollections: 0,
          rangeCompositions: 0,
        ));
        selection.clear();
        final immediate = selectionDiagnostics(selection);
        expect(immediate.selectedRoots, 0);
        expect(immediate.selectedRanges, 0);
        expect(
          immediate.offscreenResolvedRoots,
          0,
          reason:
              'crossed=${crossed.offscreenResolvedRoots}, immediate=${immediate.offscreenResolvedRoots}',
        );
        await t.pump();
        final next = selectionDiagnostics(selection);
        expect(next.selectedRoots, 0);
        expect(next.selectedRanges, 0);
        expect(next.offscreenResolvedRoots, 0);
        expect(next.cachedFragments, lessThanOrEqualTo(before.cachedFragments));
        t.dispose();
        expect(selectionDiagnostics(selection).resolvedRoots, 0);
      },
    );
  }
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final count in [100, 10000]) {
      testWidgets(
        'capture cancellation drops crossed caches and preserves observer new drag $count $size',
        (t) async {
          final selection = SelectionController(), scroll = ScrollController();
          addTearDown(selection.dispose);
          addTearDown(scroll.dispose);
          final sources = [
            for (var i = 0; i < count; i++)
              SelectionSource.markdown(
                id: i,
                revision: 0,
                text: 'Record $i\n\nbody $i',
              ),
          ];
          final finalized = <SelectionValue>[];
          var restart = false;
          MouseEvent at(MouseEventKind kind, int x, int y) => MouseEvent(
            kind,
            position: Offset(x, y),
            button: MouseButton.primary,
          );
          await t.pumpWidget(
            SelectionArea(
              controller: selection,
              selectionStyle: Style.inverse,
              onSelectionFinalized: finalized.add,
              onSelectionChanged: (value) {
                if (restart && value.phase == SelectionPhase.none) {
                  restart = false;
                  t.host.handleMouse(at(MouseEventKind.press, 0, 0));
                  t.host.handleMouse(at(MouseEventKind.move, 2, 0));
                }
              },
              child: Column(
                children: [
                  Text('header'),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: count,
                      selectionDelegate: SelectionChildDelegate(
                        itemCount: count,
                        idAt: (i) => i,
                        indexOfId: (id) =>
                            id is int && id >= 0 && id < count ? id : null,
                        sourceAt: (i) => sources[i],
                      ),
                      itemBuilder: (_, i) =>
                          Markdown.fromSelectionSource(sources[i]),
                    ),
                  ),
                  Text('footer'),
                ],
              ),
            ),
            size: size,
          );
          final baseline = selectionDiagnostics(selection);
          await t.mouse(at(MouseEventKind.press, 0, 0));
          await t.mouse(at(MouseEventKind.move, 0, size.height - 1));
          expect(
            selectionDiagnostics(selection).offscreenResolvedRoots,
            greaterThan(0),
          );
          final cancelPasses = t.inputLayoutPasses;
          t.host.cancelPointerCapture();
          expect(t.inputLayoutPasses, cancelPasses);
          final immediate = selectionDiagnostics(selection);
          expect(selection.value.phase, SelectionPhase.none);
          expect(immediate.selectedRoots, 0);
          expect(immediate.selectedRanges, 0);
          expect(immediate.offscreenResolvedRoots, 0);
          expect(finalized, isEmpty);
          await t.pump();
          final next = selectionDiagnostics(selection);
          expect(next.offscreenResolvedRoots, 0);
          expect(
            next.cachedFragments,
            lessThanOrEqualTo(baseline.cachedFragments),
          );
          expect(selection.snapshot()!.phase, SelectionPhase.none);
          expect(selectionDiagnostics(selection).offscreenResolvedRoots, 0);
          await t.mouse(at(MouseEventKind.press, 0, 0));
          await t.mouse(at(MouseEventKind.move, 0, size.height - 1));
          expect(
            selectionDiagnostics(selection).offscreenResolvedRoots,
            greaterThan(0),
          );
          restart = true;
          final reentrantPasses = t.inputLayoutPasses;
          t.host.handleMouse(at(MouseEventKind.cancel, 0, size.height - 1));
          expect(t.inputLayoutPasses, reentrantPasses);
          expect(restart, isFalse);
          expect(selection.value.phase, SelectionPhase.changing);
          expect(selection.value.text, 'hea');
          expect(selectionDiagnostics(selection).offscreenResolvedRoots, 0);
          expect(finalized, isEmpty);
          await t.pump();
          expect(t.screen.styleAt(0, 0).isInverse, isTrue);
          expect(t.screen.styleAt(3, 0).isInverse, isFalse);
          await t.mouse(at(MouseEventKind.release, 2, 0));
          expect(selection.snapshot()!.text, 'hea');
          expect(selection.value.phase, SelectionPhase.finalized);
          expect(finalized.map((v) => v.text), ['hea']);
        },
      );
    }
  }
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'retained disposed host releases finalized range leases without callbacks $size',
      (t) async {
        final selection = SelectionController(), scroll = ScrollController();
        addTearDown(selection.dispose);
        addTearDown(scroll.dispose);
        final sources = [
          for (var i = 0; i < 100; i++)
            SelectionSource.markdown(
              id: i,
              revision: 0,
              text: 'Record $i\n\nbody $i',
            ),
        ];
        var changes = 0, finalized = 0;
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: Style.inverse,
            onSelectionChanged: (_) => changes++,
            onSelectionFinalized: (_) => finalized++,
            child: Column(
              children: [
                Text('header'),
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    itemCount: sources.length,
                    selectionDelegate: SelectionChildDelegate(
                      itemCount: sources.length,
                      idAt: (i) => i,
                      indexOfId: (id) =>
                          id is int && id >= 0 && id < sources.length
                          ? id
                          : null,
                      sourceAt: (i) => sources[i],
                    ),
                    itemBuilder: (_, i) =>
                        Markdown.fromSelectionSource(sources[i]),
                  ),
                ),
                Text('footer'),
              ],
            ),
          ),
          size: size,
        );
        MouseEvent at(MouseEventKind kind, int y) => MouseEvent(
          kind,
          position: Offset(0, y),
          button: MouseButton.primary,
        );
        await t.mouse(at(MouseEventKind.press, 0));
        await t.mouse(at(MouseEventKind.move, size.height - 1));
        await t.mouse(at(MouseEventKind.release, size.height - 1));
        expect(selection.value.phase, SelectionPhase.finalized);
        expect(finalized, 1);
        final host = t.host;
        final before =
            ((host.rootElement as StatefulElement).state as SelectionClient)
                .selectionDiagnostics;
        expect(before.selectedRoots, 102);
        expect(before.selectedRanges, greaterThan(0));
        int paintBridges() {
          var count = 0;
          void visit(RenderBox box) {
            if (box.selectionGlyphStyle != null) count++;
            box.visitChildren(visit);
          }

          final root = RenderObjectElement.firstRenderObject(host.rootElement);
          if (root != null) visit(root);
          return count;
        }

        expect(paintBridges(), greaterThan(0));
        final changeCount = changes,
            finalCount = finalized,
            passes = host.owner.inputLayoutPasses;
        t.dispose();
        expect(host.owner.inputLayoutPasses, passes);
        // Hold the disposed host deliberately: immediate release must not rely
        // on the owner dropping the old element tree or a later collection.
        final after =
            (host.rootElement as StatefulElement).state as SelectionClient;
        expect(
          after.selectionDiagnostics.selectedRoots,
          0,
          reason:
              'ranges=${after.selectionDiagnostics.selectedRanges}, paintBridges=${paintBridges()}',
        );
        expect(after.selectionDiagnostics.selectedRanges, 0);
        expect(paintBridges(), 0);
        expect(after.selectionDiagnostics.resolvedRoots, 0);
        expect(after.selectionDiagnostics.offscreenResolvedRoots, 0);
        expect(changes, changeCount);
        expect(finalized, finalCount);
        expect(selectionDiagnostics(selection).selectedRanges, 0);
      },
    );
  }
}
