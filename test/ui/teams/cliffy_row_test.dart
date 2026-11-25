// cliffyRow on the nineteen cases recorded from @cliffy/table 1.3.1 under
// bun (new Table().body([cells]).minColWidth(w).maxColWidth(w).padding(2),
// lines split on \n; docs/design/evidence/CTUI-37/drafts/framework.md 2.3).
// Where the port keeps graphemes whole and counts the framework's widths
// (the owner's Q5), its lines are pinned beside the original's.
import 'package:chord/ui/teams/cliffy_row.dart';
import 'package:test/test.dart';
import 'package:characters/characters.dart';

/// A case: its cells, their widths, cliffy's lines (null where cliffy
/// throws RangeError), and the port's where they differ.
typedef _Case = ({
  String name,
  List<CliffyCell> cells,
  List<int> widths,
  List<String>? original,
  List<String>? port,
});

const _zwj = '👩\u200d💻';

final List<_Case> _cases = [
  (
    name: 'CJK wraps',
    cells: [const CliffyCell('日本語 テキスト')],
    widths: [4],
    original: ['日本', '語  ', 'テキ', 'スト'],
    port: null,
  ),
  (
    name: 'CJK word wider',
    cells: [const CliffyCell('日本語テキスト')],
    widths: [5],
    original: ['日本 ', '語テ ', 'キス ', 'ト   '],
    port: null,
  ),
  (
    name: 'CJK at one',
    cells: [const CliffyCell('日本')],
    widths: [1],
    original: null,
    port: ['日', '本'],
  ),
  (
    name: 'narrow then CJK at one',
    cells: [const CliffyCell('a日')],
    widths: [1],
    original: null,
    port: ['a', '日'],
  ),
  (
    name: 'CJK at two',
    cells: [const CliffyCell('a日b')],
    widths: [2],
    original: ['a ', '日', 'b '],
    port: null,
  ),
  (
    name: 'CJK beside a column',
    cells: [const CliffyCell('日本語'), const CliffyCell('x')],
    widths: [3, 1],
    original: ['日   x', '本    ', '語    '],
    port: null,
  ),
  (
    name: 'combining',
    cells: [const CliffyCell('e\u0301te\u0301 cafe\u0301')],
    widths: [2],
    original: ['e\u0301t', 'e\u0301 ', 'ca', 'fe\u0301'],
    port: null,
  ),
  (
    name: 'combining at one',
    cells: [const CliffyCell('e\u0301e\u0301')],
    widths: [1],
    original: ['e\u0301', 'e\u0301'],
    port: null,
  ),
  (
    name: 'ZWJ whole',
    cells: [const CliffyCell('$_zwj dev')],
    widths: [8],
    original: ['$_zwj dev'],
    port: ['$_zwj dev  '],
  ),
  (
    name: 'ZWJ at two',
    cells: [const CliffyCell(_zwj)],
    widths: [2],
    original: ['👩\u200d', '💻'],
    port: [_zwj],
  ),
  (
    name: 'ZWJ at three',
    cells: [const CliffyCell('x $_zwj')],
    widths: [3],
    original: ['x  ', '👩\u200d ', '💻 '],
    port: ['x  ', '$_zwj '],
  ),
  (
    name: 'ZWJ at one',
    cells: [const CliffyCell(_zwj)],
    widths: [1],
    original: null,
    port: [_zwj],
  ),
  (
    name: 'ZWJ beside a column',
    cells: [const CliffyCell(_zwj), const CliffyCell('x')],
    widths: [4, 1],
    original: ['$_zwj  x'],
    port: ['$_zwj    x'],
  ),
  (
    name: 'model in its string-width column',
    cells: [const CliffyCell('claude · $_zwj')],
    widths: [11],
    original: ['claude ·   ', '$_zwj       '],
    port: ['claude · $_zwj'],
  ),
  (
    name: 'zero room',
    cells: [const CliffyCell('abc'), const CliffyCell('def')],
    widths: [0, 3],
    original: ['  def'],
    port: null,
  ),
  (
    name: 'zero room, CJK',
    cells: [const CliffyCell('日本'), const CliffyCell('x')],
    widths: [0, 1],
    original: ['  x'],
    port: null,
  ),
  (
    name: 'zero room, ZWJ',
    cells: [const CliffyCell(_zwj), const CliffyCell('x')],
    widths: [0, 1],
    original: ['  x'],
    port: null,
  ),
  (
    name: 'span to a zero filler',
    cells: [const CliffyCell(''), const CliffyCell('role words', span: 3)],
    widths: [4, 3, 5, 0],
    original: ['      role words    '],
    port: null,
  ),
  (
    name: 'span, CJK',
    cells: [const CliffyCell(''), const CliffyCell('日本語の役割', span: 3)],
    widths: [4, 3, 1, 0],
    original: ['      日本語の  ', '      役割      '],
    port: null,
  ),
];

void main() {
  group('CTUI-37 tester: cliffy grapheme boundaries', () {
    test('every positive tiny width carries whole graphemes without loss', () {
      const text = '👩‍💻é界🙂';
      for (var width = 1; width <= 8; width++) {
        final rows = cliffyRow([const CliffyCell(text)], [width]);
        expect(
          rows.map((row) => row.trimRight()).join(),
          text,
          reason: 'width $width',
        );
        expect(
          rows.expand((row) => row.trimRight().characters),
          text.characters,
          reason: 'width $width',
        );
      }
      expect(cliffyRow([const CliffyCell(text)], [0]), ['']);
    });
  });

  test('nineteen cases are recorded', () => expect(_cases, hasLength(19)));
  for (final each in _cases) {
    test(
      each.port == null
          ? '${each.name}: as cliffy prints it'
          : '${each.name}: graphemes whole, beside cliffy\'s lines',
      () => expect(
        cliffyRow(each.cells, each.widths),
        each.port ?? each.original,
      ),
    );
  }

  test('a column is joined by its padding, the last cell padded by none', () {
    expect(
      cliffyRow(
        [const CliffyCell('a'), const CliffyCell('b')],
        [3, 3],
        padding: 1,
      ),
      ['a   b  '],
    );
  });

  test('words wrap at single spaces, a double space keeping an empty word', () {
    expect(cliffyRow([const CliffyCell('one two  three')], [7]), [
      'one two',
      ' three ',
    ]);
  });

  test('a cell of several lines breaks at each, after whole words', () {
    expect(cliffyRow([const CliffyCell('a\nb c')], [3]), ['a  ', 'b c']);
  });
}
