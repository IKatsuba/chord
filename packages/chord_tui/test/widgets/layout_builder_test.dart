import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// Counts the builds of a [LayoutBuilder] and shows the width it got.
class Probe {
  var builds = 0;
  BoxConstraints? last;

  Widget call(BuildContext context, BoxConstraints c) {
    builds++;
    last = c;
    return Text('width ${c.maxWidth} height ${c.maxHeight}');
  }
}

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => CounterState();
}

class CounterState extends State<Counter> {
  var count = 0;

  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('count $count');
}

class Label extends InheritedWidget {
  const Label(this.text, {super.key, required super.child});

  final String text;

  @override
  bool updateShouldNotify(Label oldWidget) => text != oldWidget.text;
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('shows the width it is given at $size', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(LayoutBuilder(builder: probe.call), size: size);
      expect(
        tester.screen.lines.first,
        'width ${size.width} height ${size.height}',
      );
      expect(probe.last, BoxConstraints.tight(size));
    });
  }

  testWidgets('builds with the constraints its parent passes', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(
      Row(
        children: [
          SizedBox(width: 30, child: Text('left')),
          Expanded(child: LayoutBuilder(builder: probe.call)),
        ],
      ),
      size: const Size(120, 40),
    );
    expect(tester.screen, shows('left'));
    expect(tester.screen.lines.first.substring(30), 'width 90 height 40');
  });

  testWidgets('rebuilds when the window is resized', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(
      LayoutBuilder(builder: probe.call),
      size: const Size(120, 40),
    );
    expect(probe.builds, 1);
    await tester.resize(const Size(80, 24));
    expect(probe.builds, 2);
    expect(tester.screen.lines.first, 'width 80 height 24');
  });

  testWidgets('does not rebuild while the constraints stay', (tester) async {
    final probe = Probe();
    final tick = ValueNotifier(0);
    await tester.pumpWidget(
      Column(
        children: [
          ListenableBuilder(
            listenable: tick,
            builder: (_) => Text('tick ${tick.value}'),
          ),
          Expanded(child: LayoutBuilder(builder: probe.call)),
        ],
      ),
    );
    expect(probe.builds, 1);
    tick.value++;
    await tester.pump();
    await tester.pump();
    expect(tester.screen, shows('tick 1'));
    expect(probe.builds, 1);
    expect(tester.screen, shows('width 80 height 23'));
  });

  testWidgets('rebuilds when the widget is replaced', (tester) async {
    final word = ValueNotifier('one');
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: word,
        builder: (_) => LayoutBuilder(
          builder: (context, c) => Text('${word.value} ${c.maxWidth}'),
        ),
      ),
    );
    expect(tester.screen.lines.first, 'one 80');
    word.value = 'two';
    await tester.pump();
    expect(tester.screen.lines.first, 'two 80');
  });

  testWidgets('keeps the state below it across rebuilds', (tester) async {
    final key = ValueKey('counter');
    await tester.pumpWidget(
      LayoutBuilder(
        builder: (context, c) => Column(
          children: [
            Text('width ${c.maxWidth}'),
            Counter(key: key),
          ],
        ),
      ),
      size: const Size(120, 40),
    );
    final element = findState(tester.host.rootElement)!;
    element.bump();
    element.bump();
    await tester.pump();
    expect(tester.screen, shows('count 2'));
    await tester.resize(const Size(80, 24));
    expect(tester.screen, shows('width 80'));
    expect(tester.screen, shows('count 2'));
    expect(findState(tester.host.rootElement), same(element));
  });

  testWidgets('looks up inherited widgets and follows them', (tester) async {
    final text = ValueNotifier('first');
    var builds = 0;
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: text,
        builder: (_) => Label(text.value, child: const _Const()),
      ),
    );
    builds = _Const.builds;
    expect(tester.screen.lines.first, 'first 80');
    text.value = 'second';
    await tester.pump();
    expect(tester.screen.lines.first, 'second 80');
    expect(_Const.builds, builds + 1);
  });

  testWidgets('shows an error in place of a builder that throws', (
    tester,
  ) async {
    await tester.pumpWidget(
      LayoutBuilder(builder: (context, c) => throw StateError('no room')),
    );
    expect(tester.screen, shows('no room'));
  });

  testWidgets('works as an item of a list', (tester) async {
    await tester.pumpWidget(
      ListView.builder(
        itemCount: 3,
        itemBuilder: (context, i) =>
            LayoutBuilder(builder: (context, c) => Text('$i at ${c.maxWidth}')),
      ),
      size: const Size(80, 24),
    );
    expect(tester.screen.lines.take(3), ['0 at 80', '1 at 80', '2 at 80']);
  });

  group('tester: LayoutBuilder boundaries and lifecycle', () {
    testWidgets('zero and one cell recover at both window sizes', (t) async {
      final probe = Probe();
      await t.pumpWidget(LayoutBuilder(builder: probe.call));
      for (final size in const [
        Size(0, 0),
        Size(1, 1),
        Size(120, 40),
        Size(80, 24),
      ]) {
        await t.resize(size);
        expect(probe.last, BoxConstraints.tight(size));
        expect(t.screen.buffer.width, size.width);
        expect(t.screen.buffer.height, size.height);
      }
      expect(t.screen, shows('width 80 height 24'));
    });

    testWidgets('unbounded axes reach nested builders unchanged', (t) async {
      BoxConstraints? horizontal;
      BoxConstraints? vertical;
      await t.pumpWidget(
        Row(
          children: [
            LayoutBuilder(
              builder: (_, c) {
                horizontal = c;
                return Column(
                  children: [
                    LayoutBuilder(
                      builder: (_, c) {
                        vertical = c;
                        return Text('unbounded');
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );
      expect(horizontal!.maxWidth, unbounded);
      expect(horizontal!.maxHeight, 24);
      expect(vertical!.maxWidth, unbounded);
      expect(vertical!.maxHeight, unbounded);
      expect(t.screen, shows('unbounded'));
    });

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('graphemes and escapes at each edge at $size', (t) async {
        await t.pumpWidget(
          LayoutBuilder(
            builder: (_, c) => Column(
              children: [
                Text('界🙂e\u0301\x1b[31mR\x1b[0m'),
                const Spacer(),
                Row(children: [const Spacer(), Text('e\u0301🙂界')]),
              ],
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.first, '界🙂e\u0301R');
        expect(t.screen.charAt(0, 0), '界');
        expect(t.screen.charAt(size.width - 2, size.height - 1), '界');
        expect(t.screen.lines.last, endsWith('e\u0301🙂界'));
        await t.resize(const Size(1, 1));
        await t.resize(size);
        expect(t.screen.lines.first, '界🙂e\u0301R');
        expect(t.screen.lines.last, endsWith('e\u0301🙂界'));
      });

      testWidgets('coalesces a thousand updates at $size', (t) async {
        final value = ValueNotifier(0);
        addTearDown(value.dispose);
        var builds = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: value,
            builder: (_) => LayoutBuilder(
              builder: (_, c) {
                builds++;
                return Text('${value.value} at ${c.maxWidth}');
              },
            ),
          ),
          size: size,
        );
        for (var i = 1; i <= 1000; i++) {
          value.value = i;
        }
        expect(builds, 1);
        await t.pump();
        expect(builds, 2);
        expect(t.screen, shows('1000 at ${size.width}'));
      });

      testWidgets('focus survives resize away and back at $size', (t) async {
        final first = FocusNode();
        final other = FocusNode();
        addTearDown(first.dispose);
        addTearDown(other.dispose);
        final editing = TextEditingController();
        addTearDown(editing.dispose);
        await t.pumpWidget(
          Column(
            children: [
              LayoutBuilder(
                builder: (_, c) => TextInput(
                  focusNode: first,
                  autofocus: true,
                  controller: editing,
                ),
              ),
              Focus(focusNode: other, child: Text('other')),
            ],
          ),
          size: size,
        );
        await t.paste('界🙂e\u0301');
        other.requestFocus();
        await t.resize(const Size(1, 1));
        await t.resize(size);
        expect(other.hasPrimaryFocus, isTrue);
        first.requestFocus();
        await t.press('left');
        await t.press('right');
        await t.paste('!');
        expect(editing.text, '界🙂e\u0301!');
        expect(first.hasPrimaryFocus, isTrue);
      });
    }

    testWidgets('unmount cancels a live child stream and timer', (t) async {
      final show = ValueNotifier(true);
      final stream = StreamController<int>.broadcast(sync: true);
      final probe = _TesterLayoutResourceProbe(stream);
      addTearDown(show.dispose);
      addTearDown(stream.close);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: show,
          builder: (_) => LayoutBuilder(
            builder: (_, c) =>
                show.value ? _TesterLayoutResource(probe) : Text('removed'),
          ),
        ),
      );
      expect(stream.hasListener, isTrue);
      expect(probe.timer!.isActive, isTrue);
      stream.add(1);
      show.value = false;
      await t.pump();
      expect(stream.hasListener, isFalse);
      expect(probe.timer!.isActive, isFalse);
      expect(probe.disposed, isTrue);
      stream.add(2);
      await t.pump();
      expect(t.screen, shows('removed'));
    });
  });
}

/// A [LayoutBuilder] whose builder depends on [Label], under a const
/// widget, so only the dependency can rebuild it.
class _Const extends StatelessWidget {
  const _Const();

  static var builds = 0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      builds++;
      final label = context.dependOnInheritedWidgetOfExactType<Label>()!;
      return Text('${label.text} ${c.maxWidth}');
    },
  );
}

CounterState? findState(Element root) {
  CounterState? found;
  void walk(Element e) {
    if (e is StatefulElement && e.state is CounterState) {
      found = e.state as CounterState;
    }
    e.visitChildren(walk);
  }

  walk(root);
  return found;
}

class _TesterLayoutResourceProbe {
  _TesterLayoutResourceProbe(this.stream);
  final StreamController<int> stream;
  Timer? timer;
  var disposed = false;
}

class _TesterLayoutResource extends StatefulWidget {
  const _TesterLayoutResource(this.probe);
  final _TesterLayoutResourceProbe probe;
  @override
  State<_TesterLayoutResource> createState() => _TesterLayoutResourceState();
}

class _TesterLayoutResourceState extends State<_TesterLayoutResource> {
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
  Widget build(BuildContext context) => Text('live');
  @override
  void dispose() {
    subscription.cancel();
    widget.probe.timer!.cancel();
    widget.probe.disposed = true;
    super.dispose();
  }
}
