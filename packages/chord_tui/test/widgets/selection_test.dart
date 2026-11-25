import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent pointer(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

Future<void> drag(WidgetTester t, Offset from, Offset to, {Offset? up}) async {
  await t.mouse(pointer(MouseEventKind.press, from.x, from.y));
  await t.mouse(pointer(MouseEventKind.move, to.x, to.y));
  final release = up ?? to;
  await t.mouse(pointer(MouseEventKind.release, release.x, release.y));
}

Widget area(
  SelectionController controller,
  Widget child, {
  void Function(SelectionValue)? finalized,
}) => SelectionArea(
  controller: controller,
  selectionStyle: const Style(inverse: true),
  onSelectionFinalized: finalized,
  child: child,
);

class _CoverageProbe extends SingleChildRenderObjectWidget {
  const _CoverageProbe({
    required this.known,
    required super.child,
    this.churn = false,
    this.inspect,
  });
  final bool known, churn;
  final void Function(BuildOwner)? inspect;
  @override
  RenderBox createRenderObject(BuildContext context) =>
      _RenderCoverageProbe(context.owner, known, churn, inspect);
  @override
  void updateRenderObject(BuildContext context, _RenderCoverageProbe box) {
    box
      ..known = known
      ..churn = churn;
  }
}

class _RenderCoverageProbe extends RenderProxyBox {
  _RenderCoverageProbe(this.owner, this.known, this.churn, this.inspect);
  final BuildOwner owner;
  bool known, churn;
  final void Function(BuildOwner)? inspect;
  @override
  PaintCoverage? describePaintCoverage(Rect localClip) =>
      known ? const PaintCoverage.empty(_RenderCoverageProbe) : null;
  @override
  void performLayout() {
    inspect?.call(owner);
    super.performLayout();
    if (churn) owner.afterLayout(owner.requestFrame);
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    inspect?.call(owner);
    super.paint(canvas, origin);
  }
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('inclusive/reverse endpoints and last-motion release $size', (
      t,
    ) async {
      final c = SelectionController();
      final values = <SelectionValue>[];
      await t.pumpWidget(
        area(c, Text('This reply'), finalized: values.add),
        size: size,
      );
      await drag(t, const Offset(0, 0), const Offset(3, 0));
      expect(c.snapshot()!.text, 'This');
      expect(values, hasLength(1));
      expect(c.value.phase, SelectionPhase.finalized);
      expect(t.screen.styleAt(0, 0).isInverse, isTrue);
      expect(t.screen.styleAt(4, 0).isInverse, isFalse);
      await drag(t, const Offset(3, 0), const Offset(0, 0));
      expect(c.snapshot()!.text, 'This');
      await drag(
        t,
        const Offset(0, 0),
        const Offset(1, 0),
        up: const Offset(3, 0),
      );
      expect(c.snapshot()!.text, 'Th');
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.release, 8, 0));
      expect(c.snapshot()!.text, '');
      expect(values, hasLength(4));
      c.dispose();
    });

    testWidgets('header transcript draft ordered forward and reverse $size', (
      t,
    ) async {
      final c = SelectionController();
      final draft = TextAreaController(text: 'draft');
      await t.pumpWidget(
        area(
          c,
          Column(
            children: [
              Text('header'),
              SelectionContainer.disabled(child: Text('furniture')),
              Text('transcript'),
              TextArea(controller: draft),
            ],
          ),
        ),
        size: size,
      );
      await drag(t, const Offset(0, 0), const Offset(4, 3));
      expect(c.snapshot()!.text, 'header\ntranscript\ndraft');
      await drag(t, const Offset(4, 3), const Offset(0, 0));
      expect(c.snapshot()!.text, 'header\ntranscript\ndraft');
      c.dispose();
      draft.dispose();
    });
  }
  testWidgets(
    'known overlay gates hits/highlight while logical interior survives',
    (t) async {
      final c = SelectionController();
      await t.pumpWidget(
        area(
          c,
          Stack(
            children: [
              Text('abcd'),
              Positioned(
                left: 1,
                top: 0,
                child: SelectionContainer.disabled(
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: DecoratedBox(background: Style.inverse),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await drag(t, const Offset(0, 0), const Offset(3, 0));
      expect(c.snapshot()!.text, 'abcd');
      c.clear();
      await t.mouse(pointer(MouseEventKind.press, 1, 0));
      await t.mouse(pointer(MouseEventKind.move, 3, 0));
      await t.mouse(pointer(MouseEventKind.release, 3, 0));
      expect(c.value.phase, SelectionPhase.none);
      c.dispose();
    },
  );

  testWidgets('transparent overlay border leaves interior source exposed', (
    t,
  ) async {
    final c = SelectionController();
    await t.pumpWidget(
      area(
        c,
        Stack(
          children: [
            Text('abcdef\nabcdef\nabcdef'),
            Positioned(
              left: 1,
              top: 0,
              child: SelectionContainer.disabled(
                child: SizedBox(
                  width: 4,
                  height: 3,
                  child: DecoratedBox(border: const Border()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await drag(t, const Offset(2, 1), const Offset(3, 1));
    expect(c.snapshot()!.text, 'cd');
    c.clear();
    await drag(t, const Offset(1, 1), const Offset(3, 1));
    expect(c.value.phase, SelectionPhase.none);
    c.dispose();
  });

  testWidgets(
    'unknown coverage cancels without finalize then recovers retained range',
    (t) async {
      final c = SelectionController();
      final known = ValueNotifier(true);
      var finalizations = 0;
      await t.pumpWidget(
        ListenableBuilder(
          listenable: known,
          builder: (_) => area(
            c,
            _CoverageProbe(known: known.value, child: Text('abcd')),
            finalized: (_) => finalizations++,
          ),
        ),
      );
      await drag(t, const Offset(0, 0), const Offset(3, 0));
      known.value = false;
      expect(c.snapshot(), isNull);
      expect(c.visibleCodeBlocks(), isEmpty);
      expect(c.value.text, 'abcd');
      await t.pump();
      expect(t.screen.styleAt(0, 0).isInverse, isFalse);
      known.value = true;
      expect(c.snapshot()!.text, 'abcd');
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 2, 0));
      known.value = false;
      expect(c.snapshot(), isNull);
      await t.mouse(pointer(MouseEventKind.release, 2, 0));
      known.value = true;
      expect(c.snapshot()!.phase, SelectionPhase.none);
      expect(finalizations, 1);
      c.dispose();
      known.dispose();
    },
  );

  testWidgets('unknown clipped out of effective area does not block queries', (
    t,
  ) async {
    final c = SelectionController();
    await t.pumpWidget(
      area(
        c,
        Stack(
          children: [
            Text('abcd'),
            Positioned(
              left: 1000,
              top: 0,
              child: _CoverageProbe(
                known: false,
                child: SizedBox(width: 2, height: 2),
              ),
            ),
          ],
        ),
      ),
    );
    await drag(t, const Offset(0, 0), const Offset(3, 0));
    expect(c.snapshot()!.text, 'abcd');
    c.dispose();
  });

  testWidgets(
    'blank LF lane is startable while frame and gutter stay excluded',
    (t) async {
      final c = SelectionController();
      await t.pumpWidget(area(c, Markdown('```\n\necho done\n```')));
      await drag(t, const Offset(4, 1), const Offset(7, 1));
      expect(c.snapshot()!.text, '');
      await drag(t, const Offset(4, 1), const Offset(12, 2));
      expect(c.snapshot()!.text, '\necho done');
      await drag(t, const Offset(12, 2), const Offset(7, 1));
      expect(c.snapshot()!.text, '\necho done');
      c.clear();
      await drag(t, const Offset(0, 1), const Offset(12, 2));
      expect(c.value.phase, SelectionPhase.none);
      c.dispose();
    },
  );

  testWidgets(
    'virtual logical interval copies offscreen sources without new widgets',
    (t) async {
      final c = SelectionController(), scroll = ScrollController();
      final sources = [
        for (var i = 0; i < 20; i++)
          SelectionSource.text(id: i, revision: 0, text: TextSpan('record $i')),
      ];
      final calls = <int>[];
      final delegate = SelectionChildDelegate(
        itemCount: sources.length,
        idAt: (i) => i,
        indexOfId: (id) => id is int && id >= 0 && id < 20 ? id : null,
        sourceAt: (i) {
          calls.add(i);
          return sources[i];
        },
      );
      var builds = 0;
      await t.pumpWidget(
        area(
          c,
          Column(
            children: [
              Text('header'),
              SizedBox(
                height: 2,
                child: ListView.builder(
                  controller: scroll,
                  selectionDelegate: delegate,
                  itemCount: sources.length,
                  itemVersion: (i) => sources[i].revision,
                  itemBuilder: (_, i) {
                    builds++;
                    return Text.fromSelectionSource(sources[i]);
                  },
                ),
              ),
              Text('draft'),
            ],
          ),
        ),
      );
      expect(calls.toSet(), {0, 1});
      final before = builds;
      await drag(t, const Offset(0, 0), const Offset(4, 3));
      expect(
        c.snapshot()!.text,
        [
          'header',
          for (var i = 0; i < 20; i++) 'record $i',
          'draft',
        ].join('\n'),
      );
      expect(builds, before);
      await drag(t, const Offset(4, 3), const Offset(0, 0));
      expect(
        c.snapshot()!.text,
        [
          'header',
          for (var i = 0; i < 20; i++) 'record $i',
          'draft',
        ].join('\n'),
      );
      c.dispose();
      scroll.dispose();
    },
  );

  testWidgets(
    'source update and copy in one input batch observes current revision',
    (t) async {
      final c = SelectionController();
      var source = SelectionSource.text(
        id: 'text',
        revision: 0,
        text: const TextSpan('abcd'),
      );
      final version = ValueNotifier(0);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: version,
          builder: (_) => area(c, Text.fromSelectionSource(source)),
        ),
      );
      await drag(t, const Offset(0, 0), const Offset(3, 0));
      source = SelectionSource.text(
        id: 'text',
        revision: 1,
        text: const TextSpan('abXd'),
        previous: source,
      );
      version.value++;
      expect(c.snapshot()!.text, 'abXd');
      c.dispose();
      version.dispose();
    },
  );

  testWidgets(
    'two-pass exhaustion suppresses stale copy and late finalization',
    (t) async {
      final c = SelectionController();
      final churn = ValueNotifier(false);
      var layouts = 0, finalizations = 0;
      await t.pumpWidget(
        ListenableBuilder(
          listenable: churn,
          builder: (_) => area(
            c,
            _CoverageProbe(
              known: true,
              churn: churn.value,
              inspect: (owner) {
                layouts++;
                expect(c.snapshot, throwsStateError);
                expect(c.visibleCodeBlocks, throwsStateError);
              },
              child: Text('abcd'),
            ),
            finalized: (_) => finalizations++,
          ),
        ),
      );
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 3, 0));
      layouts = 0;
      churn.value = true;
      expect(c.snapshot(), isNull);
      expect(layouts, 2);
      t.host.handleMouse(pointer(MouseEventKind.release, 3, 0));
      expect(finalizations, 0);
      churn.value = false;
      expect(c.snapshot()!.phase, SelectionPhase.none);
      c.dispose();
      churn.dispose();
    },
  );

  testWidgets(
    'provider reveal uses shared nested code bounds and fresh geometry',
    (t) async {
      final c = SelectionController(), scroll = ScrollController();
      final sources = [
        for (var i = 0; i < 8; i++)
          SelectionSource.markdown(
            id: i,
            revision: 0,
            text: '> ```dart\n> code $i\n> ```',
          ),
      ];
      final delegate = SelectionChildDelegate(
        itemCount: sources.length,
        idAt: (i) => i,
        indexOfId: (id) => id is int && id >= 0 && id < 8 ? id : null,
        sourceAt: (i) => sources[i],
      );
      await t.pumpWidget(
        area(
          c,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 3,
              child: ListView.builder(
                controller: scroll,
                itemCount: sources.length,
                selectionDelegate: delegate,
                itemVersion: (i) => sources[i].revision,
                itemBuilder: (_, i) => Markdown.fromSelectionSource(sources[i]),
              ),
            ),
          ),
        ),
      );
      final id = sources.last.codeBlocks.single.id;
      expect(c.codeBlockGeometry(id), isNull);
      expect(c.revealCodeBlock(id), isTrue);
      final geometry = c.codeBlockGeometry(id)!;
      expect(geometry.bounds.top, 0);
      expect(geometry.bounds.height, 3);
      expect(geometry.visibleRects, isNotEmpty);
      final offset = scroll.offset;
      expect(c.revealCodeBlock(id), isTrue);
      expect(scroll.offset, offset);
      c.dispose();
      scroll.dispose();
    },
  );
  testWidgets('wide glyph occlusion suppresses both halves as endpoints', (
    t,
  ) async {
    final c = SelectionController();
    await t.pumpWidget(
      area(
        c,
        Stack(
          children: [
            Text('a界b'),
            Positioned(
              left: 2,
              top: 0,
              child: SelectionContainer.disabled(
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: DecoratedBox(background: Style.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await drag(t, const Offset(1, 0), const Offset(3, 0));
    expect(c.value.phase, SelectionPhase.none);
    await drag(t, const Offset(0, 0), const Offset(3, 0));
    expect(c.snapshot()!.text, 'a界b');
    expect(t.screen.styleAt(1, 0).isInverse, isFalse);
    c.dispose();
  });

  testWidgets('intrinsic ellipsis gap never reappears in logical copy', (
    t,
  ) async {
    final c = SelectionController();
    await t.pumpWidget(
      area(
        c,
        Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 8,
                child: Text(
                  'begin hidden END',
                  softWrap: false,
                  overflow: TextOverflow.middle,
                ),
              ),
            ),
            Text('tail'),
          ],
        ),
      ),
    );
    await drag(t, const Offset(0, 0), const Offset(3, 1));
    expect(c.snapshot()!.text, isNot(contains('hidden')));
    expect(c.snapshot()!.text, isNot(contains('...')));
    expect(c.snapshot()!.text, endsWith('\ntail'));
    c.dispose();
  });

  testWidgets('known code overlay splits visible rectangles around its hole', (
    t,
  ) async {
    final c = SelectionController();
    final source = SelectionSource.markdown(
      id: 'm',
      revision: 0,
      text: '```\necho done\n```',
    );
    await t.pumpWidget(
      area(
        c,
        Stack(
          children: [
            Markdown.fromSelectionSource(source),
            Positioned(
              left: 0,
              top: 0,
              child: SelectionContainer.disabled(
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: DecoratedBox(background: Style.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final geometry = c.codeBlockGeometry(source.codeBlocks.single.id)!;
    expect(geometry.bounds.top, 0);
    expect(geometry.visibleRects.any((r) => r.contains(0, 0)), isFalse);
    expect(geometry.visibleRects.any((r) => r.contains(1, 0)), isTrue);
    final cells = <Offset>{};
    for (final rect in geometry.visibleRects) {
      for (var y = rect.top; y < rect.bottom; y++) {
        for (var x = rect.left; x < rect.right; x++) {
          expect(cells.add(Offset(x, y)), isTrue);
        }
      }
    }
    c.dispose();
  });

  testWidgets(
    'same-batch wheel then release projects last motion through new rows',
    (t) async {
      final c = SelectionController(), scroll = ScrollController();
      final sources = [
        for (var i = 0; i < 8; i++)
          SelectionSource.text(id: i, revision: 0, text: TextSpan('record $i')),
      ];
      final delegate = SelectionChildDelegate(
        itemCount: 8,
        idAt: (i) => i,
        indexOfId: (id) => id is int && id >= 0 && id < 8 ? id : null,
        sourceAt: (i) => sources[i],
      );
      await t.pumpWidget(
        area(
          c,
          Column(
            children: [
              SizedBox(
                height: 2,
                child: Listener(
                  onPointerSignal: (_) => scroll.lineDown(),
                  child: ListView.builder(
                    controller: scroll,
                    itemCount: 8,
                    selectionDelegate: delegate,
                    itemVersion: (_) => 0,
                    itemBuilder: (_, i) => Text.fromSelectionSource(sources[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      t.host.handleMouse(pointer(MouseEventKind.press, 0, 0));
      t.host.handleMouse(pointer(MouseEventKind.move, 7, 1));
      t.host.handleMouse(
        const MouseEvent(
          MouseEventKind.wheel,
          position: Offset(1, 1),
          scrollDelta: Offset(0, 1),
        ),
      );
      t.host.handleMouse(pointer(MouseEventKind.release, 0, 0));
      expect(c.snapshot()!.text, 'record 0\nrecord 1\nrecord 2');
      c.dispose();
      scroll.dispose();
    },
  );

  testWidgets(
    'finalized range survives endpoint root removal without selecting new roots',
    (t) async {
      final c = SelectionController();
      final changes = ValueNotifier(false);
      final a = SelectionSource.text(
        id: 'a',
        revision: 0,
        text: const TextSpan('one'),
      );
      final b = SelectionSource.text(
        id: 'b',
        revision: 0,
        text: const TextSpan('two'),
      );
      final inserted = SelectionSource.text(
        id: 'new',
        revision: 0,
        text: const TextSpan('new'),
      );
      await t.pumpWidget(
        ListenableBuilder(
          listenable: changes,
          builder: (_) => area(
            c,
            Column(
              children: [
                if (!changes.value) Text.fromSelectionSource(a),
                if (changes.value) Text.fromSelectionSource(inserted),
                Text.fromSelectionSource(b),
              ],
            ),
          ),
        ),
      );
      await drag(t, const Offset(0, 0), const Offset(2, 1));
      changes.value = true;
      expect(c.snapshot()!.text, 'two');
      expect(c.snapshot()!.phase, SelectionPhase.finalized);
      c.dispose();
      changes.dispose();
    },
  );

  testWidgets(
    'cancel clear and disposal never emit a late finalized callback',
    (t) async {
      final c = SelectionController();
      var finalized = 0;
      await t.pumpWidget(area(c, Text('abcd'), finalized: (_) => finalized++));
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 3, 0));
      c.clear();
      await t.mouse(pointer(MouseEventKind.release, 3, 0));
      expect(finalized, 0);
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 3, 0));
      c.dispose();
      await t.mouse(pointer(MouseEventKind.release, 3, 0));
      expect(finalized, 0);
      expect(t.screen.styleAt(0, 0).isInverse, isFalse);
    },
  );

  for (final mode in ['clear', 'new drag', 'dispose']) {
    testWidgets(
      'matching release retains one immutable final event after reentrant $mode',
      (t) async {
        final c = SelectionController();
        final events = <SelectionValue>[];
        var changed = false;
        await t.pumpWidget(
          SelectionArea(
            controller: c,
            selectionStyle: Style.inverse,
            onSelectionChanged: (value) {
              expect(t.host.owner.doingLayoutOrPaint, isFalse);
              if (!changed && value.phase == SelectionPhase.finalized) {
                changed = true;
                switch (mode) {
                  case 'clear':
                    c.clear();
                  case 'new drag':
                    t.host.handleMouse(pointer(MouseEventKind.press, 1, 0));
                  case 'dispose':
                    c.dispose();
                }
              }
            },
            onSelectionFinalized: events.add,
            child: Text('abcd'),
          ),
        );
        await drag(t, const Offset(0, 0), const Offset(3, 0));
        if (mode == 'dispose') {
          expect(events, isEmpty);
        } else {
          expect(events.single.text, 'abcd');
          expect(events.single.phase, SelectionPhase.finalized);
          if (mode == 'clear') {
            expect(c.value.phase, SelectionPhase.none);
          } else {
            expect(c.value.phase, SelectionPhase.changing);
            await t.mouse(pointer(MouseEventKind.move, 2, 0));
            await t.mouse(pointer(MouseEventKind.release, 2, 0));
            expect(events.last.text, 'bc');
            expect(events, hasLength(2));
          }
          c.dispose();
        }
      },
    );
  }

  testWidgets(
    'pointer selection keeps draft focus and subsequent keyboard editing',
    (t) async {
      final c = SelectionController();
      final draft = TextAreaController(text: 'draft');
      final focus = FocusNode();
      await t.pumpWidget(
        area(
          c,
          Column(
            children: [
              Text('transcript'),
              TextArea(controller: draft, focusNode: focus, autofocus: true),
            ],
          ),
        ),
      );
      expect(focus.hasPrimaryFocus, isTrue);
      await drag(t, const Offset(0, 0), const Offset(3, 0));
      expect(focus.hasPrimaryFocus, isTrue);
      await t.type('!');
      expect(draft.text, 'draft!');
      expect(c.snapshot()!.text, 'tran');
      c.dispose();
      draft.dispose();
      focus.dispose();
    },
  );

  testWidgets('nested area owns its endpoints without outer-area capture', (
    t,
  ) async {
    final outer = SelectionController(), inner = SelectionController();
    await t.pumpWidget(
      area(
        outer,
        Column(children: [Text('outer'), area(inner, Text('inner'))]),
      ),
    );
    await drag(t, const Offset(0, 1), const Offset(4, 1));
    expect(inner.snapshot()!.text, 'inner');
    expect(outer.value.phase, SelectionPhase.none);
    expect(t.screen.styleAt(0, 1).isInverse, isTrue);
    outer.dispose();
    inner.dispose();
  });

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('equal/out-and-back and true outside clamps $size', (t) async {
      final c = SelectionController();
      await t.pumpWidget(
        area(c, Padding(padding: const EdgeInsets.all(1), child: Text('This'))),
        size: size,
      );
      await drag(t, const Offset(1, 1), const Offset(1, 1));
      expect(c.value.text, '');
      await t.mouse(pointer(MouseEventKind.press, 1, 1));
      await t.mouse(pointer(MouseEventKind.move, 4, 1));
      await t.mouse(pointer(MouseEventKind.move, 1, 1));
      await t.mouse(pointer(MouseEventKind.release, 4, 1));
      expect(c.value.text, '');
      await drag(t, const Offset(1, 1), Offset(size.width + 2, 1));
      expect(c.snapshot()!.text, 'This');
      await drag(t, const Offset(4, 1), const Offset(0, 1));
      expect(c.snapshot()!.text, 'This');
      await drag(t, const Offset(4, 1), const Offset(1, -2));
      expect(c.snapshot()!.text, 'This');
      c.dispose();
    });
  }

  testWidgets(
    'settled source projection does not schedule endless repaint frames',
    (t) async {
      final c = SelectionController();
      await t.pumpWidget(area(c, Text('abcd')));
      var requests = 0;
      t.host.owner.onNeedsFrame = () => requests++;
      await t.pump();
      expect(requests, 0);
      c.snapshot();
      c.visibleCodeBlocks();
      expect(requests, 0);
      c.dispose();
    },
  );

  testWidgets(
    'initially dirty reveal shares two passes and never performs a third',
    (t) async {
      final c = SelectionController(), scroll = ScrollController();
      final dirty = ValueNotifier(false);
      var invalidated = false;
      final sources = [
        for (var i = 0; i < 8; i++)
          SelectionSource.markdown(
            id: i,
            revision: 0,
            text: '```\ncode $i\n```',
          ),
      ];
      final delegate = SelectionChildDelegate(
        itemCount: 8,
        idAt: (i) => i,
        indexOfId: (id) => id is int && id >= 0 && id < 8 ? id : null,
        sourceAt: (i) => sources[i],
      );
      await t.pumpWidget(
        ListenableBuilder(
          listenable: dirty,
          builder: (_) => area(
            c,
            _CoverageProbe(
              known: true,
              inspect: (owner) {
                if (dirty.value &&
                    !invalidated &&
                    owner.settlingInputGeometry) {
                  invalidated = true;
                  owner.afterLayout(owner.requestFrame);
                }
              },
              child: Column(
                children: [
                  SizedBox(
                    height: 3,
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: 8,
                      selectionDelegate: delegate,
                      itemVersion: (_) => 0,
                      itemBuilder: (_, i) =>
                          Markdown.fromSelectionSource(sources[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      dirty.value = true;
      final before = t.host.owner.inputLayoutPasses;
      expect(c.revealCodeBlock(sources.last.codeBlocks.single.id), isFalse);
      expect(t.host.owner.inputLayoutPasses - before, 2);
      expect(c.revealCodeBlock(sources.last.codeBlocks.single.id), isTrue);
      c.dispose();
      scroll.dispose();
      dirty.dispose();
    },
  );

  testWidgets('mounted group insets must agree with frozen source geometry', (
    t,
  ) async {
    final c = SelectionController();
    final child = SelectionSource.text(
      id: 'child',
      revision: 0,
      text: const TextSpan('record'),
    );
    final source = SelectionSource.group(
      id: 'group',
      revision: 0,
      children: [SelectionSourceChild(source: child, insetLeft: 2)],
    );
    final delegate = SelectionChildDelegate(
      itemCount: 1,
      idAt: (_) => 'group',
      indexOfId: (id) => id == 'group' ? 0 : null,
      sourceAt: (_) => source,
    );
    await expectLater(
      t.pumpWidget(
        area(
          c,
          ListView.builder(
            itemCount: 1,
            selectionDelegate: delegate,
            itemVersion: (_) => 0,
            itemBuilder: (_, _) => Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Text.fromSelectionSource(child),
            ),
          ),
        ),
      ),
      throwsStateError,
    );
    c.dispose();
  });

  testWidgets(
    'one controller rejects multiple live areas after reconciliation',
    (t) async {
      final c = SelectionController();
      await expectLater(
        t.pumpWidget(
          Column(children: [area(c, Text('one')), area(c, Text('two'))]),
        ),
        throwsStateError,
      );
      c.dispose();
    },
  );

  testWidgets(
    'known covered interior retains exact last endpoint until exposed hit or edge',
    (t) async {
      final c = SelectionController();
      await t.pumpWidget(
        area(
          c,
          Stack(
            children: [
              Text('abcdef'),
              Positioned(
                left: 2,
                top: 0,
                child: SelectionContainer.disabled(
                  child: SizedBox(
                    width: 2,
                    height: 1,
                    child: DecoratedBox(background: Style.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 1, 0));
      expect(c.snapshot()!.text, 'ab');
      await t.mouse(pointer(MouseEventKind.move, 2, 0));
      expect(c.snapshot()!.text, 'ab');
      await t.mouse(pointer(MouseEventKind.move, 3, 0));
      expect(c.snapshot()!.text, 'ab');
      await t.mouse(pointer(MouseEventKind.move, 4, 0));
      expect(c.snapshot()!.text, 'abcde');
      await t.mouse(pointer(MouseEventKind.move, 80, 0));
      expect(c.snapshot()!.text, 'abcdef');
      await t.mouse(pointer(MouseEventKind.release, 0, 0));
      expect(c.snapshot()!.text, 'abcdef');
      c.dispose();
    },
  );

  testWidgets(
    'clipped source interior retains endpoint but beyond full source clamps full end',
    (t) async {
      final c = SelectionController(), scroll = ScrollController();
      final text = [for (var i = 0; i < 100; i++) 'row $i'].join('\n');
      final source = SelectionSource.text(
        id: 'long',
        revision: 0,
        text: TextSpan(text),
      );
      final delegate = SelectionChildDelegate(
        itemCount: 1,
        idAt: (_) => 'long',
        indexOfId: (id) => id == 'long' ? 0 : null,
        sourceAt: (_) => source,
      );
      await t.pumpWidget(
        area(
          c,
          Column(
            children: [
              SizedBox(
                height: 2,
                child: ListView.builder(
                  controller: scroll,
                  itemCount: 1,
                  selectionDelegate: delegate,
                  itemVersion: (_) => 0,
                  itemBuilder: (_, _) => Text.fromSelectionSource(source),
                ),
              ),
            ],
          ),
        ),
      );
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 4, 1));
      expect(c.snapshot()!.text, 'row 0\nrow 1');
      await t.mouse(pointer(MouseEventKind.move, 20, 3));
      expect(c.snapshot()!.text, 'row 0\nrow 1');
      expect(scroll.offset, 0);
      await t.mouse(pointer(MouseEventKind.move, 20, 101));
      expect(c.snapshot()!.text, text);
      expect(scroll.offset, 0);
      await t.mouse(pointer(MouseEventKind.release, 0, 0));
      expect(c.snapshot()!.text, text);
      c.dispose();
      scroll.dispose();
    },
  );

  testWidgets(
    'TextArea has one source across its existing scrolled rows and caret',
    (t) async {
      final c = SelectionController();
      final draft = TextAreaController(text: 'first\nsecond\nthird');
      await t.pumpWidget(
        area(
          c,
          Column(
            children: [
              Text('header'),
              TextArea(controller: draft, autofocus: true, maxHeight: 2),
            ],
          ),
        ),
      );
      expect(draft.lastLayout!.rowOffset, 1);
      final cursor = t.screen.buffer.cursor;
      await drag(t, const Offset(0, 1), const Offset(4, 2));
      expect(c.snapshot()!.text, 'second\nthird');
      expect(t.screen.styleAt(0, 1).isInverse, isTrue);
      expect(t.screen.styleAt(0, 2).isInverse, isTrue);
      expect(t.screen.buffer.cursor, cursor);
      await t.mouse(pointer(MouseEventKind.press, 0, 1));
      await t.mouse(pointer(MouseEventKind.move, 20, 10));
      expect(c.snapshot()!.text, 'second\nthird');
      await t.mouse(pointer(MouseEventKind.release, 0, 0));
      expect(draft.text, 'first\nsecond\nthird');
      c.dispose();
      draft.dispose();
    },
  );

  testWidgets(
    'TextArea copy uses displayed ANSI provenance through current live rows',
    (t) async {
      final c = SelectionController();
      final draft = TextAreaController(text: '\x1b[31mred\nx');
      await t.pumpWidget(
        area(c, Column(children: [TextArea(controller: draft)])),
      );
      await drag(t, const Offset(0, 0), const Offset(0, 1));
      expect(c.snapshot()!.text, 'red\nx');
      expect(draft.text, '\x1b[31mred\nx');
      c.dispose();
      draft.dispose();
    },
  );

  testWidgets(
    'zero area surface returns unresolved with no stale code geometry',
    (t) async {
      final c = SelectionController();
      final source = SelectionSource.markdown(
        id: 'code',
        revision: 0,
        text: '```\ncode\n```',
      );
      final zero = ValueNotifier(false);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: zero,
          builder: (_) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: zero.value ? 0 : 20,
              height: zero.value ? 0 : 4,
              child: area(c, Markdown.fromSelectionSource(source)),
            ),
          ),
        ),
      );
      expect(c.visibleCodeBlocks(), hasLength(1));
      zero.value = true;
      expect(c.snapshot(), isNull);
      expect(c.visibleCodeBlocks(), isEmpty);
      expect(c.revealCodeBlock(source.codeBlocks.single.id), isFalse);
      c.dispose();
      zero.dispose();
    },
  );

  testWidgets('syntax color survives an explicit inverse selection style', (
    t,
  ) async {
    final c = SelectionController();
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark(),
        child: area(c, Code('if (true) return;', language: 'dart')),
      ),
    );
    final color = t.screen.styleAt(2, 0).fg;
    await drag(t, const Offset(2, 0), const Offset(3, 0));
    expect(c.snapshot()!.text, 'if');
    expect(t.screen.styleAt(2, 0).fg, color);
    expect(t.screen.styleAt(2, 0).isInverse, isTrue);
    c.dispose();
  });
  testWidgets(
    'controller disposal releases active registration before notifying nobody',
    (t) async {
      final c = SelectionController();
      var notifications = 0, changes = 0;
      c.addListener(() => notifications++);
      await t.pumpWidget(
        SelectionArea(
          controller: c,
          selectionStyle: Style.inverse,
          onSelectionChanged: (_) => changes++,
          child: Text('abcd'),
        ),
      );
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 3, 0));
      notifications = changes = 0;
      c.dispose();
      expect(notifications, 0);
      expect(changes, 0);
      await t.mouse(pointer(MouseEventKind.release, 3, 0));
      expect(t.screen.styleAt(0, 0).isInverse, isFalse);
    },
  );
  for (final listener in ['widget', 'controller']) {
    testWidgets(
      'clear completes old cleanup before $listener none observer starts new drag',
      (t) async {
        final c = SelectionController();
        final finalized = <SelectionValue>[];
        var restart = false;
        void observe() {
          if (restart && c.value.phase == SelectionPhase.none) {
            restart = false;
            t.host.handleMouse(pointer(MouseEventKind.press, 1, 0));
          }
        }

        if (listener == 'controller') c.addListener(observe);
        await t.pumpWidget(
          SelectionArea(
            controller: c,
            selectionStyle: Style.inverse,
            onSelectionChanged: (_) {
              if (listener == 'widget') observe();
            },
            onSelectionFinalized: finalized.add,
            child: Text('abcd'),
          ),
        );
        await t.mouse(pointer(MouseEventKind.press, 0, 0));
        await t.mouse(pointer(MouseEventKind.move, 3, 0));
        restart = true;
        c.clear();
        expect(c.value.phase, SelectionPhase.changing);
        await t.mouse(pointer(MouseEventKind.move, 2, 0));
        await t.mouse(pointer(MouseEventKind.release, 2, 0));
        expect(finalized.single.text, 'bc');
        expect(c.snapshot()!.text, 'bc');
        c.dispose();
      },
    );
  }

  for (final provider in [false, true]) {
    for (final reverse in [false, true]) {
      for (final removed in ['anchor', 'extent', 'middle']) {
        testWidgets(
          'held surviving endpoints provider=$provider reverse=$reverse removed=$removed',
          (t) async {
            final c = SelectionController();
            final changed = ValueNotifier(false);
            final sources = [
              for (final (id, text) in [
                ('a', 'one'),
                ('b', 'two'),
                ('c', 'three'),
              ])
                SelectionSource.text(id: id, revision: 0, text: TextSpan(text)),
            ];
            final inserted = SelectionSource.text(
              id: 'new',
              revision: 0,
              text: const TextSpan('INSERTED'),
            );
            final index = removed == 'middle'
                ? 1
                : (removed == 'anchor' ? (reverse ? 2 : 0) : (reverse ? 0 : 2));
            await t.pumpWidget(
              ListenableBuilder(
                listenable: changed,
                builder: (_) {
                  final current = [
                    for (var i = 0; i < 3; i++)
                      changed.value && i == index ? inserted : sources[i],
                  ];
                  final Widget child;
                  if (provider) {
                    final delegate = SelectionChildDelegate(
                      itemCount: 3,
                      idAt: (i) => current[i].id,
                      indexOfId: (id) {
                        final i = current.indexWhere((s) => s.id == id);
                        return i < 0 ? null : i;
                      },
                      sourceAt: (i) => current[i],
                    );
                    child = ListView.builder(
                      itemCount: 3,
                      selectionDelegate: delegate,
                      itemVersion: (i) => current[i].id,
                      itemBuilder: (_, i) =>
                          Text.fromSelectionSource(current[i]),
                    );
                  } else {
                    child = Column(
                      children: [
                        for (final source in current)
                          Text.fromSelectionSource(
                            source,
                            key: ValueKey(source.id),
                          ),
                      ],
                    );
                  }
                  return area(c, child);
                },
              ),
            );
            final from = reverse ? const Offset(4, 2) : Offset.zero;
            final to = reverse ? Offset.zero : const Offset(4, 2);
            await t.mouse(pointer(MouseEventKind.press, from.x, from.y));
            await t.mouse(pointer(MouseEventKind.move, to.x, to.y));
            changed.value = true;
            final expected = [
              for (var i = 0; i < 3; i++)
                if (i != index) ['one', 'two', 'three'][i],
            ].join('\n');
            expect(c.snapshot()!.phase, SelectionPhase.changing);
            expect(c.snapshot()!.text, expected);
            await t.mouse(pointer(MouseEventKind.release, to.x, to.y));
            expect(c.snapshot()!.phase, SelectionPhase.finalized);
            expect(c.snapshot()!.text, expected);
            c.dispose();
            changed.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'unknown cancellation observer can recover and start a surviving new drag',
    (t) async {
      final c = SelectionController();
      final known = ValueNotifier(true);
      final finalized = <SelectionValue>[];
      var restart = false;
      await t.pumpWidget(
        ListenableBuilder(
          listenable: known,
          builder: (_) => SelectionArea(
            controller: c,
            selectionStyle: Style.inverse,
            onSelectionChanged: (value) {
              if (restart && value.phase == SelectionPhase.none) {
                restart = false;
                known.value = true;
                t.host.handleMouse(pointer(MouseEventKind.press, 1, 0));
              }
            },
            onSelectionFinalized: finalized.add,
            child: _CoverageProbe(known: known.value, child: Text('abcd')),
          ),
        ),
      );
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 3, 0));
      restart = true;
      known.value = false;
      c.snapshot();
      expect(c.value.phase, SelectionPhase.changing);
      await t.mouse(pointer(MouseEventKind.move, 2, 0));
      await t.mouse(pointer(MouseEventKind.release, 2, 0));
      expect(finalized.single.text, 'bc');
      c.dispose();
      known.dispose();
    },
  );

  testWidgets(
    'clear old capture cleanup cannot release a new drag from ancestor cancellation',
    (t) async {
      final c = SelectionController();
      final finalized = <SelectionValue>[];
      var restart = false;
      await t.pumpWidget(
        Listener(
          onPointerCancel: (_) {
            if (restart) {
              restart = false;
              t.host.handleMouse(pointer(MouseEventKind.press, 1, 0));
            }
          },
          child: area(c, Text('abcd'), finalized: finalized.add),
        ),
      );
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 3, 0));
      restart = true;
      c.clear();
      expect(c.value.phase, SelectionPhase.changing);
      await t.mouse(pointer(MouseEventKind.move, 2, 0));
      await t.mouse(pointer(MouseEventKind.release, 2, 0));
      expect(finalized.single.text, 'bc');
      c.dispose();
    },
  );

  testWidgets(
    'same-fragment source reflow refreshes held endpoint before matching release',
    (t) async {
      final c = SelectionController();
      final changed = ValueNotifier(false);
      var source = SelectionSource.text(
        id: 'same',
        revision: 0,
        text: const TextSpan('abcd\nefgh'),
      );
      await t.pumpWidget(
        ListenableBuilder(
          listenable: changed,
          builder: (_) => area(
            c,
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 4,
                child: Text.fromSelectionSource(source),
              ),
            ),
          ),
        ),
      );
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 1, 1));
      expect(c.snapshot()!.text, 'abcd\nef');
      source = SelectionSource.text(
        id: 'same',
        revision: 1,
        text: const TextSpan('ab\ncdefgh'),
        previous: source,
      );
      changed.value = true;
      t.host.handleMouse(pointer(MouseEventKind.release, 20, 20));
      expect(c.snapshot()!.text, 'ab\ncd');
      c.dispose();
      changed.dispose();
    },
  );

  for (final admit in ['motion', 'explicit clamped scroll', 'release only']) {
    testWidgets(
      'inserted Markdown fragments excluded by refresh/up until $admit',
      (t) async {
        final c = SelectionController(), scroll = ScrollController();
        final changed = ValueNotifier(false);
        var source = SelectionSource.markdown(
          id: 'md',
          revision: 0,
          text: 'alpha\n\nomega',
        );
        await t.pumpWidget(
          ListenableBuilder(
            listenable: changed,
            builder: (_) {
              final delegate = SelectionChildDelegate(
                itemCount: 1,
                idAt: (_) => 'md',
                indexOfId: (id) => id == 'md' ? 0 : null,
                sourceAt: (_) => source,
              );
              return area(
                c,
                ListView.builder(
                  controller: scroll,
                  itemCount: 1,
                  selectionDelegate: delegate,
                  itemVersion: (_) => source.revision,
                  itemBuilder: (_, _) => Markdown.fromSelectionSource(source),
                ),
              );
            },
          ),
        );
        await t.mouse(pointer(MouseEventKind.press, 0, 0));
        await t.mouse(pointer(MouseEventKind.move, 4, 2));
        expect(c.snapshot()!.text, 'alpha\n \nomega');
        source = SelectionSource.markdown(
          id: 'md',
          revision: 1,
          text: 'alpha\n\nINSERTED\n\nomega',
          previous: source,
        );
        changed.value = true;
        expect(c.snapshot()!.text, 'alpha\nomega');
        expect(c.snapshot()!.text, 'alpha\nomega');
        if (admit == 'release only') {
          await t.mouse(pointer(MouseEventKind.release, 4, 2));
          expect(c.snapshot()!.text, 'alpha\nomega');
          expect(c.value.phase, SelectionPhase.finalized);
          c.dispose();
          scroll.dispose();
          changed.dispose();
          return;
        }
        if (admit == 'motion') {
          await t.mouse(pointer(MouseEventKind.move, 4, 2));
        } else {
          expect(scroll.contentRows, lessThanOrEqualTo(scroll.viewRows));
          scroll.lineDown();
        }
        expect(c.snapshot()!.text, 'alpha\n \nINSER');
        await t.mouse(pointer(MouseEventKind.release, 40, 20));
        expect(c.snapshot()!.text, 'alpha\n \nINSER');
        c.dispose();
        scroll.dispose();
        changed.dispose();
      },
    );
  }

  testWidgets(
    'all-source-removal cancellation observer can start new current-source drag',
    (t) async {
      final c = SelectionController();
      final changed = ValueNotifier(false);
      final oldSource = SelectionSource.text(
        id: 'old',
        revision: 0,
        text: const TextSpan('abcd'),
      );
      final newSource = SelectionSource.text(
        id: 'new',
        revision: 0,
        text: const TextSpan('WXYZ'),
      );
      final finalized = <SelectionValue>[];
      var restart = false;
      await t.pumpWidget(
        ListenableBuilder(
          listenable: changed,
          builder: (_) => SelectionArea(
            controller: c,
            selectionStyle: Style.inverse,
            onSelectionChanged: (value) {
              if (restart && value.phase == SelectionPhase.none) {
                restart = false;
                t.host.handleMouse(pointer(MouseEventKind.press, 1, 0));
              }
            },
            onSelectionFinalized: finalized.add,
            child: Text.fromSelectionSource(
              changed.value ? newSource : oldSource,
            ),
          ),
        ),
      );
      await t.mouse(pointer(MouseEventKind.press, 0, 0));
      await t.mouse(pointer(MouseEventKind.move, 3, 0));
      restart = true;
      changed.value = true;
      c.snapshot();
      expect(c.value.phase, SelectionPhase.changing);
      await t.mouse(pointer(MouseEventKind.move, 2, 0));
      await t.mouse(pointer(MouseEventKind.release, 2, 0));
      expect(finalized.single.text, 'XY');
      c.dispose();
      changed.dispose();
    },
  );
}
