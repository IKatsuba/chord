import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:chord_tui/src/text/wrap_breaks.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

List<String> rows(String text, int width, {bool keepSpaces = false}) =>
    TextLayout.compute(
      TextSpan(text),
      maxWidth: width,
      keepSpaces: keepSpaces,
    ).lines.map((line) => line.map((g) => g.text).join()).toList();

void main() {
  group('OpenTUI word wrap', () {
    for (final (width, source, expected) in wrapCases) {
      test('${_show(source)} at $width', () {
        expect(rows(source, width), expected);
      });
    }
  });

  group('the break set probe', () {
    for (final (char, expected) in breakSet) {
      test('U+${char.runes.first.toRadixString(16).toUpperCase()}', () {
        expect(rows('ab abc${char}defghij', 10), expected);
      });
    }
  });

  test('break kinds by first code point', () {
    expect(wrapBreakOf('/'), WrapBreak.punctuation);
    expect(wrapBreakOf('\u{3002}'), WrapBreak.punctuation);
    expect(wrapBreakOf('\u{205F}'), WrapBreak.whitespace);
    expect(wrapBreakOf('\u{2011}'), WrapBreak.none);
    expect(wrapBreakOf('a'), WrapBreak.none);
    expect(breaksBetween('中', '文'), isTrue);
    expect(breaksBetween('か', '\u{3099}'), isFalse);
    expect(breaksBetween('a', '中'), isTrue);
    expect(breaksBetween('中', '_'), isTrue);
    expect(breaksBetween('中', '-'), isFalse);
    expect(breaksBetween('a', 'b'), isFalse);
  });

  test("the CTUI-29 settings warning wraps as the original's", () {
    // The port's transcript row: 80 columns less the gutter and insets.
    expect(
      rows(
        '.chord/settings.json: "theme" is read only from '
        '/tmp/ctui29-look/cfg/chord/settings.json, ignored',
        76,
      ),
      [
        '.chord/settings.json: "theme" is read only from '
            '/tmp/ctui29-look/cfg/chord/',
        'settings.json, ignored',
      ],
    );
  });

  test('a punctuation break keeps each span its style', () {
    final layout = TextLayout.compute(
      const TextSpan(
        '',
        children: [
          TextSpan('ab abc/', style: Style(bold: true)),
          TextSpan('defghij', style: Style(italic: true)),
        ],
      ),
      maxWidth: 10,
    );
    expect(layout.lines.first.last.text, '/');
    expect(layout.lines.first.last.style.isBold, isTrue);
    expect(layout.lines.last.first.text, 'd');
    expect(layout.lines.last.first.style.isItalic, isTrue);
  });

  test('sources across a slash break and a dropped run', () {
    final slash = TextLayout.compute(
      const TextSpan('ab abc/defghij'),
      maxWidth: 10,
    );
    expect(
      [for (final s in slash.lineSources) (s.start, s.end, s.softBreak)],
      [(0, 7, true), (7, 14, false)],
    );
    final run = TextLayout.compute(
      const TextSpan('abcdefghij   kl'),
      maxWidth: 10,
    );
    expect(
      [for (final s in run.lineSources) (s.start, s.end, s.softBreak)],
      [(0, 10, true), (13, 15, false)],
    );
  });

  test('a copy across slash breaks and a dropped run is the source', () {
    const source = 'ab abc/defghij   kl/mnopqrstuvw';
    final shape = shapeSelectionSource(
      SelectionSource.text(id: 't', revision: 0, text: const TextSpan(source)),
      width: 10,
    );
    expect(
      [
        for (final row in shape.rows)
          row.glyphs.map((g) => g.glyph.text).join(),
      ],
      ['ab abc/', 'defghij', 'kl/', 'mnopqrstuv', 'w'],
    );
    expect(shape.selectedText, source);
  });

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('Text breaks a path after a slash at $size', (t) async {
      final path = '/tmp/${'nested/' * 30}end.txt';
      await t.pumpWidget(Text('see $path'), size: size);
      final lines = t.screen.lines.where((l) => l.trim().isNotEmpty).toList();
      expect(lines.first, startsWith('see /tmp/nested/'));
      for (final line in lines.take(lines.length - 1)) {
        expect(line.trimRight(), endsWith('/'));
      }
      expect(lines.map((l) => l.trimRight()).join(), 'see $path');
    });
  }

  test('a glyph wider than one cell never leaves an empty row', () {
    expect(rows('a/中', 1), ['a', '/', '中']);
    expect(rows('é/👩‍💻/中', 1), ['é', '/', '👩‍💻', '/', '中']);
    expect(rows('中', 1), ['中']);
    expect(rows('a 中', 1, keepSpaces: true), ['a', ' ', '中']);
  });

  test('leading spaces before an overlong word are a row of their own', () {
    // Probed under bun with OpenTUI 0.8.4's TextRenderable, word wrap.
    expect(rows('    xxxxxxxxxxxxxxx', 10), ['', 'xxxxxxxxxx', 'xxxxx']);
    expect(rows('ab    xxxxxxxxxxxxxxx', 10), ['ab', 'xxxxxxxxxx', 'xxxxx']);
    expect(rows('  ab', 10), ['  ab']);
  });

  test('keepSpaces breaks only at spaces and drops none', () {
    expect(rows('a/b/c/d/e/f', 4, keepSpaces: true), ['a/b/', 'c/d/', 'e/f']);
    expect(rows('ab abcdefghijkl', 10, keepSpaces: true), [
      'ab abcdefg',
      'hijkl',
    ]);
    expect(rows('abcdefghij   kl', 10, keepSpaces: true), [
      'abcdefghij',
      '   kl',
    ]);
  });

  test('no wrapping cuts at the edge as before', () {
    String cut(TextOverflow overflow) => TextLayout.compute(
      const TextSpan('src/ui/app/App.tsx:12'),
      maxWidth: 8,
      softWrap: false,
      overflow: overflow,
    ).lines.single.map((g) => g.text).join();
    expect(cut(TextOverflow.clip), 'src/ui/app/App.tsx:12');
    expect(cut(TextOverflow.ellipsis), 'src/ui/…');
    expect(cut(TextOverflow.middle), 'sr...:12');
  });
}

String _show(String text) => text.replaceAllMapped(
  RegExp(r'[^\x21-\x7e]'),
  (m) => 'U+${m[0]!.runes.first.toRadixString(16).toUpperCase()}',
);

// OpenTUI 0.8.4 probes, docs/design/evidence/CTUI-57. Left out: the
// combining-mark row and the control and format characters (U+000B, U+000C,
// U+0085, U+180E, U+2028, U+2029, U+FEFF), whose cell widths, not their
// breaks, part from the framework's.
const wrapCases = <(int, String, List<String>)>[
  (10, 'xx abcdefg(hijk', ['xx', 'abcdefg(', 'hijk']),
  (10, 'abcdefgh(ij', ['abcdefgh(', 'ij']),
  (10, 'abcdefghi(j', ['abcdefghi(', 'j']),
  (10, 'abcdefghij/kl', ['abcdefghij', '/kl']),
  (10, 'abcdefghij kl', ['abcdefghij', 'kl']),
  (10, 'abcdefghi/jkl', ['abcdefghi/', 'jkl']),
  (10, 'aaaa/bbbbbbbbbbbbbbb', ['aaaa/', 'bbbbbbbbbb', 'bbbbb']),
  (10, 'aaaa/bbbb/cccc/dddd/eeee', ['aaaa/bbbb/', 'cccc/dddd/', 'eeee']),
  (10, 'http://example.com/a/b', ['http://', 'example.', 'com/a/b']),
  (10, 'abc//defghijkl', ['abc//', 'defghijkl']),
  (10, 'ab /defghijkl', ['ab /', 'defghijkl']),
  (10, 'abcdefgh   ijk', ['abcdefgh', 'ijk']),
  (10, 'abcdefghij   kl', ['abcdefghij', 'kl']),
  (10, 'ab    cdefghijkl', ['ab', 'cdefghijkl']),
  (10, 'ab 中文中文中文中文', ['ab 中文中', '文中文中文']),
  (10, '中文中文中文中文中文中', ['中文中文中', '文中文中文', '中']),
  (10, 'ab 中文，中文中文', ['ab 中文，', '中文中文']),
  (7, 'abc def ghi jkl mno', ['abc def', 'ghi jkl', 'mno']),
  (10, 'a-b-c-d-e-f-g-h-i-j-k', ['a-b-c-d-e-', 'f-g-h-i-j-', 'k']),
  (8, 'src/ui/app/App.tsx:12', ['src/ui/', 'app/App.', 'tsx:12']),
  (10, 'x (abcdefghijk)', ['x (', 'abcdefghij', 'k)']),
  (6, 'foo.bar.baz.qux', ['foo.', 'bar.', 'baz.', 'qux']),
  (10, '  indented longword here', ['  indented', 'longword', 'here']),
  (10, 'ab\u{9}cdefghijkl', ['ab', 'cdefghijkl']),
  (10, 'abc/ defghijkl', ['abc/', 'defghijkl']),
  (10, 'abcdefghi/ jk', ['abcdefghi/', 'jk']),
  (10, 'abcdefghi- jk', ['abcdefghi-', 'jk']),
  (6, 'ab ccc.', ['ab', 'ccc.']),
  (6, 'ab cccc.', ['ab', 'cccc.']),
  (6, 'ab ccccc.', ['ab', 'ccccc.']),
  (5, 'aaaaaaaaaaaa', ['aaaaa', 'aaaaa', 'aa']),
  (10, 'ab abcdefghijkl', ['ab', 'abcdefghij', 'kl']),
  (10, 'abcd abcdefghijkl', ['abcd', 'abcdefghij', 'kl']),
  (10, 'ab abcdefg中hij', ['ab abcdefg', '中hij']),
  (10, 'ab abcdefgh中ij', ['ab', 'abcdefgh中', 'ij']),
  (10, 'abcdefgh 中文中文', ['abcdefgh', '中文中文']),
  (10, 'あいうえおかきくけこさ', ['あいうえお', 'かきくけこ', 'さ']),
  (10, 'ab あいうえおかき', ['ab あいう', 'えおかき']),
  (10, '가나다라마바사아자차카', ['가나다라마', '바사아자차', '카']),
  (10, 'ab 가나다라마바', ['ab 가나다', '라마바']),
  (10, 'ab カタカナカタカナ', ['ab カタカ', 'ナカタカナ']),
  (10, 'ab 😀😀😀😀😀😀', ['ab', '😀😀😀😀😀', '😀']),
  (10, 'abcdefghij\u{A0}kl', ['abcdefghij', 'kl']),
  (10, 'ab cd\u{A0}efghijkl', ['ab cd', 'efghijkl']),
  (10, 'ab\u{A0}\u{A0}\u{A0}\u{A0}cdefghijkl', ['ab', 'cdefghijkl']),
  (10, 'abcdefghi\u{3000}jk', ['abcdefghi', 'jk']),
  (10, 'abc\u{AD}defghijkl', ['abc\u{AD}', 'defghijkl']),
  (10, 'ab abc.defghijklmn', ['ab abc.', 'defghijklm', 'n']),
  (10, 'ab.cd efghijklmn', ['ab.cd', 'efghijklmn']),
  (10, 'abcdefghij', ['abcdefghij']),
  (10, 'abcdefghij.', ['abcdefghij', '.']),
  (10, 'abcdefghi .', ['abcdefghi', '.']),
  (3, 'ab /', ['ab', '/']),
  (1, 'a b c d e f', ['a', 'b', 'c', 'd', 'e', 'f']),
  (2, 'ab-', ['ab', '-']),
  (4, 'ab cd-efgh', ['ab', 'cd-', 'efgh']),
];

// Probe 'ab abc<c>defghij' at width 10.
const breakSet = <(String, List<String>)>[
  ('!', ['ab abc!', 'defghij']),
  ('"', ['ab', 'abc"defghi', 'j']),
  ('\$', ['ab', 'abc\$defghi', 'j']),
  ('%', ['ab', 'abc%defghi', 'j']),
  ('&', ['ab', 'abc&defghi', 'j']),
  ('\'', ['ab', 'abc\'defghi', 'j']),
  ('(', ['ab abc(', 'defghij']),
  (')', ['ab abc)', 'defghij']),
  ('*', ['ab', 'abc*defghi', 'j']),
  ('+', ['ab', 'abc+defghi', 'j']),
  (',', ['ab abc,', 'defghij']),
  ('-', ['ab abc-', 'defghij']),
  ('.', ['ab abc.', 'defghij']),
  ('/', ['ab abc/', 'defghij']),
  (':', ['ab abc:', 'defghij']),
  (';', ['ab abc;', 'defghij']),
  ('<', ['ab', 'abc<defghi', 'j']),
  ('=', ['ab', 'abc=defghi', 'j']),
  ('>', ['ab', 'abc>defghi', 'j']),
  ('?', ['ab abc?', 'defghij']),
  ('@', ['ab', 'abc@defghi', 'j']),
  ('[', ['ab abc[', 'defghij']),
  ('\\', ['ab abc\\', 'defghij']),
  (']', ['ab abc]', 'defghij']),
  ('^', ['ab', 'abc^defghi', 'j']),
  ('_', ['ab', 'abc_defghi', 'j']),
  ('`', ['ab', 'abc`defghi', 'j']),
  ('{', ['ab abc{', 'defghij']),
  ('|', ['ab', 'abc|defghi', 'j']),
  ('}', ['ab abc}', 'defghij']),
  ('~', ['ab', 'abc~defghi', 'j']),
  ('\u{9}', ['ab abc', 'defghij']),
  ('\u{A0}', ['ab abc', 'defghij']),
  ('\u{2000}', ['ab abc', 'defghij']),
  ('\u{2002}', ['ab abc', 'defghij']),
  ('\u{2003}', ['ab abc', 'defghij']),
  ('\u{2009}', ['ab abc', 'defghij']),
  ('\u{200A}', ['ab abc', 'defghij']),
  ('\u{200B}', ['ab abc', 'defghij']),
  ('\u{202F}', ['ab abc', 'defghij']),
  ('\u{205F}', ['ab abc', 'defghij']),
  ('\u{3000}', ['ab abc', 'defghij']),
  ('‐', ['ab abc‐', 'defghij']),
  ('‑', ['ab', 'abc‑defghi', 'j']),
  ('–', ['ab', 'abc–defghi', 'j']),
  ('—', ['ab', 'abc—defghi', 'j']),
  ('…', ['ab', 'abc…defghi', 'j']),
  ('、', ['ab abc、', 'defghij']),
  ('。', ['ab abc。', 'defghij']),
  ('，', ['ab abc，', 'defghij']),
  ('／', ['ab', 'abc／defgh', 'ij']),
  ('\u{AD}', ['ab abc\u{AD}', 'defghij']),
  ('\u{1680}', ['ab abc', 'defghij']),
];
