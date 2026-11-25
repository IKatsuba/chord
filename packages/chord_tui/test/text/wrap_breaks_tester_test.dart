import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:chord_tui/src/text/wrap_breaks.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

List<String> _rows(TextLayout layout) => [
  for (final row in layout.lines) row.map((glyph) => glyph.text).join(),
];

void main() {
  group('tester: word-wrap contract boundaries', () {
    test('remaining Unicode spaces and fullwidth punctuation wrap', () {
      for (final separator in [
        '\u2001',
        '\u2004',
        '\u2005',
        '\u2006',
        '\u2007',
        '\u2008',
      ]) {
        expect(
          _rows(
            TextLayout.compute(
              TextSpan('ab abc${separator}defghij'),
              maxWidth: 10,
            ),
          ),
          ['ab abc', 'defghij'],
          reason: 'whitespace U+${separator.runes.first.toRadixString(16)}',
        );
      }
      for (final punctuation in ['！', '：', '？']) {
        expect(
          _rows(
            TextLayout.compute(
              TextSpan('ab abc${punctuation}defghij'),
              maxWidth: 10,
            ),
          ),
          ['ab abc$punctuation', 'defghij'],
        );
      }
    });

    test('CJK ranges and attaching kana keep the specified boundaries', () {
      for (final codepoint in [
        0x3400,
        0x4DBF,
        0x4E00,
        0x9FFF,
        0xF900,
        0xFAFF,
        0x20000,
        0x2A6DF,
        0x2A700,
        0x2EE5D,
        0x2F800,
        0x2FA1F,
        0x3040,
        0x30FF,
        0x31F0,
        0x31FF,
        0xFF66,
        0xFF9D,
        0x1100,
        0x11FF,
        0x3130,
        0x318F,
        0xA960,
        0xA97F,
        0xAC00,
        0xD7FF,
      ]) {
        final grapheme = String.fromCharCode(codepoint);
        expect(breaksBetween(grapheme, '文'), isTrue);
        expect(breaksBetween('A', grapheme), isTrue);
        expect(breaksBetween(grapheme, '0'), isTrue);
        expect(breaksBetween('_', grapheme), isTrue);
        expect(breaksBetween(grapheme, '😀'), isFalse);
      }
      for (final attached in ['\u3099', '\u309A', '\u30A0', '\u30FB']) {
        expect(breaksBetween('か', attached), isFalse);
      }
      for (final outside in ['\u33FF', '\u4DC0', '\uA000', '\uD800', '🙂']) {
        expect(breaksBetween('A', outside), isFalse);
      }
    });

    test('zero, one and unbounded room retain whole source graphemes', () {
      const source = 'e\u0301/👩‍💻/中';
      final zero = TextLayout.compute(const TextSpan(source), maxWidth: 0);
      expect(_rows(zero), ['']);
      expect(zero.sourceText, source);
      final one = TextLayout.compute(const TextSpan(source), maxWidth: 1);
      expect(_rows(one), ['e\u0301', '/', '👩‍💻', '/', '中']);
      expect(one.lines.expand((row) => row).map((g) => g.sourceOffset), [
        0,
        1,
        2,
        3,
        4,
      ]);
      expect(_rows(TextLayout.compute(const TextSpan(source))), [source]);
    });

    test('wide and combined clusters at every edge keep source and styles', () {
      for (final cluster in ['中', '👩‍💻', 'e\u0301']) {
        for (var width = 1; width <= 12; width++) {
          final source = 'ab/$cluster/${cluster}tail';
          final layout = TextLayout.compute(
            TextSpan(
              '',
              children: [
                const TextSpan('ab/', style: Style(bold: true)),
                TextSpan(
                  '$cluster/${cluster}tail',
                  style: const Style(italic: true),
                ),
              ],
            ),
            maxWidth: width,
          );
          final glyphs = layout.lines.expand((row) => row).toList();
          expect(glyphs.map((g) => g.text).join(), source);
          expect(glyphs.take(3).every((g) => g.style.isBold), isTrue);
          expect(glyphs.skip(3).every((g) => g.style.isItalic), isTrue);
          expect(
            glyphs.map((g) => g.sourceOffset),
            List.generate(10, (i) => i),
          );
          final shape = shapeSelectionSource(
            SelectionSource.text(
              id: 'source',
              revision: 0,
              text: TextSpan(source),
            ),
            width: width,
          );
          if (width >= cellWidth(cluster)) {
            expect(shape.selectedText, source);
          }
        }
      }
    });

    testWidgets('ANSI punctuation reflows after updates and tiny resizes', (
      t,
    ) async {
      const source = '\x1b[31mab/中/👩‍💻/e\u0301/\x1b[0mabcdefghijk';
      final value = ValueNotifier('old');
      addTearDown(value.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: value,
          builder: (_) => Text.ansi(value.value),
        ),
        size: const Size(120, 40),
      );
      for (var i = 0; i < 1000; i++) {
        value.value = i == 999 ? source : 'old/$i';
      }
      await t.pump();
      for (final size in [
        Size.zero,
        const Size(1, 1),
        const Size(7, 24),
        const Size(80, 24),
        const Size(120, 40),
      ]) {
        await t.resize(size);
        final fresh = WidgetTester();
        try {
          await fresh.pumpWidget(Text.ansi(source), size: size);
          expect(t.screen.buffer.lines, fresh.screen.buffer.lines);
        } finally {
          fresh.dispose();
        }
      }
      expect(t.screen.lines.first, 'ab/中/👩‍💻/e\u0301/abcdefghijk');
      expect(t.screen.styleAt(2, 0).fg, Colors.red);
      expect(t.screen.styleAt(13, 0).fg, isNot(Colors.red));
      await t.pumpWidget(const SizedBox());
      value.value = 'late/notification';
      await t.pump();
      expect(t.screen.text, isEmpty);
    });
  });
}
