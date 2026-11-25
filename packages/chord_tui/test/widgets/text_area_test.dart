import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _wide = Size(120, 40);
const _narrow = Size(80, 24);

/// [area] framed as an app would: a title row above, a row below.
Widget _framed(Widget area) =>
    Column(children: [Text('title'), area, Text('below')]);

String _sixLines() => [for (var i = 1; i <= 6; i++) 'line $i'].join('\n');

void main() {
  group('CTUI-68 tester: placeholder gap boundaries', () {
    for (final gap in [true, false]) {
      testWidgets(
        'gap=$gap keeps Unicode, focus and cursor through resizes and burst updates',
        (t) async {
          final controller = TextAreaController();
          final focus = FocusNode();
          final outside = FocusNode();
          try {
            await t.pumpWidget(
              Column(
                children: [
                  TextArea(
                    controller: controller,
                    focusNode: focus,
                    placeholder: '界🙂e\u0301\u001b[31mhint\u001b[0m',
                    placeholderGap: gap,
                  ),
                  Focus(focusNode: outside, child: Text('outside')),
                ],
              ),
              size: _wide,
            );
            focus.requestFocus();
            await t.pump();
            for (final size in const [
              _wide,
              _narrow,
              Size(1, 1),
              Size.zero,
              _narrow,
              _wide,
            ]) {
              await t.resize(size);
              if (size.width >= 80) {
                expect(t.screen.lines.first, '${gap ? ' ' : ''}界🙂e\u0301hint');
                expect(t.screen.buffer.cursor, Offset.zero);
              }
            }
            outside.requestFocus();
            await t.pump();
            expect(t.screen.lines.first, '界🙂e\u0301hint');
            focus.requestFocus();
            await t.pump();
            for (var update = 0; update < 1000; update++) {
              controller.text = 'update$update';
            }
            await t.pump();
            expect(t.screen.lines.first, 'update999');
            controller.clear();
            await t.pump();
            expect(t.screen.lines.first, '${gap ? ' ' : ''}界🙂e\u0301hint');
            await t.paste('界🙂e\u0301');
            expect(controller.text, '界🙂e\u0301');
            expect(t.screen.lines.first, '界🙂e\u0301');
          } finally {
            t.dispose();
            controller.dispose();
            focus.dispose();
            outside.dispose();
          }
        },
      );

      testWidgets(
        'gap=$gap preserves unbounded height and bounded-width requirement',
        (t) async {
          await t.pumpWidget(
            Column(
              children: [
                TextArea(
                  autofocus: true,
                  placeholder: 'hint',
                  placeholderGap: gap,
                ),
              ],
            ),
          );
          expect(t.screen.lines.first, '${gap ? ' ' : ''}hint');
          await t.pumpWidget(
            Row(
              children: [TextArea(placeholder: 'hint', placeholderGap: gap)],
            ),
          );
          expect(t.screen, shows('A TextArea needs a bounded width.'));
        },
      );
    }
  });

  _testerAreaCases();
  for (final size in [_wide, _narrow]) {
    group('TextArea at ${size.width}x${size.height}', () {
      testWidgets('shows its placeholder from the first cell', (t) async {
        await t.pumpWidget(
          _framed(const TextArea(placeholder: 'Write a message')),
          size: size,
        );
        expect(t.screen.lines.take(3), ['title', 'Write a message', 'below']);
        expect(t.screen.styleAt(0, 1), Style.dim);
      });

      testWidgets('draws a blank cursor before the placeholder when focused', (
        t,
      ) async {
        await t.pumpWidget(
          _framed(const TextArea(autofocus: true, placeholder: 'Write')),
          size: size,
        );
        expect(t.screen.lines[1], ' Write');
        expect(t.screen.buffer.cursor, const Offset(0, 1));
        expect(t.screen.styleAt(1, 1), Style.dim);
        // Placeholder takes no row of its own and is not text.
        expect(t.screen.lines[2], 'below');
      });

      testWidgets('without a placeholder gap, the cursor sits on the '
          "placeholder's first cell; nothing else moves", (t) async {
        await t.pumpWidget(
          _framed(
            const TextArea(
              autofocus: true,
              placeholder: 'Write',
              placeholderGap: false,
            ),
          ),
          size: size,
        );
        expect(t.screen.lines[1], 'Write');
        expect(t.screen.buffer.cursor, const Offset(0, 1));
        expect(t.screen.styleAt(0, 1), Style.dim);
        expect(t.screen.lines[2], 'below');

        // Unfocused and empty, or focused with text, both ways are one.
        for (final gap in [true, false]) {
          await t.pumpWidget(
            _framed(TextArea(placeholder: 'Write', placeholderGap: gap)),
            size: size,
          );
          expect(t.screen.lines[1], 'Write');
          await t.pumpWidget(
            _framed(
              TextArea(
                controller: TextAreaController(text: 'hi'),
                autofocus: true,
                placeholder: 'Write',
                placeholderGap: gap,
              ),
            ),
            size: size,
          );
          expect(t.screen.lines[1], 'hi');
          expect(t.screen.buffer.cursor, const Offset(2, 1));
        }
      });

      testWidgets('types, wraps by cell and keeps wide graphemes whole', (
        t,
      ) async {
        final c = TextAreaController();
        await t.pumpWidget(
          _framed(TextArea(controller: c, autofocus: true)),
          size: size,
        );
        final w = size.width;
        await t.type('${'a' * (w - 1)}界b');
        // 界 does not fit the first row's last cell: it starts the second.
        expect(t.screen.lines[1], 'a' * (w - 1));
        expect(t.screen.lines[2], '界b');
        expect(t.screen.buffer.cursor, const Offset(3, 2));
        expect(t.screen.lines[3], 'below');
        await t.press('left left');
        // The terminal cursor claims the leading cell of a wide grapheme.
        expect(t.screen.buffer.cursor, const Offset(0, 2));
        expect(t.screen.styleAt(1, 2).isInverse, isFalse);
        expect(t.screen.styleAt(2, 2).isInverse, isFalse);
      });

      testWidgets('grows to maxHeight, then scrolls to the cursor', (t) async {
        final c = TextAreaController();
        await t.pumpWidget(
          _framed(TextArea(controller: c, autofocus: true, maxHeight: 4)),
          size: size,
        );
        for (var i = 1; i <= 6; i++) {
          if (i > 1) await t.press('shift+enter');
          await t.type('line $i');
        }
        expect(t.screen.lines.take(6), [
          'title',
          'line 3',
          'line 4',
          'line 5',
          'line 6',
          'below',
        ]);
        expect(c.rowOffset, 2);
        await t.press('up up up');
        expect(t.screen.lines[1], 'line 3');
        expect((c.cursorLine, c.cursorColumn), (2, 6));
        await t.press('up');
        expect(t.screen.lines.take(5), [
          'title',
          'line 2',
          'line 3',
          'line 4',
          'line 5',
        ]);
        expect(c.rowOffset, 1);
      });

      testWidgets('hides only the cursor when unfocused', (t) async {
        final c = TextAreaController(text: _sixLines());
        final node = FocusNode();
        await t.pumpWidget(
          _framed(
            TextArea(
              controller: c,
              focusNode: node,
              autofocus: true,
              maxHeight: 4,
            ),
          ),
          size: size,
        );
        final focused = t.screen.lines.take(6).toList();
        expect(t.screen.buffer.cursor, const Offset(6, 4));
        node.unfocus();
        await t.pump();
        expect(t.screen.lines.take(6), focused);
        expect(t.screen.buffer.cursor, isNull);
        node.dispose();
      });

      testWidgets('keeps text and cursor through a narrow resize', (t) async {
        final c = TextAreaController(text: 'x' * 100)..cursor = 50;
        await t.pumpWidget(
          _framed(TextArea(controller: c, autofocus: true, maxHeight: 2)),
          size: size,
        );
        await t.resize(const Size(20, 10));
        expect((c.text.length, c.cursor), (100, 50));
        // Row 2 of 5 holds offset 50 at column 10.
        expect(t.screen.lines.take(4), ['title', 'x' * 20, 'x' * 20, 'below']);
        expect(c.rowOffset, 1);
        expect(t.screen.buffer.cursor, const Offset(10, 2));
      });
    });
  }

  group('TextArea keys', () {
    testWidgets('Enter submits without clearing; a backslash continues', (
      t,
    ) async {
      final submitted = <String>[];
      final c = TextAreaController();
      await t.pumpWidget(
        TextArea(controller: c, autofocus: true, onSubmit: submitted.add),
      );
      await t.type('one');
      await t.press('enter');
      expect(submitted, ['one']);
      expect(c.text, 'one');
      await t.type(r'\');
      await t.press('enter');
      expect(c.text, 'one\n');
      expect(submitted, ['one']);
    });

    testWidgets('shift, alt and ctrl with enter, and ctrl+j, add a line', (
      t,
    ) async {
      final c = TextAreaController(text: 'ab')..cursor = 1;
      await t.pumpWidget(TextArea(controller: c, autofocus: true));
      for (final keys in ['shift+enter', 'alt+enter', 'ctrl+enter', 'ctrl+j']) {
        await t.press(keys);
      }
      expect(c.text, 'a\n\n\n\nb');
      expect(c.cursor, 5);
    });

    testWidgets('edits by word and by line', (t) async {
      final c = TextAreaController();
      await t.pumpWidget(TextArea(controller: c, autofocus: true));
      await t.type('one two');
      await t.press('shift+enter');
      await t.type('three four');
      await t.press('alt+b');
      expect(c.cursorColumn, 6);
      // Reaching a line start, a word move left stops at the line above's
      // end, as OpenTUI does.
      await t.press('alt+left');
      expect((c.cursorLine, c.cursorColumn), (0, 7));
      await t.press('alt+f alt+right');
      expect((c.cursorLine, c.cursorColumn), (1, 6));
      await t.press('ctrl+a');
      expect((c.cursorLine, c.cursorColumn), (1, 0));
      await t.press('ctrl+e ctrl+w');
      expect(c.text, 'one two\nthree ');
      // The word before reaches the line's start, so the break goes too.
      await t.press('alt+backspace');
      expect(c.text, 'one two');
      await t.press('shift+enter');
      await t.type('z');
      await t.press('up ctrl+e ctrl+u');
      expect(c.text, '\nz');
      await t.type('xy');
      await t.press('left ctrl+k');
      expect(c.text, 'x\nz');
      await t.press('down ctrl+e backspace');
      expect(c.text, 'x\n');
      await t.press('backspace shift+backspace right delete');
      expect(c.text, '');
    });

    testWidgets('a paste goes in whole, line breaks normalized', (t) async {
      final submitted = <String>[];
      final changes = <String>[];
      final c = TextAreaController();
      await t.pumpWidget(
        TextArea(
          controller: c,
          autofocus: true,
          onSubmit: submitted.add,
          onChanged: changes.add,
        ),
      );
      await t.paste('a\r\nb\rc\n');
      expect(c.text, 'a\nb\nc\n');
      expect(submitted, isEmpty);
      expect(changes, ['a\nb\nc\n']);
    });

    testWidgets('onChanged hears edits, not moves', (t) async {
      final changes = <String>[];
      await t.pumpWidget(TextArea(autofocus: true, onChanged: changes.add));
      await t.type('ab');
      await t.press('left right left');
      await t.press('backspace');
      expect(changes, ['a', 'ab', 'b']);
    });

    testWidgets('onKey sees keys first; true takes them', (t) async {
      final seen = <String>[];
      final c = TextAreaController();
      await t.pumpWidget(
        TextArea(
          controller: c,
          autofocus: true,
          onKey: (e) {
            seen.add('${e.combo}');
            return e.combo.toString() == 'tab' || e.combo.toString() == 'x';
          },
        ),
      );
      await t.type('axb');
      await t.press('tab enter');
      expect(c.text, 'ab');
      expect(seen, ['a', 'x', 'b', 'tab', 'enter']);
    });

    testWidgets('unhandled keys reach the actions above untouched', (t) async {
      final hits = <String>[];
      final c = TextAreaController(text: 'abc')..cursor = 1;
      var hooked = 0;
      await t.pumpWidget(
        Actions(
          bindings: [
            Binding('home', 'Top', () => hits.add('home')),
            Binding('end', 'Bottom', () => hits.add('end')),
            Binding('ctrl+a', 'All', () => hits.add('ctrl+a')),
            Binding('x', 'Ex', () => hits.add('x')),
          ],
          child: TextArea(
            controller: c,
            autofocus: true,
            unhandledKeys: const {'home', 'end', 'ctrl+a', 'x'},
            onKey: (_) {
              hooked++;
              return false;
            },
          ),
        ),
      );
      await t.press('home end ctrl+a');
      await t.type('x');
      expect(hits, ['home', 'end', 'ctrl+a', 'x']);
      expect((c.text, c.cursor), ('abc', 1));
      expect(hooked, 0);
    });

    testWidgets('Home and End go to the text\'s ends when not left out', (
      t,
    ) async {
      final c = TextAreaController(text: 'ab\nc')..cursor = 1;
      await t.pumpWidget(
        TextArea(controller: c, autofocus: true, unhandledKeys: const {}),
      );
      await t.press('home');
      expect(c.cursor, 0);
      await t.press('end');
      expect(c.cursor, 4);
    });

    testWidgets('an unparsable unhandled key fails on mount', (t) async {
      await expectLater(
        t.pumpWidget(const TextArea(unhandledKeys: {'bogus+x'})),
        throwsA(anything),
      );
    });

    testWidgets('up and down at an edge call onEdge once', (t) async {
      final edges = <TextAreaDirection>[];
      final above = <String>[];
      final c = TextAreaController(text: 'one\ntwo');
      await t.pumpWidget(
        Actions(
          bindings: [
            Binding('up', 'Above up', () => above.add('up')),
            Binding('down', 'Above down', () => above.add('down')),
          ],
          child: TextArea(controller: c, autofocus: true, onEdge: edges.add),
        ),
      );
      await t.press('down');
      expect(edges, [TextAreaDirection.down]);
      await t.press('up');
      expect(c.cursorLine, 0);
      expect(edges, [TextAreaDirection.down]);
      await t.press('up');
      expect(edges, [TextAreaDirection.down, TextAreaDirection.up]);
      expect(above, isEmpty);
      expect(c.cursorLine, 0);
    });

    testWidgets('up and down at an edge go on without onEdge', (t) async {
      final above = <String>[];
      final c = TextAreaController(text: 'one\ntwo');
      await t.pumpWidget(
        Actions(
          bindings: [
            Binding('up', 'Above up', () => above.add('up')),
            Binding('down', 'Above down', () => above.add('down')),
          ],
          child: TextArea(controller: c, autofocus: true),
        ),
      );
      await t.press('down');
      expect(above, ['down']);
      await t.press('up');
      expect(above, ['down']);
      expect(c.cursorLine, 0);
      await t.press('up');
      expect(above, ['down', 'up']);
    });

    testWidgets('without room it draws nothing and makes no edge', (t) async {
      final edges = <TextAreaDirection>[];
      final above = <String>[];
      final c = TextAreaController(text: 'one\ntwo')..cursor = 2;
      await t.pumpWidget(
        Actions(
          bindings: [Binding('up', 'Above up', () => above.add('up'))],
          child: Column(
            children: [
              SizedBox(
                height: 0,
                child: TextArea(
                  controller: c,
                  autofocus: true,
                  onEdge: edges.add,
                ),
              ),
              Text('after'),
            ],
          ),
        ),
      );
      expect(t.screen.lines.first, 'after');
      await t.press('up');
      expect(edges, isEmpty);
      expect(above, ['up']);
      expect((c.text, c.cursor), ('one\ntwo', 2));
    });

    testWidgets('the shortcuts panel lists its edits', (t) async {
      await t.pumpWidget(
        const Column(children: [TextArea(autofocus: true), KeyHelp()]),
        size: const Size(3000, 4),
      );
      for (final description in [
        'enter Submit',
        // One action's keys are one entry.
        'shift+enter/alt+enter/ctrl+enter/ctrl+j Insert newline',
        'alt+b/alt+left/ctrl+left Move cursor back a word',
        'alt+f/alt+right/ctrl+right Move cursor forward a word',
        'ctrl+w/alt+backspace/ctrl+backspace Delete word before cursor',
        'ctrl+u Delete to line start',
        'ctrl+k Delete to line end',
        'ctrl+a Move to line start',
        'ctrl+e Move to line end',
        'super+left/alt+a Move to row start',
        'super+right/alt+e Move to row end',
        'delete/ctrl+d/shift+delete Delete character after cursor',
      ]) {
        expect(t.screen, shows(description));
      }
      // Home and End are left out by default; shift with them selects.
      expect(t.screen, shows('  super+up Move to text start'));
      expect(t.screen, shows('  super+down Move to text end'));
      expect(t.screen, shows('shift+home/shift+super+up Select to text start'));
    });
  });

  group('TextArea and its controller', () {
    testWidgets('a widget beside it reads the geometry of the same frame', (
      t,
    ) async {
      final c = TextAreaController(text: _sixLines());
      await t.pumpWidget(
        Column(
          children: [
            ListenableBuilder(
              listenable: c,
              builder: (context) => Text('offset ${c.rowOffset}'),
            ),
            TextArea(controller: c, autofocus: true, maxHeight: 4),
          ],
        ),
      );
      // Settled in the first frame, not the next.
      expect(t.screen.lines.first, 'offset 2');
      await t.press('up up up up');
      expect(t.screen.lines.first, 'offset 1');
    });

    testWidgets('lastLayout is what the area settled, with less room', (
      t,
    ) async {
      final c = TextAreaController(text: _sixLines());
      expect(c.lastLayout, isNull);
      final seen = <String>[];
      await t.pumpWidget(
        Column(
          children: [
            ListenableBuilder(
              listenable: c,
              builder: (context) {
                final l = c.lastLayout;
                final text = l == null
                    ? 'none'
                    : '${l.rowOffset} ${l.height} ${l.rows.length}';
                seen.add(text);
                return Text(text);
              },
            ),
            // Two rows of room for an area that would grow to four.
            SizedBox(
              height: 2,
              child: TextArea(controller: c, autofocus: true, maxHeight: 4),
            ),
          ],
        ),
        size: const Size(30, 10),
      );
      expect(t.screen.lines.take(3), ['4 2 6', 'line 5', 'line 6']);
      expect((c.lastLayout!.width, c.lastLayout!.height), (30, 2));
      // Up moves in the two rows shown: one more scrolls by one.
      await t.press('up');
      expect(t.screen.lines.take(3), ['4 2 6', 'line 5', 'line 6']);
      await t.press('up');
      expect(t.screen.lines.take(3), ['3 2 6', 'line 4', 'line 5']);
      expect(seen.first, 'none');
    });

    for (final size in [_wide, _narrow]) {
      testWidgets('unkeyed area survives shifting siblings at $size', (
        t,
      ) async {
        final c = TextAreaController(text: 'draft');
        final before = ValueNotifier(0);
        final changes = <String>[];
        try {
          await t.pumpWidget(
            ListenableBuilder(
              listenable: before,
              builder: (context) => Column(
                children: [
                  for (var i = 0; i < before.value; i++) Text('above $i'),
                  TextArea(
                    controller: c,
                    autofocus: true,
                    onChanged: changes.add,
                  ),
                  Text('below'),
                ],
              ),
            ),
            size: size,
          );
          for (final count in [1, 2, 0, 2, 1, 0]) {
            before.value = count;
            await t.pump();
            await t.type('x');
            expect(t.screen.lines[count], c.text);
            expect(t.screen.buffer.cursor, Offset(c.cursor, count));
          }
          expect(c.text, 'draftxxxxxx');
          expect(changes, hasLength(6));
          await t.pumpWidget(Text('removed'));
          c.insert('late');
          expect(changes, hasLength(6));
          await t.pumpWidget(TextArea(controller: c, autofocus: true));
          await t.type('y');
          expect(c.text, 'draftxxxxxxlatey');
        } finally {
          t.dispose();
          before.dispose();
          c.dispose();
        }
      });
    }

    testWidgets('one controller cannot serve two areas', (t) async {
      final c = TextAreaController();
      await expectLater(
        t.pumpWidget(
          Column(
            children: [
              TextArea(controller: c),
              TextArea(controller: c),
            ],
          ),
        ),
        throwsStateError,
      );
    });

    testWidgets('a replaced controller is let go of', (t) async {
      final first = TextAreaController(text: 'first');
      final second = TextAreaController(text: 'second');
      final which = ValueNotifier(first);
      final changes = <String>[];
      await t.pumpWidget(
        ListenableBuilder(
          listenable: which,
          builder: (context) => TextArea(
            controller: which.value,
            autofocus: true,
            onChanged: changes.add,
          ),
        ),
      );
      expect(t.screen.lines.first, 'first');
      which.value = second;
      await t.pump();
      expect(t.screen.lines.first, 'second');
      first.text = 'gone';
      await t.pump();
      expect(changes, isEmpty);
      // The first may now serve another area.
      await t.pumpWidget(TextArea(controller: first));
      expect(t.screen.lines.first, 'gone');
    });

    testWidgets('disposes only what it made', (t) async {
      final c = TextAreaController(text: 'kept');
      final node = FocusNode();
      await t.pumpWidget(TextArea(controller: c, focusNode: node));
      await t.pumpWidget(Text('gone'));
      c.text = 'still usable';
      expect(c.isDisposed, isFalse);
      expect(node.isDisposed, isFalse);
      node.dispose();
    });
  });
}

void _testerAreaCases() {
  group('tester: TextArea boundary and lifecycle integration', () {
    for (final size in [_wide, _narrow]) {
      testWidgets(
        'emoji and combining marks stay whole at wrap edges at $size',
        (t) async {
          final c = TextAreaController();
          try {
            await t.pumpWidget(
              TextArea(controller: c, autofocus: true),
              size: size,
            );
            await t.paste('${'x' * (size.width - 1)}👩‍💻e\u0301');
            expect(t.screen.lines[0], 'x' * (size.width - 1));
            expect(t.screen.lines[1], '👩‍💻e\u0301');
            await t.press('left left');
            expect(t.screen.buffer.cursor, const Offset(0, 1));
            expect(t.screen.styleAt(1, 1).isInverse, isFalse);
            await t.press('right delete');
            expect(c.text, '${'x' * (size.width - 1)}👩‍💻');
            await t.press('backspace');
            expect(c.text, 'x' * (size.width - 1));
          } finally {
            t.dispose();
            c.dispose();
          }
        },
      );

      testWidgets('default Home End scroll the surrounding list at $size', (
        t,
      ) async {
        final scroll = ScrollController();
        final c = TextAreaController(text: 'draft')..cursor = 2;
        var hooks = 0;
        try {
          await t.pumpWidget(
            Actions(
              bindings: scrollBindings(scroll),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: 100,
                      itemBuilder: (context, i) => Text('row $i'),
                    ),
                  ),
                  TextArea(
                    controller: c,
                    autofocus: true,
                    onKey: (_) {
                      hooks++;
                      return false;
                    },
                  ),
                ],
              ),
            ),
            size: size,
          );
          await t.press('end');
          expect(t.screen, shows('row 99'));
          expect(scroll.offset, greaterThan(0));
          await t.press('home');
          expect(scroll.offset, 0);
          expect(t.screen.lines.first, 'row 0');
          expect((c.text, c.cursor, hooks), ('draft', 2, 0));
        } finally {
          t.dispose();
          c.dispose();
          scroll.dispose();
        }
      });
    }

    testWidgets(
      'zero and one cell recover without history edges after resize',
      (t) async {
        final c = TextAreaController(text: '界👩‍💻e\u0301');
        final edges = <TextAreaDirection>[];
        try {
          await t.pumpWidget(
            TextArea(controller: c, autofocus: true, onEdge: edges.add),
            size: const Size(0, 0),
          );
          await t.press('up down');
          expect(edges, isEmpty);
          expect(c.cursor, 3);
          await t.resize(const Size(1, 1));
          expect(c.text, '界👩‍💻e\u0301');
          await t.resize(_narrow);
          expect(t.screen.lines.first, '界👩‍💻e\u0301');
          expect(c.cursor, 3);
        } finally {
          t.dispose();
          c.dispose();
        }
      },
    );

    testWidgets('unbounded height works and unbounded width is rejected', (
      t,
    ) async {
      final c = TextAreaController(text: _sixLines());
      try {
        await t.pumpWidget(
          Column(children: [TextArea(controller: c, maxHeight: 4)]),
        );
        expect(t.screen.lines.take(4), [
          'line 3',
          'line 4',
          'line 5',
          'line 6',
        ]);
        await t.pumpWidget(const Row(children: [TextArea()]));
        expect(t.screen, shows('A TextArea needs a bounded width.'));
      } finally {
        t.dispose();
        c.dispose();
      }
    });

    testWidgets('history hook can own arrows until editing resumes', (t) async {
      final c = TextAreaController(text: 'first\nsecond')..cursor = 2;
      var walking = true;
      var history = 0;
      final edges = <TextAreaDirection>[];
      try {
        await t.pumpWidget(
          TextArea(
            controller: c,
            autofocus: true,
            onEdge: edges.add,
            onKey: (event) {
              if (walking && (event.key == 'up' || event.key == 'down')) {
                history++;
                return true;
              }
              return false;
            },
          ),
        );
        await t.press('down up');
        expect((history, c.cursor), (2, 2));
        walking = false;
        await t.type('x');
        await t.press('down');
        expect(c.cursorLine, 1);
        await t.press('down');
        expect(edges, [TextAreaDirection.down]);
      } finally {
        t.dispose();
        c.dispose();
      }
    });

    testWidgets(
      'thousand updates settle once drawn and detach with a live stream',
      (t) async {
        final c = TextAreaController();
        final events = StreamController<String>.broadcast(sync: true);
        final subscription = events.stream.listen((text) => c.text = text);
        final changes = <String>[];
        try {
          await t.pumpWidget(
            TextArea(
              controller: c,
              autofocus: true,
              maxHeight: 2,
              onChanged: changes.add,
            ),
            size: _wide,
          );
          for (var i = 0; i < 1000; i++) {
            events.add('line $i\n界e\u0301');
          }
          await t.pump();
          expect(t.screen.lines.take(2), ['line 999', '界e\u0301']);
          expect(changes, hasLength(1000));
          await t.pumpWidget(Text('removed'));
          events.add('late');
          await t.pump();
          expect(changes, hasLength(1000));
          expect(t.screen.lines.first, 'removed');
          expect(c.text, 'late');
        } finally {
          t.dispose();
          await subscription.cancel();
          await events.close();
          c.dispose();
        }
      },
    );

    testWidgets(
      'focus replacement detaches the old node and preserves geometry',
      (t) async {
        final c = TextAreaController(text: _sixLines());
        final first = FocusNode();
        final second = FocusNode();
        final useSecond = ValueNotifier(false);
        try {
          await t.pumpWidget(
            ListenableBuilder(
              listenable: useSecond,
              builder: (context) => TextArea(
                controller: c,
                focusNode: useSecond.value ? second : first,
                autofocus: true,
                maxHeight: 4,
              ),
            ),
          );
          final before = t.screen.lines;
          useSecond.value = true;
          await t.pump();
          first.requestFocus();
          await t.pump();
          second.requestFocus();
          await t.pump();
          expect(t.screen.lines, before);
          expect(c.rowOffset, 2);
          expect(t.screen.buffer.cursor, const Offset(6, 3));
          second.unfocus();
          await t.pump();
          expect(t.screen.buffer.cursor, isNull);
          second.requestFocus();
          await t.pump();
          expect(t.screen.buffer.cursor, const Offset(6, 3));
        } finally {
          t.dispose();
          useSecond.dispose();
          first.dispose();
          second.dispose();
          c.dispose();
        }
      },
    );

    testWidgets(
      'editing keys stay local and unlisted names reach ancestors unchanged',
      (t) async {
        final keys = [
          'ctrl+d',
          'ctrl+b',
          'ctrl+f',
          'pageup',
          'pagedown',
          'shift+left',
          'shift+right',
          'escape',
        ];
        final hits = <String>[];
        final c = TextAreaController(text: 'draft');
        try {
          await t.pumpWidget(
            Actions(
              bindings: [
                for (final key in keys) Binding(key, key, () => hits.add(key)),
              ],
              child: TextArea(controller: c, autofocus: true),
            ),
          );
          for (final key in keys) {
            await t.press(key);
          }
          expect(hits, ['pageup', 'pagedown', 'escape']);
          expect(c.text, 'draft');
        } finally {
          t.dispose();
          c.dispose();
        }
      },
    );

    for (final fallback in [false, true]) {
      testWidgets(
        'parser distinguishes submission and paste with fallback $fallback',
        (t) async {
          final c = TextAreaController();
          final sent = <String>[];
          final parser = InputParser()..linefeedIsEnter = fallback;
          try {
            await t.pumpWidget(
              TextArea(controller: c, autofocus: true, onSubmit: sent.add),
            );
            for (final bytes in ['a', '\n', 'b', '\r']) {
              for (final event in parser.feed(bytes)) {
                if (event is KeyEvent) t.host.handleKey(event);
              }
              await t.pump();
            }
            expect(sent, fallback ? ['a', 'ab'] : ['a\nb']);
            final previous = c.text;
            for (final bytes in ['\x1b[20', '0~x\r', '\ny\n', '\x1b[201~']) {
              for (final event in parser.feed(bytes)) {
                if (event is PasteEvent) t.host.handlePaste(event.text);
              }
            }
            await t.pump();
            expect(c.text, '${previous}x\ny\n');
            expect(sent, fallback ? ['a', 'ab'] : ['a\nb']);
          } finally {
            t.dispose();
            c.dispose();
          }
        },
      );
    }

    testWidgets(
      'escape sequences pasted as text cannot inject terminal styles',
      (t) async {
        final c = TextAreaController();
        try {
          await t.pumpWidget(TextArea(controller: c, autofocus: true));
          await t.paste('a\x1b[31mb\x1b[0mc');
          expect(c.text, 'a\x1b[31mb\x1b[0mc');
          expect(t.screen.text, isNot(contains('\x1b')));
          for (var x = 0; x < 20; x++) {
            expect(t.screen.styleAt(x, 0).fg, isNot(const IndexedColor(1)));
          }
        } finally {
          t.dispose();
          c.dispose();
        }
      },
    );
  });

  group('CTUI-163: super+left and super+right move in the shown row', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('wrapped rows, the wrap boundary, and ctrl+a/e on the '
          'logical line at $size', (t) async {
        final c = TextAreaController(
          text: '${List.generate(120, (i) => 'w$i').join(' ')}\nnext',
        );
        await t.pumpWidget(
          TextArea(controller: c, autofocus: true),
          size: size,
        );
        await t.pump();
        final rows = c.lastLayout!.rows;
        expect(rows.where((r) => r.line == 0).length, greaterThan(2));
        c.cursor = rows[1].start + 3;
        await t.pump();
        expect(c.lastLayout!.rows.map((r) => r.end), rows.map((r) => r.end));
        await t.press('super+left');
        expect(c.cursor, rows[1].start);
        expect(c.lastLayout!.cursorRow, 1);
        await t.press('super+right');
        expect(c.cursor, rows[1].end - 1);
        expect(c.lastLayout!.cursorRow, 1);
        await t.press('super+right');
        expect(c.cursor, rows[1].end - 1);
        // At the boundary the cursor is drawn on the next row, and moves in
        // it.
        c.cursor = rows[1].end;
        await t.pump();
        expect(c.lastLayout!.cursorRow, 2);
        await t.press('super+left');
        expect(c.cursor, rows[2].start);
        // The line's last row ends at the line's end.
        final last = rows.lastWhere((r) => r.line == 0);
        c.cursor = last.start;
        await t.pump();
        await t.press('super+right');
        expect(c.cursor, last.end);
        await t.press('ctrl+a');
        expect(c.cursor, 0);
        await t.press('ctrl+e');
        expect(c.cursor, last.end);
        await t.press('right');
        await t.press('super+right');
        expect(c.text.substring(c.cursor - 4, c.cursor), 'next');
      });

      testWidgets('wide graphemes, never split, at $size', (t) async {
        final c = TextAreaController(text: '日' * 200);
        await t.pumpWidget(
          Row(
            children: [
              SizedBox(
                width: 9,
                child: TextArea(controller: c, autofocus: true),
              ),
            ],
          ),
          size: size,
        );
        await t.pump();
        final rows = c.lastLayout!.rows;
        // Four wide graphemes in nine cells, the ninth left empty.
        expect(rows.first.end - rows.first.start, 4);
        c.cursor = 1;
        await t.pump();
        await t.press('super+right');
        expect(c.cursor, 3);
        await t.press('super+left');
        expect(c.cursor, 0);
      });
    }
  });
}
