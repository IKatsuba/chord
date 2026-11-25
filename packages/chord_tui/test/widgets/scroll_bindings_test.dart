import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const sizes = [Size(120, 40), Size(80, 24)];

/// A list of [n] rows above a focused widget that takes no keys, with the
/// scroll bindings above both, as the transcript has them.
Widget app(
  ScrollController c, {
  int n = 500,
  ScrollKeys keys = const ScrollKeys(),
  List<Binding> inner = const [],
}) => Actions(
  bindings: scrollBindings(c, keys: keys),
  child: Column(
    children: [
      Expanded(
        child: ListView.builder(
          controller: c,
          itemCount: n,
          itemBuilder: (context, i) => Text('item $i'),
        ),
      ),
      Actions(
        bindings: inner,
        child: Focus(autofocus: true, child: Text('prompt')),
      ),
    ],
  ),
);

void main() {
  test('the defaults bind pages and the ends, with descriptions', () {
    final c = ScrollController();
    expect(scrollBindings(c).map((b) => '$b'), [
      'pageup: Scroll up a page',
      'pagedown: Scroll down a page',
      'home: Scroll to the top',
      'end: Scroll to the bottom',
    ]);
  });

  test(
    "chord's keys: two keys for a step are two bindings, one description",
    () {
      final c = ScrollController();
      final bindings = scrollBindings(
        c,
        keys: const ScrollKeys(
          pageUp: ['pageup', 'shift+pageup'],
          pageDown: ['pagedown', 'shift+pagedown'],
          lineUp: ['shift+up'],
          lineDown: ['shift+down'],
          top: ['home', 'shift+home'],
          bottom: ['end', 'shift+end'],
        ),
      );
      expect(bindings.length, 10);
      expect(
        bindings.where((b) => b.description == 'Scroll up a page').length,
        2,
      );
      expect(bindings.map((b) => b.description).toSet(), {
        'Scroll up a page',
        'Scroll down a page',
        'Scroll up a line',
        'Scroll down a line',
        'Scroll to the top',
        'Scroll to the bottom',
      });
      checkBindings(bindings);
    },
  );

  for (final size in sizes) {
    final rows = size.height - 1;

    testWidgets('the default keys scroll a following list at '
        '${size.width}x${size.height}', (tester) async {
      final c = ScrollController(follow: Follow.bottom);
      await tester.pumpWidget(app(c), size: size);
      expect(tester.screen.lines[rows - 1], 'item 499');
      expect(tester.screen.lines.last, 'prompt');

      await tester.press('pageup');
      expect(c.isFollowing, isFalse);
      expect(c.offset, 500 - rows - (rows - 2));
      expect(tester.screen.lines.first, 'item ${c.offset}');

      await tester.press('home');
      expect(tester.screen.lines.first, 'item 0');

      await tester.press('pagedown');
      expect(tester.screen.lines.first, 'item ${rows - 2}');

      await tester.press('end');
      expect(c.isFollowing, isTrue);
      expect(tester.screen.lines[rows - 1], 'item 499');

      // No line keys by default: up and down are not the list's.
      await tester.press('up');
      expect(c.isFollowing, isTrue);
    });

    testWidgets('shift+up and shift+down step a line at '
        '${size.width}x${size.height}', (tester) async {
      final c = ScrollController(follow: Follow.bottom);
      await tester.pumpWidget(
        app(
          c,
          keys: const ScrollKeys(
            lineUp: ['shift+up'],
            lineDown: ['shift+down'],
          ),
        ),
        size: size,
      );
      await tester.press('shift+up');
      expect(tester.screen.lines.first, 'item ${500 - rows - 1}');
      expect(tester.screen.lines[rows - 1], 'item 498');
      await tester.press('shift+down');
      expect(c.isFollowing, isTrue);
      expect(tester.screen.lines[rows - 1], 'item 499');
    });
  }

  testWidgets("a nearer scope's pageup shadows the list's", (tester) async {
    final c = ScrollController(follow: Follow.bottom);
    var own = 0;
    await tester.pumpWidget(
      app(c, inner: [Binding('pageup', 'Page the box up', () => own++)]),
    );
    await tester.press('pageup');
    expect(own, 1);
    expect(c.isFollowing, isTrue);
    // Keys the nearer scope does not bind still reach the list.
    await tester.press('home');
    expect(c.offset, 0);
  });

  testWidgets('KeyHelp lists the scroll bindings', (tester) async {
    final c = ScrollController(follow: Follow.bottom);
    await tester.pumpWidget(
      Column(
        children: [
          Expanded(child: app(c)),
          const KeyHelp(),
        ],
      ),
      size: const Size(160, 10),
    );
    expect(tester.screen.lines.last, contains('pageup Scroll up a page'));
    expect(tester.screen.lines.last, contains('end Scroll to the bottom'));
  });

  group('tester: complete key dispatch', () {
    const aliases = ScrollKeys(
      pageUp: ['pageup', 'shift+pageup'],
      pageDown: ['pagedown', 'shift+pagedown'],
      lineUp: ['shift+up'],
      lineDown: ['shift+down'],
      top: ['home', 'shift+home'],
      bottom: ['end', 'shift+end'],
    );
    const empty = ScrollKeys(pageUp: [], pageDown: [], top: [], bottom: []);

    test('empty key lists create no bindings', () {
      expect(scrollBindings(ScrollController(), keys: empty), isEmpty);
    });

    for (final size in sizes) {
      testWidgets('every alias invokes its described step at $size', (
        tester,
      ) async {
        final c = ScrollController(follow: Follow.bottom);
        await tester.pumpWidget(app(c, keys: aliases), size: size);
        final page = size.height - 3;
        for (final key in aliases.pageUp) {
          c.jumpTo(200);
          await tester.press(key);
          expect(c.offset, 200 - page, reason: key);
        }
        for (final key in aliases.pageDown) {
          c.jumpTo(200);
          await tester.press(key);
          expect(c.offset, 200 + page, reason: key);
        }
        c.jumpTo(200);
        await tester.press('shift+up');
        expect(c.offset, 199);
        await tester.press('shift+down');
        expect(c.offset, 200);
        for (final key in aliases.top) {
          c.jumpTo(200);
          await tester.press(key);
          expect(c.offset, 0, reason: key);
        }
        for (final key in aliases.bottom) {
          c.jumpTo(200);
          c.markNews();
          await tester.press(key);
          expect(c.isFollowing, isTrue, reason: key);
          expect(c.hasNews, isFalse, reason: key);
        }
      });

      testWidgets('empty bindings leave every scroll key unhandled at $size', (
        tester,
      ) async {
        final c = ScrollController();
        await tester.pumpWidget(app(c, keys: empty), size: size);
        for (final key in [
          'pageup',
          'pagedown',
          'home',
          'end',
          'up',
          'down',
          'shift+pageup',
          'shift+pagedown',
          'shift+home',
          'shift+end',
          'shift+up',
          'shift+down',
        ]) {
          c.jumpTo(200);
          await tester.press(key);
          expect(c.offset, 200, reason: key);
        }
      });

      testWidgets('focus leaving and returning controls dispatch at $size', (
        tester,
      ) async {
        final c = ScrollController(follow: Follow.bottom);
        await tester.pumpWidget(
          Row(
            children: [
              Expanded(child: app(c)),
              Focus(child: Text('outside')),
            ],
          ),
          size: size,
        );
        final end = c.offset;
        await tester.press('tab');
        await tester.press('pageup');
        expect(c.offset, end);
        await tester.press('shift+tab');
        await tester.press('pageup');
        expect(c.offset, end - (size.height - 3));
      });
    }
  });
}
