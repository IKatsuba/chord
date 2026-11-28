import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget page(
  ScrollController c,
  int items, {
  bool thumbVisibility = true,
  EdgeInsets padding = EdgeInsets.zero,
}) => Padding(
  padding: padding,
  child: Scrollbar(
    controller: c,
    thumbVisibility: thumbVisibility,
    child: ListView.builder(
      controller: c,
      itemCount: items,
      itemBuilder: (context, i) => Text('item $i'),
    ),
  ),
);

/// The rows of the screen's column [x] that show the thumb.
List<int> thumbRows(WidgetTester t, int x) => [
  for (final (y, line) in t.screen.lines.indexed)
    if (line.length > x && line[x] == '┃') y,
];

MouseEvent press(int x, int y) => MouseEvent(
  MouseEventKind.press,
  position: Offset(x, y),
  button: MouseButton.primary,
);
MouseEvent drag(int x, int y) => MouseEvent(
  MouseEventKind.move,
  position: Offset(x, y),
  button: MouseButton.primary,
);
MouseEvent release(int x, int y) => MouseEvent(
  MouseEventKind.release,
  position: Offset(x, y),
  button: MouseButton.primary,
);

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    final bar = size.width - 1;
    final h = size.height;
    final length = (h * h / 400).round();

    testWidgets('the thumb is view² / content rows, at the top, at $size', (
      t,
    ) async {
      final c = ScrollController();
      await t.pumpWidget(page(c, 400), size: size);
      expect(thumbRows(t, bar), [for (var y = 0; y < length; y++) y]);
      expect(t.screen.lines.first, startsWith('item 0'));
    });

    testWidgets('it follows the offset to the end at $size', (t) async {
      final c = ScrollController();
      await t.pumpWidget(page(c, 400), size: size);
      c.toBottom();
      await t.pump();
      expect(thumbRows(t, bar).last, h - 1);
      expect(thumbRows(t, bar).length, length);
    });

    testWidgets('no thumb when everything fits, and the column stays at '
        '$size', (t) async {
      final c = ScrollController();
      await t.pumpWidget(page(c, 3), size: size);
      expect(thumbRows(t, bar), isEmpty);
      expect(t.screen.lines.first, 'item 0');
      expect(c.viewRows, h);
    });

    testWidgets('a press below the thumb pages down, above it pages up, at '
        '$size', (t) async {
      final c = ScrollController();
      await t.pumpWidget(page(c, 400), size: size);
      await t.mouse(press(bar, h - 1));
      await t.mouse(release(bar, h - 1));
      expect(c.offset, h - 2);
      await t.mouse(press(bar, 0));
      await t.mouse(release(bar, 0));
      expect(c.offset, 0);
    });

    testWidgets('dragging the thumb moves the view at $size', (t) async {
      final c = ScrollController();
      await t.pumpWidget(page(c, 400), size: size);
      final room = h - length;
      await t.mouse(press(bar, 0));
      await t.mouse(drag(bar, room));
      expect(c.offset, 400 - h);
      expect(thumbRows(t, bar).last, h - 1);
      await t.mouse(drag(bar, room ~/ 2));
      expect(
        c.offset,
        scrollbarOffsetFor(top: room ~/ 2, track: h, view: h, content: 400),
      );
      await t.mouse(release(bar, room ~/ 2));
      await t.mouse(drag(bar, 0));
      expect(
        c.offset,
        scrollbarOffsetFor(top: room ~/ 2, track: h, view: h, content: 400),
        reason: 'a move after the release drags nothing',
      );
    });

    testWidgets('a press on the list beside it does nothing to the view at '
        '$size', (t) async {
      final c = ScrollController();
      await t.pumpWidget(page(c, 400), size: size);
      await t.mouse(press(bar - 1, h - 1));
      expect(c.offset, 0);
    });
  }

  testWidgets('a padded track maps presses by its own rows', (t) async {
    final c = ScrollController();
    await t.pumpWidget(
      page(c, 400, padding: const EdgeInsets.only(top: 5, right: 3)),
      size: const Size(80, 24),
    );
    // Track 19 rows from row 5; view 19, content 400: thumb 1 row at row 5.
    expect(thumbRows(t, 76), [5]);
    await t.mouse(press(76, 5));
    await t.mouse(drag(76, 5 + 18));
    expect(c.offset, 400 - 19);
    expect(thumbRows(t, 76), [5 + 18]);
  });

  testWidgets('thumbVisibility false shows the thumb only while the view '
      'moves, for 600 ms', (t) async {
    final c = ScrollController();
    await t.pumpWidget(
      page(c, 400, thumbVisibility: false),
      size: const Size(80, 24),
    );
    expect(thumbRows(t, 79), isEmpty);
    c.lineDown();
    await t.pump();
    expect(thumbRows(t, 79), isNotEmpty);
    await t.pump(const Duration(milliseconds: 300));
    expect(thumbRows(t, 79), isNotEmpty);
    await t.pump(const Duration(milliseconds: 400));
    expect(thumbRows(t, 79), isEmpty);
  });

  for (final kind in [MouseEventKind.release, MouseEventKind.cancel]) {
    testWidgets('a thumb held past 600 ms hides on its ${kind.name}, with no '
        'scroll after', (t) async {
      final c = ScrollController();
      await t.pumpWidget(
        page(c, 400, thumbVisibility: false),
        size: const Size(80, 24),
      );
      c.lineDown();
      await t.pump();
      final top = thumbRows(t, 79).first;
      await t.mouse(press(79, top));
      await t.pump(const Duration(milliseconds: 700));
      expect(thumbRows(t, 79), isNotEmpty, reason: 'held, it stays');
      t.host.handleMouse(
        MouseEvent(
          kind,
          position: Offset(79, top),
          button: MouseButton.primary,
        ),
      );
      await t.pump();
      expect(thumbRows(t, 79), isEmpty);
    });
  }

  testWidgets('it takes the theme\'s border style for the thumb', (t) async {
    final c = ScrollController();
    await t.pumpWidget(page(c, 400), size: const Size(80, 24));
    expect(t.screen.styleAt(79, 0), ThemeData.dark().border);
  });
}
