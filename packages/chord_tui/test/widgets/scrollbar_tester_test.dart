import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget _page(ScrollController c, {bool quiet = false, String? label}) =>
    Scrollbar(
      controller: c,
      thumbVisibility: !quiet,
      child: ListView.builder(
        controller: c,
        itemCount: 2000,
        itemBuilder: (_, i) => Text(label ?? 'row $i'),
      ),
    );

List<int> _thumb(WidgetTester t) => [
  for (final (y, line) in t.screen.lines.indexed)
    if (line.endsWith('┃')) y,
];

MouseEvent _pointer(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

void main() {
  group('CHD-638 tester: scrollbar layout and input', () {
    testWidgets('zero and one cell recover on resize', (t) async {
      final c = ScrollController();
      await t.pumpWidget(_page(c), size: Size.zero);
      for (final size in [
        const Size(1, 1),
        const Size(0, 24),
        const Size(80, 0),
        const Size(1, 24),
        const Size(80, 24),
      ]) {
        await t.resize(size);
      }
      expect(t.screen, shows('row 0'));
      expect(_thumb(t), [0]);
    });

    testWidgets('an unbounded track is finite and draws no thumb', (t) async {
      final c = ScrollController();
      await t.pumpWidget(
        Row(
          children: [
            Column(
              children: [
                Scrollbar(
                  controller: c,
                  child: SizedBox(width: 8, height: 2, child: Text('child')),
                ),
              ],
            ),
          ],
        ),
      );
      expect(_thumb(t), isEmpty);
      expect(t.screen.text, isNot(contains('Error')));
    });

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('thousand updates settle at the bottom at $size', (t) async {
        final c = ScrollController();
        await t.pumpWidget(_page(c), size: size);
        for (var i = 0; i < 1000; i++) {
          c.jumpTo(i);
        }
        c.toBottom();
        await t.pump();
        expect(c.offset, c.contentRows - c.viewRows);
        expect(_thumb(t).last, size.height - 1);
        expect(t.screen, shows('row 1999'));
        await t.resize(
          size.width == 120 ? const Size(80, 24) : const Size(120, 40),
        );
        c.toBottom();
        await t.pump();
        expect(_thumb(t).last, t.size.height - 1);
      });

      testWidgets('wide and styled text keeps its own column at $size', (
        t,
      ) async {
        final c = ScrollController();
        const glyphs = '界👩‍💻e\u0301';
        await t.pumpWidget(
          _page(c, label: '\x1b[31m${glyphs * 30}\x1b[0m'),
          size: size,
        );
        for (final width in [size.width, 8, 7, 6, 5, 4, 3, 2, 1, size.width]) {
          await t.resize(Size(width, size.height));
          expect(
            t.screen.lines.every((line) => cellWidth(line) <= width),
            isTrue,
          );
          expect(t.screen.text, isNot(contains('\x1b')));
        }
        expect(t.screen, shows(glyphs));
        expect(_thumb(t), isNotEmpty);
      });
    }

    testWidgets('every scroll key follows focus away and back', (t) async {
      final c = ScrollController();
      final inside = FocusNode(), outside = FocusNode();
      addTearDown(inside.dispose);
      addTearDown(outside.dispose);
      await t.pumpWidget(
        Column(
          children: [
            Focus(focusNode: outside, child: Text('outside')),
            Expanded(
              child: Actions(
                bindings: scrollBindings(
                  c,
                  keys: const ScrollKeys(lineUp: ['up'], lineDown: ['down']),
                ),
                child: Focus(
                  focusNode: inside,
                  autofocus: true,
                  child: _page(c),
                ),
              ),
            ),
          ],
        ),
      );
      await t.press('end');
      expect(c.offset, c.contentRows - c.viewRows);
      await t.press('home');
      expect(c.offset, 0);
      await t.press('down');
      expect(c.offset, 1);
      await t.press('up');
      expect(c.offset, 0);
      await t.press('pagedown');
      expect(c.offset, c.viewRows - 2);
      await t.press('pageup');
      expect(c.offset, 0);
      outside.requestFocus();
      await t.pump();
      await t.press('end');
      expect(c.offset, 0);
      inside.requestFocus();
      await t.pump();
      await t.press('end');
      expect(c.offset, c.contentRows - c.viewRows);
    });

    testWidgets('drag outside the track clamps and removal ends capture', (
      t,
    ) async {
      final c = ScrollController();
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: visible,
          builder: (_) => visible.value ? _page(c) : Text('removed'),
        ),
      );
      await t.mouse(_pointer(MouseEventKind.press, 79, 0));
      await t.mouse(_pointer(MouseEventKind.move, -10, 100));
      expect(c.offset, c.contentRows - c.viewRows);
      await t.mouse(_pointer(MouseEventKind.move, -10, -100));
      expect(c.offset, 0);
      visible.value = false;
      await t.pump();
      await t.mouse(_pointer(MouseEventKind.move, 79, 23));
      await t.mouse(_pointer(MouseEventKind.release, 79, 23));
      expect(t.screen.text, 'removed');
    });
  });

  group('CHD-638 tester: scrollbar quiet lifecycle', () {
    testWidgets('a later move restarts the quiet interval', (t) async {
      final c = ScrollController();
      await t.pumpWidget(_page(c, quiet: true));
      c.lineDown();
      await t.pump(const Duration(milliseconds: 350));
      c.lineDown();
      await t.pump(const Duration(milliseconds: 350));
      expect(_thumb(t), isNotEmpty);
      await t.pump(const Duration(milliseconds: 350));
      expect(_thumb(t), isEmpty);
    });

    testWidgets('removal cancels a live quiet timer and listener', (t) async {
      final c = ScrollController();
      await t.pumpWidget(_page(c, quiet: true));
      c.lineDown();
      await t.pump();
      expect(_thumb(t), isNotEmpty);
      await t.pumpWidget(Text('replacement'));
      c.lineDown();
      await t.pump(const Duration(milliseconds: 700));
      expect(t.screen.text, 'replacement');
    });

    testWidgets('replacing the controller removes the old listener', (t) async {
      final old = ScrollController(), next = ScrollController();
      final current = ValueNotifier(old);
      addTearDown(current.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: current,
          builder: (_) => _page(current.value),
        ),
      );
      current.value = next;
      await t.pump();
      old.toBottom();
      await t.pump();
      expect(_thumb(t), [0]);
      next.toBottom();
      await t.pump();
      expect(_thumb(t).last, 23);
    });
  });
}
