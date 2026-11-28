import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget _target(String kind, bool canRequestFocus, FocusNode node) =>
    switch (kind) {
      'filled' => FilledButton(
        action: 'run',
        canRequestFocus: canRequestFocus,
        focusNode: node,
        autofocus: true,
        child: Text('Run'),
      ),
      'outlined' => OutlinedButton(
        action: 'run',
        canRequestFocus: canRequestFocus,
        focusNode: node,
        autofocus: true,
        child: Text('Run'),
      ),
      _ => Link(
        'Run',
        action: 'run',
        canRequestFocus: canRequestFocus,
        focusNode: node,
        autofocus: true,
      ),
    };

void main() {
  group('CHD-638 tester: optional activation focus', () {
    for (final kind in ['filled', 'outlined', 'link']) {
      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        testWidgets(
          '$kind without focus keeps page keys, action and pointer at $size',
          (t) async {
            final node = FocusNode(), page = FocusNode();
            addTearDown(node.dispose);
            addTearDown(page.dispose);
            var calls = 0, pageCalls = 0;
            await t.pumpWidget(
              Actions(
                bindings: [
                  Binding('k', 'Run', () => calls++, id: 'run'),
                  Binding('enter', 'Page Enter', () => pageCalls++),
                  Binding('space', 'Page Space', () => pageCalls++),
                ],
                child: Focus(
                  focusNode: page,
                  autofocus: true,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: 1,
                          itemBuilder: (_, _) => Align(
                            alignment: Alignment.topLeft,
                            child: _target(kind, false, node),
                          ),
                        ),
                      ),
                      const KeyHelp(),
                    ],
                  ),
                ),
              ),
              size: size,
            );
            expect(node.attached, isFalse);
            expect(t.focusManager.primaryFocus, same(page));
            expect(t.screen.lines.last, contains('Page Enter'));
            expect(t.screen.lines.last, contains('Page Space'));
            await t.press('enter');
            await t.press('space');
            await t.press('k');
            final position = kind == 'link'
                ? const Offset(0, 0)
                : const Offset(4, 1);
            for (final event in [
              MouseEventKind.press,
              MouseEventKind.release,
            ]) {
              await t.mouse(
                MouseEvent(
                  event,
                  position: position,
                  button: MouseButton.primary,
                ),
              );
            }
            expect((calls, pageCalls), (2, 2));
            expect(t.focusManager.primaryFocus, same(page));
            expect(
              t.screen.styleAt(position.x, position.y).isUnderline,
              kind == 'link',
            );
            if (kind == 'link') {
              expect(t.screen.styleAt(0, 0).isInverse, isFalse);
            }
          },
        );
      }

      testWidgets('$kind removes and restores its activation scope live', (
        t,
      ) async {
        final node = FocusNode(), other = FocusNode();
        addTearDown(node.dispose);
        addTearDown(other.dispose);
        final canFocus = ValueNotifier(true);
        addTearDown(canFocus.dispose);
        var calls = 0;
        await t.pumpWidget(
          Actions(
            bindings: [Binding('k', 'Run', () => calls++, id: 'run')],
            child: ListenableBuilder(
              listenable: canFocus,
              builder: (_) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _target(kind, canFocus.value, node),
                  Focus(focusNode: other, child: Text('other')),
                  const Spacer(),
                  const KeyHelp(),
                ],
              ),
            ),
          ),
        );
        await t.press('enter');
        expect(calls, 1);
        canFocus.value = false;
        await t.pump();
        other.requestFocus();
        await t.pump();
        await t.press('enter');
        expect(calls, 1);
        expect(node.attached, isFalse);
        canFocus.value = true;
        await t.pump();
        node.requestFocus();
        await t.pump();
        await t.press('enter');
        expect(calls, 2);
        expect(
          t.screen.lines.last,
          contains(kind == 'link' ? 'open' : 'press'),
        );
      });
    }
  });
}
