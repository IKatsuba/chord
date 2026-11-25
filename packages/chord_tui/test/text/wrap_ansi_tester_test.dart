import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

List<String> _rows(TextLayout layout) => [
  for (final row in layout.lines) row.map((glyph) => glyph.text).join(),
];

void main() {
  group('tester: wrap-ansi Unicode and source boundaries', () {
    test('trimming retains NEL as JavaScript does', () {
      final layout = TextLayout.wrapAnsi(
        const TextSpan('\u0085a b'),
        1,
        hard: true,
        wordWrap: false,
      );
      expect(_rows(layout), ['\u0085a', 'b']);
      expect(layout.lines.first.first.sourceOffset, 0);
      expect(_rows(TextLayout.wrapAnsi(const TextSpan('\u0085'), 1)), [
        '\u0085',
      ]);
    });

    // Agent-free probes of the original's pinned wrap-ansi 10.0.2.
    // Widths below a wide glyph retain that whole glyph, as upstream does.
    for (final (source, width, expected) in <(String, int, List<String>)>[
      ('中/文 abc', 1, ['中', '/', '文', 'a', 'b', 'c']),
      ('中/文 abc', 5, ['中/文', 'abc']),
      ('a 👩‍💻👩‍💻 z', 1, ['a', '👩‍💻', '👩‍💻', 'z']),
      ('a 👩‍💻👩‍💻 z', 5, ['a', '👩‍💻👩‍💻', 'z']),
      ('a 👩‍💻👩‍💻 z', 8, ['a 👩‍💻👩‍💻 z']),
      ('\t中\tend', 5, ['中', 'end']),
      ('界\tZ\tX', 8, ['界', 'Z', 'X']),
      ('\u00A0a b', 1, ['\u00A0', 'a', 'b']),
      ('\u00A0a b', 5, ['a b']),
      ('a\u00A0 b', 1, ['a', 'b']),
      ('a \u200B b', 1, ['a \u200B', 'b']),
      ('a\n\n b\n', 1, ['a', '', 'b', '']),
      (' \r\n x', 5, ['', 'x']),
    ]) {
      test('$source at $width', () {
        expect(
          _rows(TextLayout.wrapAnsi(TextSpan(source), width, hard: true)),
          expected,
        );
      });
    }

    test('combining clusters split across styled spans stay whole', () {
      final layout = TextLayout.wrapAnsi(
        const TextSpan(
          '',
          children: [
            TextSpan('e', style: Style(bold: true)),
            TextSpan('\u0301/👩‍💻/中', style: Style(italic: true)),
          ],
        ),
        2,
        hard: true,
      );
      expect(_rows(layout), ['e\u0301/', '👩‍💻', '/', '中']);
      final glyphs = layout.lines.expand((row) => row).toList();
      expect(glyphs.first.text, 'e\u0301');
      expect(glyphs.first.style.isBold, isTrue);
      expect(glyphs.skip(1).every((g) => g.style.isItalic), isTrue);
      expect(glyphs.map((g) => g.sourceOffset), [0, 1, 2, 3, 4]);
      expect(layout.sourceText, 'e\u0301/👩‍💻/中');
    });

    test('tabs after wide glyphs keep style and repeated source offset', () {
      final layout = TextLayout.wrapAnsi(
        const TextSpan(
          '',
          children: [
            TextSpan('界'),
            TextSpan('\t', style: Style(bold: true)),
            TextSpan('Z\tX'),
          ],
        ),
        80,
        trim: false,
      );
      expect(_rows(layout), ['界      Z       X']);
      expect(layout.width, 17);
      final glyphs = layout.lines.single;
      expect(glyphs.skip(1).take(6).every((g) => g.style.isBold), isTrue);
      expect(
        glyphs.skip(1).take(6).map((g) => g.sourceOffset),
        everyElement(1),
      );
      expect(
        glyphs.skip(8).take(7).map((g) => g.sourceOffset),
        everyElement(3),
      );
      expect(layout.lineSources.single.start, 0);
      expect(layout.lineSources.single.end, 5);
      expect(layout.sourceText, '界\tZ\tX');
    });

    test('empty hard lines retain real newline provenance', () {
      final layout = TextLayout.wrapAnsi(
        const TextSpan('a\n\n b\n'),
        1,
        hard: true,
      );
      expect(
        [
          for (final s in layout.lineSources)
            (s.start, s.end, s.hardBreak, s.softBreak),
        ],
        [
          (0, 1, 1, false),
          (2, 2, 2, false),
          (4, 5, 5, false),
          (6, 6, null, false),
        ],
      );
    });

    test('negative columns throw and unbounded room preserves the source', () {
      expect(
        () => TextLayout.wrapAnsi(const TextSpan('a'), -1),
        throwsRangeError,
      );
      const source = '中/👩‍💻/e\u0301 longword';
      expect(_rows(TextLayout.wrapAnsi(const TextSpan(source), unbounded)), [
        source,
      ]);
    });
  });
}
