import 'package:chord_tui/src/text/display_glyphs.dart';
import 'package:test/test.dart';

String drawn(String text, DisplaySize size) => [
  for (final row in displayRows(text, size)) row.map((r) => r.text).join(),
].join('\n');

void main() {
  test('every glyph the pages use is a 5x7 bitmap', () {
    const marks = ".,:!?-_/'+&# ";
    for (final c in [
      ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.split(''),
      ...marks.split(''),
    ]) {
      final glyph = displayGlyphs[c];
      expect(glyph, isNotNull, reason: c);
      expect(glyph, hasLength(7), reason: c);
      for (final row in glyph!) {
        expect(row, matches(RegExp(r'^[#.]{5}$')), reason: '$c: $row');
      }
    }
  });

  test('lower case draws as capitals; anything else as a hollow box', () {
    expect(glyphFor('a'), displayGlyphs['A']);
    expect(glyphFor('~'), missingGlyph);
    expect(glyphFor('é'), missingGlyph);
    expect(drawn('~', DisplaySize.large).split('\n').first, '██████████');
  });

  test('each size takes its rows and columns, the gap counted between '
      'glyphs and not after the last', () {
    for (final (size, rows, columns) in const [
      (DisplaySize.half, 4, 6),
      (DisplaySize.numeral, 4, 12),
      (DisplaySize.large, 7, 12),
      (DisplaySize.huge, 14, 24),
    ]) {
      expect(size.rows, rows);
      expect(size.columns, columns);
      final lines = drawn('AB', size).split('\n');
      expect(lines, hasLength(rows), reason: '$size');
      final gap = columns ~/ 6;
      for (final line in lines) {
        expect(line.length, 2 * columns - gap, reason: '$size');
      }
      expect(displayMeasure('AB', size), (
        width: 2 * columns - gap,
        height: rows,
      ));
    }
    expect(displayMeasure('', DisplaySize.huge), (width: 0, height: 14));
  });

  test('large is a full block a pixel, two columns wide', () {
    expect(drawn('I', DisplaySize.large).split('\n'), [
      '██████████',
      '    ██    ',
      '    ██    ',
      '    ██    ',
      '    ██    ',
      '    ██    ',
      '██████████',
    ]);
  });

  test('huge doubles each pixel row', () {
    final lines = drawn('-', DisplaySize.huge).split('\n');
    expect(lines[6], '█' * 20);
    expect(lines[7], '█' * 20);
    expect(lines[5].trim(), '');
    expect(lines[8].trim(), '');
  });

  test('half and numeral pair pixel rows into half blocks', () {
    // 1: rows 0–1 share the first cell row: '..#..' over '.##..'.
    expect(drawn('1', DisplaySize.half).split('\n'), [
      ' ▄█  ',
      '  █  ',
      '  █  ',
      ' ▀▀▀ ',
    ]);
    expect(drawn('1', DisplaySize.numeral).split('\n').first, '  ▄▄██    ');
  });

  test('runs say which character each glyph draws; gaps are -1', () {
    final row = displayRows('AB', DisplaySize.large).first;
    expect([for (final r in row) r.source], [0, -1, 1]);
  });

  test('the glyphs in the approved captures draw as they do there', () {
    const approved = {
      'A': '.###. #...# #...# ##### #...# #...# #...#',
      'C': '.#### #.... #.... #.... #.... #.... .####',
      'D': '####. #...# #...# #...# #...# #...# ####.',
      'E': '##### #.... #.... ####. #.... #.... #####',
      'G': '.#### #.... #.... #.### #...# #...# .####',
      'H': '#...# #...# #...# ##### #...# #...# #...#',
      'I': '##### ..#.. ..#.. ..#.. ..#.. ..#.. #####',
      'L': '#.... #.... #.... #.... #.... #.... #####',
      'O': '.###. #...# #...# #...# #...# #...# .###.',
      'P': '####. #...# #...# ####. #.... #.... #....',
      'R': '####. #...# #...# ####. #.#.. #..#. #...#',
      'T': '##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..',
      'U': '#...# #...# #...# #...# #...# #...# .###.',
      'Y': '#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..',
      '.': '..... ..... ..... ..... ..... ##... ##...',
      '0': '.###. #...# #...# #...# #...# #...# .###.',
      '1': '..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.',
      '2': '.###. #...# ....# ...#. ..#.. .#... #####',
      '3': '####. ....# ....# .###. ....# ....# ####.',
      '4': '...#. ..##. .#.#. #..#. ##### ...#. ...#.',
    };
    for (final MapEntry(:key, :value) in approved.entries) {
      expect(displayGlyphs[key]!.join(' '), value, reason: key);
    }
  });
}
