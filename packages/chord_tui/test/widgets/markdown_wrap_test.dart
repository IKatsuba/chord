import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/markdown_layout.dart' show wrapMarkdownLine;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../example/markdown_wrap.dart' show wrappingSample;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('reported table and styled URL rows at $size', (t) async {
      await t.pumpWidget(
        const Padding(
          padding: EdgeInsets.only(left: 3, right: 1),
          child: Markdown(wrappingSample),
        ),
        size: size,
      );
      final lines = t.screen.lines;
      if (size.width == 80) {
        expect(lines.take(3), [
          '   The session layer wraps the SDK so the interface never touches a process.',
          '   Start with src/session/session.ts, then see the ACP spec (https://',
          '   agentclientprotocol.com) for the wire format.',
        ]);
        expect(
          t.screen.styleAt(lines[1].indexOf('ACP'), 1),
          ThemeData.dark().link.merge(Style.underline),
        );
        expect(t.screen.styleAt(lines[1].indexOf('https'), 1), Style.dim);
        expect(t.screen.styleAt(3, 2), Style.dim);
        final row = lines.indexWhere((l) => l.contains('│ session.ts'));
        expect(lines[row].split('│')[2].trim(), 'opening, prompting');
        expect(lines[row + 1].split('│')[2].trim(), 'and closing a session');
      } else {
        expect(lines.take(2), [
          '   The session layer wraps the SDK so the interface never touches a process. Start with src/session/session.ts, then',
          '   see the ACP spec (https://agentclientprotocol.com) for the wire format.',
        ]);
        final row = lines.indexWhere((l) => l.contains('│ session.ts'));
        expect(
          lines[row],
          contains('│ opening, prompting and closing         │'),
        );
        expect(
          lines[row + 1],
          contains('│ a session                              │'),
        );
        expect(
          t.screen.styleAt(lines[row].indexOf('session.ts'), row),
          ThemeData.dark().inlineCode,
        );
      }
      final complete = t.screen.buffer.lines;
      for (var end = 1; end < wrappingSample.length; end += 19) {
        await t.pumpWidget(
          Padding(
            padding: const EdgeInsets.only(left: 3, right: 1),
            child: Markdown(wrappingSample.substring(0, end), growing: true),
          ),
          size: size,
        );
      }
      await t.pumpWidget(
        const Padding(
          padding: EdgeInsets.only(left: 3, right: 1),
          child: Markdown(wrappingSample),
        ),
        size: size,
      );
      expect(t.screen.buffer.lines, complete);
    });
  }
  testWidgets(
    'paragraph punctuation breaks retain styles and plain Text policy',
    (t) async {
      for (final punctuation in [
        '/',
        '-',
        ':',
        '.',
        ',',
        ';',
        '!',
        '?',
        '(',
        ')',
        '[',
        ']',
        '{',
        '}',
        r'\',
      ]) {
        final source = 'prefix abc${punctuation}defghijklmnop';
        // Escaping keeps Markdown punctuation literal.
        final markdown = source.replaceAll(punctuation, '\\$punctuation');
        await t.pumpWidget(Markdown(markdown), size: const Size(20, 40));
        expect(t.screen.lines.take(2), [
          'prefix abc$punctuation',
          'defghijklmnop',
        ]);
      }
      for (final punctuation in [
        '_',
        '=',
        '+',
        '&',
        '#',
        '@',
        '%',
        '|',
        '~',
        '—',
        '–',
      ]) {
        final source = 'prefix abc${punctuation}defghijklmnop';
        await t.pumpWidget(Markdown(source), size: const Size(20, 40));
        expect(t.screen.lines.take(2), [
          'prefix',
          'abc${punctuation}defghijklmnop',
        ]);
      }
      await t.pumpWidget(
        Text('prefix abc/defghijklmnop'),
        size: const Size(20, 40),
      );
      expect(t.screen.lines.take(2), ['prefix abc/', 'defghijklmnop']);
    },
  );
  testWidgets('paragraphs take the Unicode breaks and tables do not', (
    t,
  ) async {
    for (final (between, first) in [
      ('\u{A0}', 'prefix abc'),
      ('\u{2010}', 'prefix abc\u{2010}'),
      ('\u{3001}', 'prefix abc\u{3001}'),
    ]) {
      await t.pumpWidget(
        Markdown('prefix abc${between}defghijklmnop'),
        size: const Size(20, 40),
      );
      expect(t.screen.lines.take(2), [first, 'defghijklmnop']);
    }
    List<String> cell(bool table) => [
      for (final row in wrapMarkdownLine(
        TextLayout.compute(const TextSpan('xx abc/defghij klm')).lines.single,
        10,
        table: table,
      ))
        row.map((g) => g.text).join(),
    ];
    expect(cell(false), ['xx abc/', 'defghij', 'klm']);
    expect(cell(true), ['xx', 'abc/defghij', 'klm']);
  });
  testWidgets('table orphan articles and phrases retain styled tails', (
    t,
  ) async {
    for (final tail in [
      'a',
      'an',
      'the',
      'to',
      'of',
      'with',
      'and',
      'or',
      'in',
      'on',
      'for',
      'WITH THE',
    ]) {
      final text = '| Holds |\n|---|\n| alpha **$tail** beta |';
      // One padded column + markdansi furniture gives exactly the desired
      // content width, with room for the orphan but not the following word.
      final width = 6 + 'alpha $tail'.length;
      await t.pumpWidget(Markdown(text), size: Size(width, 40));
      expect(t.screen.lines[3].trim(), startsWith('│ alpha '));
      expect(t.screen.lines[4], contains('$tail beta'));
      expect(t.screen.styleAt(2, 4).isBold, isTrue);
    }
  });
  testWidgets('an overflowing orphan phrase truncates the whole table', (
    t,
  ) async {
    await t.pumpWidget(
      const Markdown(
        '| Holds |\n|---|\n| alpha with abcdefgh |\n| one two three four |',
      ),
      size: const Size(16, 40),
    );
    expect(t.screen.lines.take(6), [
      '┌────────────┐',
      '│ Holds      │',
      '├────────────┤',
      '│ alpha wit… │',
      '│ one two t… │',
      '└────────────┘',
    ]);
    for (var y = 1; y < 5; y++) {
      expect(t.screen.charAt(13, y), y == 2 ? '┤' : '│');
    }
  });
}
