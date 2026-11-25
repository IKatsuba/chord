import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A box of [char] that wants [width] by [height] cells.
class Patch extends LeafRenderObjectWidget {
  const Patch(this.char, {this.width = 0, this.height = 0, this.style});

  final String char;
  final int width;
  final int height;
  final Style? style;

  @override
  RenderBox createRenderObject(BuildContext context) => RenderPatch(this);

  @override
  void updateRenderObject(BuildContext context, RenderPatch r) => r.w = this;
}

class RenderPatch extends RenderBox {
  RenderPatch(this.w);

  Patch w;

  @override
  void performLayout() => size = constraints.constrain(Size(w.width, w.height));

  @override
  void paint(Canvas canvas, Offset origin) => canvas.fill(
    Rect.fromOffsetSize(origin, size),
    w.style ?? Style.plain,
    w.char,
  );
}

/// The page: a patterned transcript, a zero-row target, then [below] rows
/// (prompt gap, prompt, status, hints by default). Counts its builds.
class Page extends StatelessWidget {
  const Page(this.link, {super.key, this.below = 4, this.target = true});

  final LayerLink link;
  final int below;
  final bool target;

  static var builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return Column(
      children: [
        Expanded(
          child: Patch(
            '#',
            width: 999,
            height: 999,
            style: const Style(fg: Colors.green, bg: Colors.blue),
          ),
        ),
        if (target)
          CompositedTransformTarget(
            link: link,
            child: const SizedBox(height: 0),
          ),
        for (var i = 0; i < below; i++) Text('row $i'),
      ],
    );
  }
}

/// A follower sitting on the target's top edge, as chord's pickers do.
OverlayEntry above(
  LayerLink link,
  Widget child, {
  Alignment targetAnchor = Alignment.topLeft,
  Alignment followerAnchor = Alignment.bottomLeft,
  Offset offset = Offset.zero,
  bool showWhenUnlinked = false,
}) => OverlayEntry(
  builder: (_) => CompositedTransformFollower(
    link: link,
    targetAnchor: targetAnchor,
    followerAnchor: followerAnchor,
    offset: offset,
    showWhenUnlinked: showWhenUnlinked,
    child: child,
  ),
);

/// Lays out and paints its first child, and its second only when [both];
/// it always visits both, as a closed fold keeps its body mounted.
class FirstOnly extends MultiChildRenderObjectWidget {
  const FirstOnly({required this.both, super.children});

  final bool both;

  @override
  RenderBox createRenderObject(BuildContext context) => RenderFirstOnly(both);

  @override
  void updateRenderObject(BuildContext context, RenderFirstOnly r) =>
      r.both = both;
}

class RenderFirstOnly extends RenderBox with RenderWithChildren {
  RenderFirstOnly(this.both);

  bool both;

  @override
  void performLayout() {
    size = constraints.biggest;
    for (final (i, c) in children.indexed) {
      if (i > 0 && !both) break;
      c.layout(constraints.loosen());
      c.offset = Offset(0, i * 3);
    }
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    for (final (i, c) in children.indexed) {
      if (i > 0 && !both) break;
      c.paint(canvas, origin + c.offset);
    }
  }
}

OverlayState overlayOf(WidgetTester t) {
  final states = <OverlayState>[];
  void walk(Element e) {
    if (e is StatefulElement && e.state is OverlayState) {
      states.add(e.state as OverlayState);
    }
    e.visitChildren(walk);
  }

  walk(t.host.rootElement);
  return states.first;
}

void main() {
  testerEdges();
  setUp(() => Page.builds = 0);

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final h = size.height, w = size.width, anchor = size.height - 4;

    testWidgets('a picker sits on the anchor in the same frame at $size', (
      t,
    ) async {
      final link = LayerLink();
      await t.pumpWidget(
        Overlay(initialEntries: [OverlayEntry(builder: (_) => Page(link))]),
        size: size,
      );
      overlayOf(t).insert(above(link, Patch('p', width: 20, height: 4)));
      await t.pump();
      final rows = t.screen.lines;
      expect(rows[anchor - 5], '#' * w);
      for (var y = anchor - 4; y < anchor; y++) {
        expect(rows[y], '${'p' * 20}${'#' * (w - 20)}');
      }
      expect(rows.sublist(anchor), ['row 0', 'row 1', 'row 2', 'row 3']);
      expect(Page.builds, 1);
    });

    testWidgets('a tall picker gets only the rows above at $size', (t) async {
      final link = LayerLink();
      BoxConstraints? room;
      await t.pumpWidget(
        Overlay(initialEntries: [OverlayEntry(builder: (_) => Page(link))]),
        size: size,
      );
      overlayOf(t).insert(
        above(
          link,
          LayoutBuilder(
            builder: (_, c) {
              room = c;
              return Patch('p', width: 999, height: 40);
            },
          ),
        ),
      );
      await t.pump();
      // The zero-row target takes the window's width from its column.
      expect(room, BoxConstraints(maxWidth: w, maxHeight: anchor));
      final rows = t.screen.lines;
      expect(rows.take(anchor), everyElement('p' * w));
      expect(rows[anchor], 'row 0');
      expect(rows[h - 1], 'row 3');
    });
  }

  testWidgets('the layer follows a moving target, unchanged and unbuilt', (
    t,
  ) async {
    final link = LayerLink();
    final below = ValueNotifier(4);
    var builds = 0;
    await t.pumpWidget(
      Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => ListenableBuilder(
              listenable: below,
              builder: (_) => Page(link, below: below.value),
            ),
          ),
        ],
      ),
    );
    final entry = above(
      link,
      LayoutBuilder(
        builder: (_, c) {
          builds++;
          return Patch('p', width: 3, height: 1);
        },
      ),
    );
    overlayOf(t).insert(entry);
    await t.pump();
    expect(t.screen.lines[19], startsWith('ppp#'));
    expect(builds, 1);
    await t.pump();
    expect(builds, 1, reason: 'the room did not change');
    below.value = 8;
    await t.pump();
    expect(t.screen.lines[15], startsWith('ppp#'));
    expect(t.screen.lines[19], 'row 3');
    expect(builds, 2, reason: 'the room shrank by four rows');
    await t.resize(const Size(120, 40));
    expect(t.screen.lines[31], startsWith('ppp#'));
  });

  testWidgets('a missing target hides the layer until it is laid out', (
    t,
  ) async {
    final link = LayerLink();
    final present = ValueNotifier(false);
    await t.pumpWidget(
      Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => ListenableBuilder(
              listenable: present,
              builder: (_) => Page(link, target: present.value),
            ),
          ),
        ],
      ),
    );
    final entry = above(link, Patch('p', width: 3, height: 1));
    overlayOf(t).insert(entry);
    await t.pump();
    expect(t.screen.text, isNot(contains('p')));
    present.value = true;
    await t.pump();
    expect(t.screen.lines[19], startsWith('ppp'));
    present.value = false;
    await t.pump();
    expect(t.screen.text, isNot(contains('ppp')));
  });

  testWidgets('a target scrolled out of a list is not linked', (t) async {
    final link = LayerLink();
    final scroll = ScrollController();
    await t.pumpWidget(
      Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => ListView.builder(
              controller: scroll,
              itemCount: 100,
              itemBuilder: (_, i) => i == 50
                  ? CompositedTransformTarget(
                      link: link,
                      child: Text('item $i'),
                    )
                  : Text('item $i'),
            ),
          ),
        ],
      ),
    );
    overlayOf(t).insert(
      above(
        link,
        Patch('p', width: 3, height: 1),
        followerAnchor: Alignment.topLeft,
        offset: const Offset(7, 0),
      ),
    );
    await t.pump();
    expect(t.screen.text, isNot(contains('ppp')));
    scroll.jumpTo(45);
    await t.pump();
    final row = t.screen.lines.indexWhere((l) => l.startsWith('item 50'));
    expect(row, greaterThanOrEqualTo(0));
    expect(t.screen.lines[row], 'item 50ppp');
  });

  testWidgets('a top anchor gets the rows below, a centre twice the less', (
    t,
  ) async {
    final link = LayerLink();
    final rooms = <BoxConstraints>[];
    Widget probe() => LayoutBuilder(
      builder: (_, c) {
        rooms.add(c);
        return const SizedBox();
      },
    );
    await t.pumpWidget(
      Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => Stack(
              children: [
                Positioned(
                  left: 10,
                  top: 5,
                  child: CompositedTransformTarget(
                    link: link,
                    child: Patch('t', width: 4, height: 2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final overlay = overlayOf(t);
    overlay.insert(
      above(
        link,
        probe(),
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
      ),
    );
    overlay.insert(
      above(
        link,
        probe(),
        targetAnchor: Alignment.center,
        followerAnchor: Alignment.center,
      ),
    );
    await t.pump();
    // Below the target's bottom (row 7) to row 24; right of column 10.
    expect(rooms[0], const BoxConstraints(maxWidth: 70, maxHeight: 17));
    // Centre (12, 6): 12 columns to the left, 6 rows above.
    expect(rooms[1], const BoxConstraints(maxWidth: 24, maxHeight: 12));
  });

  testWidgets('the layer blanks what it covers, and only that', (t) async {
    final link = LayerLink();
    await t.pumpWidget(
      Overlay(initialEntries: [OverlayEntry(builder: (_) => Page(link))]),
    );
    overlayOf(t).insert(
      above(
        link,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [Text('a  b'), Text('')],
        ),
      ),
    );
    await t.pump();
    expect(t.screen.lines[18], 'a  b${'#' * 76}');
    expect(t.screen.lines[19], ' ' * 4 + '#' * 76);
    for (final x in [1, 2]) {
      expect(t.screen.charAt(x, 18), ' ');
      expect(t.screen.styleAt(x, 18), Style.plain);
    }
    expect(t.screen.styleAt(0, 19), Style.plain);
    expect(t.screen.styleAt(4, 19).bg, Colors.blue);
    expect(t.screen.styleAt(0, 17).bg, Colors.blue);
  });

  testWidgets('a nested overlay keeps its targets to itself', (t) async {
    final link = LayerLink();
    final inner = OverlayEntry(
      builder: (_) => Column(
        children: [
          Text('inner page'),
          CompositedTransformTarget(link: link, child: Text('target')),
        ],
      ),
    );
    await t.pumpWidget(
      Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => Column(
              children: [
                Text('outer page'),
                Expanded(child: Overlay(initialEntries: [inner])),
              ],
            ),
          ),
        ],
      ),
    );
    final overlays = <OverlayState>[];
    void walk(Element e) {
      if (e is StatefulElement && e.state is OverlayState) {
        overlays.add(e.state as OverlayState);
      }
      e.visitChildren(walk);
    }

    walk(t.host.rootElement);
    final [outer, nested] = overlays;
    outer.insert(
      above(
        link,
        Text('OUT'),
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
      ),
    );
    nested.insert(
      above(
        link,
        Text('IN'),
        offset: const Offset(6, 0),
        followerAnchor: Alignment.topLeft,
      ),
    );
    await t.pump();
    expect(t.screen.text, isNot(contains('OUT')));
    // The nested overlay starts at row 1; its target is its row 1.
    expect(t.screen.lines.take(3), ['outer page', 'inner page', 'targetIN']);
  });

  testWidgets('two targets for one link in one overlay are an error', (
    t,
  ) async {
    final link = LayerLink();
    await expectLater(
      t.pumpWidget(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => Column(
                children: [
                  CompositedTransformTarget(link: link, child: Text('a')),
                  CompositedTransformTarget(link: link, child: Text('b')),
                ],
              ),
            ),
          ],
        ),
      ),
      throwsStateError,
    );
  });

  testWidgets('showWhenUnlinked puts the layer at the corner, moved', (
    t,
  ) async {
    final link = LayerLink();
    await t.pumpWidget(
      Overlay(
        initialEntries: [
          OverlayEntry(builder: (_) => Page(link, target: false)),
          above(
            link,
            Text('lost'),
            offset: const Offset(2, 1),
            showWhenUnlinked: true,
          ),
        ],
      ),
    );
    expect(t.screen.lines[1], '##lost${'#' * 74}');
  });

  testWidgets('a follower outside an overlay is an error', (t) async {
    await expectLater(
      t.pumpWidget(
        CompositedTransformFollower(link: LayerLink(), child: Text('x')),
      ),
      throwsStateError,
    );
  });

  testWidgets('a target its parent skipped this frame is not linked', (
    t,
  ) async {
    final link = LayerLink();
    final both = ValueNotifier(true);
    await t.pumpWidget(
      Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => ListenableBuilder(
              listenable: both,
              builder: (_) => FirstOnly(
                both: both.value,
                children: [
                  Text('first'),
                  CompositedTransformTarget(link: link, child: Text('body')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    overlayOf(
      t,
    ).insert(above(link, Text('PICK'), followerAnchor: Alignment.topLeft));
    await t.pump();
    expect(t.screen.lines[3], 'PICK');
    both.value = false;
    await t.pump();
    // The body keeps its render object and its old offset, but was not
    // laid out: the layer must not paint where it was.
    expect(t.screen.text, isNot(contains('PICK')));
    both.value = true;
    await t.pump();
    expect(t.screen.lines[3], 'PICK');
  });

  testWidgets('a follower moved inside its entry is an error', (t) async {
    final link = LayerLink();
    await t.pumpWidget(
      Overlay(initialEntries: [OverlayEntry(builder: (_) => Page(link))]),
    );
    overlayOf(t).insert(
      OverlayEntry(
        builder: (_) => Padding(
          padding: const EdgeInsets.only(top: 1),
          child: CompositedTransformFollower(link: link, child: Text('x')),
        ),
      ),
    );
    await expectLater(t.pump(), throwsStateError);
  });
}

void testerEdges() {
  group('tester: follower boundary and lifecycle regressions', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'zero room returns on resize without rebuilding base at $size',
        (t) async {
          final link = LayerLink();
          var layerBuilds = 0;
          final entry = OverlayEntry(
            builder: (_) {
              layerBuilds++;
              return CompositedTransformFollower(
                link: link,
                followerAnchor: Alignment.bottomLeft,
                child: Text('界🙂e\u0301\x1b[31mR\x1b[0m'),
              );
            },
          );
          await t.pumpWidget(
            Overlay(
              initialEntries: [
                OverlayEntry(builder: (_) => Page(link)),
                entry,
              ],
            ),
            size: size,
          );
          expect(t.screen.lines[size.height - 5], startsWith('界🙂e\u0301R'));
          for (final next in const [Size(0, 0), Size(1, 1)]) {
            await t.resize(next);
            expect(t.screen.buffer.size, next);
            expect(t.screen.text, isNot(contains('R')));
          }
          await t.resize(size);
          expect(t.screen.lines[size.height - 5], startsWith('界🙂e\u0301R'));
          expect(layerBuilds, 1);
          expect(Page.builds, 1);
        },
      );
      testWidgets(
        'virtualised target hides again after scrolling away at $size',
        (t) async {
          final link = LayerLink();
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await t.pumpWidget(
            Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => ListView.builder(
                    controller: scroll,
                    itemCount: 200,
                    itemBuilder: (_, i) => i == 100
                        ? CompositedTransformTarget(
                            link: link,
                            child: Text('target'),
                          )
                        : Text('item $i'),
                  ),
                ),
                above(link, Text('LAYER'), followerAnchor: Alignment.topLeft),
              ],
            ),
            size: size,
          );
          expect(t.screen.text, isNot(contains('LAYER')));
          scroll.jumpTo(95);
          await t.pump();
          expect(t.screen, shows('LAYER'));
          scroll.jumpTo(0);
          await t.pump();
          expect(t.screen.text, isNot(contains('LAYER')));
          scroll.jumpTo(95);
          await t.pump();
          expect(t.screen, shows('LAYER'));
        },
      );
      testWidgets(
        'right edge clips emoji without painting the prompt at $size',
        (t) async {
          final link = LayerLink();
          await t.pumpWidget(
            Overlay(
              initialEntries: [
                OverlayEntry(builder: (_) => Page(link)),
                above(
                  link,
                  Text('e\u0301🙂界', softWrap: false),
                  targetAnchor: Alignment.topRight,
                  followerAnchor: Alignment.bottomRight,
                ),
              ],
            ),
            size: size,
          );
          final row = size.height - 5;
          expect(t.screen.charAt(size.width - 5, row), 'e\u0301');
          expect(t.screen.charAt(size.width - 4, row), '🙂');
          expect(t.screen.charAt(size.width - 2, row), '界');
          expect(t.screen.lines[row + 1], 'row 0');
        },
      );
    }
  });

  testWidgets('a follower under a Stack in its entry is an error', (t) async {
    final link = LayerLink();
    await t.pumpWidget(
      Overlay(initialEntries: [OverlayEntry(builder: (_) => Page(link))]),
    );
    overlayOf(t).insert(
      OverlayEntry(
        builder: (_) => Stack(
          children: [CompositedTransformFollower(link: link, child: Text('x'))],
        ),
      ),
    );
    await expectLater(t.pump(), throwsStateError);
  });

  testWidgets('a follower under one-child wrappers is allowed', (t) async {
    final link = LayerLink();
    await t.pumpWidget(
      Overlay(initialEntries: [OverlayEntry(builder: (_) => Page(link))]),
    );
    overlayOf(t).insert(
      OverlayEntry(
        builder: (_) => Padding(
          padding: EdgeInsets.zero,
          child: CompositedTransformFollower(
            link: link,
            followerAnchor: Alignment.bottomLeft,
            child: Text('wrapped'),
          ),
        ),
      ),
    );
    await t.pump();
    expect(t.screen.lines[19], startsWith('wrapped#'));
  });
}
