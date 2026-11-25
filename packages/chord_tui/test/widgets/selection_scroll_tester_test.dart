import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent _pointer(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

void main() {
  group('tester: held scroll ownership and idle work', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('held one-row resize preserves full item extents $size', (
        t,
      ) async {
        final scroll = ScrollController(follow: Follow.bottom);
        final height = ValueNotifier(2);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: height,
            builder: (_) => Column(
              children: [
                SizedBox(
                  height: height.value,
                  child: ListView.builder(
                    controller: scroll,
                    itemCount: 3,
                    itemVersion: (_) => 0,
                    itemBuilder: (_, i) => Text('item $i\na\nb\nc\nd'),
                  ),
                ),
              ],
            ),
          ),
          size: size,
        );
        final total = scroll.contentRows;
        expect(total, 15);
        scroll.hold();
        for (final rows in [1, 3, 0, 1, 2]) {
          height.value = rows;
          await t.pump();
          expect(scroll.contentRows, total);
          expect(scroll.state.held, isTrue);
          expect(scroll.isFollowing, isFalse);
          for (var i = 0; i < 3; i++) {
            expect(scroll.itemRows(i), 5);
          }
        }
        scroll.release();
        expect(scroll.isFollowing, isFalse);
        scroll.toBottom();
        expect(scroll.isFollowing, isTrue);
        t.dispose();
        scroll.dispose();
        height.dispose();
      });

      testWidgets(
        'stationary outside drag produces no periodic frame or scroll $size',
        (t) async {
          final c = SelectionController();
          final scroll = ScrollController();
          final sources = [
            for (var i = 0; i < 20; i++)
              SelectionSource.text(id: i, revision: 0, text: TextSpan('row$i')),
          ];
          var dragging = false;
          await t.pumpWidget(
            SelectionArea(
              controller: c,
              selectionStyle: Style.inverse,
              onSelectionChanged: (value) {
                if (value.phase == SelectionPhase.changing && !dragging) {
                  dragging = true;
                  scroll.hold();
                } else if (value.phase != SelectionPhase.changing && dragging) {
                  dragging = false;
                  scroll.release();
                }
              },
              child: Column(
                children: [
                  SizedBox(
                    height: 2,
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: sources.length,
                      itemVersion: (_) => 0,
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
                          Text.fromSelectionSource(sources[i]),
                    ),
                  ),
                ],
              ),
            ),
            size: size,
          );
          await t.mouse(_pointer(MouseEventKind.press, 0, 0));
          await t.mouse(
            _pointer(MouseEventKind.move, size.width + 5, size.height + 5),
          );
          final before = c.snapshot()!.text;
          var frames = 0;
          t.host.owner.onNeedsFrame = () => frames++;
          await t.pump(const Duration(milliseconds: 80));
          expect(frames, 0);
          expect(scroll.offset, 0);
          expect(scroll.state.held, isTrue);
          expect(c.snapshot()!.text, before);
          c.clear();
          expect(scroll.state.held, isFalse);
          t.dispose();
          c.dispose();
          scroll.dispose();
        },
      );
    }

    testWidgets(
      'finalization-started gesture owns a fresh hold before append',
      (t) async {
        final selection = SelectionController();
        final scroll = ScrollController(follow: Follow.bottom);
        final count = ValueNotifier(2);
        final sources = [
          for (var i = 0; i < 10; i++)
            SelectionSource.text(id: i, revision: 0, text: TextSpan('row$i')),
        ];
        var dragging = false, wasFollowing = false;
        var finalized = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: count,
            builder: (_) => SelectionArea(
              controller: selection,
              selectionStyle: Style.inverse,
              onSelectionChanged: (value) {
                if (value.phase == SelectionPhase.changing && !dragging) {
                  dragging = true;
                  wasFollowing = scroll.isFollowing;
                  scroll.hold();
                } else if (value.phase != SelectionPhase.changing && dragging) {
                  dragging = false;
                  scroll.release();
                  if (wasFollowing) scroll.toBottom();
                }
              },
              onSelectionFinalized: (_) {
                finalized++;
                expect(scroll.state.held, isFalse);
                if (finalized == 1) {
                  t.host.handleMouse(_pointer(MouseEventKind.press, 1, 0));
                }
              },
              child: Column(
                children: [
                  SizedBox(
                    height: 3,
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: count.value,
                      itemVersion: (_) => 0,
                      selectionDelegate: SelectionChildDelegate(
                        itemCount: count.value,
                        idAt: (i) => i,
                        indexOfId: (id) =>
                            id is int && id >= 0 && id < count.value
                            ? id
                            : null,
                        sourceAt: (i) => sources[i],
                      ),
                      itemBuilder: (_, i) =>
                          Text.fromSelectionSource(sources[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await t.mouse(_pointer(MouseEventKind.press, 0, 0));
        await t.mouse(_pointer(MouseEventKind.move, 3, 0));
        await t.mouse(_pointer(MouseEventKind.release, 3, 0));
        expect(scroll.state.held, isTrue);
        expect(selection.value.phase, SelectionPhase.changing);
        count.value = 10;
        await t.pump();
        expect(scroll.offset, 0);
        expect(scroll.isFollowing, isFalse);
        await t.mouse(_pointer(MouseEventKind.move, 3, 0));
        await t.mouse(_pointer(MouseEventKind.release, 3, 0));
        expect(finalized, 2);
        expect(scroll.state.held, isFalse);
        expect(scroll.isFollowing, isTrue);
        expect(selection.snapshot()!.text, 'ow0');
        t.dispose();
        selection.dispose();
        scroll.dispose();
        count.dispose();
      },
    );
  });
}
