import 'dart:async';

import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const sizes = [Size(120, 40), Size(80, 24)];

/// Counts builder calls and the item states alive.
class Probe {
  final builds = <int, int>{};
  final live = <int>{};
  int get totalBuilds => builds.values.fold(0, (a, b) => a + b);

  Widget item(int i, String text) {
    builds[i] = (builds[i] ?? 0) + 1;
    return Item(i, text, this);
  }
}

class Item extends StatefulWidget {
  const Item(this.index, this.text, this.probe, {super.key});

  final int index;
  final String text;
  final Probe probe;

  @override
  State<Item> createState() => _ItemState();
}

class _ItemState extends State<Item> {
  @override
  void initState() {
    super.initState();
    widget.probe.live.add(widget.index);
  }

  @override
  void dispose() {
    widget.probe.live.remove(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.text);
}

List<String> numbered(int n) => [for (var i = 0; i < n; i++) 'item $i'];

/// One row of text per line; an item's text may hold several lines.
Widget list(
  ValueNotifier<List<String>> lines,
  ScrollController? controller,
  Probe probe, {
  bool versioned = true,
}) => ListenableBuilder(
  listenable: lines,
  builder: (context) => ListView.builder(
    controller: controller,
    itemCount: lines.value.length,
    itemVersion: versioned ? (i) => lines.value[i] : null,
    itemBuilder: (context, i) => probe.item(i, lines.value[i]),
  ),
);

/// [child] with the controller's rows below drawn over its last row, as
/// chord's rule is.
Widget withRule(Widget child, ScrollController c) => Stack(
  children: [
    child,
    Align(
      alignment: Alignment.bottomLeft,
      child: ListenableBuilder(
        listenable: c,
        builder: (context) =>
            Text(c.isFollowing ? '' : '-- ${c.rowsBelow} below --'),
      ),
    ),
  ],
);

/// Prints the screen when SHOW_SCREENS=1, for the designer's captures.
void show(WidgetTester tester, String label) {
  if (Platform.environment['SHOW_SCREENS'] != '1') return;
  final s = tester.size;
  final border = '+${'-' * s.width}+';
  print('\n== $label (${s.width}x${s.height}) ==\n$border');
  for (final l in tester.screen.lines) {
    print('|${l.padRight(s.width)}|');
  }
  print(border);
}

String sizeName(Size s) => '${s.width}x${s.height}';

void main() {
  for (final size in sizes) {
    final rows = size.height;

    group('at ${sizeName(size)}', () {
      testWidgets(
        '10 000 rows following the bottom build only those in sight',
        (tester) async {
          final probe = Probe();
          final c = ScrollController(follow: Follow.bottom);
          await tester.pumpWidget(
            list(ValueNotifier(numbered(10000)), c, probe),
            size: size,
          );
          expect(tester.screen.lines.last, 'item 9999');
          expect(tester.screen.lines.first, 'item ${10000 - rows}');
          expect(probe.live.length, rows);
          expect(c.contentRows, 10000);
          expect(c.viewRows, rows);
          expect(c.isFollowing, isTrue);
          expect((c.firstVisible, c.lastVisible), (10000 - rows, 9999));
          probe.builds.clear();
          await tester.pump();
          expect(probe.totalBuilds, 0);
          show(tester, 'following the bottom, 10 000 rows');
        },
      );

      testWidgets(
        'paging through every row never leaves more states than rows',
        (tester) async {
          final probe = Probe();
          final c = ScrollController(follow: Follow.bottom);
          await tester.pumpWidget(
            list(ValueNotifier(numbered(2000)), c, probe),
            size: size,
          );
          while (c.offset > 0) {
            c.pageUp();
            await tester.pump();
            expect(probe.live.length, lessThanOrEqualTo(rows));
            expect(tester.screen.lines.first, 'item ${c.offset}');
          }
          while (!c.isFollowing) {
            c.pageDown();
            await tester.pump();
            expect(probe.live.length, lessThanOrEqualTo(rows));
          }
          expect(tester.screen.lines.last, 'item 1999');
        },
      );

      testWidgets(
        '1 000 appends between two pumps keep the end on the last row',
        (tester) async {
          final probe = Probe();
          final lines = ValueNotifier(numbered(10));
          final c = ScrollController(follow: Follow.bottom);
          await tester.pumpWidget(list(lines, c, probe), size: size);
          expect(tester.screen.lines.first, 'item 0');
          for (var n = 11; n <= 1010; n++) {
            lines.value = numbered(n);
          }
          await tester.pump();
          expect(tester.screen.lines.last, 'item 1009');
          expect(c.isFollowing, isTrue);
          expect(probe.live.length, rows);
        },
      );

      testWidgets(
        'pageup, 200 appends, one pump: the rows hold and the count grows',
        (tester) async {
          final probe = Probe();
          final lines = ValueNotifier(numbered(500));
          final c = ScrollController(follow: Follow.bottom);
          await tester.pumpWidget(
            withRule(list(lines, c, probe), c),
            size: size,
          );
          expect(tester.screen.lines.last, 'item 499');
          c.pageUp();
          await tester.pump();
          final before = tester.screen.lines.sublist(0, rows - 1);
          final below = c.rowsBelow;
          expect(tester.screen.lines.last, '-- $below below --');
          lines.value = numbered(700);
          await tester.pump();
          expect(tester.screen.lines.sublist(0, rows - 1), before);
          expect(c.rowsBelow, below + 200);
          // The overlay reads the controller layout set, on the same pump.
          expect(tester.screen.lines.last, '-- ${below + 200} below --');
          show(tester, 'scrolled back, 200 appended, rule overlay');
        },
      );

      testWidgets(
        'an item above the view changing height keeps the top item and row',
        (tester) async {
          final probe = Probe();
          final lines = ValueNotifier(numbered(300));
          final c = ScrollController(follow: Follow.bottom);
          await tester.pumpWidget(list(lines, c, probe), size: size);
          c.jumpTo(100);
          await tester.pump();
          expect(tester.screen.lines.first, 'item 100');
          lines.value = ['item 0\nnow\nfour\nrows', ...lines.value.skip(1)];
          await tester.pump();
          expect(tester.screen.lines.first, 'item 100');
          expect(c.offset, 103);
          show(tester, 'anchor kept after an item above grew');
          expect(c.isFollowing, isFalse);
        },
      );

      testWidgets('a resize while scrolled back keeps the top item', (
        tester,
      ) async {
        final probe = Probe();
        final words = List.filled(30, 'word').join(' ');
        final lines = ValueNotifier([
          for (var i = 0; i < 300; i++) 'item $i $words',
        ]);
        final c = ScrollController(follow: Follow.bottom);
        await tester.pumpWidget(list(lines, c, probe), size: size);
        c.jumpTo(c.itemTop(150));
        await tester.pump();
        expect(tester.screen.lines.first, startsWith('item 150 '));
        await tester.resize(Size(size.width ~/ 2, rows));
        expect(tester.screen.lines.first, startsWith('item 150 '));
        await tester.resize(size);
        expect(tester.screen.lines.first, startsWith('item 150 '));
        expect(c.firstVisible, 150);
        show(tester, 'anchor kept across a resize');
      });

      testWidgets('items of 1, 3 and 20 rows; one cut at both edges', (
        tester,
      ) async {
        final probe = Probe();
        String tall(String name, int n) =>
            [for (var r = 0; r < n; r++) '$name row $r'].join('\n');
        final lines = ValueNotifier([
          tall('one', 1),
          tall('three', 3),
          tall('big', rows + 20),
          tall('end', 1),
        ]);
        final c = ScrollController();
        await tester.pumpWidget(list(lines, c, probe), size: size);
        expect(tester.screen.lines.take(5), [
          'one row 0',
          'three row 0',
          'three row 1',
          'three row 2',
          'big row 0',
        ]);
        expect(c.contentRows, 1 + 3 + rows + 20 + 1);
        expect((c.itemTop(2), c.itemRows(2)), (4, rows + 20));
        c.jumpTo(14);
        await tester.pump();
        expect(tester.screen.lines.first, 'big row 10');
        expect(tester.screen.lines.last, 'big row ${10 + rows - 1}');
        expect(probe.live, {2});
        show(tester, 'a 20+ row item cut at both edges');
        c.toBottom();
        await tester.pump();
        expect(tester.screen.lines.last, 'end row 0');
        expect(tester.screen.lines.first, 'big row 21');
      });
    });
  }

  testWidgets('a builder that throws gives one error row and the rest draw', (
    tester,
  ) async {
    await tester.pumpWidget(
      ListView.builder(
        itemCount: 5,
        itemBuilder: (context, i) =>
            i == 2 ? throw StateError('no item 2') : Text('item $i'),
      ),
    );
    final l = tester.screen.lines;
    expect(l.take(2), ['item 0', 'item 1']);
    expect(l[2], contains('no item 2'));
    expect(l.skip(3).take(2), ['item 3', 'item 4']);
    expect(tester.screen.styleAt(0, 2).bg, Colors.red);
  });

  testWidgets('itemCount shrinking under the view, and to zero', (
    tester,
  ) async {
    final probe = Probe();
    final lines = ValueNotifier(numbered(200));
    final c = ScrollController(follow: Follow.bottom);
    await tester.pumpWidget(list(lines, c, probe), size: const Size(80, 10));
    c.jumpTo(150);
    await tester.pump();
    expect(tester.screen.lines.first, 'item 150');
    lines.value = numbered(100);
    await tester.pump();
    expect(tester.screen.lines.last, 'item 99');
    expect(c.offset, 90);
    expect(probe.live.length, 10);
    lines.value = [];
    await tester.pump();
    expect(tester.screen.text, '');
    expect((c.contentRows, c.firstVisible, c.lastVisible), (0, -1, -1));
    expect(c.isFollowing, isTrue);
    expect(probe.live, isEmpty);
    lines.value = numbered(3);
    await tester.pump();
    expect(tester.screen.lines.take(3), ['item 0', 'item 1', 'item 2']);
  });

  testWidgets('views of 0 and 1 rows; 0 rows still measures', (tester) async {
    final probe = Probe();
    final c = ScrollController(follow: Follow.bottom);
    final room = ValueNotifier(0);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: room,
        builder: (context) => Column(
          children: [
            SizedBox(
              height: room.value,
              child: list(ValueNotifier(['a', 'b\nc', 'd']), c, probe),
            ),
            Text('below'),
          ],
        ),
      ),
    );
    expect(tester.screen.lines.first, 'below');
    expect((c.contentRows, c.viewRows), (4, 0));
    expect(probe.live, isEmpty);
    room.value = 1;
    await tester.pump();
    expect(tester.screen.lines.take(2), ['d', 'below']);
    expect(c.viewRows, 1);
    expect(probe.live, {2});
  });

  testWidgets('a width of 0 measures nothing and reports 0 rows', (
    tester,
  ) async {
    final probe = Probe();
    final c = ScrollController();
    await tester.pumpWidget(
      Row(
        children: [
          SizedBox(width: 0, child: list(ValueNotifier(['a', 'b']), c, probe)),
          Text('x'),
        ],
      ),
    );
    expect(c.contentRows, 0);
    expect(probe.totalBuilds, 0);
  });

  testWidgets('unbounded height throws, naming the fix', (tester) async {
    await expectLater(
      tester.pumpWidget(
        Column(
          children: [
            ListView.builder(itemCount: 1, itemBuilder: (c, i) => Text('x')),
          ],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('unbounded height'), contains('Expanded')),
        ),
      ),
    );
  });

  testWidgets('unbounded width throws, naming the fix', (tester) async {
    await expectLater(
      tester.pumpWidget(
        Row(
          children: [
            ListView.builder(itemCount: 1, itemBuilder: (c, i) => Text('x')),
          ],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('unbounded width'), contains('SizedBox')),
        ),
      ),
    );
  });

  testWidgets('streaming into the last item re-measures only that item', (
    tester,
  ) async {
    final probe = Probe();
    final lines = ValueNotifier(numbered(1000));
    final c = ScrollController(follow: Follow.bottom);
    await tester.pumpWidget(list(lines, c, probe), size: const Size(80, 10));
    for (var chunk = 0; chunk < 10; chunk++) {
      probe.builds.clear();
      final next = List.of(lines.value);
      next[999] = '${next[999]} more';
      lines.value = next;
      await tester.pump();
      // Items in sight rebuild with the list; nothing out of sight builds.
      expect(probe.builds.keys.every((i) => i >= 990), isTrue);
      expect(probe.totalBuilds, lessThanOrEqualTo(10));
    }
    expect(tester.screen.lines.last, startsWith('item 999 more more'));
  });

  testWidgets('a steady frame builds at most the items in sight plus the '
      'changed ones', (tester) async {
    final probe = Probe();
    final lines = ValueNotifier(numbered(500));
    final c = ScrollController();
    await tester.pumpWidget(list(lines, c, probe), size: const Size(80, 10));
    probe.builds.clear();
    final next = List.of(lines.value);
    next[300] = 'changed 300';
    next[400] = 'changed 400';
    lines.value = next;
    await tester.pump();
    expect(probe.totalBuilds, lessThanOrEqualTo(10 + 2));
    expect(probe.builds.keys.toSet(), {
      ...List.generate(10, (i) => i),
      300,
      400,
    });
  });

  testWidgets('without itemVersion a rebuild measures every item again', (
    tester,
  ) async {
    final probe = Probe();
    final lines = ValueNotifier(numbered(50));
    await tester.pumpWidget(
      list(lines, null, probe, versioned: false),
      size: const Size(80, 10),
    );
    probe.builds.clear();
    lines.value = List.of(lines.value);
    await tester.pump();
    expect(probe.builds.length, 50);
  });

  testWidgets('a Follow.none list that grows past its room does not move', (
    tester,
  ) async {
    final probe = Probe();
    final lines = ValueNotifier(numbered(2));
    final c = ScrollController();
    await tester.pumpWidget(list(lines, c, probe), size: const Size(80, 10));
    lines.value = numbered(50);
    await tester.pump();
    expect(tester.screen.lines.first, 'item 0');
    expect(c.rowsBelow, 40);
  });

  testWidgets('an owned controller, and a swapped one', (tester) async {
    final probe = Probe();
    final lines = ValueNotifier(numbered(50));
    final which = ValueNotifier<ScrollController?>(null);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: which,
        builder: (context) => list(lines, which.value, probe),
      ),
      size: const Size(80, 10),
    );
    expect(tester.screen.lines.first, 'item 0');
    final a = ScrollController(initialOffset: 20);
    which.value = a;
    await tester.pump();
    expect(tester.screen.lines.first, 'item 20');
    final b = ScrollController(follow: Follow.bottom);
    which.value = b;
    await tester.pump();
    expect(tester.screen.lines.last, 'item 49');
    // a was let go of: another list may take it.
    await tester.pumpWidget(list(lines, a, probe), size: const Size(80, 10));
    expect(tester.screen.lines.first, 'item 20');
  });

  testWidgets('a Focus that asks for focus inside an item asserts', (
    tester,
  ) async {
    await expectLater(
      tester.pumpWidget(
        ListView.builder(
          itemCount: 1,
          itemBuilder: (context, i) => Focus(child: Text('x')),
        ),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('an item updated to hold a Focus asserts', (tester) async {
    final focusable = ValueNotifier(false);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: focusable,
        builder: (context) => ListView.builder(
          itemCount: 3,
          itemBuilder: (context, i) =>
              focusable.value ? Focus(child: Text('x')) : Text('x'),
        ),
      ),
    );
    focusable.value = true;
    await expectLater(tester.pump(), throwsA(isA<AssertionError>()));
  });

  testWidgets('a Focus added by a rebuild inside an item asserts', (
    tester,
  ) async {
    final focusable = ValueNotifier(false);
    await tester.pumpWidget(
      ListView.builder(
        itemCount: 3,
        itemBuilder: (context, i) => ListenableBuilder(
          listenable: focusable,
          builder: (context) =>
              focusable.value ? Focus(child: Text('x')) : Text('x'),
        ),
      ),
    );
    focusable.value = true;
    await expectLater(tester.pump(), throwsA(isA<AssertionError>()));
  });

  testWidgets('items built from inherited data rebuild when it changes', (
    tester,
  ) async {
    final label = ValueNotifier('one');
    final c = ScrollController();
    final view = ListView.builder(
      controller: c,
      itemCount: 3,
      itemBuilder: (context, i) => Text(
        '${context.dependOnInheritedWidgetOfExactType<Label>()!.text} $i',
      ),
    );
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: label,
        builder: (context) => Label(label.value, child: view),
      ),
    );
    expect(tester.screen.lines.take(3), ['one 0', 'one 1', 'one 2']);
    label.value = 'two\nrows';
    await tester.pump();
    expect(tester.screen.lines.take(4), ['two', 'rows 0', 'two', 'rows 1']);
    expect(c.contentRows, 6);
  });
  group('tester: list retention and lifecycle edges', () {
    for (final size in sizes) {
      testWidgets('zero-height items between visible rows survive at $size', (
        tester,
      ) async {
        final c = ScrollController();
        final probe = TesterListProbe();
        await tester.pumpWidget(
          ListView.builder(
            controller: c,
            itemCount: 2 * size.height + 10,
            itemVersion: (i) => i,
            itemBuilder: (context, i) =>
                TesterListItem(i, i.isEven ? 0 : 1, probe),
          ),
          size: size,
        );
        expect(c.contentRows, size.height + 5);
        expect(tester.screen.lines.first, 'row 1');
        expect(tester.screen.lines.last, 'row ${2 * size.height - 1}');
        expect(probe.live.keys.toSet(), {
          for (var i = 1; i < 2 * size.height; i++) i,
        });
        c.jumpTo(3);
        await tester.pump();
        expect(tester.screen.lines.first, 'row 7');
        expect(c.firstVisible, 7);
        expect(c.itemRows(8), 0);
        expect(c.itemTop(8), 4);
      });

      testWidgets(
        'retained state survives parent rebuild and version invalidation at $size',
        (tester) async {
          final c = ScrollController();
          final generation = ValueNotifier(0);
          final probe = TesterListProbe();
          await tester.pumpWidget(
            ListenableBuilder(
              listenable: generation,
              builder: (context) => ListView.builder(
                controller: c,
                itemCount: 200,
                itemVersion: (i) => generation.value,
                itemBuilder: (context, i) => TesterListItem(i, 1, probe),
              ),
            ),
            size: size,
          );
          c.jumpTo(50);
          await tester.pump();
          final before = Map.of(probe.live);
          generation.value++;
          await tester.pump();
          expect(c.offset, 50);
          for (final entry in before.entries) {
            expect(probe.live[entry.key], same(entry.value));
          }
          expect(probe.live.length, size.height);
          await tester.pumpWidget(Text('removed'), size: size);
          expect(probe.live, isEmpty);
        },
      );

      testWidgets('a folded anchor clamps its within-item row at $size', (
        tester,
      ) async {
        final lines = ValueNotifier([
          'before',
          [for (var i = 0; i < 8; i++) 'anchor $i'].join('\n'),
          ...numbered(100),
        ]);
        final c = ScrollController();
        await tester.pumpWidget(list(lines, c, Probe()), size: size);
        c.jumpTo(7);
        await tester.pump();
        expect(tester.screen.lines.first, 'anchor 6');
        lines.value = ['before\nextra', 'folded', ...numbered(100)];
        await tester.pump();
        expect(tester.screen.lines.first, 'folded');
        expect(c.offset, 2);
        expect(c.firstVisible, 1);
        expect(c.isFollowing, isFalse);
      });

      testWidgets('ANSI and graphemes clip through a tall item at $size', (
        tester,
      ) async {
        final c = ScrollController();
        final text = '\x1b[31m界é🙂${'x' * (size.width - 6)}界\x1b[0m';
        await tester.pumpWidget(
          ListView.builder(
            controller: c,
            itemCount: 1,
            itemBuilder: (context, i) => Text.ansi(
              [for (var row = 0; row < size.height + 4; row++) text].join('\n'),
              softWrap: false,
            ),
          ),
          size: size,
        );
        c.jumpTo(2);
        await tester.pump();
        for (var y = 0; y < size.height; y++) {
          expect(tester.screen.charAt(0, y), '界');
          expect(tester.screen.charAt(1, y), '');
          expect(tester.screen.charAt(2, y), 'é');
          expect(tester.screen.charAt(3, y), '🙂');
          expect(tester.screen.charAt(4, y), '');
          expect(tester.screen.charAt(size.width - 1, y), ' ');
        }
        expect(tester.screen.text.contains('\x1b'), isFalse);
      });
    }

    testWidgets(
      'all zero-height items leave no mounted states or visible items',
      (tester) async {
        final probe = TesterListProbe();
        final c = ScrollController(follow: Follow.bottom);
        await tester.pumpWidget(
          ListView.builder(
            controller: c,
            itemCount: 50,
            itemBuilder: (context, i) => TesterListItem(i, 0, probe),
          ),
        );
        expect(c.contentRows, 0);
        expect((c.firstVisible, c.lastVisible), (-1, -1));
        expect(tester.screen.text, '');
        expect(probe.live, isEmpty);
      },
    );

    testWidgets(
      'measurement, scrolling and removal cancel item timers and subscriptions',
      (tester) async {
        final probe = TesterListProbe();
        final c = ScrollController();
        await tester.pumpWidget(
          ListView.builder(
            controller: c,
            itemCount: 100,
            itemVersion: (i) => i,
            itemBuilder: (context, i) =>
                TesterListItem(i, 1, probe, listen: true),
          ),
          size: const Size(80, 24),
        );
        expect(probe.live.length, 24);
        expect(probe.timers.where((t) => t.isActive).length, 24);
        for (var event = 0; event < 1000; event++) {
          probe.stream.add(event);
        }
        await tester.pump();
        c.toBottom();
        await tester.pump();
        expect(probe.live.length, 24);
        expect(probe.timers.where((t) => t.isActive).length, 24);
        await tester.pumpWidget(Text('gone'));
        expect(probe.live, isEmpty);
        expect(probe.timers.every((t) => !t.isActive), isTrue);
        expect(probe.stream.hasListener, isFalse);
        probe.stream.add(1001);
        await tester.pump();
        expect(tester.screen.text, 'gone');
        await probe.stream.close();
      },
    );
  });
}

/// Data an item builder depends on.
class Label extends InheritedWidget {
  const Label(this.text, {super.key, required super.child});

  final String text;

  @override
  bool updateShouldNotify(Label oldWidget) => text != oldWidget.text;
}

/// Tester-owned state identities and cancellable resources.
class TesterListProbe {
  final live = <int, State<TesterListItem>>{};
  final timers = <Timer>[];
  final stream = StreamController<int>.broadcast(sync: true);
}

class TesterListItem extends StatefulWidget {
  const TesterListItem(
    this.index,
    this.rows,
    this.probe, {
    this.listen = false,
  });
  final int index;
  final int rows;
  final TesterListProbe probe;
  final bool listen;

  @override
  State<TesterListItem> createState() => _TesterListItemState();
}

class _TesterListItemState extends State<TesterListItem> {
  Timer? timer;
  StreamSubscription<int>? subscription;

  @override
  void initState() {
    super.initState();
    widget.probe.live[widget.index] = this;
    if (widget.listen) {
      timer = Timer.periodic(const Duration(days: 1), (_) => setState(() {}));
      widget.probe.timers.add(timer!);
      subscription = widget.probe.stream.stream.listen((_) => setState(() {}));
    }
  }

  @override
  Widget build(BuildContext context) => widget.rows == 0
      ? const SizedBox(height: 0)
      : Text('row ${widget.index}');

  @override
  void dispose() {
    timer?.cancel();
    subscription?.cancel();
    widget.probe.live.remove(widget.index);
    super.dispose();
  }
}
