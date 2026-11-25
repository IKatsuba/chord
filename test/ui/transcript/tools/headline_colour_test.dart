// A sent message's headline draws `@name` bold in the recipient's colour,
// as the original's headlineRows does, alike in the drawn rows and in the
// selection source's text; any other headline takes no colour.
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

/// Each character of [span] with the style it is drawn in.
List<(String, Style)> styled(TextSpan span, [Style style = Style.plain]) {
  final own = span.style == null ? style : style.merge(span.style!);
  return [
    for (final char in span.text.split('')) (char, own),
    for (final child in span.children) ...styled(child, own),
  ];
}

void main() {
  const lexer = RgbColor(196, 156, 255);
  const sent = Headline('lexer', sent: true, note: ' · queued');

  test('a sent headline draws @name bold in the colour, the rest without', () {
    final cells = styled(headlineSpan(sent, colour: lexer));
    expect(cells.map((c) => c.$1).join(), 'to @lexer · queued');
    for (final (char, style) in cells.sublist(3, 9)) {
      expect(style.fg, lexer, reason: char);
      expect(style.isBold, isTrue, reason: char);
    }
    for (final (char, style) in [...cells.take(3), ...cells.skip(9)]) {
      expect(style.fg, isNull, reason: char);
      expect(style.isDim, isTrue, reason: char);
    }
  });

  test('the wrapped rows carry the same colours as the span', () {
    for (final width in const [80, 120, 8]) {
      final rows = headlineRows(sent, width, colour: lexer);
      final drawn = [
        for (final row in rows)
          for (final glyph in row)
            if (glyph.text.trim().isNotEmpty) (glyph.text, glyph.style),
      ];
      final source = [
        for (final cell in styled(headlineSpan(sent, colour: lexer)))
          if (cell.$1.trim().isNotEmpty) cell,
      ];
      expect(drawn, source, reason: 'width $width');
    }
  });

  test('a tool headline takes no colour', () {
    final cells = styled(
      headlineSpan(const Headline('lexer', arg: 'x'), colour: lexer),
    );
    expect(cells.every((c) => c.$2.fg == null), isTrue);
  });
}
