import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('cellWidth', () {
    test('ascii', () => expect(cellWidth('hello'), 5));
    test('cjk is two cells', () => expect(cellWidth('日本語'), 6));
    test('emoji is two cells', () => expect(cellWidth('🙂'), 2));
    test('a joined emoji is one grapheme of two cells', () {
      expect(cellWidth('👨‍👩‍👧'), 2);
    });
    test('a flag is two cells', () => expect(cellWidth('🇯🇵'), 2));
    test('combining marks take no cell', () => expect(cellWidth('é'), 1));
    test('ansi sequences take no cell', () {
      expect(cellWidth('\x1b[31mred\x1b[0m'), 3);
    });
    test('cyrillic', () => expect(cellWidth('привет'), 6));
  });

  test('truncate cuts by cells and adds an ellipsis', () {
    expect(truncate('hello world', 8), 'hello w…');
    expect(truncate('日本語です', 5), '日本…');
    expect(truncate('short', 10), 'short');
  });

  group('TextLayout', () {
    List<String> lines(
      String s,
      int w, {
      TextOverflow o = TextOverflow.clip,
      int? maxLines,
      bool wrap = true,
    }) => TextLayout.compute(
      TextSpan(s),
      maxWidth: w,
      overflow: o,
      maxLines: maxLines,
      softWrap: wrap,
    ).lines.map((l) => l.map((g) => g.text).join()).toList();

    test('wraps at spaces', () {
      expect(lines('the quick brown fox', 10), ['the quick', 'brown fox']);
    });
    test('breaks a word longer than the line', () {
      expect(lines('abcdefghij', 4), ['abcd', 'efgh', 'ij']);
    });
    test('keeps explicit newlines', () {
      expect(lines('a\n\nb', 10), ['a', '', 'b']);
    });
    test('wraps wide characters by cells', () {
      expect(lines('日本語です', 4), ['日本', '語で', 'す']);
    });
    test('ellipsis on overflow without wrapping', () {
      expect(lines('hello world', 8, o: TextOverflow.ellipsis, wrap: false), [
        'hello w…',
      ]);
    });
    test('maxLines with ellipsis', () {
      expect(
        lines('one two three four', 7, o: TextOverflow.ellipsis, maxLines: 2),
        ['one two', 'three…'],
      );
    });
  });

  test('parseAnsi turns SGR into styled spans', () {
    final runs = parseAnsi('a\x1b[1;31mb\x1b[0mc').flatten();
    expect(runs.map((r) => r.$1), ['a', 'b', 'c']);
    expect(runs[1].$2.isBold, isTrue);
    expect(runs[1].$2.fg, Colors.red);
    expect(runs[2].$2, Style.plain);
  });

  test('keepSpaces wraps without dropping a space', () {
    List<String> rows(String s, int w, {bool keep = true}) =>
        TextLayout.compute(
          TextSpan(s),
          maxWidth: w,
          keepSpaces: keep,
        ).lines.map((l) => l.map((g) => g.text).join()).toList();
    expect(rows('a    b', 5), ['a    ', 'b']);
    expect(rows('a      b', 5), ['a    ', '  b']);
    expect(rows('        x', 5), ['     ', '   x']);
    expect(rows('one two', 5), ['one ', 'two']);
  });
}
