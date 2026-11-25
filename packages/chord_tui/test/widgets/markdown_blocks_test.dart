import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

final _dark = ThemeData.dark();

/// A body with a heading, a tight and a loose list, inline code with `__`
/// in it, a fenced block with a blank line inside, a quote and a table.
const _body = '''# How bugfix works

The lead reads the job, names who edits which files, and keeps `__init__`
and `a__b` whole as they are written in the code it points at.

1. tester writes the failing test.
2. coder fixes it.

- one writer per file

- members agree on files

```dart
void main() {

  print('hi');
}
```

> Report to main when the job is done or cannot be done.

| Agent | Role |
| --- | --- |
| tester | Writes the test |
''';

/// [row]'s cells: each grapheme with its width and style, as drawn.
List<(String, Style)> _cells(TextSpan row) => [
  for (final (text, style) in row.flatten())
    for (final grapheme in text.characters) (grapheme, style),
];

String _plain(TextSpan row) =>
    [for (final (text, _) in row.flatten()) text].join();

/// The rows [Markdown.blocksOf] gives, joined by the blank row the widget
/// puts between blocks.
List<TextSpan> _joined(List<List<TextSpan>> blocks) => [
  for (final (i, block) in blocks.indexed) ...[
    if (i > 0) const TextSpan(''),
    ...block,
  ],
];

void main() {
  group('CTUI-37 tester: Markdown block projection boundaries', () {
    const text =
        '# 界👩‍💻é\n\n'
        '`a__b` and [link](https://example.com).\n\n'
        '> 界é\n\n'
        '```\n\u0301\na\u200Bb 👩‍💻\n\n\x1b[31mred\x1b[0m\n```';
    for (final theme in [ThemeData.dark(), ThemeData.light()]) {
      for (final quoteBars in [true, false]) {
        testWidgets('tiny widths and resize keep projected glyphs and styles, '
            'theme ${theme.brightness}, quoteBars $quoteBars', (t) async {
          final projection = WidgetTester();
          addTearDown(projection.dispose);
          await t.pumpWidget(
            Theme(
              data: theme,
              child: Markdown(text, quoteBars: quoteBars),
            ),
            size: const Size(0, 1),
          );
          for (final size in const [
            Size(0, 1),
            Size(1, 24),
            Size(2, 24),
            Size(3, 24),
            Size(80, 24),
            Size(120, 40),
          ]) {
            final rows = _joined(
              Markdown.blocksOf(
                text,
                size.width,
                theme: theme,
                quoteBars: quoteBars,
              ),
            );
            await t.resize(size);
            await projection.pumpWidget(
              Theme(
                data: theme,
                child: Column(
                  children: [
                    for (final row in rows) Text.rich(row, softWrap: false),
                  ],
                ),
              ),
              size: size,
            );
            for (var y = 0; y < size.height; y++) {
              for (var x = 0; x < size.width; x++) {
                var char = t.screen.charAt(x, y);
                if (char.isNotEmpty && graphemeWidth(char) == 0) char = ' ';
                expect(
                  (
                    projection.screen.charAt(x, y),
                    projection.screen.styleAt(x, y),
                  ),
                  (char, t.screen.styleAt(x, y)),
                  reason: '$size cell $x,$y',
                );
              }
            }
          }
        });
      }
    }

    test('a thousand later projections leave an earlier snapshot intact', () {
      final first = Markdown.blocksOf('# Original\n\ntext', 80, theme: _dark);
      final before = [
        for (final block in first)
          [for (final row in block) row.flatten().toList()],
      ];
      for (var i = 0; i < 1000; i++) {
        final next = Markdown.blocksOf(
          'Update $i\n\n> 界👩‍💻é',
          1 + i % 120,
          theme: _dark,
          quoteBars: i.isEven,
        );
        expect(next.first.first.toPlainText(), startsWith('U'));
      }
      expect([
        for (final block in first)
          [for (final row in block) row.flatten().toList()],
      ], before);
      expect(first.map((block) => block.map(_plain).join('\n')), [
        'Original',
        'text',
      ]);
    });
  });

  test('two paragraphs, a heading and a list are four blocks in order, the '
      "heading in the theme's heading style and the list's numbers dim", () {
    final blocks = Markdown.blocksOf(
      'One.\n\n# Two\n\nThree.\n\n1. four\n2. five',
      40,
      theme: _dark,
    );
    expect(
      [
        for (final block in blocks) [for (final row in block) _plain(row)],
      ],
      [
        ['One.'],
        ['Two'],
        ['Three.'],
        ['1. four', '2. five'],
      ],
    );
    final heading = blocks[1].single.flatten().first.$2;
    expect((heading.isBold, heading.isUnderline), (true, true));
    final number = blocks[3].first.flatten().first;
    expect(number.$1.startsWith('1'), isTrue);
    expect(number.$2.isDim, isTrue);
  });

  for (final width in const [40, 77, 120]) {
    testWidgets('the blocks are, row for row and cell for cell, what the '
        'widget draws at $width columns', (t) async {
      final blocks = Markdown.blocksOf(_body, width, theme: _dark);
      final rows = _joined(blocks);
      await t.pumpWidget(
        Theme(data: _dark, child: const Markdown(_body)),
        size: Size(width, rows.length + 2),
      );
      for (final (y, row) in rows.indexed) {
        var x = 0;
        for (final (grapheme, style) in _cells(row)) {
          expect(t.screen.charAt(x, y), grapheme, reason: 'row $y col $x');
          expect(t.screen.styleAt(x, y), style, reason: 'row $y col $x');
          x += graphemeWidth(grapheme);
        }
        // Past what the row draws, nothing.
        for (; x < width; x++) {
          expect(t.screen.charAt(x, y), ' ', reason: 'row $y col $x');
          expect(t.screen.styleAt(x, y), Style.plain, reason: 'row $y col $x');
        }
      }
      expect(t.screen.lines.sublist(rows.length), everyElement(isEmpty));
    });
  }

  test("the rows of all blocks and the blank rows between them are "
      "heightOf's", () {
    for (final width in const [20, 40, 77, 120]) {
      final blocks = Markdown.blocksOf(_body, width, theme: _dark);
      final source = SelectionSource.markdown(
        id: 'm',
        revision: 0,
        text: _body,
      );
      expect(
        blocks.fold(0, (sum, block) => sum + block.length) + blocks.length - 1,
        Markdown.heightOf(source, width),
        reason: '$width',
      );
    }
  });

  test('a paragraph wider than the width wraps to the rows the widget '
      'draws; one that fits is one row', () {
    final wide = Markdown.blocksOf('word ' * 10, 12, theme: _dark);
    expect(
      [for (final row in wide.single) _plain(row)],
      ['word word', 'word word', 'word word', 'word word', 'word word'],
    );
    expect(
      Markdown.blocksOf('A short line.', 40, theme: _dark).single,
      hasLength(1),
    );
  });

  test('a fence with a blank line inside stays one block, its blank row '
      "inside it; inline code holding __ is one run", () {
    final fenced = Markdown.blocksOf(
      '```\nfirst\n\nthird\n```',
      40,
      theme: _dark,
    );
    expect(fenced, hasLength(1));
    expect(fenced.single.any((row) => _plain(row).contains('first')), isTrue);
    expect(fenced.single.any((row) => _plain(row).contains('third')), isTrue);
    final code = Markdown.blocksOf('Keep `a__b` whole.', 40, theme: _dark);
    expect(code, hasLength(1));
    expect(_plain(code.single.single), 'Keep a__b whole.');
    expect(
      code.single.single.flatten().where((run) => run.$1.contains('a__b')),
      hasLength(1),
    );
  });

  test('empty text and text with only an invisible block give no blocks; a '
      'link definition, which the widget draws as written, is one', () {
    expect(Markdown.blocksOf('', 40, theme: _dark), isEmpty);
    expect(
      Markdown.blocksOf('![a picture](pic.png)', 40, theme: _dark),
      isEmpty,
    );
    expect(
      Markdown.blocksOf('[home]: https://example.com', 40, theme: _dark),
      hasLength(1),
    );
  });

  test('a glyph of no width alone in a code frame, a zero-width space or a '
      'lone combining mark, takes its cell and the row still ends', () {
    for (final mark in const ['\u200B', '\u0301']) {
      final blocks = Markdown.blocksOf('```\n$mark\n```', 40, theme: _dark);
      expect(blocks, hasLength(1));
      final rows = [for (final row in blocks.single) _plain(row)];
      expect(rows, hasLength(3));
      // Its cell shows nothing; the frame's right border stays in the
      // column the widget puts it.
      expect(rows[1], '│  │');
    }
  }, timeout: const Timeout(Duration(seconds: 5)));

  // Bounded: a row that never ends would hold the run otherwise.
  group(
    'glyphs of no width',
    timeout: const Timeout(Duration(seconds: 10)),
    () {
      for (final width in const [40, 80]) {
        testWidgets(
          'with zero-width, combining and wide glyphs, the blocks drawn '
          'as text are the widget, cell for cell and style for style, at '
          '$width columns',
          (t) async {
            const text =
                '```\na\u200Bb \u0301x é 中文 ｗｉｄｅ\n```\n\n'
                'Plain a\u200Bb, \u0301lone, e\u0301, 中文 and ｗｉｄｅ.\n\n'
                '```\n\u200B\n```\n\n'
                '```\n\u0301\n```\n\n'
                '> quoted 中文 e\u0301\n\n'
                '| 中 | e\u0301 |\n| --- | --- |\n| a\u200Bb | x |';
            final rows = _joined(Markdown.blocksOf(text, width, theme: _dark));
            final size = Size(width, rows.length + 2);
            await t.pumpWidget(
              Theme(data: _dark, child: const Markdown(text)),
              size: size,
            );
            final widget = [
              for (var y = 0; y < size.height; y++)
                [
                  for (var x = 0; x < width; x++)
                    (t.screen.charAt(x, y), t.screen.styleAt(x, y)),
                ],
            ];
            await t.pumpWidget(
              Theme(
                data: _dark,
                child: Column(
                  children: [
                    for (final row in rows) Text.rich(row, softWrap: false),
                  ],
                ),
              ),
              size: size,
            );
            for (var y = 0; y < size.height; y++) {
              for (var x = 0; x < width; x++) {
                var (char, style) = widget[y][x];
                // A cell holding only a glyph of no width shows nothing;
                // drawn as text, it is a space.
                if (char.isNotEmpty && graphemeWidth(char) == 0) char = ' ';
                expect(t.screen.charAt(x, y), char, reason: 'row $y col $x');
                expect(t.screen.styleAt(x, y), style, reason: 'row $y col $x');
              }
            }
          },
        );
      }
    },
  );

  testWidgets('quoteBars: false gives a quote without its bar, as the widget '
      'draws it', (t) async {
    const text = 'Before.\n\n> quoted line';
    final blocks = Markdown.blocksOf(text, 40, theme: _dark, quoteBars: false);
    expect([for (final row in blocks.last) _plain(row)], ['quoted line']);
    await t.pumpWidget(
      Theme(data: _dark, child: const Markdown(text, quoteBars: false)),
      size: const Size(40, 5),
    );
    expect(t.screen.lines.sublist(0, 3), ['Before.', '', 'quoted line']);
    final barred = Markdown.blocksOf(text, 40, theme: _dark);
    expect(_plain(barred.last.single), isNot('quoted line'));
  });
}
