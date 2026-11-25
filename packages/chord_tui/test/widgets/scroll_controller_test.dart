import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A list of [heights], as a viewport would report it.
class FakeClient implements ScrollClient {
  FakeClient(this.heights);

  final List<int> heights;
  var changes = 0;

  @override
  int itemTop(int index) => heights.take(index).fold(0, (a, b) => a + b);

  @override
  int itemRows(int index) => heights[index];

  @override
  int itemAtRow(int row) {
    for (var i = heights.length - 1; i >= 0; i--) {
      if (itemTop(i) <= row) return i;
    }
    return -1;
  }

  @override
  void scrollChanged() => changes++;
}

/// A controller attached to [heights] in a view of [view] rows, laid out.
ScrollController laidOut(
  List<int> heights,
  int view, {
  Follow follow = Follow.bottom,
}) {
  final c = ScrollController(follow: follow)..attach(FakeClient(heights));
  c.setFromLayout(
    reduceMeasured(
      c.state,
      content: heights.fold(0, (a, b) => a + b),
      view: view,
      follow: follow,
    ),
  );
  c.notifyAfterLayout();
  return c;
}

void main() {
  group('tester: explicit row anchors survive live list changes', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'jumpToAnchor holds an interior line through updates and resize at $size',
        (t) async {
          final items = ValueNotifier([
            for (var i = 0; i < 100; i++)
              'item $i first\nitem $i second\nitem $i third',
          ]);
          final controller = ScrollController(follow: Follow.bottom);
          final shown = ValueNotifier<ScrollController?>(controller);
          await t.pumpWidget(shownList(shown, items), size: size);
          controller.jumpToAnchor(const ListAnchor(40, 1));
          await t.pump();
          expect(t.screen.lines.first, startsWith('item 40 second'));
          for (var i = 0; i < 1000; i++) {
            items.value = [
              'extra $i\nitem 0 first\nitem 0 second\nitem 0 third',
              ...items.value.skip(1),
            ];
          }
          await t.pump();
          expect(t.screen.lines.first, startsWith('item 40 second'));
          expect(controller.anchor, const ListAnchor(40, 1));
          await t.resize(
            size == const Size(120, 40)
                ? const Size(80, 24)
                : const Size(120, 40),
          );
          expect(t.screen.lines.first, startsWith('item 40 second'));
          await t.pumpWidget(const SizedBox());
          controller.dispose();
          shown.dispose();
          items.dispose();
        },
      );
    }
  });

  anchorTests();
  testerAnchorTests();
  // CTUI-85: a row inside an item goes on top, the item's own top plus the
  // rows into it.
  test(
    'jumpToAnchor puts a row inside an item on top, and stops following',
    () {
      final c = laidOut([1, 3, 20, 2, 4], 10);
      expect(c.isFollowing, isTrue);
      c.jumpToAnchor(const ListAnchor(2, 5));
      expect(c.offset, 1 + 3 + 5);
      expect(c.isFollowing, isFalse);
      // Clamped as a jump is: no further than the last full view.
      c.jumpToAnchor(const ListAnchor(4, 3));
      expect(c.offset, 30 - 10);
    },
  );

  test('counts are zero and items -1 until attached', () {
    final c = ScrollController();
    expect((c.contentRows, c.viewRows, c.offset, c.rowsBelow), (0, 0, 0, 0));
    expect((c.firstVisible, c.lastVisible), (-1, -1));
    expect(() => c.itemTop(0), throwsStateError);
  });

  test('counts and visible items come from the measured state', () {
    final c = laidOut([1, 3, 20, 2, 4], 10);
    expect((c.contentRows, c.viewRows, c.offset, c.rowsBelow), (30, 10, 20, 0));
    expect(c.isFollowing, isTrue);
    expect((c.firstVisible, c.lastVisible), (2, 4));
    expect((c.itemTop(3), c.itemRows(3)), (24, 2));
    c.toTop();
    expect((c.firstVisible, c.lastVisible), (0, 2));
    expect(c.rowsBelow, 20);
    expect(c.offset + c.viewRows + c.rowsBelow, c.contentRows);
  });

  test('a list that fits shows its last item on its last content row', () {
    final c = laidOut([1, 2], 10);
    expect((c.firstVisible, c.lastVisible), (0, 1));
    expect(laidOut([], 10).firstVisible, -1);
    expect(laidOut([3], 0).lastVisible, -1);
  });

  test('steps move the view by a page, a line, to the top and bottom', () {
    final c = laidOut(List.filled(100, 1), 20);
    c.pageUp();
    expect(c.offset, 62);
    expect(c.isFollowing, isFalse);
    c.lineUp();
    expect(c.offset, 61);
    c.lineDown();
    c.pageDown();
    expect(c.offset, 80);
    expect(c.isFollowing, isTrue);
    c.toTop();
    expect(c.offset, 0);
    c.jumpTo(30);
    expect(c.offset, 30);
    c.jumpTo(1000);
    expect(c.isFollowing, isTrue);
    c.toBottom();
    expect(c.offset, 80);
  });

  test('notifies once per change and never for an identical state', () {
    final c = laidOut(List.filled(100, 1), 20);
    var calls = 0;
    c.addListener(() => calls++);
    c.lineDown(); // following: nothing to do
    c.toBottom();
    expect(calls, 0);
    c.lineUp();
    expect(calls, 1);
    c.jumpTo(79);
    expect(calls, 1);
    c.toTop();
    c.toTop();
    expect(calls, 2);
  });

  test('a step tells the attached list it needs a frame', () {
    final client = FakeClient(List.filled(100, 1));
    final c = ScrollController(follow: Follow.bottom)..attach(client);
    c.setFromLayout(
      reduceMeasured(c.state, content: 100, view: 20, follow: c.follow),
    );
    c.pageUp();
    c.pageDown();
    c.pageDown(); // following again: no change
    expect(client.changes, 2);
  });

  test('markNews while following, or with Follow.none, does nothing', () {
    final c = laidOut(List.filled(100, 1), 20);
    var calls = 0;
    c.addListener(() => calls++);
    c.markNews();
    expect(c.hasNews, isFalse);
    expect(calls, 0);
    c.pageUp();
    c.markNews();
    expect(c.hasNews, isTrue);
    expect(calls, 2);
    c.markNews();
    expect(calls, 2);
    c.toBottom();
    expect(c.hasNews, isFalse);

    final picker = laidOut(List.filled(100, 1), 20, follow: Follow.none);
    picker.markNews();
    expect(picker.hasNews, isFalse);
    expect(picker.isFollowing, isFalse);
  });

  test('a Follow.none controller starts at its initial offset', () {
    final c = ScrollController(initialOffset: 30)
      ..attach(FakeClient(List.filled(100, 1)));
    c.setFromLayout(
      reduceMeasured(c.state, content: 100, view: 20, follow: c.follow),
    );
    expect(c.offset, 30);
  });

  test('layout sets the state without notifying, then notifies once', () {
    final c = laidOut(List.filled(100, 1), 20);
    var calls = 0;
    c.addListener(() => calls++);
    expect(
      c.setFromLayout(
        reduceMeasured(c.state, content: 150, view: 20, follow: c.follow),
      ),
      isTrue,
    );
    expect(calls, 0);
    expect(c.contentRows, 150);
    c.notifyAfterLayout();
    expect(calls, 1);
    c.notifyAfterLayout();
    expect(calls, 1);
    expect(c.setFromLayout(c.state), isFalse);
    c.notifyAfterLayout();
    expect(calls, 1);
  });

  test('a listener that steps again notifies twice, not recursively', () {
    final c = laidOut(List.filled(100, 1), 20);
    var depth = 0;
    var maxDepth = 0;
    final seen = <int>[];
    c.addListener(() {
      depth++;
      if (depth > maxDepth) maxDepth = depth;
      seen.add(c.offset);
      if (seen.length == 1) {
        c.lineUp();
        // Applied after the round, not inside it.
        expect(c.offset, 62);
      }
      depth--;
    });
    c.pageUp();
    expect(seen, [62, 61]);
    expect(maxDepth, 1);
  });

  test("a listener stepping on every round drains in a loop, not a stack", () {
    final c = laidOut(List.filled(200000, 1), 2);
    var rounds = 0;
    c.addListener(() {
      rounds++;
      c.lineUp();
    });
    c.lineUp();
    expect(c.offset, 0);
    // One round per row moved, from 199 997 to 0.
    expect(rounds, 199998);
  });

  test("a mutation during a direct notifyListeners waits for the round", () {
    final c = laidOut(List.filled(100, 1), 20);
    final seen = <(String, int)>[];
    c.addListener(() {
      seen.add(("first", c.offset));
      if (seen.length == 1) c.lineUp();
    });
    c.addListener(() => seen.add(("second", c.offset)));
    c.notifyListeners();
    expect(seen, [
      ("first", 80),
      ("second", 80),
      ("first", 79),
      ("second", 79),
    ]);
  });

  test(
    "notifyListeners called by a listener notifies once more after the round",
    () {
      final c = laidOut(List.filled(100, 1), 20);
      var calls = 0;
      var depth = 0;
      var maxDepth = 0;
      c.addListener(() {
        depth++;
        maxDepth = depth > maxDepth ? depth : maxDepth;
        calls++;
        if (calls == 1) c.notifyListeners();
        depth--;
      });
      c.notifyListeners();
      expect(calls, 2);
      expect(maxDepth, 1);
    },
  );

  test("a listener that steps and disposes leaves no queued step behind", () {
    final client = FakeClient(List.filled(100, 1));
    final c = ScrollController(follow: Follow.bottom)..attach(client);
    c.setFromLayout(
      reduceMeasured(c.state, content: 100, view: 20, follow: c.follow),
    );
    c.addListener(() {
      c.lineUp();
      c.dispose();
    });
    c.pageUp();
    expect(c.isDisposed, isTrue);
    expect(c.offset, 62);
    expect(client.changes, 1);
    expect(() => c.itemTop(0), throwsStateError);
  });

  test('a disposed controller throws when attached, stepped or notified', () {
    final c = ScrollController()..dispose();
    expect(() => c.attach(FakeClient([1])), throwsStateError);
    expect(c.pageUp, throwsStateError);
    expect(c.markNews, throwsStateError);
    expect(c.notifyListeners, throwsStateError);
    expect(() => c.addListener(() {}), throwsStateError);
    c.removeListener(() {});
  });

  test('a second list attaching the same controller throws', () {
    final first = FakeClient([1]);
    final c = ScrollController()..attach(first);
    c.attach(first);
    expect(() => c.attach(FakeClient([1])), throwsStateError);
    c.detach(first);
    c.attach(FakeClient([2]));
  });
  group('tester: delivery and attachment boundaries', () {
    test(
      'queued steps compose in order after every listener sees the old state',
      () {
        final c = laidOut(List.filled(100, 1), 20);
        final seen = <(String, int, bool)>[];
        var queued = false;
        c.addListener(() {
          seen.add(('first', c.offset, c.hasNews));
          if (!queued) {
            queued = true;
            c.toTop();
            c.lineDown();
            c.markNews();
            c.jumpTo(12);
          }
        });
        c.addListener(() => seen.add(('second', c.offset, c.hasNews)));
        c.pageUp();
        expect(seen, [
          ('first', 62, false),
          ('second', 62, false),
          ('first', 12, true),
          ('second', 12, true),
        ]);
        c.dispose();
      },
    );

    test('queued steps with no net change do not notify another round', () {
      final c = laidOut(List.filled(100, 1), 20);
      c.toTop();
      var calls = 0;
      c.addListener(() {
        calls++;
        c.lineDown();
        c.lineUp();
      });
      c.notifyListeners();
      expect(calls, 1);
      expect(c.offset, 0);
      c.dispose();
    });

    test(
      'one thousand layout changes notify once with the latest geometry',
      () {
        final c = laidOut(List.filled(100, 1), 20);
        final seen = <int>[];
        c.addListener(() => seen.add(c.contentRows));
        for (var content = 101; content <= 1100; content++) {
          c.setFromLayout(
            reduceMeasured(
              c.state,
              content: content,
              view: 20,
              follow: c.follow,
            ),
          );
        }
        expect(seen, isEmpty);
        c.notifyAfterLayout();
        c.notifyAfterLayout();
        expect(seen, [1100]);
        expect(c.offset, 1080);
        c.dispose();
      },
    );

    test(
      'detaching another client preserves attachment; the owner can transfer it',
      () {
        final first = FakeClient([1, 3]);
        final second = FakeClient([8]);
        final c = ScrollController()..attach(first);
        c.detach(second);
        expect(c.itemRows(1), 3);
        expect(() => c.attach(second), throwsStateError);
        c.detach(first);
        expect(() => c.itemRows(0), throwsStateError);
        c.attach(second);
        expect(c.itemRows(0), 8);
        c.dispose();
      },
    );

    test(
      'zero room hides visible items while keeping exact content geometry',
      () {
        final c = laidOut([1, 3, 20], 1);
        expect((c.firstVisible, c.lastVisible), (2, 2));
        c.setFromLayout(
          reduceMeasured(c.state, content: 24, view: 0, follow: c.follow),
        );
        expect((c.contentRows, c.offset, c.rowsBelow), (24, 24, 0));
        expect((c.firstVisible, c.lastVisible), (-1, -1));
        c.dispose();
        c.notifyAfterLayout();
        expect(() => c.setFromLayout(const ScrollState()), throwsStateError);
        for (final action in <void Function()>[
          c.pageUp,
          c.pageDown,
          c.lineUp,
          c.lineDown,
          c.toTop,
          c.toBottom,
          () => c.jumpTo(0),
          c.markNews,
        ]) {
          expect(action, throwsStateError);
        }
      },
    );
  });
  group('S4 held controller', () {
    test(
      'hold/release notify real lifecycle changes without implying explicit scroll',
      () {
        final c = laidOut([30, 30, 30], 33);
        final epoch = c.explicitScrollEpoch;
        var calls = 0;
        c.addListener(() => calls++);
        c.hold();
        expect((c.state.held, c.isFollowing, c.offset), (true, false, 57));
        expect(c.explicitScrollEpoch, epoch);
        c.hold();
        expect(calls, 1);
        c.toBottom();
        expect(c.state.held, isTrue);
        expect(c.isFollowing, isFalse);
        c.release();
        expect((c.state.held, c.isFollowing), (false, false));
        expect(calls, 2);
        c.release();
        expect(calls, 2);
        c.toBottom();
        expect(c.isFollowing, isTrue);
        c.dispose();
      },
    );

    test(
      'hold/release queued by listeners drains without recursive notification',
      () {
        final c = laidOut([90], 33);
        var calls = 0, depth = 0, maxDepth = 0;
        c.addListener(() {
          calls++;
          depth++;
          if (depth > maxDepth) maxDepth = depth;
          if (calls == 1) {
            c.toBottom();
            c.release();
          }
          depth--;
        });
        c.hold();
        expect(calls, 2);
        expect(maxDepth, 1);
        expect(c.state.held, isFalse);
        expect(c.isFollowing, isFalse);
        c.dispose();
      },
    );
  });
}

/// The list a window shows for whichever controller [shown] holds, or
/// nothing while it holds none; one `ListView` across controller swaps.
Widget shownList(
  ValueNotifier<ScrollController?> shown,
  ValueNotifier<List<String>> items,
) => ListenableBuilder(
  listenable: shown,
  builder: (context) {
    final c = shown.value;
    if (c == null) return const SizedBox();
    return ListenableBuilder(
      listenable: items,
      builder: (context) => ListView.builder(
        controller: c,
        itemCount: items.value.length,
        itemVersion: (i) => items.value[i],
        itemBuilder: (context, i) => Text(items.value[i]),
      ),
    );
  },
);

/// Items 3 rows tall at 80 columns and 6 at 40.
List<String> tallItems(int n) => [
  for (var i = 0; i < n; i++)
    'item ${i.toString().padLeft(3, '0')}${' abcd' * 40}',
];

void anchorTests() {
  group('F1 the controller keeps its anchor', () {
    const wide = Size(80, 24);
    const narrow = Size(40, 24);

    testWidgets('reattached across a width change, on the same item', (
      tester,
    ) async {
      final items = ValueNotifier(tallItems(100));
      final c = ScrollController(follow: Follow.bottom);
      final shown = ValueNotifier<ScrollController?>(c);
      await tester.pumpWidget(shownList(shown, items), size: wide);
      expect(c.itemRows(40), 3);
      c.jumpTo(c.itemTop(40));
      await tester.pump();
      expect(c.firstVisible, 40);
      shown.value = null;
      await tester.pump();
      await tester.resize(narrow);
      shown.value = c;
      await tester.pump();
      expect(c.itemRows(40), 6);
      expect(c.firstVisible, 40);
      expect(c.offset, c.itemTop(40));
      expect(tester.screen.lines.first, startsWith('item 040 '));
    });

    testWidgets('an offset inside an item is kept, and clamped to it', (
      tester,
    ) async {
      final items = ValueNotifier(tallItems(100));
      final c = ScrollController(follow: Follow.bottom);
      final shown = ValueNotifier<ScrollController?>(c);
      await tester.pumpWidget(shownList(shown, items), size: wide);
      c.jumpTo(c.itemTop(40) + 2);
      await tester.pump();
      shown.value = null;
      await tester.pump();
      await tester.resize(narrow);
      shown.value = c;
      await tester.pump();
      expect(c.offset, c.itemTop(40) + 2);
      c.jumpTo(c.itemTop(40) + 5);
      await tester.pump();
      shown.value = null;
      await tester.pump();
      await tester.resize(wide);
      shown.value = c;
      await tester.pump();
      expect(c.offset, c.itemTop(40) + 2);
    });

    testWidgets('news arriving while detached keeps the place and the mark', (
      tester,
    ) async {
      final items = ValueNotifier(tallItems(100));
      final c = ScrollController(follow: Follow.bottom);
      final shown = ValueNotifier<ScrollController?>(c);
      await tester.pumpWidget(shownList(shown, items), size: wide);
      c.jumpTo(c.itemTop(40));
      await tester.pump();
      shown.value = null;
      await tester.pump();
      items.value = [...items.value, ...tallItems(105).skip(100)];
      c.markNews();
      await tester.resize(narrow);
      shown.value = c;
      await tester.pump();
      expect(c.firstVisible, 40);
      expect(c.isFollowing, isFalse);
      expect(c.hasNews, isTrue);
    });

    testWidgets('a detached jumpTo wins over the old anchor', (tester) async {
      final items = ValueNotifier(tallItems(100));
      final c = ScrollController(follow: Follow.bottom);
      final shown = ValueNotifier<ScrollController?>(c);
      await tester.pumpWidget(shownList(shown, items), size: wide);
      c.jumpTo(c.itemTop(40));
      await tester.pump();
      shown.value = null;
      await tester.pump();
      c.jumpTo(30);
      await tester.resize(narrow);
      shown.value = c;
      await tester.pump();
      expect(c.offset, 30);
      expect(c.firstVisible, 5);
    });

    for (final follow in Follow.values) {
      testWidgets('a detached toBottom ends at the bottom, $follow', (
        tester,
      ) async {
        final items = ValueNotifier(tallItems(100));
        final c = ScrollController(follow: follow);
        final shown = ValueNotifier<ScrollController?>(c);
        await tester.pumpWidget(shownList(shown, items), size: wide);
        c.jumpTo(c.itemTop(40));
        await tester.pump();
        shown.value = null;
        await tester.pump();
        c.toBottom();
        // Follow.none keeps the rows asked for, which are the bottom only
        // at the width they were asked at; Follow.bottom follows anywhere.
        if (follow == Follow.bottom) await tester.resize(narrow);
        shown.value = c;
        await tester.pump();
        expect(c.rowsBelow, 0);
        expect(c.isFollowing, follow == Follow.bottom);
        expect(tester.screen.lines.last, contains('abcd'));
        expect(c.lastVisible, 99);
      });
    }

    testWidgets('an empty list drops the anchor, as today', (tester) async {
      final items = ValueNotifier(tallItems(100));
      final c = ScrollController(follow: Follow.bottom);
      final shown = ValueNotifier<ScrollController?>(c);
      await tester.pumpWidget(shownList(shown, items), size: wide);
      c.jumpTo(c.itemTop(40));
      await tester.pump();
      final all = items.value;
      items.value = [];
      await tester.pump();
      expect(c.anchor, isNull);
      items.value = all;
      await tester.pump();
      expect(c.isFollowing, isTrue);
      expect(c.lastVisible, 99);
    });

    testWidgets('a zero-width frame drops the anchor, as today', (
      tester,
    ) async {
      final items = ValueNotifier(tallItems(100));
      final c = ScrollController(follow: Follow.bottom);
      final shown = ValueNotifier<ScrollController?>(c);
      await tester.pumpWidget(shownList(shown, items), size: wide);
      c.jumpTo(c.itemTop(40));
      await tester.pump();
      await tester.resize(const Size(0, 24));
      expect(c.anchor, isNull);
      await tester.resize(wide);
      expect(c.isFollowing, isTrue);
      expect(c.lastVisible, 99);
    });

    testWidgets('swapped controllers each come back on their own item', (
      tester,
    ) async {
      final items = ValueNotifier(tallItems(100));
      final a = ScrollController(follow: Follow.bottom);
      final b = ScrollController(follow: Follow.bottom);
      final shown = ValueNotifier<ScrollController?>(a);
      await tester.pumpWidget(shownList(shown, items), size: wide);
      a.jumpTo(a.itemTop(40));
      await tester.pump();
      shown.value = b;
      await tester.pump();
      b.jumpTo(b.itemTop(60));
      await tester.pump();
      await tester.resize(narrow);
      expect(b.firstVisible, 60);
      shown.value = a;
      await tester.pump();
      expect(a.firstVisible, 40);
      expect(a.offset, a.itemTop(40));
      shown.value = b;
      await tester.pump();
      expect(b.firstVisible, 60);
    });

    testWidgets('a following controller reattached is at the bottom', (
      tester,
    ) async {
      final items = ValueNotifier(tallItems(100));
      final c = ScrollController(follow: Follow.bottom);
      final shown = ValueNotifier<ScrollController?>(c);
      await tester.pumpWidget(shownList(shown, items), size: wide);
      expect(c.isFollowing, isTrue);
      shown.value = null;
      await tester.pump();
      items.value = [...items.value, ...tallItems(103).skip(100)];
      await tester.resize(narrow);
      shown.value = c;
      await tester.pump();
      expect(c.isFollowing, isTrue);
      expect(c.lastVisible, 102);
      expect(c.rowsBelow, 0);
    });
  });
}

void testerAnchorTests() {
  group('tester: F1 detached anchor boundaries', () {
    for (final size in [
      const Size(120, 40),
      const Size(80, 24),
      const Size(1, 1),
    ]) {
      testWidgets(
        'nonmoving detached commands preserve Unicode place at $size',
        (tester) async {
          final items = ValueNotifier([
            for (var i = 0; i < 100; i++)
              '$i 界🙂e\u0301\x1b[31m${' abcd' * 40}',
          ]);
          final c = ScrollController(follow: Follow.bottom);
          final shown = ValueNotifier<ScrollController?>(c);
          await tester.pumpWidget(shownList(shown, items), size: size);
          c.jumpTo(c.itemTop(40));
          await tester.pump();
          shown.value = null;
          await tester.pump();
          c.jumpTo(c.offset);
          c.hold();
          c.release();
          for (var i = 0; i < 1000; i++) {
            items.value = [...items.value, 'news $i'];
            c.markNews();
          }
          await tester.resize(const Size(60, 20));
          shown.value = c;
          await tester.pump();
          expect(c.firstVisible, 40);
          expect(c.offset, c.itemTop(40));
          expect(c.hasNews, isTrue);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          shown.dispose();
          items.dispose();
        },
      );
    }

    testWidgets('detached queued movement wins after a listener round', (
      tester,
    ) async {
      final items = ValueNotifier(tallItems(100));
      final c = ScrollController(follow: Follow.bottom);
      final shown = ValueNotifier<ScrollController?>(c);
      await tester.pumpWidget(
        shownList(shown, items),
        size: const Size(80, 24),
      );
      c.jumpTo(c.itemTop(40));
      await tester.pump();
      shown.value = null;
      await tester.pump();
      var moved = false;
      c.addListener(() {
        if (!moved) {
          moved = true;
          c.toTop();
          c.lineDown();
        }
      });
      c.markNews();
      await tester.resize(const Size(40, 24));
      shown.value = c;
      await tester.pump();
      expect(c.offset, 1);
      expect(c.firstVisible, 0);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      shown.dispose();
      items.dispose();
    });

    testWidgets('a removed detached anchor clamps to the last remaining item', (
      tester,
    ) async {
      final items = ValueNotifier(tallItems(100));
      final c = ScrollController(follow: Follow.none);
      final shown = ValueNotifier<ScrollController?>(c);
      await tester.pumpWidget(shownList(shown, items), size: const Size(80, 1));
      c.jumpTo(c.itemTop(90));
      await tester.pump();
      shown.value = null;
      await tester.pump();
      items.value = items.value.take(50).toList();
      await tester.resize(const Size(40, 1));
      shown.value = c;
      await tester.pump();
      expect(c.firstVisible, 49);
      expect(c.offset, c.itemTop(49));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      shown.dispose();
      items.dispose();
    });
  });
}
