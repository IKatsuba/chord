import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// Counts its builds and its states.
class Page extends StatefulWidget {
  const Page({super.key});

  static var builds = 0;
  static var states = 0;

  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  @override
  void initState() {
    super.initState();
    Page.states++;
  }

  @override
  Widget build(BuildContext context) {
    Page.builds++;
    return Text('page ' * 40);
  }
}

class Label extends InheritedWidget {
  const Label(this.text, {super.key, required super.child});

  final String text;

  @override
  bool updateShouldNotify(Label oldWidget) => text != oldWidget.text;
}

/// An entry showing [text] at row [row].
OverlayEntry layer(String text, {int row = 0}) => OverlayEntry(
  builder: (context) => Stack(
    children: [Positioned(left: 0, top: row, child: Text(text))],
  ),
);

/// The overlay of the tree [t] drew.
OverlayState overlayOf(WidgetTester t) {
  OverlayState? found;
  void walk(Element e) {
    if (e is StatefulElement && e.state is OverlayState) {
      found = e.state as OverlayState;
    }
    e.visitChildren(walk);
  }

  walk(t.host.rootElement);
  return found!;
}

void main() {
  testerEdges();
  setUp(() {
    Page.builds = 0;
    Page.states = 0;
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('layers paint over the page, in order, at $size', (t) async {
      final page = OverlayEntry(builder: (_) => const Page());
      await t.pumpWidget(Overlay(initialEntries: [page]), size: size);
      expect(t.screen.lines.first, startsWith('page page'));
      final overlay = overlayOf(t);
      final a = layer('AAAAAA', row: size.height - 1);
      final b = layer('BBB', row: size.height - 1);
      overlay.insert(a);
      overlay.insert(b);
      await t.pump();
      expect(t.screen.lines.first, startsWith('page page'));
      expect(t.screen.lines.last, 'BBBAAA');
      a.remove();
      await t.pump();
      expect(t.screen.lines.last, 'BBB');
    });
  }

  testWidgets('below and above place an entry among the others', (t) async {
    await t.pumpWidget(Overlay(initialEntries: [layer('base')]));
    final overlay = overlayOf(t);
    final top = layer('T');
    overlay.insert(top);
    overlay.insert(layer('XY'), below: top);
    await t.pump();
    expect(t.screen.lines.first, 'TYse');
    overlay.insert(layer('UVW'), above: top);
    await t.pump();
    expect(t.screen.lines.first, 'UVWe');
    expect(
      () => overlay.insert(layer('z'), below: top, above: top),
      throwsArgumentError,
    );
    expect(
      () => overlay.insert(layer('z'), below: layer('elsewhere')),
      throwsArgumentError,
    );
  });

  testWidgets('the page is neither rebuilt nor remade as layers change', (
    t,
  ) async {
    await t.pumpWidget(
      Overlay(initialEntries: [OverlayEntry(builder: (_) => const Page())]),
    );
    expect((Page.builds, Page.states), (1, 1));
    final overlay = overlayOf(t);
    final a = layer('a');
    overlay.insert(a);
    await t.pump();
    final b = layer('b');
    overlay.insert(b, below: a);
    await t.pump();
    a.remove();
    b.remove();
    await t.pump();
    expect((Page.builds, Page.states), (1, 1));
    await t.resize(const Size(120, 40));
    expect((Page.builds, Page.states), (1, 1));
  });

  testWidgets('an entry keeps its state and rebuilds on markNeedsBuild', (
    t,
  ) async {
    var n = 0;
    final entry = OverlayEntry(builder: (_) => Text('n ${++n}'));
    expect(entry.mounted, isFalse);
    await t.pumpWidget(Overlay(initialEntries: [entry]));
    expect(entry.mounted, isTrue);
    expect(t.screen.lines.first, 'n 1');
    overlayOf(t).insert(layer('', row: 3));
    await t.pump();
    expect(t.screen.lines.first, 'n 1');
    entry.markNeedsBuild();
    await t.pump();
    expect(t.screen.lines.first, 'n 2');
  });

  testWidgets('entries inherit at the overlay, not at the caller', (t) async {
    late BuildContext caller;
    await t.pumpWidget(
      Label(
        'outer',
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => Label(
                'inner',
                child: Builder(
                  builder: (context) {
                    caller = context;
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final overlay = Overlay.of(caller);
    expect(overlay, same(overlayOf(t)));
    overlay.insert(
      OverlayEntry(
        builder: (context) =>
            Text(context.dependOnInheritedWidgetOfExactType<Label>()!.text),
      ),
    );
    await t.pump();
    expect(t.screen.lines.first, 'outer');
  });

  testWidgets('Overlay.of needs an overlay, maybeOf does not', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    expect(Overlay.maybeOf(context), isNull);
    expect(() => Overlay.of(context), throwsStateError);
  });

  testWidgets('an entry is in one overlay, and dead once disposed', (t) async {
    await t.pumpWidget(Overlay(initialEntries: [layer('base')]));
    final overlay = overlayOf(t);
    final entry = layer('e');
    overlay.insert(entry);
    expect(() => overlay.insert(entry), throwsStateError);
    await t.pump();
    expect(() => entry.dispose(), throwsA(isA<AssertionError>()));
    entry.remove();
    entry.remove();
    await t.pump();
    expect(entry.mounted, isFalse);
    expect(t.screen.lines.first, 'base');
    entry.dispose();
    expect(() => overlay.insert(entry), throwsStateError);
  });

  testWidgets('removing the overlay unmounts its entries and frees them', (
    t,
  ) async {
    final show = ValueNotifier(true);
    final base = layer('base');
    await t.pumpWidget(
      ListenableBuilder(
        listenable: show,
        builder: (_) =>
            show.value ? Overlay(initialEntries: [base]) : Text('gone'),
      ),
    );
    final floating = layer('f', row: 1);
    overlayOf(t).insert(floating);
    await t.pump();
    expect(floating.mounted, isTrue);
    show.value = false;
    await t.pump();
    expect(t.screen.lines.first, 'gone');
    expect((base.mounted, floating.mounted), (false, false));
    floating.remove();
    floating.dispose();
    base.dispose();
  });

  testWidgets('a new initialEntries list does not replace the entries', (
    t,
  ) async {
    final which = ValueNotifier('first');
    await t.pumpWidget(
      ListenableBuilder(
        listenable: which,
        builder: (_) => Overlay(initialEntries: [layer(which.value)]),
      ),
    );
    which.value = 'second';
    await t.pump();
    expect(t.screen.lines.first, 'first');
  });

  testWidgets('every layer is laid out at the overlay size', (t) async {
    await t.pumpWidget(
      Column(
        children: [
          Text('above'),
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 5,
              width: 30,
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => LayoutBuilder(
                      builder: (_, c) => Text('${c.minWidth}x${c.minHeight}'),
                    ),
                  ),
                  OverlayEntry(
                    builder: (_) => Align(
                      alignment: Alignment.bottomRight,
                      child: Text('corner'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text('below'),
        ],
      ),
    );
    expect(t.screen.lines.take(7), [
      'above',
      '30x5',
      '',
      '',
      '',
      '${' ' * 24}corner',
      'below',
    ]);
  });

  testWidgets('an overlay with no cells suspends its floating entries', (
    t,
  ) async {
    final page = FocusNode(debugLabel: 'page');
    final layer = FocusNode(debugLabel: 'layer');
    await t.pumpWidget(
      Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) =>
                Focus(focusNode: page, autofocus: true, child: Text('p')),
          ),
        ],
      ),
    );
    overlayOf(t).insert(
      OverlayEntry(
        builder: (_) =>
            Focus(focusNode: layer, autofocus: true, child: Text('l')),
      ),
    );
    await t.pump();
    expect(t.focusManager.primaryFocus, layer);
    await t.resize(Size.zero);
    expect(t.focusManager.primaryFocus, page);
    await t.resize(const Size(80, 24));
    expect(t.focusManager.primaryFocus, layer);
    page.dispose();
    layer.dispose();
  });
}

void testerEdges() {
  group('tester: Overlay entry invalidation and ownership', () {
    testWidgets(
      'removing a streaming entry cancels its timer and subscription',
      (t) async {
        final stream = StreamController<int>.broadcast(sync: true);
        addTearDown(stream.close);
        final probe = _TesterEntryResources(stream);
        final entry = OverlayEntry(builder: (_) => _TesterLiveEntry(probe));
        await t.pumpWidget(Overlay(initialEntries: [layer('base'), entry]));
        expect(stream.hasListener, isTrue);
        expect(probe.timer!.isActive, isTrue);
        stream.add(1);
        entry.remove();
        await t.pump();
        expect(stream.hasListener, isFalse);
        expect(probe.timer!.isActive, isFalse);
        stream.add(2);
        await t.pump();
        expect(t.screen.lines.first, 'base');
        entry.dispose();
      },
    );

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a thousand invalidations build once at $size', (t) async {
        var value = 0, builds = 0;
        final base = OverlayEntry(builder: (_) => const Page());
        final floating = OverlayEntry(
          builder: (_) {
            builds++;
            return Align(
              alignment: Alignment.bottomRight,
              child: Text('$value'),
            );
          },
        );
        await t.pumpWidget(
          Overlay(initialEntries: [base, floating]),
          size: size,
        );
        for (var i = 1; i <= 1000; i++) {
          value = i;
          floating.markNeedsBuild();
        }
        expect(builds, 1);
        await t.pump();
        expect(builds, 2);
        expect(t.screen.lines.last, endsWith('1000'));
        expect(Page.builds, 1);
        floating.remove();
        floating.markNeedsBuild();
        await t.pump();
        expect(floating.mounted, isFalse);
        floating.dispose();
        floating.markNeedsBuild();
        await t.pump();
        expect(builds, 2);
      });
      testWidgets('empty overlay accepts remove and reinsert at $size', (
        t,
      ) async {
        await t.pumpWidget(const Overlay(), size: size);
        final state = overlayOf(t);
        final entry = OverlayEntry(builder: (_) => Text('界🙂e\u0301'));
        state.insert(entry);
        await t.pump();
        expect(t.screen.lines.first, '界🙂e\u0301');
        entry.remove();
        await t.pump();
        expect(t.screen.text, isEmpty);
        state.insert(entry);
        await t.pump();
        expect(entry.mounted, isTrue);
        expect(t.screen.lines.first, '界🙂e\u0301');
      });
    }
    testWidgets('unbounded parent is rejected before allocation', (t) async {
      await expectLater(
        t.pumpWidget(Column(children: [const Overlay()])),
        throwsA(isA<AssertionError>()),
      );
    });
    testWidgets('inherited change updates an existing entry', (t) async {
      final word = ValueNotifier('before');
      addTearDown(word.dispose);
      final entry = OverlayEntry(
        builder: (context) =>
            Text(context.dependOnInheritedWidgetOfExactType<Label>()!.text),
      );
      final overlay = Overlay(initialEntries: [entry]);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: word,
          builder: (_) => Label(word.value, child: overlay),
        ),
      );
      word.value = 'after';
      await t.pump();
      expect(t.screen.lines.first, 'after');
      expect(entry.mounted, isTrue);
    });
  });
}

class _TesterEntryResources {
  _TesterEntryResources(this.stream);
  final StreamController<int> stream;
  Timer? timer;
}

class _TesterLiveEntry extends StatefulWidget {
  const _TesterLiveEntry(this.probe);
  final _TesterEntryResources probe;
  @override
  State<_TesterLiveEntry> createState() => _TesterLiveEntryState();
}

class _TesterLiveEntryState extends State<_TesterLiveEntry> {
  late final StreamSubscription<int> subscription;
  @override
  void initState() {
    super.initState();
    subscription = widget.probe.stream.stream.listen((_) => setState(() {}));
    widget.probe.timer = Timer.periodic(
      const Duration(days: 1),
      (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) => Text('streaming');
  @override
  void dispose() {
    subscription.cancel();
    widget.probe.timer!.cancel();
    super.dispose();
  }
}
