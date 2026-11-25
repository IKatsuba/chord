import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'onLayoutChanged publishes the initial viewport in one pump $size',
      (t) async {
        final c = TextAreaController(text: 'hello');
        final seen = <TextAreaLayout>[];
        await t.pumpWidget(
          TextArea(
            controller: c,
            onLayoutChanged: (layout) {
              expect(identical(layout, c.lastLayout), isTrue);
              seen.add(layout);
            },
          ),
          size: size,
        );
        expect(seen, hasLength(1));
        expect(seen.single.shownRows.single.text, 'hello');
      },
    );

    testWidgets(
      'a sibling gutter settles with wrapping scrolling and resize $size',
      (t) async {
        final c = TextAreaController(text: 'a\nb\nc\nd');
        await t.pumpWidget(_Gutter(c), size: size);
        expect(t.screen.lines.take(2), ['3c', '4d']);
        c.cursor = 0;
        await t.pump();
        expect(t.screen.lines.take(2), ['1a', '2b']);
        c.text = 'x' * 150;
        await t.pump();
        await t.resize(const Size(20, 10));
        expect(t.screen.lines.first, startsWith('1'));
        expect(c.lastLayout!.width, 19);
        expect(c.lastLayout!.rowOffset, greaterThan(0));
      },
    );
  }

  testWidgets(
    'onLayoutChanged reports actual constrained height and zero space',
    (t) async {
      final c = TextAreaController(text: 'a\nb\nc');
      final seen = <TextAreaLayout>[];
      final callback = seen.add;
      Widget area(int width, int height) => SizedBox(
        width: width,
        height: height,
        child: TextArea(
          controller: c,
          maxHeight: 10,
          onLayoutChanged: callback,
        ),
      );
      await t.pumpWidget(Column(children: [area(20, 2)]));
      expect((seen.last.height, seen.last.rowOffset), (2, 1));
      await t.resize(const Size(0, 24));
      expect(seen.last.shownRows, isEmpty);
      expect(seen.last.width, 0);
      await t.pumpWidget(Column(children: [area(20, 0)]));
      expect(seen.last.height, 0);
      await t.pumpWidget(Column(children: [area(20, 2)]));
      expect(seen.last.height, 2);
    },
  );

  testWidgets('onLayoutChanged reports source line piece last and rowOffset', (
    t,
  ) async {
    final c = TextAreaController(text: 'abcd\nx');
    final seen = <TextAreaLayout>[];
    await t.pumpWidget(
      Column(
        children: [
          SizedBox(
            width: 3,
            child: TextArea(
              controller: c,
              maxHeight: 2,
              onLayoutChanged: seen.add,
            ),
          ),
        ],
      ),
      size: const Size(3, 24),
    );
    final layout = seen.last;
    expect(layout.rowOffset, 1);
    expect(layout.rows.map((r) => (r.line, r.piece, r.last)), [
      (0, 0, false),
      (0, 1, false),
      (1, 0, true),
    ]);
  });

  testWidgets(
    'identical relayout and focus changes do not repeat the callback',
    (t) async {
      final c = TextAreaController(text: 'a');
      final node = FocusNode();
      final seen = <TextAreaLayout>[];
      final callback = seen.add;
      Widget area() =>
          TextArea(controller: c, focusNode: node, onLayoutChanged: callback);
      await t.pumpWidget(area());
      await t.pump();
      node.requestFocus();
      await t.pump();
      node.unfocus();
      await t.pump();
      expect(
        seen.map(
          (l) => (l.width, l.height, l.cursorRow, l.cursorColumn, l.rowOffset),
        ),
        hasLength(1),
      );
      t.dispose();
      node.dispose();
      c.dispose();
    },
  );

  testWidgets('offscreen row edits publish without geometry changes', (
    t,
  ) async {
    final c = TextAreaController(text: 'a\nb\nc');
    final seen = <TextAreaLayout>[];
    await t.pumpWidget(
      TextArea(controller: c, maxHeight: 1, onLayoutChanged: seen.add),
    );
    c.text = 'x\nb\nc';
    await t.pump();
    expect(seen, hasLength(2));
    expect(seen.first.shownRows.single.text, seen.last.shownRows.single.text);
    expect(seen.last.rows.first.text, 'x');
  });

  testWidgets('layout notifications do not call onChanged', (t) async {
    final c = TextAreaController(text: 'a\nb');
    final changes = <String>[];
    await t.pumpWidget(
      TextArea(controller: c, onLayoutChanged: (_) {}, onChanged: changes.add),
    );
    c.cursor = 0;
    await t.resize(const Size(10, 4));
    expect(changes, isEmpty);
  });

  testWidgets(
    'replacing controller or callback publishes only the current viewport',
    (t) async {
      final first = TextAreaController(text: 'a');
      final second = TextAreaController(text: 'a');
      final old = <TextAreaLayout>[];
      final current = <TextAreaLayout>[];
      final callback = old.add;
      final child = ValueNotifier<Widget>(
        TextArea(controller: first, onLayoutChanged: callback),
      );
      await t.pumpWidget(
        ListenableBuilder(listenable: child, builder: (_) => child.value),
      );
      child.value = TextArea(controller: second, onLayoutChanged: callback);
      await t.pump();
      expect(old, hasLength(2));
      child.value = TextArea(controller: second, onLayoutChanged: current.add);
      await t.pump();
      expect(current, hasLength(1));
      expect(identical(current.single, second.lastLayout), isTrue);
    },
  );

  testWidgets(
    'removed callbacks and disposed areas receive no pending notification',
    (t) async {
      final c = TextAreaController();
      final seen = <TextAreaLayout>[];
      final child = ValueNotifier<Widget>(
        TextArea(controller: c, onLayoutChanged: seen.add),
      );
      await t.pumpWidget(
        ListenableBuilder(listenable: child, builder: (_) => child.value),
      );
      child.value = TextArea(controller: c);
      await t.pump();
      c.insert('a');
      await t.pump();
      child.value = Text('gone');
      await t.pump();
      c.insert('b');
      await t.pump();
      expect(seen, hasLength(1));
    },
  );

  testWidgets(
    'a callback edit does not recurse and old snapshots stay unchanged',
    (t) async {
      final c = TextAreaController(text: 'a');
      final seen = <TextAreaLayout>[];
      var active = false;
      void changed(TextAreaLayout layout) {
        expect(active, isFalse);
        active = true;
        seen.add(layout);
        if (seen.length == 1) c.insert('b');
        active = false;
      }

      await t.pumpWidget(TextArea(controller: c, onLayoutChanged: changed));
      await t.pump();
      expect(seen, hasLength(2));
      expect(seen.first.rows.single.text, 'a');
      expect(seen.last.rows.single.text, 'ab');
    },
  );
  group('tester U1 viewport delivery boundaries', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'a thousand edits settle once with zero and one cell at $size',
        (t) async {
          final c = TextAreaController();
          final focus = FocusNode();
          addTearDown(c.dispose);
          addTearDown(focus.dispose);
          final seen = <TextAreaLayout>[];
          void changed(TextAreaLayout layout) {
            expect(identical(layout, c.lastLayout), isTrue);
            seen.add(layout);
          }

          await t.pumpWidget(
            TextArea(
              controller: c,
              focusNode: focus,
              autofocus: true,
              maxHeight: 2,
              onLayoutChanged: changed,
            ),
            size: size,
          );
          final initial = seen.single;
          for (var i = 0; i < 1000; i++) {
            c.insert('界');
          }
          expect(seen, hasLength(1));
          await t.pump();
          expect(seen, hasLength(2));
          expect(seen.last.rows.map((r) => r.text).join(), '界' * 1000);
          expect(initial.rows.single.text, '');
          focus.unfocus();
          await t.pump();
          focus.requestFocus();
          await t.pump();
          expect(seen, hasLength(2));
          await t.resize(const Size(1, 1));
          expect((seen.last.width, seen.last.height, c.cursor), (1, 1, 1000));
          await t.resize(const Size(0, 0));
          expect(seen.last.shownRows, isEmpty);
          await t.resize(size);
          expect(seen.last.rows.map((r) => r.text).join(), '界' * 1000);
        },
      );
    }

    testWidgets('callback replacement and removal discard pending edits', (
      t,
    ) async {
      final c = TextAreaController(text: 'start');
      addTearDown(c.dispose);
      final old = <TextAreaLayout>[];
      final current = <TextAreaLayout>[];
      final child = ValueNotifier<Widget>(
        TextArea(controller: c, onLayoutChanged: old.add),
      );
      addTearDown(child.dispose);
      await t.pumpWidget(
        ListenableBuilder(listenable: child, builder: (_) => child.value),
      );
      c.insert(' changed');
      child.value = TextArea(controller: c, onLayoutChanged: current.add);
      await t.pump();
      expect(old, hasLength(1));
      expect(current, hasLength(1));
      expect(current.single.rows.single.text, 'start changed');
      child.value = TextArea(controller: c);
      c.insert(' without callback');
      await t.pump();
      child.value = Text('removed');
      c.insert(' pending removal');
      await t.pump();
      expect(current, hasLength(1));
      expect(t.screen, shows('removed'));
    });

    testWidgets('an always-editing callback remains bounded per frame', (
      t,
    ) async {
      final c = TextAreaController();
      addTearDown(c.dispose);
      final seen = <TextAreaLayout>[];
      var active = false;
      void changed(TextAreaLayout layout) {
        expect(active, isFalse);
        active = true;
        seen.add(layout);
        c.insert('x');
        active = false;
      }

      await t.pumpWidget(TextArea(controller: c, onLayoutChanged: changed));
      expect(seen.length, inInclusiveRange(1, 2));
      final before = seen.length;
      await t.pump();
      expect(seen.length - before, inInclusiveRange(1, 2));
      expect(seen.first.rows.single.text, '');
      await t.pumpWidget(Text('done'));
      final count = seen.length;
      c.insert('after removal');
      await t.pump();
      expect(seen, hasLength(count));
    });

    testWidgets(
      'offscreen Unicode offsets publish and snapshots stay immutable',
      (t) async {
        final c = TextAreaController(text: '界🙂e\u0301\nvisible');
        addTearDown(c.dispose);
        final seen = <TextAreaLayout>[];
        await t.pumpWidget(
          TextArea(controller: c, maxHeight: 1, onLayoutChanged: seen.add),
        );
        final first = seen.single;
        c.text = 'a\nvisible';
        await t.pump();
        expect(seen, hasLength(2));
        expect(first.shownRows.single.text, seen.last.shownRows.single.text);
        expect(first.shownRows.single.start, 4);
        expect(seen.last.shownRows.single.start, 2);
        expect(() => first.rows.clear(), throwsUnsupportedError);
        final shown = first.shownRows;
        shown.clear();
        expect(first.shownRows.single.text, 'visible');
        expect(first.rows.first.text, '界🙂e\u0301');
      },
    );
  });
}

class _Gutter extends StatefulWidget {
  const _Gutter(this.controller);
  final TextAreaController controller;
  @override
  State<_Gutter> createState() => _GutterState();
}

class _GutterState extends State<_Gutter> {
  TextAreaLayout? viewport;
  void changed(TextAreaLayout layout) => setState(() => viewport = layout);
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 1,
        child: Column(
          children: [
            for (final row in viewport?.shownRows ?? <TextAreaRow>[])
              Text('${row.line + 1}'),
          ],
        ),
      ),
      Expanded(
        child: TextArea(
          controller: widget.controller,
          maxHeight: 2,
          onLayoutChanged: changed,
        ),
      ),
    ],
  );
}
