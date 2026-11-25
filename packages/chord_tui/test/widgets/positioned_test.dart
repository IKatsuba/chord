import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A box of [char] that wants [width] by [height] cells and records the
/// constraints it got.
class Patch extends LeafRenderObjectWidget {
  const Patch(this.char, {this.width = 0, this.height = 0, this.seen});

  final String char;
  final int width;
  final int height;
  final List<BoxConstraints>? seen;

  @override
  RenderBox createRenderObject(BuildContext context) => RenderPatch(this);

  @override
  void updateRenderObject(BuildContext context, RenderPatch r) => r.w = this;
}

class RenderPatch extends RenderBox {
  RenderPatch(this.w);

  Patch w;

  @override
  void performLayout() {
    w.seen?.add(constraints);
    size = constraints.constrain(Size(w.width, w.height));
  }

  @override
  void paint(Canvas canvas, Offset origin) =>
      canvas.fill(Rect.fromOffsetSize(origin, size), Style.plain, w.char);
}

/// A [stack] laid in a box of [width] by [height] at the top left.
Widget boxed(int width, int height, Widget stack) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(width: width, height: height, child: stack),
);

void main() {
  testerEdges();
  misuse();
  group('positioned children', () {
    testWidgets('left and top place, the child keeps its size', (t) async {
      await t.pumpWidget(
        boxed(
          10,
          4,
          Stack(
            children: [
              Positioned(
                left: 2,
                top: 1,
                child: Patch('x', width: 3, height: 2),
              ),
            ],
          ),
        ),
      );
      expect(t.screen.lines.take(4), ['', '  xxx', '  xxx', '']);
    });

    testWidgets('right and bottom place the far edge', (t) async {
      await t.pumpWidget(
        boxed(
          10,
          4,
          Stack(
            children: [
              Positioned(
                right: 1,
                bottom: 0,
                child: Patch('x', width: 3, height: 2),
              ),
            ],
          ),
        ),
      );
      expect(t.screen.lines.take(4), ['', '', '      xxx', '      xxx']);
    });

    testWidgets('opposing edges give a tight size, never negative', (t) async {
      final seen = <BoxConstraints>[];
      await t.pumpWidget(
        boxed(
          10,
          4,
          Stack(
            children: [
              Positioned(
                left: 1,
                right: 2,
                top: 1,
                bottom: 1,
                child: Patch('x', seen: seen),
              ),
              Positioned(
                left: 6,
                right: 6,
                top: 0,
                bottom: 9,
                child: Patch('y', seen: seen),
              ),
            ],
          ),
        ),
      );
      expect(seen, [
        BoxConstraints.tight(const Size(7, 2)),
        BoxConstraints.tight(Size.zero),
      ]);
      expect(t.screen.lines.take(4), ['', ' xxxxxxx', ' xxxxxxx', '']);
    });

    testWidgets('an explicit size is tight, with either edge', (t) async {
      final seen = <BoxConstraints>[];
      await t.pumpWidget(
        boxed(
          10,
          4,
          Stack(
            children: [
              Positioned(
                right: 0,
                width: 4,
                height: 1,
                child: Patch('x', width: 9, height: 9, seen: seen),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                width: 2,
                height: 2,
                child: Patch('y', seen: seen),
              ),
            ],
          ),
        ),
      );
      expect(seen, [
        BoxConstraints.tight(const Size(4, 1)),
        BoxConstraints.tight(const Size(2, 2)),
      ]);
      expect(t.screen.lines.take(4), ['      xxxx', '', 'yy', 'yy']);
    });

    testWidgets('no edge or size is loose up to the stack, at zero', (t) async {
      final seen = <BoxConstraints>[];
      await t.pumpWidget(
        boxed(
          10,
          4,
          Stack(
            children: [
              Positioned(
                top: 2,
                child: Patch('x', width: 30, height: 1, seen: seen),
              ),
            ],
          ),
        ),
      );
      expect(seen, [const BoxConstraints(maxWidth: 10, maxHeight: 4)]);
      expect(t.screen.lines.take(4), ['', '', 'xxxxxxxxxx', '']);
    });

    testWidgets('only unpositioned children size the stack', (t) async {
      await t.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: Stack(
            children: [
              Patch('a', width: 4, height: 2),
              Positioned(
                left: 0,
                top: 0,
                child: Patch('b', width: 20, height: 9),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Patch('c', width: 1, height: 1),
              ),
            ],
          ),
        ),
      );
      // b is cut to the 4x2 that a gives; c sits in that box's corner.
      expect(t.screen.lines.take(3), ['bbbb', 'bbbc', '']);
    });

    testWidgets('only positioned children fill what is bounded', (t) async {
      await t.pumpWidget(
        Column(
          children: [
            Stack(
              children: [
                Positioned(
                  right: 0,
                  top: 0,
                  child: Patch('x', width: 2, height: 1),
                ),
              ],
            ),
            Text('below'),
          ],
        ),
        size: const Size(20, 5),
      );
      // The column gives unbounded height: the stack takes no rows, so its
      // child is cut away, and the width is filled.
      expect(t.screen.lines.take(2), ['below', '']);
      await t.pumpWidget(
        Stack(
          children: [
            Positioned(
              right: 0,
              bottom: 0,
              child: Patch('x', width: 2, height: 1),
            ),
          ],
        ),
        size: const Size(20, 5),
      );
      expect(t.screen.lines[4], '${' ' * 18}xx');
    });

    testWidgets('negative offsets are clipped to the stack', (t) async {
      await t.pumpWidget(
        Column(
          children: [
            Text('above'),
            boxed(
              6,
              2,
              Stack(
                children: [
                  Positioned(
                    left: -2,
                    top: -1,
                    child: Patch('x', width: 4, height: 2),
                  ),
                  Positioned(
                    left: 4,
                    top: 1,
                    child: Patch('y', width: 5, height: 3),
                  ),
                ],
              ),
            ),
            Text('below'),
          ],
        ),
      );
      expect(t.screen.lines.take(4), ['above', 'xx', '    yy', 'below']);
    });

    testWidgets('a wide grapheme at the clip edge is not split', (t) async {
      await t.pumpWidget(
        boxed(
          5,
          1,
          Stack(
            children: [
              Positioned(left: 0, top: 0, child: Text('ab漢字', softWrap: false)),
              Positioned(
                left: 0,
                top: 0,
                width: 9,
                child: Text('  漢字', softWrap: false),
              ),
            ],
          ),
        ),
      );
      expect(t.screen.lines.first, '  漢');
      expect(t.screen.charAt(4, 0), ' ');
    });

    testWidgets('children paint in order, later over earlier', (t) async {
      await t.pumpWidget(
        boxed(
          6,
          2,
          Stack(
            children: [
              Patch('a', width: 6, height: 2),
              Positioned(
                left: 1,
                top: 0,
                child: Patch('b', width: 3, height: 2),
              ),
              Positioned(
                left: 2,
                top: 1,
                child: Patch('c', width: 1, height: 1),
              ),
            ],
          ),
        ),
      );
      expect(t.screen.lines.take(2), ['abbbaa', 'abcbaa']);
    });

    testWidgets('a tight stack keeps its size when a child grows', (t) async {
      final grow = ValueNotifier(1);
      await t.pumpWidget(
        Column(
          children: [
            boxed(
              8,
              2,
              ListenableBuilder(
                listenable: grow,
                builder: (_) => Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Patch('x', width: grow.value, height: grow.value),
                    ),
                  ],
                ),
              ),
            ),
            Text('below'),
          ],
        ),
      );
      expect(t.screen.lines.take(3), ['x', '', 'below']);
      grow.value = 5;
      await t.pump();
      expect(t.screen.lines.take(3), ['xxxxx', 'xxxxx', 'below']);
    });

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a bottom bar over a full page at $size', (t) async {
        await t.pumpWidget(
          Stack(
            children: [
              Patch('.', width: 999, height: 999),
              Positioned(left: 0, right: 0, bottom: 0, child: Text('status')),
            ],
          ),
          size: size,
        );
        final rows = t.screen.lines;
        expect(rows[size.height - 2], '.' * size.width);
        // Text paints no background: the page shows on beside it.
        expect(rows.last, 'status${'.' * (size.width - 6)}');
      });
    }

    test('more than two on an axis is rejected', () {
      expect(
        () => Positioned(left: 0, right: 0, width: 1, child: Text('')),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Positioned(top: 0, bottom: 0, height: 1, child: Text('')),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Positioned(width: -1, child: Text('')),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

void misuse() {
  group('a Positioned away from its Stack', () {
    testWidgets('outside a Stack is an error', (t) async {
      await expectLater(
        t.pumpWidget(Positioned(width: 5, child: Text('x'))),
        throwsStateError,
      );
    });

    testWidgets('under a box drawn inside the Stack is an error', (t) async {
      await expectLater(
        t.pumpWidget(
          Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(1),
                child: Positioned(left: 0, child: Text('x')),
              ),
            ],
          ),
        ),
        throwsStateError,
      );
    });

    testWidgets('under widgets that draw nothing it still works', (t) async {
      await t.pumpWidget(
        boxed(
          6,
          2,
          Stack(
            children: [
              Builder(
                builder: (_) => Positioned(
                  right: 0,
                  bottom: 0,
                  child: Patch('x', width: 2, height: 1),
                ),
              ),
            ],
          ),
        ),
      );
      expect(t.screen.lines.take(2), ['', '    xx']);
    });
  });
}

void testerEdges() {
  group('tester: Positioned cell boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('resize through empty and one cell at $size', (t) async {
        final seen = <BoxConstraints>[];
        await t.pumpWidget(
          Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: Patch('x', seen: seen),
              ),
            ],
          ),
          size: size,
        );
        for (final next in [Size.zero, const Size(1, 1), size]) {
          await t.resize(next);
          expect(seen.last, BoxConstraints.tight(next));
          expect(t.screen.buffer.size, next);
          if (next.width > 0) expect(t.screen.lines.first, 'x' * next.width);
        }
      });
      testWidgets('negative edges clip whole graphemes at $size', (t) async {
        await t.pumpWidget(
          Stack(
            children: [
              Positioned(
                left: -1,
                top: 0,
                width: 8,
                child: Text('界🙂e\u0301\x1b[31mR\x1b[0m', softWrap: false),
              ),
              Positioned(
                right: -1,
                bottom: 0,
                width: 5,
                child: Text('e\u0301🙂界', softWrap: false),
              ),
            ],
          ),
          size: size,
        );
        expect(t.screen.charAt(0, 0), ' ');
        expect(t.screen.charAt(1, 0), '🙂');
        expect(t.screen.charAt(3, 0), 'e\u0301');
        expect(t.screen.charAt(4, 0), 'R');
        expect(t.screen.charAt(size.width - 1, size.height - 1), ' ');
        expect(t.screen.charAt(size.width - 3, size.height - 1), '🙂');
      });
    }
    testWidgets('both unbounded axes take their minimum', (t) async {
      final seen = <BoxConstraints>[];
      await t.pumpWidget(
        Row(
          children: [
            Column(
              children: [
                Stack(
                  children: [
                    Positioned(
                      width: 4,
                      height: 2,
                      child: Patch('x', seen: seen),
                    ),
                  ],
                ),
                Text('below'),
              ],
            ),
          ],
        ),
      );
      expect(seen.single, BoxConstraints.tight(const Size(4, 2)));
      expect(t.screen.lines.first, 'below');
      expect(t.screen.text, isNot(contains('x')));
    });
  });
}
