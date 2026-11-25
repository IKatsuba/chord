import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/foundation/selection_controller.dart'
    show SelectionClient;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent _at(MouseEventKind kind, int y, {int x = 0}) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

Widget _history(
  SelectionController controller,
  Size size, {
  void Function(SelectionValue)? changed,
  void Function(SelectionValue)? finalized,
}) {
  final sources = [
    for (var i = 0; i < 600; i++)
      SelectionSource.markdown(
        id: i,
        revision: 0,
        text: 'Record $i 界👩‍💻\n\nbody e\u0301',
      ),
  ];
  return SelectionArea(
    controller: controller,
    selectionStyle: Style.inverse,
    onSelectionChanged: changed,
    onSelectionFinalized: finalized,
    child: Column(
      children: [
        Text('header'),
        Expanded(
          child: ListView.builder(
            itemCount: sources.length,
            itemVersion: (_) => 0,
            selectionDelegate: SelectionChildDelegate(
              itemCount: sources.length,
              idAt: (i) => i,
              indexOfId: (id) =>
                  id is int && id >= 0 && id < sources.length ? id : null,
              sourceAt: (i) => sources[i],
            ),
            itemBuilder: (_, i) => Markdown.fromSelectionSource(sources[i]),
          ),
        ),
        Text('footer'),
      ],
    ),
  );
}

int _paintBridges(AppHost host) {
  var count = 0;
  void visit(RenderBox box) {
    if (box.selectionGlyphStyle != null) {
      count++;
    }
    box.visitChildren(visit);
  }

  final root = RenderObjectElement.firstRenderObject(host.rootElement);
  if (root != null) {
    visit(root);
  }
  return count;
}

void main() {
  group(
    'tester: selected history releases structural references at lifecycle boundaries',
    () {
      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        for (final end in [
          'host cancel',
          'controller dispose',
          'host dispose',
        ]) {
          testWidgets(
            '$end clears retained live state before another frame $size',
            (t) async {
              final controller = SelectionController();
              var finalized = 0, changes = 0;
              await t.pumpWidget(
                _history(
                  controller,
                  size,
                  changed: (_) => changes++,
                  finalized: (_) => finalized++,
                ),
                size: size,
              );
              final host = t.host;
              final state =
                  (host.rootElement as StatefulElement).state
                      as SelectionClient;
              await t.mouse(_at(MouseEventKind.press, 0));
              await t.mouse(_at(MouseEventKind.move, size.height - 1));
              expect(
                state.selectionDiagnostics.offscreenResolvedRoots,
                greaterThan(0),
              );
              expect(state.selectionDiagnostics.selectedRoots, 602);
              expect(_paintBridges(host), greaterThan(0));
              final passes = t.inputLayoutPasses, notices = changes;
              switch (end) {
                case 'host cancel':
                  host.cancelPointerCapture();
                case 'controller dispose':
                  controller.dispose();
                case 'host dispose':
                  host.dispose();
              }
              expect(host.owner.inputLayoutPasses, passes);
              expect(state.selectionDiagnostics.selectedRoots, 0);
              expect(state.selectionDiagnostics.selectedRanges, 0);
              expect(state.selectionDiagnostics.offscreenResolvedRoots, 0);
              expect(state.selectionDiagnostics.resolvedRoots, 0);
              expect(_paintBridges(host), 0);
              expect(finalized, 0);
              if (end != 'controller dispose') {
                expect(changes, notices + 1);
              } else {
                expect(changes, notices);
              }
              if (end != 'host dispose') {
                await t.pump();
                expect(state.selectionDiagnostics.offscreenResolvedRoots, 0);
                expect(state.selectionDiagnostics.selectedRanges, 0);
                await t.mouse(_at(MouseEventKind.release, size.height - 1));
                expect(finalized, 0);
              }
              final delivered = changes;
              t.dispose();
              expect(changes, delivered);
              controller.dispose();
            },
          );
        }

        testWidgets(
          'none observer replaces crossed history drag without old cache or completion $size',
          (t) async {
            final controller = SelectionController();
            var restart = false;
            final finalized = <String>[];
            await t.pumpWidget(
              _history(
                controller,
                size,
                changed: (value) {
                  if (restart && value.phase == SelectionPhase.none) {
                    restart = false;
                    t.host.handleMouse(_at(MouseEventKind.press, 0));
                    t.host.handleMouse(_at(MouseEventKind.move, 0, x: 2));
                  }
                },
                finalized: (value) => finalized.add(value.text),
              ),
              size: size,
            );
            final host = t.host;
            final state =
                (host.rootElement as StatefulElement).state as SelectionClient;
            await t.mouse(_at(MouseEventKind.press, 0));
            await t.mouse(_at(MouseEventKind.move, size.height - 1));
            expect(
              state.selectionDiagnostics.offscreenResolvedRoots,
              greaterThan(0),
            );
            restart = true;
            host.cancelPointerCapture();
            expect(controller.value.text, 'hea');
            expect(state.selectionDiagnostics.selectedRoots, 1);
            expect(state.selectionDiagnostics.offscreenResolvedRoots, 0);
            expect(finalized, isEmpty);
            await t.pump();
            expect(t.screen.styleAt(0, 0).isInverse, isTrue);
            expect(t.screen.styleAt(3, 0).isInverse, isFalse);
            await t.mouse(_at(MouseEventKind.release, 0, x: 2));
            expect(finalized, ['hea']);
            t.dispose();
            expect(state.selectionDiagnostics.selectedRoots, 0);
            expect(state.selectionDiagnostics.selectedRanges, 0);
            expect(state.selectionDiagnostics.resolvedRoots, 0);
            expect(_paintBridges(host), 0);
            controller.dispose();
          },
        );
      }
    },
  );
}
