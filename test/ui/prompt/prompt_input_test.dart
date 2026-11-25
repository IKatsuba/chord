import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('rounded prompt has original geometry at $size', (t) async {
      final c = TextAreaController();
      final sent = <String>[];
      await t.pumpWidget(
        Column(
          children: [
            PromptInput(
              controller: c,
              windowRows: size.height,
              onSubmit: sent.add,
              onOlder: () {},
              onNewer: () {},
            ),
          ],
        ),
        size: size,
      );
      expect(t.screen.lines.take(4), [
        '',
        '╭${'─' * (size.width - 2)}╮',
        '│ › ${' ' * (size.width - 5)}│',
        '╰${'─' * (size.width - 2)}╯',
      ]);
      expect(c.lastLayout!.width, size.width - 6);
      expect(t.screen.buffer.cursor, const Offset(4, 2));
      expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
      expect(t.screen.styleAt(4, 2).isInverse, isFalse);
      await t.type('hello');
      await t.press('shift+enter');
      await t.type('there');
      await t.press('enter');
      expect(sent, ['hello\nthere']);
      expect(t.screen.lines[3], startsWith('│   there'));
    });

    testWidgets('prompt gutter follows scrolling and history edges at $size', (
      t,
    ) async {
      final c = TextAreaController(
        text: [for (var i = 0; i < 15; i++) 'line $i'].join('\n'),
      );
      var older = 0;
      var newer = 0;
      await t.pumpWidget(
        Column(
          children: [
            PromptInput(
              controller: c,
              windowRows: size.height,
              onSubmit: (_) {},
              onOlder: () => older++,
              onNewer: () => newer++,
            ),
          ],
        ),
        size: size,
      );
      expect(t.screen.lines[2], startsWith('│ ↑ '));
      await t.press('down');
      expect(newer, 1);
      c.cursor = 0;
      await t.pump();
      expect(t.screen.lines[2], startsWith('│ › '));
      expect(t.screen.lines[2 + c.lastLayout!.height - 1], startsWith('│ ↓ '));
      await t.press('up');
      expect(older, 1);
    });

    testWidgets('untouched recall walks from an interior row at $size', (
      t,
    ) async {
      final c = TextAreaController(text: 'one\ntwo\nthree')..cursor = 5;
      var older = 0;
      var newer = 0;
      await t.pumpWidget(
        Column(
          children: [
            PromptInput(
              controller: c,
              windowRows: size.height,
              walking: true,
              onSubmit: (_) {},
              onOlder: () => older++,
              onNewer: () => newer++,
            ),
          ],
        ),
        size: size,
      );
      await t.press('up down');
      expect((older, newer, c.cursor), (1, 1, 5));
    });

    // The original's box reads cmd+↑ and cmd+↓ as ↑ and ↓: history at the
    // text's edges or while walking, nothing on an interior row.
    for (final walking in [false, true]) {
      testWidgets('cmd arrows walk as arrows, walking $walking, at $size', (
        t,
      ) async {
        final c = TextAreaController(text: 'one\ntwo\nthree')..cursor = 5;
        var older = 0;
        var newer = 0;
        await t.pumpWidget(
          Column(
            children: [
              PromptInput(
                controller: c,
                windowRows: size.height,
                walking: walking,
                onSubmit: (_) {},
                onOlder: () => older++,
                onNewer: () => newer++,
              ),
            ],
          ),
          size: size,
        );
        await t.press('super+up super+down');
        expect(
          (older, newer, c.cursor, c.text),
          (walking ? 1 : 0, walking ? 1 : 0, 5, 'one\ntwo\nthree'),
        );
        if (walking) return;
        c.cursor = 0;
        await t.pump();
        await t.press('super+up');
        c.cursor = c.text.length;
        await t.pump();
        await t.press('super+down');
        expect((older, newer, c.text), (1, 1, 'one\ntwo\nthree'));
      });
    }
  }
  group('tester U6 prompt composition boundaries', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('cap and resize use the actual viewport at $size', (t) async {
        final c = TextAreaController(
          text: [for (var i = 0; i < 20; i++) 'row $i'].join('\n'),
        );
        addTearDown(c.dispose);
        await t.pumpWidget(
          LayoutBuilder(
            builder: (_, constraints) => Column(
              children: [
                PromptInput(
                  controller: c,
                  windowRows: constraints.maxHeight,
                  onSubmit: (_) {},
                  onOlder: () {},
                  onNewer: () {},
                ),
              ],
            ),
          ),
          size: size,
        );
        expect(c.lastLayout!.height, size.height == 40 ? 10 : 8);
        expect(t.screen.lines[2], startsWith('│ ↑ '));
        final cursor = c.cursor;
        await t.resize(const Size(12, 8));
        expect(c.lastLayout!.width, 6);
        expect(c.lastLayout!.height, 3);
        expect(c.cursor, cursor);
        expect(t.screen.lines[2], startsWith('│ ↑ '));
        expect(t.screen.lines[4], startsWith('│   '));
        await t.resize(size);
        expect(c.lastLayout!.height, size.height == 40 ? 10 : 8);
        expect(c.cursor, cursor);
      });

      testWidgets(
        'Unicode soft-wrap boundaries retain source and gutter at $size',
        (t) async {
          final c = TextAreaController(
            text: '${'a' * (size.width - 8)}界🙂e\u0301',
          );
          addTearDown(c.dispose);
          await t.pumpWidget(
            Column(
              children: [
                PromptInput(
                  controller: c,
                  windowRows: size.height,
                  onSubmit: (_) {},
                  onOlder: () {},
                  onNewer: () {},
                ),
              ],
            ),
            size: size,
          );
          final layout = c.lastLayout!;
          expect(layout.rows.first.text, '${'a' * (size.width - 8)}界');
          expect(layout.rows[1].text, '🙂e\u0301');
          expect(t.screen.lines[2], startsWith('│ › '));
          expect(t.screen.lines[3], startsWith('│   🙂e\u0301'));
          expect(layout.rows.map((r) => r.text).join(), c.text);
          await t.resize(const Size(10, 8));
          expect(c.lastLayout!.rows.map((r) => r.text).join(), c.text);
        },
      );

      testWidgets(
        'all newline aliases and continuation defer submission at $size',
        (t) async {
          final c = TextAreaController();
          addTearDown(c.dispose);
          final sent = <String>[];
          await t.pumpWidget(
            Column(
              children: [
                PromptInput(
                  controller: c,
                  windowRows: size.height,
                  onSubmit: sent.add,
                  onOlder: () {},
                  onNewer: () {},
                ),
              ],
            ),
            size: size,
          );
          for (final key in [
            'shift+enter',
            'alt+enter',
            'ctrl+enter',
            'ctrl+j',
          ]) {
            c.text = 'leftRIGHT';
            c.cursor = 4;
            await t.press(key);
            expect((c.text, c.cursor), ('left\nRIGHT', 5));
          }
          c.text = 'a\\b';
          c.cursor = 2;
          await t.press('enter');
          expect((c.text, c.cursor), ('a\nb', 2));
          expect(sent, isEmpty);
          await t.press('enter');
          expect(sent, ['a\nb']);
          expect(c.text, 'a\nb');
        },
      );
    }

    testWidgets('window scroll keys propagate while history is walking', (
      t,
    ) async {
      final c = TextAreaController(text: 'one\ntwo\nthree')..cursor = 5;
      addTearDown(c.dispose);
      final heard = <String>[];
      var history = 0;
      const keys = [
        'esc',
        'home',
        'end',
        'shift+home',
        'shift+end',
        'shift+up',
        'shift+down',
        'pageup',
        'pagedown',
        'shift+pageup',
        'shift+pagedown',
      ];
      await t.pumpWidget(
        Actions(
          bindings: [
            for (final key in keys)
              Binding(key, 'Outer $key', () => heard.add(key)),
          ],
          child: Column(
            children: [
              PromptInput(
                controller: c,
                windowRows: 24,
                walking: true,
                onSubmit: (_) {},
                onOlder: () => history++,
                onNewer: () => history++,
              ),
            ],
          ),
        ),
      );
      for (final key in keys) {
        await t.press(key);
      }
      expect(heard, keys);
      expect((history, c.cursor), (0, 5));
    });
  });
}
