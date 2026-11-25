import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/text_area.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final w = size.width;
    final h = size.height;
    final top = '┌${'─' * (w - 4)}┐';
    final bottom = '└${'─' * (w - 4)}┘';
    const hint = 'Enter sends · Shift+Enter adds a line · Ctrl+Q quits';

    testWidgets('frames an empty, focused editor at $size', (t) async {
      await t.pumpWidget(const TextAreaExample(), size: size);
      final lines = t.screen.lines;
      expect(lines.first, 'Text area');
      expect(lines[h - 6], ' $top');
      expect(lines[h - 5], ' │  Write a message${' ' * (w - 21)}│');
      expect(lines[h - 4], ' $bottom');
      expect(lines[h - 3], 'line 1, column 1 · rows 1–1 of 1');
      expect(lines[h - 2], hint);
      expect(lines[h - 1], startsWith('enter Submit'));
      // The blank cursor cell, then the dim placeholder.
      expect(t.screen.buffer.cursor, Offset(3, h - 5));
      expect(t.screen.styleAt(4, h - 5), Style.dim);
    });

    testWidgets('wraps at the window width less six at $size', (t) async {
      await t.pumpWidget(const TextAreaExample(), size: size);
      await t.type('${'a' * (w - 6)}b');
      final lines = t.screen.lines;
      expect(lines[h - 6], ' │ ${'a' * (w - 6)} │');
      expect(lines[h - 5], ' │ b${' ' * (w - 6)}│');
      expect(lines[h - 3], 'line 1, column ${w - 4} · rows 1–2 of 2');
    });

    testWidgets('scrolls four rows of six lines and labels them at $size', (
      t,
    ) async {
      await t.pumpWidget(const TextAreaExample(), size: size);
      for (var i = 1; i <= 6; i++) {
        if (i > 1) await t.press('shift+enter');
        await t.type('line $i');
      }
      String row(String text) => ' │ $text${' ' * (w - 6 - text.length)} │';
      var lines = t.screen.lines;
      expect(lines.sublist(h - 9, h - 3), [
        ' $top',
        row('line 3'),
        row('line 4'),
        row('line 5'),
        row('line 6'),
        ' $bottom',
      ]);
      expect(lines[h - 3], 'line 6, column 7 · rows 3–6 of 6');
      await t.press('up up up');
      expect(t.screen.lines[h - 3], 'line 3, column 7 · rows 3–6 of 6');
      await t.press('up');
      lines = t.screen.lines;
      expect(lines[h - 8], row('line 2'));
      expect(lines[h - 3], 'line 2, column 7 · rows 2–5 of 6');
    });

    testWidgets('sends above, clears, and quits at $size', (t) async {
      await t.pumpWidget(const TextAreaExample(), size: size);
      await t.type('hello');
      await t.press('shift+enter');
      await t.type('there');
      await t.press('enter');
      final lines = t.screen.lines;
      expect(lines.sublist(1, 4), ['', 'hello', 'there']);
      expect(lines[h - 5], ' │  Write a message${' ' * (w - 21)}│');
      expect(lines[h - 3], 'line 1, column 1 · rows 1–1 of 1');
      await t.press('ctrl+q');
      expect(t.exitRequested, isTrue);
    });
  }

  testWidgets('a narrow window rewraps and keeps the cursor', (t) async {
    await t.pumpWidget(const TextAreaExample(), size: const Size(80, 24));
    await t.type('x' * 60);
    await t.resize(const Size(40, 24));
    // 34 cells a row: 60 graphemes take two rows, the cursor at the end.
    expect(t.screen.lines[24 - 3], 'line 1, column 61 · rows 1–2 of 2');
    expect(t.screen.lines[24 - 6], ' │ ${'x' * 34} │');
    expect(t.screen.lines[24 - 5], ' │ ${'x' * 26}${' ' * 8} │');
  });
}
