import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  _testerCursorCases();
  _testerShowCursorCases();
  test(
    'cursor claims obey clips, bounds and paint order including wide halves',
    () {
      final b = Buffer(8, 2);
      final c = Canvas(b);
      c.drawText(2, 0, '界');
      c.setCursor(const Offset(2, 0), style: CursorStyle.steadyBar);
      c.setCursor(const Offset(8, 0));
      c.clipped(const Rect(0, 0, 1, 1)).setCursor(const Offset(2, 0));
      expect(b.cursor, const Offset(2, 0));
      expect(b.cursorStyle, CursorStyle.steadyBar);
      c.put(3, 0, ' ', 1, Style.plain);
      expect(b.cursor, isNull);
      c.setCursor(const Offset(4, 0));
      c.put(4, 0, ' ', 1, Style.plain);
      expect(
        b.cursor,
        isNull,
        reason: 'identical bytes still cover the cursor',
      );
      c.setCursor(const Offset(5, 0));
      c.fill(const Rect(0, 1, 8, 1));
      expect(b.cursor, const Offset(5, 0));
      c.fill(const Rect(5, 0, 1, 1));
      expect(b.cursor, isNull);
      c.setCursor(const Offset(6, 0));
      c.setCursor(const Offset(7, 1));
      expect(b.cursor, const Offset(7, 1));
      expect(Buffer(8, 2).cursor, isNull);
    },
  );

  for (final style in CursorStyle.values) {
    test('renderer hides paints resets styles positions and shows $style', () {
      final b = Buffer(3, 1);
      Canvas(b).drawText(0, 0, 'abc');
      Canvas(b).setCursor(const Offset(1, 0), style: style);
      final end = '\x1b[0m\x1b[${style.index + 1} q\x1b[1;2H\x1b[?25h';
      expect(diffBuffers(null, b), startsWith('\x1b[?2026h\x1b[?25l'));
      expect(diffBuffers(null, b), endsWith('$end\x1b[?2026l'));
      expect(diffBuffers(b, b, synchronized: false), '\x1b[?25l$end');
      final moved = Buffer(3, 1);
      Canvas(moved).drawText(0, 0, 'abc');
      Canvas(moved).setCursor(const Offset(2, 0), style: style);
      expect(
        diffBuffers(b, moved, synchronized: false),
        '\x1b[?25l\x1b[0m\x1b[${style.index + 1} q\x1b[1;3H\x1b[?25h',
      );
      expect(diffBuffers(moved, Buffer(3, 1)), isNot(contains('\x1b[?25h')));
    });
  }

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('area cursor follows actual viewport and focus at $size', (
      t,
    ) async {
      final c = TextAreaController(text: '界e\u0301🙂\nlast');
      final node = FocusNode();
      addTearDown(c.dispose);
      addTearDown(node.dispose);
      await t.pumpWidget(
        Padding(
          padding: const EdgeInsets.all(2),
          child: TextArea(
            controller: c,
            focusNode: node,
            autofocus: true,
            maxHeight: 2,
            cursorStyle: CursorStyle.steadyBar,
          ),
        ),
        size: size,
      );
      expect(t.screen.buffer.cursor, const Offset(6, 3));
      c.cursor = 1;
      await t.pump();
      expect(t.screen.buffer.cursor, const Offset(4, 2));
      expect(t.screen.styleAt(4, 2).isInverse, isFalse);
      c.cursor = 3;
      await t.pump();
      expect(t.screen.buffer.cursor, const Offset(7, 2));
      c.text = 'a' * (size.width - 4);
      await t.pump();
      expect(t.screen.buffer.cursor, const Offset(2, 3));
      c.text = 'one\ntwo\nthree\nfour';
      await t.pump();
      expect(t.screen.buffer.cursor, const Offset(6, 3));
      await t.resize(const Size(6, 4));
      expect(t.screen.buffer.cursor, isNull);
      await t.resize(Size.zero);
      expect(t.screen.buffer.cursor, isNull);
      await t.resize(size);
      expect(t.screen.buffer.cursor, const Offset(6, 3));
      node.unfocus();
      await t.pump();
      expect(t.screen.buffer.cursor, isNull);
      node.requestFocus();
      await t.pump();
      expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBar);
      await t.pumpWidget(Text('removed'));
      expect(t.screen.buffer.cursor, isNull);
    });

    testWidgets('showCursor false hides the area and input cursors and '
        'keeps their focus and typing, at $size', (t) async {
      final area = TextAreaController(text: 'ab');
      final input = TextEditingController(text: 'cd');
      final node = FocusNode();
      addTearDown(area.dispose);
      addTearDown(input.dispose);
      addTearDown(node.dispose);
      Widget editors({required bool show, required bool onArea}) => Column(
        children: [
          TextArea(
            controller: area,
            focusNode: onArea ? node : null,
            autofocus: onArea,
            maxHeight: 2,
            showCursor: show,
          ),
          TextInput(
            controller: input,
            focusNode: onArea ? null : node,
            autofocus: !onArea,
            showCursor: show,
          ),
        ],
      );
      for (final onArea in [true, false]) {
        await t.pumpWidget(editors(show: true, onArea: onArea), size: size);
        final shown = t.screen.buffer.cursor;
        expect(shown, isNotNull);
        await t.pumpWidget(editors(show: false, onArea: onArea), size: size);
        expect(t.screen.buffer.cursor, isNull);
        expect(node.hasFocus, isTrue);
        await t.type('x');
        expect(onArea ? area.text : input.text, onArea ? 'abx' : 'cdx');
        await t.pumpWidget(editors(show: true, onArea: onArea), size: size);
        expect(t.screen.buffer.cursor, shown! + const Offset(1, 0));
      }
    });

    testWidgets(
      'input cursor uses painted prefix LF tabs and graphemes at $size',
      (t) async {
        final c = TextEditingController(text: '界e\u0301🙂\nend');
        addTearDown(c.dispose);
        await t.pumpWidget(
          TextInput(
            controller: c,
            autofocus: true,
            prefix: '> ',
            cursorStyle: CursorStyle.steadyUnderline,
          ),
          size: size,
        );
        expect(t.screen.buffer.cursor, const Offset(3, 1));
        c.cursor = 1;
        await t.pump();
        expect(t.screen.buffer.cursor, const Offset(4, 0));
        c.cursor = 3;
        await t.pump();
        expect(t.screen.buffer.cursor, const Offset(7, 0));
        expect(t.screen.lines.take(2), ['> 界e\u0301🙂', 'end']);
        c.text = '\tx';
        c.cursor = 0;
        await t.pump();
        expect(t.screen.buffer.cursor, const Offset(2, 0));
        c.cursor = 1;
        await t.pump();
        expect(t.screen.buffer.cursor, const Offset(6, 0));
        expect(t.screen.lines[0], '>     x');
        await t.resize(Size.zero);
        expect(t.screen.buffer.cursor, isNull);
      },
    );
  }

  testWidgets('input cursor hides on a space removed by wrapping', (t) async {
    final c = TextEditingController(text: 'ab cd')..cursor = 2;
    addTearDown(c.dispose);
    await t.pumpWidget(
      TextInput(controller: c, autofocus: true),
      size: const Size(3, 4),
    );
    expect(t.screen.lines.take(2), ['ab', 'cd']);
    expect(t.screen.buffer.cursor, isNull);
    c.cursor = 3;
    await t.pump();
    expect(t.screen.buffer.cursor, const Offset(0, 1));
  });

  testWidgets(
    'input cursor at exact width maps its EOF blank through wrapping',
    (t) async {
      final c = TextEditingController(text: 'abc');
      addTearDown(c.dispose);
      await t.pumpWidget(
        TextInput(controller: c, autofocus: true),
        size: const Size(3, 3),
      );
      expect(t.screen.lines.take(2), ['abc', '']);
      expect(
        t.screen.buffer.cursor,
        isNull,
        reason: 'wrapping drops the EOF space',
      );
    },
  );

  testWidgets(
    'later opaque paint covers cursor while transparent space retains it',
    (t) async {
      Widget page(Widget surface) =>
          Stack(children: [const TextArea(autofocus: true), surface]);
      await t.pumpWidget(page(const SizedBox(width: 1, height: 1)));
      expect(t.screen.buffer.cursor, Offset.zero);
      await t.pumpWidget(page(Text(' ')));
      expect(t.screen.buffer.cursor, isNull);
    },
  );

  testWidgets(
    'overlay focus suppresses cursor and passive paint covers only its cell',
    (t) async {
      late OverlayState overlay;
      final base = OverlayEntry(
        builder: (context) {
          overlay = Overlay.of(context);
          return const TextArea(autofocus: true);
        },
      );
      await t.pumpWidget(Overlay(initialEntries: [base]));
      expect(t.screen.buffer.cursor, Offset.zero);
      final passive = OverlayEntry(
        requestFocus: false,
        builder: (_) => Stack(
          children: [Positioned(left: 0, top: 2, child: Text('completion'))],
        ),
      );
      overlay.insert(passive);
      await t.pump();
      expect(t.screen.buffer.cursor, Offset.zero);
      final picker = OverlayEntry(
        builder: (_) => Focus(autofocus: true, child: Text('picker')),
      );
      overlay.insert(picker);
      await t.pump();
      expect(t.screen.buffer.cursor, isNull);
      picker.remove();
      await t.pump();
      expect(t.screen.buffer.cursor, Offset.zero);
      final covered = OverlayEntry(
        requestFocus: false,
        builder: (_) => Text(' '),
      );
      overlay.insert(covered);
      await t.pump();
      expect(t.screen.buffer.cursor, isNull);
      covered.remove();
      await t.pump();
      expect(t.screen.buffer.cursor, Offset.zero);
      passive.remove();
    },
  );

  test('style-only frame updates the cursor without repainting text', () {
    final before = Buffer(2, 1);
    Canvas(before).setCursor(Offset.zero);
    final after = Buffer(2, 1);
    Canvas(after).setCursor(Offset.zero, style: CursorStyle.blinkingBar);
    expect(
      diffBuffers(before, after, synchronized: false),
      '\x1b[?25l\x1b[0m\x1b[5 q\x1b[1;1H\x1b[?25h',
    );
  });

  test(
    'layout source offsets survive wrapping and synthesized glyphs have none',
    () {
      final layout = TextLayout.compute(
        const TextSpan('a\tb\nc'),
        maxWidth: 20,
      );
      expect(layout.lines[0].map((g) => g.sourceOffset), [0, 1, 1, 1, 1, 2]);
      expect(layout.lines[1].single.sourceOffset, 4);
      final clipped = TextLayout.compute(
        const TextSpan('abcdef'),
        maxWidth: 4,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
      expect(clipped.lines.single.last.sourceOffset, isNull);
      final middle = TextLayout.compute(
        const TextSpan('abcdefgh'),
        maxWidth: 5,
        softWrap: false,
        overflow: TextOverflow.middle,
      );
      expect(middle.lines.single.map((g) => g.sourceOffset), [
        0,
        null,
        null,
        null,
        7,
      ]);
    },
  );
}

void _testerCursorCases() {
  group('tester: cursor frame and editor boundaries', () {
    for (final area in [false, true]) {
      final name = area ? 'TextArea' : 'TextInput';
      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        testWidgets(
          '$name batches edits and styles without stale claims at $size',
          (t) async {
            final c = area ? TextAreaController() : TextEditingController();
            final style = ValueNotifier(CursorStyle.steadyBlock);
            final visible = ValueNotifier(true);
            final node = FocusNode();
            final changes = StreamController<String>(sync: true);
            final subscription = changes.stream.listen(
              (value) => c.text = value,
            );
            addTearDown(c.dispose);
            addTearDown(style.dispose);
            addTearDown(visible.dispose);
            addTearDown(node.dispose);
            addTearDown(changes.close);
            addTearDown(subscription.cancel);
            await t.pumpWidget(
              ListenableBuilder(
                listenable: visible,
                builder: (_) => visible.value
                    ? ListenableBuilder(
                        listenable: style,
                        builder: (_) => area
                            ? TextArea(
                                controller: c as TextAreaController,
                                focusNode: node,
                                autofocus: true,
                                cursorStyle: style.value,
                              )
                            : TextInput(
                                controller: c,
                                focusNode: node,
                                autofocus: true,
                                cursorStyle: style.value,
                              ),
                      )
                    : const SizedBox(),
              ),
              size: size,
            );
            for (var i = 0; i < 1000; i++) {
              changes.add('界e\u0301🙂$i');
            }
            await t.pump();
            expect(t.screen.buffer.cursor, const Offset(8, 0));
            expect(t.screen.lines.first, '界e\u0301🙂999');
            for (final selected in CursorStyle.values) {
              style.value = selected;
              await t.pump();
              expect(t.screen.buffer.cursorStyle, selected);
              expect(t.screen.buffer.cursor, const Offset(8, 0));
              expect(t.screen.styleAt(8, 0).isInverse, isFalse);
            }
            node.unfocus();
            await t.pump();
            expect(t.screen.buffer.cursor, isNull);
            node.requestFocus();
            await t.pump();
            expect(t.screen.buffer.cursor, const Offset(8, 0));
            visible.value = false;
            await t.pump();
            changes.add('late 界🙂');
            await t.pump();
            expect(t.screen.buffer.cursor, isNull);
            expect(t.screen.text, isEmpty);
          },
        );
      }
      for (final glyph in ['界', '🙂', 'e\u0301']) {
        testWidgets(
          '$name clips a one-cell $glyph edge and returns after resize',
          (t) async {
            final c = area
                ? TextAreaController(text: glyph)
                : TextEditingController(text: glyph);
            c.cursor = 0;
            addTearDown(c.dispose);
            await t.pumpWidget(
              area
                  ? TextArea(
                      controller: c as TextAreaController,
                      autofocus: true,
                    )
                  : TextInput(controller: c, autofocus: true),
              size: const Size(1, 1),
            );
            // An oversized glyph stays on this row and is clipped in place.
            expect(t.screen.buffer.cursor, Offset.zero);
            expect(t.screen.charAt(0, 0), glyph == 'e\u0301' ? glyph : ' ');
            await t.resize(Size.zero);
            expect(t.screen.buffer.cursor, isNull);
            await t.resize(const Size(80, 24));
            expect(t.screen.buffer.cursor, Offset.zero);
            expect(t.screen.charAt(0, 0), glyph);
          },
        );
      }
    }

    testWidgets('area cursor uses bounded width with unbounded height', (
      t,
    ) async {
      final c = TextAreaController(text: 'one\ntwo\nthree\nfour\nfive');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Column(
          children: [TextArea(controller: c, autofocus: true, maxHeight: 4)],
        ),
      );
      expect(t.screen.buffer.cursor, const Offset(4, 3));
      expect(t.screen.lines.take(4), ['two', 'three', 'four', 'five']);
    });

    testWidgets('input cursor maps prefix under unbounded width', (t) async {
      final c = TextEditingController(text: '界e\u0301🙂');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Row(
          children: [TextInput(controller: c, autofocus: true, prefix: '> ')],
        ),
      );
      expect(t.screen.buffer.cursor, const Offset(7, 0));
    });

    testWidgets('input ANSI prefix counts painted graphemes once', (t) async {
      final c = TextEditingController(text: '界e\u0301🙂');
      addTearDown(c.dispose);
      await t.pumpWidget(
        TextInput(controller: c, autofocus: true, prefix: '\x1b[31m>\x1b[0m '),
        size: const Size(80, 24),
      );
      expect(t.screen.buffer.cursor, const Offset(7, 0));
      expect(t.screen.lines.first, '> 界e\u0301🙂');
      c.cursor = 0;
      await t.pump();
      expect(t.screen.buffer.cursor, const Offset(2, 0));
    });

    test(
      'clipped overpaint invalidates only the actually replaced wide glyph',
      () {
        final b = Buffer(6, 2);
        final c = Canvas(b);
        c.drawText(1, 0, '界🙂');
        c.setCursor(const Offset(3, 0));
        c.clipped(const Rect(1, 0, 1, 1)).drawText(1, 0, '界');
        expect(b.cursor, const Offset(3, 0));
        c.clipped(const Rect(4, 0, 1, 1)).fill(const Rect(0, 0, 6, 2));
        expect(b.cursor, isNull);
        c.setCursor(const Offset(0, 1), style: CursorStyle.blinkingUnderline);
        c.clipped(Rect.zero).setCursor(Offset.zero);
        expect(b.cursor, const Offset(0, 1));
        expect(b.cursorStyle, CursorStyle.blinkingUnderline);
      },
    );
  });
}

void _testerShowCursorCases() {
  group('tester: CTUI-78 hidden editor cursor boundaries', () {
    for (final area in [false, true]) {
      final name = area ? 'TextArea' : 'TextInput';
      for (final size in const [
        Size.zero,
        Size(1, 1),
        Size(80, 24),
        Size(120, 40),
      ]) {
        testWidgets(
          '$name retains hidden edits and focus across $size resize',
          (t) async {
            final c = area
                ? TextAreaController(text: '界e\u0301🙂\x1b[31mx')
                : TextEditingController(text: '界e\u0301🙂\x1b[31mx');
            final node = FocusNode();
            final show = ValueNotifier(false);
            addTearDown(c.dispose);
            addTearDown(node.dispose);
            addTearDown(show.dispose);
            await t.pumpWidget(
              ListenableBuilder(
                listenable: show,
                builder: (_) => area
                    ? TextArea(
                        controller: c as TextAreaController,
                        focusNode: node,
                        autofocus: true,
                        showCursor: show.value,
                      )
                    : TextInput(
                        controller: c,
                        focusNode: node,
                        autofocus: true,
                        showCursor: show.value,
                      ),
              ),
              size: size,
            );
            expect(t.screen.buffer.cursor, isNull);
            expect(node.hasFocus, isTrue);
            for (var index = 0; index < 1000; index++) {
              c.text = '界e\u0301🙂$index';
            }
            await t.pump();
            expect(t.screen.buffer.cursor, isNull);
            await t.resize(const Size(80, 24));
            expect(t.screen.lines.first, '界e\u0301🙂999');
            node.unfocus();
            show.value = true;
            await t.pump();
            expect(t.screen.buffer.cursor, isNull);
            node.requestFocus();
            await t.pump();
            expect(t.screen.buffer.cursor, const Offset(8, 0));
            show.value = false;
            await t.pump();
            await t.type('x');
            await t.press('left right backspace');
            expect(c.text, '界e\u0301🙂999');
            expect(t.screen.buffer.cursor, isNull);
            show.value = true;
            await t.pump();
            expect(t.screen.buffer.cursor, const Offset(8, 0));
            await t.pumpWidget(const SizedBox());
            c.text = 'late 界🙂e\u0301';
            await t.pump();
            expect(t.screen.buffer.cursor, isNull);
          },
        );
      }

      testWidgets(
        '$name hidden cursor changes no painted text when unbounded',
        (t) async {
          final c = area
              ? TextAreaController(text: '界🙂e\u0301')
              : TextEditingController(text: '界🙂e\u0301');
          final show = ValueNotifier(true);
          addTearDown(c.dispose);
          addTearDown(show.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: show,
              builder: (_) => area
                  ? Column(
                      children: [
                        TextArea(
                          controller: c as TextAreaController,
                          autofocus: true,
                          maxHeight: 2,
                          showCursor: show.value,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        TextInput(
                          controller: c,
                          autofocus: true,
                          prefix: '\x1b[31m>\x1b[0m ',
                          showCursor: show.value,
                        ),
                      ],
                    ),
            ),
            size: const Size(80, 24),
          );
          final lines = t.screen.lines.toList();
          final position = t.screen.buffer.cursor;
          expect(position, isNotNull);
          show.value = false;
          await t.pump();
          expect(t.screen.lines, lines);
          expect(t.screen.buffer.cursor, isNull);
          show.value = true;
          await t.pump();
          expect(t.screen.buffer.cursor, position);
        },
      );
    }
  });
}
