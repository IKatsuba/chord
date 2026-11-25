import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

List<Glyph> laid(String text, int width) => TextLayout.compute(
  TextSpan(text),
  maxWidth: width,
  softWrap: false,
  overflow: TextOverflow.middle,
).lines.single;
String shown(String text, int width) =>
    laid(text, width).map((g) => g.text).join();
void main() {
  test('ASCII middle budgets match the original for zero and odd widths', () {
    const text = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    for (final (width, expected) in [
      (0, ''),
      (1, ''),
      (2, ''),
      (3, ''),
      (4, '...Z'),
      (5, 'A...Z'),
      (6, 'A...YZ'),
      (8, 'AB...XYZ'),
      (9, 'ABC...XYZ'),
    ]) {
      expect(shown(text, width), expected);
    }
    expect(shown(text, unbounded), text);
    expect(shown('', 0), '');
    expect(shown('abc', 3), 'abc');
  });
  test(
    'Unicode cuts retain whole graphemes without redistributing budgets',
    () {
      const text = 'abc日本語👩‍💻XYZ';
      for (final (width, expected) in [
        (10, 'abc...XYZ'),
        (11, 'abc...XYZ'),
        (12, 'abc...👩‍💻XYZ'),
        (13, 'abc日...👩‍💻XYZ'),
        (14, text),
      ]) {
        expect(shown(text, width), expected);
      }
      expect(shown('e\u0301abcdefg界', 7), 'e\u0301a...界');
      expect(shown('界abcdef界', 4), '...');
      expect(shown('a b    x z', 8), 'a ...x z');
    },
  );
  test('retained glyphs keep inline styles and marker takes resolved base', () {
    const base = Style.italic;
    final span = TextSpan(
      '',
      children: [
        TextSpan('ABCDEFGHIJKLM', style: Style(fg: IndexedColor(1))),
        TextSpan('NOPQRSTUVWXYZ', style: Style.bold),
      ],
    );
    final line = TextLayout.compute(
      span,
      base: base,
      maxWidth: 9,
      softWrap: false,
      overflow: TextOverflow.middle,
    ).lines.single;
    expect(line.map((g) => g.text).join(), 'ABC...XYZ');
    expect(line.first.style.fg, const IndexedColor(1));
    expect(line.last.style.isBold, isTrue);
    expect(line.sublist(3, 6).every((g) => g.style == base), isTrue);
  });
  test(
    'middle marks horizontal omission only and preserves ordinary ellipsis',
    () {
      final middle = TextLayout.compute(
        const TextSpan('short\nlast'),
        maxWidth: 8,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.middle,
      );
      expect(middle.lines.single.map((g) => g.text).join(), 'short');
      final ellipsis = TextLayout.compute(
        const TextSpan('ABCDEFGHIJ'),
        maxWidth: 5,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
      expect(ellipsis.lines.single.map((g) => g.text).join(), 'ABCD…');
    },
  );
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('rich ANSI inherited overflow and live mode updates at $size', (
      t,
    ) async {
      final mode = ValueNotifier(TextOverflow.middle);
      addTearDown(mode.dispose);
      await t.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: ListenableBuilder(
            listenable: mode,
            builder: (context) => SizedBox(
              width: 9,
              child: DefaultTextStyle(
                softWrap: false,
                maxLines: 1,
                overflow: mode.value,
                style: Style.italic,
                child: Text.ansi('\x1b[31mABCDEFGHIJKLMNOPQRSTUVWXYZ\x1b[0m'),
              ),
            ),
          ),
        ),
        size: size,
      );
      expect(t.screen.lines.first, 'ABC...XYZ');
      expect(t.screen.styleAt(0, 0).fg, const IndexedColor(1));
      expect(t.screen.styleAt(3, 0).fg, isNull);
      expect(t.screen.styleAt(3, 0).isItalic, isTrue);
      mode.value = TextOverflow.ellipsis;
      await t.pump();
      expect(t.screen.lines.first, 'ABCDEFGH…');
      mode.value = TextOverflow.clip;
      await t.pump();
      expect(t.screen.lines.first, 'ABCDEFGHI');
    });
  }
}
