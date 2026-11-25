import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

List<String> texts(TextLayout layout) => [
  for (final row in layout.lines) row.map((g) => g.text).join(),
];

TextLayout wrap(String options, String source, int columns) =>
    switch (options) {
      'ht' || 'h' => TextLayout.wrapAnsi(TextSpan(source), columns, hard: true),
      'hnt' => TextLayout.wrapAnsi(
        TextSpan(source),
        columns,
        hard: true,
        trim: false,
      ),
      'cut' => TextLayout.wrapAnsi(
        TextSpan(source),
        columns,
        hard: true,
        trim: false,
        wordWrap: false,
      ),
      _ => TextLayout.wrapAnsi(TextSpan(source), columns),
    };

void main() {
  group('wrap-ansi', () {
    for (final (options, columns, source, rows) in cases) {
      test('$options ${source.replaceAll('\n', r'\n')} at $columns', () {
        expect(texts(wrap(options, source, columns)), rows);
      });
    }
  });

  test('styles stay on their glyphs across a cut word and rows', () {
    // The recorded "\e[31mab abcdefghijkl\e[39m" row, as a span.
    final layout = TextLayout.wrapAnsi(
      parseAnsi('\x1b[31mab abcdefghijkl\x1b[39m tail'),
      10,
      hard: true,
    );
    expect(texts(layout), ['ab abcdefg', 'hijkl tail']);
    final red = layout.lines.first.first.style;
    expect(red, isNot(Style.plain));
    expect(layout.lines.first.every((g) => g.style == red), isTrue);
    expect(layout.lines.last.take(5).every((g) => g.style == red), isTrue);
    expect(layout.lines.last.last.style, Style.plain);
  });

  test('sources across a soft break, a cut and a hard newline', () {
    final layout = TextLayout.wrapAnsi(
      const TextSpan('ab abcdefghijkl\nxy'),
      10,
      hard: true,
    );
    expect(texts(layout), ['ab abcdefg', 'hijkl', 'xy']);
    expect(
      [
        for (final s in layout.lineSources)
          (s.start, s.end, s.softBreak, s.hardBreak),
      ],
      [(0, 10, true, null), (10, 15, false, 15), (16, 18, false, null)],
    );
  });

  test('a tab moves to the next 8-cell stop and keeps its source', () {
    final layout = TextLayout.wrapAnsi(const TextSpan('ab\tc'), 20);
    expect(texts(layout), ['ab      c']);
    expect(layout.lines.single[2].sourceOffset, 2);
    expect(layout.lines.single[7].sourceOffset, 2);
    expect(layout.lines.single.last.sourceOffset, 3);
    expect(layout.sourceText, 'ab\tc');
  });

  test('trimming keeps U+0085, as trim in JavaScript does', () {
    expect(
      texts(
        TextLayout.wrapAnsi(
          const TextSpan('\u{85}a b'),
          1,
          hard: true,
          wordWrap: false,
        ),
      ),
      ['\u{85}a', 'b'],
    );
    // Probed under bun: an ideographic space opening a later word stays.
    expect(
      texts(TextLayout.wrapAnsi(const TextSpan(' \u{3000}a'), 5, hard: true)),
      ['\u{3000}a'],
    );
  });

  test('a space and the combining mark after it stay one grapheme', () {
    // Deliberate: wrap-ansi splits words at U+0020 before it segments
    // graphemes, so it gives one row 'abcdef \u{301}'; the framework keeps
    // the cluster whole, as main chose.
    expect(
      texts(
        TextLayout.wrapAnsi(const TextSpan('abcdef \u{301}'), 6, hard: true),
      ),
      ['abcdef', ' \u{301}'],
    );
  });

  test('columns below 1 throw', () {
    expect(() => TextLayout.wrapAnsi(const TextSpan('a'), 0), throwsRangeError);
  });
}

// wrap-ansi 10.0.2 under bun, docs/design/evidence/CTUI-57/wrap-ansi-cases.txt:
// options, columns, source, rows.
const cases = <(String, int, String, List<String>)>[
  ('ht', 10, 'ab abc/defghij', ['ab abc/def', 'ghij']),
  ('ht', 8, 'src/ui/app/App.tsx:12 x', ['src/ui/a', 'pp/App.t', 'sx:12 x']),
  ('ht', 10, 'ab abcdefghijkl', ['ab abcdefg', 'hijkl']),
  ('ht', 10, 'abcd abcdefghijkl', ['abcd abcde', 'fghijkl']),
  (
    'ht',
    10,
    'abcdefgh abcdefghijklmnopqrstuvw',
    ['abcdefgh', 'abcdefghij', 'klmnopqrst', 'uvw'],
  ),
  ('ht', 10, 'abcdefgh abcdefghijklmnop', ['abcdefgh', 'abcdefghij', 'klmnop']),
  (
    'ht',
    10,
    'abcdefgh abcdefghijklmnopqrs',
    ['abcdefgh', 'abcdefghij', 'klmnopqrs'],
  ),
  ('ht', 5, 'aaaaaaaaaaaa', ['aaaaa', 'aaaaa', 'aa']),
  ('ht', 10, 'abcdefghij   kl', ['abcdefghij', 'kl']),
  ('ht', 10, 'abcdefgh   ijk', ['abcdefgh', 'ijk']),
  ('ht', 10, '  indented longword here', ['indented', 'longword', 'here']),
  ('ht', 10, 'ab    cdefghijkl', ['ab', 'cdefghijkl']),
  ('ht', 5, '   ', ['']),
  ('ht', 5, '', ['']),
  ('ht', 10, 'a\u{9}b\u{9}c', ['a       b', 'c']),
  ('ht', 8, 'abcdef\u{9}gh', ['abcdef', 'gh']),
  ('ht', 6, 'ab cd efghijkl', ['ab cd', 'efghij', 'kl']),
  ('ht', 10, 'x (abcdefghijk)', ['x (abcdefg', 'hijk)']),
  ('ht', 10, 'ab 中文中文中文中文', ['ab 中文中', '文中文中文']),
  ('ht', 5, '中文 中文中文', ['中文', '中文', '中文']),
  ('ht', 7, 'one\u{A}two three four', ['one', 'two', 'three', 'four']),
  ('ht', 5, 'a\u{D}\u{A}b', ['a', 'b']),
  ('ht', 4, 'word  two', ['word', 'two']),
  ('ht', 5, 'abcde fghij', ['abcde', 'fghij']),
  ('h', 10, 'ab abcdefghijkl', ['ab abcdefg', 'hijkl']),
  ('h', 10, '  indented longword here', ['indented', 'longword', 'here']),
  ('hnt', 10, '  indented longword here', ['  indented', ' longword ', 'here']),
  ('hnt', 10, 'abcdefghij   kl', ['abcdefghij', '   kl']),
  ('hnt', 10, 'ab abcdefghijkl', ['ab abcdefg', 'hijkl']),
  ('hnt', 5, 'abcde fghij', ['abcde', ' ', 'fghij']),
  ('cut', 10, 'ab abcdefghijkl', ['ab abcdefg', 'hijkl']),
  ('cut', 10, 'abcdefghij   kl', ['abcdefghij', '   kl']),
  ('cut', 6, '  lead text here ok', ['  lead', ' text ', 'here o', 'k']),
  ('cut', 5, 'abcde fghij', ['abcde', ' fghi', 'j']),
  ('soft', 10, 'ab abcdefghijkl', ['ab', 'abcdefghijkl']),
  ('soft', 7, 'abc def ghi jkl mno', ['abc def', 'ghi jkl', 'mno']),
];
