import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A page: 50 numbered rows, a text area, 50 more rows, then a focusable
/// line at the end: 102 rows in all.
Widget page(
  ScrollController scroll, {
  TextAreaController? text,
  FocusNode? area,
  FocusNode? end,
  List<Binding> keys = const [],
  void Function(BuildContext context)? heading,
  FocusNode? pageFocus,
}) => Actions(
  bindings: [
    ...scrollBindings(
      scroll,
      keys: const ScrollKeys(lineUp: ['up'], lineDown: ['down']),
    ),
    ...keys,
  ],
  child: Focus(
    focusNode: pageFocus,
    autofocus: true,
    child: Scrollbar(
      controller: scroll,
      child: SingleChildScrollView(
        controller: scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 50; i++) Text('row $i'),
            TextArea(controller: text, focusNode: area, maxHeight: 4),
            for (var i = 50; i < 100; i++) Text('row $i'),
            Focus(
              focusNode: end,
              child: Builder(
                builder: (context) {
                  heading?.call(context);
                  return Text('the end');
                },
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

String bare(String line) => line.replaceAll('┃', '').trimRight();

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('it paints the rows [offset, offset + view)', (t) async {
        final scroll = ScrollController();
        await t.pumpWidget(page(scroll), size: size);
        expect(bare(t.screen.lines.first), 'row 0');
        expect(scroll.contentRows, 102);
        expect(scroll.viewRows, size.height);
        scroll.jumpTo(5);
        await t.pump();
        expect(bare(t.screen.lines.first), 'row 5');
        expect(bare(t.screen.lines.last), 'row ${5 + size.height - 1}');
      });

      testWidgets('the page\'s keys and the wheel scroll it; the scrollbar '
          'tracks it', (t) async {
        final scroll = ScrollController();
        await t.pumpWidget(page(scroll), size: size);
        await t.press('down');
        expect(scroll.offset, 1);
        await t.press('end');
        await t.pump();
        expect(scroll.offset, 102 - size.height);
        expect(t.screen.charAt(size.width - 1, size.height - 1), '┃');
        await t.press('home');
        await t.mouse(
          MouseEvent(
            MouseEventKind.wheel,
            position: const Offset(2, 2),
            scrollDelta: const Offset(0, 3),
          ),
        );
        await t.pump();
        expect(scroll.offset, 3);
      });

      testWidgets('a text area keeps its text and focus across a scroll away '
          'and back', (t) async {
        final scroll = ScrollController();
        final text = TextAreaController();
        final area = FocusNode();
        await t.pumpWidget(
          page(scroll, text: text, area: area),
          size: size,
        );
        area.requestFocus();
        await t.pump();
        await t.type('kept');
        scroll.toTop();
        await t.pump();
        expect(t.screen, isNot(shows('kept')));
        expect(area.hasPrimaryFocus, isTrue);
        scroll.jumpTo(40);
        await t.pump();
        expect(t.screen, shows('kept'));
        expect(text.text, 'kept');
        expect(area.hasPrimaryFocus, isTrue);
      });

      testWidgets('focus moving to a widget out of view scrolls it in', (
        t,
      ) async {
        final scroll = ScrollController();
        final end = FocusNode();
        await t.pumpWidget(page(scroll, end: end), size: size);
        end.requestFocus();
        await t.pump();
        await t.pump();
        expect(bare(t.screen.lines.last), 'the end');
        expect(scroll.offset, 102 - size.height);
      });

      testWidgets('typing into a focused editor scrolled away brings its '
          'cursor back', (t) async {
        final scroll = ScrollController();
        final area = FocusNode();
        await t.pumpWidget(page(scroll, area: area), size: size);
        area.requestFocus();
        await t.pump();
        await t.pump();
        scroll.toTop();
        await t.pump();
        // Scrolled away, the area keeps the keys.
        await t.type('typed');
        await t.pump();
        expect(t.screen, shows('typed'));
      });

      testWidgets('arrows go to a focused child first, and scroll the page '
          'otherwise', (t) async {
        final scroll = ScrollController();
        final area = FocusNode();
        final pageFocus = FocusNode();
        final text = TextAreaController()..text = 'one\ntwo\nthree';
        await t.pumpWidget(
          page(scroll, text: text, area: area, pageFocus: pageFocus),
          size: size,
        );
        area.requestFocus();
        await t.pump();
        await t.pump();
        final before = scroll.offset;
        await t.press('up');
        expect(scroll.offset, before, reason: 'the area moved its cursor');
        pageFocus.requestFocus();
        await t.pump();
        await t.press('down');
        expect(scroll.offset, before + 1);
      });

      testWidgets('rowOf and ensureVisible place a widget', (t) async {
        final scroll = ScrollController();
        late BuildContext context;
        await t.pumpWidget(
          page(scroll, heading: (c) => context = c),
          size: size,
        );
        expect(Scrollable.rowOf(context), 101);
        Scrollable.ensureVisible(context, alignment: 0);
        await t.pump();
        expect(scroll.offset, 102 - size.height, reason: 'clamped at the end');
        scroll.toTop();
        await t.pump();
        Scrollable.ensureVisible(context);
        await t.pump();
        expect(bare(t.screen.lines.last), 'the end');
      });
    });
  }

  testWidgets('rowOf is null outside a scroll view', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return Text('x');
        },
      ),
    );
    expect(Scrollable.rowOf(context), isNull);
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a following controller starts at the top, End reaches the '
        'end, and growth does not follow, at $size', (t) async {
      final scroll = ScrollController(follow: Follow.bottom);
      final rows = ValueNotifier(100);
      await t.pumpWidget(
        Actions(
          bindings: scrollBindings(scroll),
          child: Focus(
            autofocus: true,
            child: ListenableBuilder(
              listenable: rows,
              builder: (context) => SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [for (var i = 0; i < rows.value; i++) Text('$i')],
                ),
              ),
            ),
          ),
        ),
        size: size,
      );
      expect(scroll.offset, 0);
      await t.press('end');
      await t.pump();
      expect(scroll.offset, 100 - size.height);
      expect(t.screen.lines.last, '99');
      rows.value = 120;
      await t.pump();
      expect(scroll.offset, 100 - size.height, reason: 'no following');
      await t.press('end');
      await t.pump();
      expect(scroll.offset, 120 - size.height);
    });

    testWidgets('a key a focused widget without a cursor takes brings it '
        'back; a key it leaves scrolls the page, at $size', (t) async {
      final scroll = ScrollController();
      final toggle = FocusNode();
      await t.pumpWidget(
        Actions(
          bindings: scrollBindings(
            scroll,
            keys: const ScrollKeys(lineUp: ['up'], lineDown: ['down']),
          ),
          child: Focus(
            autofocus: true,
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  for (var i = 0; i < 50; i++) Text('row $i'),
                  _Toggle(toggle),
                  for (var i = 50; i < 100; i++) Text('row $i'),
                ],
              ),
            ),
          ),
        ),
        size: size,
      );
      toggle.requestFocus();
      await t.pump();
      await t.pump();
      expect(t.screen, shows('[ off ]'));
      // Wheeled away, it stays focused and out of sight.
      await t.mouse(
        MouseEvent(
          MouseEventKind.wheel,
          position: const Offset(1, 1),
          scrollDelta: const Offset(0, 45),
        ),
      );
      await t.pump();
      expect(t.screen, isNot(shows('[ off ]')));
      final away = scroll.offset;
      // A key the toggle leaves goes on to the page, which scrolls.
      await t.press('down');
      await t.pump();
      expect(scroll.offset, away + 1);
      // One it takes changes it, and brings it back.
      await t.press('space');
      await t.pump();
      await t.pump();
      expect(t.screen, shows('[ on ]'));
    });
  }

  testWidgets('a page never follows its end', (t) async {
    final scroll = ScrollController(follow: Follow.bottom);
    await t.pumpWidget(page(scroll), size: const Size(80, 24));
    expect(bare(t.screen.lines.first), 'row 0');
  });
}

/// A focusable toggle with no cursor: space flips its label.
class _Toggle extends StatefulWidget {
  const _Toggle(this.node);
  final FocusNode node;
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  var _on = false;
  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.node,
    onKey: (event) {
      if (!event.matches('space')) return false;
      setState(() => _on = !_on);
      return true;
    },
    child: Text(_on ? '[ on ]' : '[ off ]'),
  );
}
