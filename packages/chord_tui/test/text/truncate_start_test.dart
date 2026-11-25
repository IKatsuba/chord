import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test('retains suffix after a leading marker and preserves fitting input', () {
    expect(truncateStart('abcdef', 4), '…def');
    expect(truncateStart('abcdef', 1), '…');
    expect(truncateStart('abcdef', 0), '');
    expect(truncateStart('abcdef', -2), '');
    expect(truncateStart('', 2), '');
    expect(truncateStart('abcd', 4), 'abcd');
    expect(truncateStart('\x1b[31mabcd\x1b[0m', 4), '\x1b[31mabcd\x1b[0m');
    expect(truncateStart('\x1b[31mabcdef\x1b[0m', 4), '…def');
  });

  test('custom markers are clipped by whole graphemes and cells', () {
    expect(truncateStart('abcdef', 3, ellipsis: ''), 'def');
    expect(truncateStart('abcdef', 2, ellipsis: '...'), '..');
    expect(truncateStart('abcdef', 1, ellipsis: '界'), '');
    expect(truncateStart('abcdef', 2, ellipsis: '界x'), '界');
    expect(truncateStart('abcdef', 3, ellipsis: '界x'), '界x');
    expect(truncateStart('abcdef', 2, ellipsis: 'e\u0301xx'), 'e\u0301x');
    expect(truncateStart('abcdef', 1, ellipsis: '👩‍💻'), '');
  });

  test('styled marker clips its glyphs without emitting partial escapes', () {
    const red = '\x1b[31m…\x1b[0m';
    const wide = '\x1b[31m界\x1b[0m';
    expect(truncateStart('abcdef', 1, ellipsis: red), '…');
    expect(truncateStart('abcdef', 2, ellipsis: red), '…f');
    expect(truncateStart('abcdef', 1, ellipsis: wide), '');
    expect(truncateStart('abcdef', 2, ellipsis: wide), '界');
    expect(truncateStart('abcdef', 3, ellipsis: wide), '界f');
  });

  test('CJK combining and joined emoji remain whole in the suffix', () {
    expect(truncateStart('界abc', 3), '…bc');
    expect(truncateStart('abc界', 3), '…界');
    expect(truncateStart('abc界', 2), '…');
    expect(truncateStart('abce\u0301', 3), '…ce\u0301');
    expect(truncateStart('abc👩‍💻', 3), '…👩‍💻');
    expect(truncateStart('abc👩‍💻', 2), '…');
    // A wide grapheme that cannot fit ends the contiguous suffix.
    expect(truncateStart('abc界z', 3), '…z');
  });

  test('all budgets stay within cells without splitting clusters', () {
    for (final text in ['abcdef', '界界a', 'abe\u0301👩‍💻z']) {
      for (final marker in ['', '…', '...', '界', '👩‍💻']) {
        for (var width = 0; width <= 12; width++) {
          expect(
            cellWidth(truncateStart(text, width, ellipsis: marker)),
            lessThanOrEqualTo(width),
          );
        }
      }
    }
  });
}
