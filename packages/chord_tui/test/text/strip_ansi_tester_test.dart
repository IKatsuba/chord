import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester: original ANSI ranges across styled boundaries', () {
    for (final (raw, clean) in [
      ('e\x1b[31m\u0301界\x1b[0mZ', 'e\u0301界Z'),
      ('e\u009b31m\u0301界\u009b0mZ', 'e\u0301界Z'),
      ('\x1b]8;;url\x1b\\👩‍💻\x1b]8;;\x07', '👩‍💻'),
      ('\u009b0m\u009d0;title\u009c界', '界'),
    ]) {
      test('every style split preserves clean text ${raw.codeUnits}', () {
        expect(stripAnsi(raw), clean);
        for (var split = 0; split <= raw.length; split++) {
          final span = TextSpan(
            '',
            children: [
              TextSpan(raw.substring(0, split), style: Style.bold),
              TextSpan(raw.substring(split)),
            ],
          );
          for (final width in [80, 120, unbounded]) {
            final layout = TextLayout.compute(span, maxWidth: width);
            expect(
              layout.lines.expand((row) => row).map((g) => g.text).join(),
              clean,
              reason: 'split $split, width $width',
            );
          }
        }
      });
    }

    test('standalone C1 OSC fast path agrees for styled and plain input', () {
      const raw = '\u009d0;title\x07';
      final plain = TextLayout.compute(const TextSpan(raw));
      final split = TextLayout.compute(
        const TextSpan(
          '',
          children: [TextSpan('\u009d'), TextSpan('0;title\x07')],
        ),
      );
      expect(stripAnsi(raw), raw);
      expect(
        split.lines.expand((row) => row).map((g) => (g.text, g.sourceOffset)),
        plain.lines.expand((row) => row).map((g) => (g.text, g.sourceOffset)),
      );
    });
  });
}
