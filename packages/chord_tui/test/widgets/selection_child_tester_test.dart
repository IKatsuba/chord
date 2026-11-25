import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent _pointer(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

void main() {
  group('tester: exclusion boundaries and surviving range leases', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final held in [false, true]) {
        testWidgets(
          'middle eligibility drops its custom separator without resurrection held=$held $size',
          (t) async {
            final c = SelectionController();
            final enabled = ValueNotifier(true);
            c.addListener(enabled.notifyListeners);
            SelectionValue snapshot() {
              final before = t.inputLayoutPasses;
              final value = c.snapshot();
              expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
              return value!;
            }

            final leaves = [
              for (final (id, text) in [
                ('a', 'A界'),
                ('b', 'Be\u0301'),
                ('c', 'C👩‍💻'),
              ])
                SelectionSource.text(id: id, revision: 0, text: TextSpan(text)),
            ];
            var revision = 0;
            SelectionSource? root;
            await t.pumpWidget(
              ListenableBuilder(
                listenable: enabled,
                builder: (_) {
                  root = SelectionSource.group(
                    id: 'root',
                    revision: revision++,
                    previous: root,
                    children: [
                      SelectionSourceChild(source: leaves[0]),
                      SelectionSourceChild(
                        source: leaves[1],
                        selectable: enabled.value,
                        separatorBefore: ':',
                      ),
                      SelectionSourceChild(
                        source: leaves[2],
                        separatorBefore: '|',
                      ),
                    ],
                  );
                  return SelectionArea(
                    controller: c,
                    selectionStyle: Style.inverse,
                    child: ListView.builder(
                      itemCount: 1,
                      itemVersion: (_) => root!.revision,
                      selectionDelegate: SelectionChildDelegate(
                        itemCount: 1,
                        idAt: (_) => 'root',
                        indexOfId: (id) => id == 'root' ? 0 : null,
                        sourceAt: (_) => root!,
                      ),
                      itemBuilder: (_, _) => Column(
                        children: [
                          for (final leaf in leaves)
                            Text.fromSelectionSource(leaf),
                        ],
                      ),
                    ),
                  );
                },
              ),
              size: size,
            );
            await t.mouse(_pointer(MouseEventKind.press, 0, 0));
            await t.mouse(_pointer(MouseEventKind.move, 2, 2));
            if (!held) await t.mouse(_pointer(MouseEventKind.release, 2, 2));
            expect(snapshot().text, 'A界:Be\u0301|C👩‍💻');
            enabled.value = false;
            expect(snapshot().text, 'A界|C👩‍💻');
            await t.pump();
            expect(t.screen.lines.take(3), ['A界', 'Be\u0301', 'C👩‍💻']);
            expect(t.screen.styleAt(0, 1).isInverse, isFalse);
            enabled.value = true;
            expect(snapshot().text, 'A界|C👩‍💻');
            if (held) {
              t.host.handleMouse(_pointer(MouseEventKind.release, 50, 20));
              expect(snapshot().text, 'A界|C👩‍💻');
            }
            await t.mouse(_pointer(MouseEventKind.press, 0, 0));
            await t.mouse(_pointer(MouseEventKind.move, 2, 2));
            await t.mouse(_pointer(MouseEventKind.release, 2, 2));
            expect(snapshot().text, 'A界:Be\u0301|C👩‍💻');
            t.dispose();
            c.dispose();
            enabled.dispose();
          },
        );
      }
    }
  });
}
