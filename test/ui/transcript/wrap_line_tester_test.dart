import 'package:chord/ui/transcript/message.dart';
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

List<String> _texts(List<List<Glyph>> rows) => [
  for (final row in rows) row.map((g) => g.text).join(),
];

void main() {
  group('tester: port wrapLine original boundaries', () {
    test('original over-indented message leaves one cell on every row', () {
      // Carried from the original message_test's 80-space indent case.
      expect(_texts(wrapLine(TextSpan('${' ' * 80}two words'), 76)), [
        '${' ' * 75}t',
        ...'wowords'.split(''),
      ]);
      expect(_texts(wrapLine(const TextSpan('  indented'), 76)), [
        '  indented',
      ]);
    });

    test('zero and negative room use the original one-cell minimum', () {
      for (final width in [-1, 0, 1]) {
        expect(_texts(wrapLine(const TextSpan('  ab/c'), width)), [
          'a',
          'b',
          '/',
          'c',
        ]);
        expect(_texts(wrapLine(const TextSpan(''), width)), ['']);
        expect(_texts(wrapLine(const TextSpan('   '), width)), ['']);
      }
    });

    test('tab indentation stays inside the room by the owner decision', () {
      // Deliberate original-slip correction: the original measures its
      // preserved tab as zero cells, then OpenTUI draws past that room.
      for (final text in ['\tabc', ' \tabc']) {
        final rows = wrapLine(TextSpan(text), 5);
        expect(_texts(rows), ['    a', 'b', 'c']);
        expect(
          rows.map(TextLayout.lineWidth),
          everyElement(lessThanOrEqualTo(5)),
        );
      }
    });

    test('Unicode indent split across styles keeps the body style', () {
      final rows = wrapLines(
        const TextSpan(
          '',
          children: [
            TextSpan(' \u2003', style: Style(bold: true)),
            TextSpan('\u00A0ab/中/👩‍💻/e\u0301\n', style: Style(italic: true)),
            TextSpan('  tail', style: Style(underline: true)),
          ],
        ),
        8,
      );
      expect(_texts(rows), [' \u2003\u00A0ab/中', '/👩‍💻/e\u0301', '  tail']);
      expect(rows.first.take(2).every((g) => g.style.isBold), isTrue);
      expect(rows[1].every((g) => g.style.isItalic), isTrue);
      expect(rows.last.every((g) => g.style.isUnderline), isTrue);
    });

    test('original multiline headline keeps indent but cuts URL words', () {
      // The original tools_test cases exercise wrapLine through headlineRows.
      expect(
        _texts(
          headlineRows(const Headline('Bash', arg: 'f\n    two words'), 10),
        ),
        ['Bash(f', '    two', 'words)'],
      );
      expect(
        _texts(
          headlineRows(
            const Headline('Fetch', arg: 'https://example.com/a'),
            10,
          ),
        ),
        ['Fetch(http', 's://exampl', 'e.com/a)'],
      );
    });

    test('unbounded room preserves Unicode body and ANSI styles', () {
      final rows = wrapLines(
        parseAnsi('\x1b[31m  中/👩‍💻/e\u0301\x1b[0m\nend'),
        unbounded,
      );
      expect(_texts(rows), ['  中/👩‍💻/e\u0301', 'end']);
      expect(rows.first.every((g) => g.style.fg == Colors.red), isTrue);
      expect(rows.last.every((g) => g.style.fg != Colors.red), isTrue);
    });
  });
}
