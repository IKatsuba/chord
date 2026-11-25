import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _source =
    "void main() {\n"
    "  print('A long message about terminal cells, 日本語, and keeping "
    "every grapheme together on screen.');\n"
    "}";

const _wide = Size(120, 40);
const _narrow = Size(80, 24);

/// [code] above a marker, so the rows Code takes are visible.
Widget _framed(Widget code, {ThemeData? theme}) {
  final column = Column(children: [code, Text('end')]);
  return theme == null ? column : Theme(data: theme, child: column);
}

void main() {
  testWidgets('at 120x40 every line fits, numbered', (t) async {
    await t.pumpWidget(
      _framed(const Code(_source, language: 'dart', lineNumbers: true)),
      size: _wide,
    );
    expect(t.screen.lines.take(4), [
      '1   void main() {',
      "2     print('A long message about terminal cells, 日本語, and keeping "
          "every grapheme together on screen.');",
      '3   }',
      'end',
    ]);
  });

  testWidgets('at 80x24 a long line wraps under a mark, unnumbered', (t) async {
    await t.pumpWidget(
      _framed(const Code(_source, language: 'dart', lineNumbers: true)),
      size: _narrow,
    );
    expect(t.screen.lines.take(5), [
      '1   void main() {',
      "2     print('A long message about terminal cells, 日本語, and keeping "
          "every",
      "  ↪ grapheme together on screen.');",
      '3   }',
      'end',
    ]);
  });

  for (final size in [_wide, _narrow]) {
    testWidgets('without numbers only the mark column is left at $size', (
      t,
    ) async {
      await t.pumpWidget(_framed(const Code(_source)), size: size);
      expect(t.screen.lines[0], '  void main() {');
      if (size == _narrow) {
        expect(t.screen.lines[2], "↪ grapheme together on screen.');");
      } else {
        expect(t.screen.lines[2], '  }');
      }
    });

    testWidgets('code takes the theme\'s tones; numbers and marks dim at '
        '$size', (t) async {
      await t.pumpWidget(
        _framed(const Code(_source, language: 'dart', lineNumbers: true)),
        size: size,
      );
      final tones = ThemeData.dark().code!.terminal;
      expect(t.screen.styleAt(4, 0), tones.keyword); // void
      expect(t.screen.styleAt(0, 0), Style.dim); // 1
      expect(t.screen.styleAt(4, 1), Style.plain); // print
      if (size == _narrow) expect(t.screen.styleAt(2, 2), Style.dim); // ↪
    });

    testWidgets('the light theme gives its own tones at $size', (t) async {
      await t.pumpWidget(
        _framed(
          const Code(_source, language: 'dart'),
          theme: ThemeData.light(),
        ),
        size: size,
      );
      expect(t.screen.styleAt(2, 0), ThemeData.light().code!.terminal.keyword);
    });

    testWidgets('the plain theme paints no colour at $size', (t) async {
      await t.pumpWidget(
        _framed(
          const Code(_source, language: 'dart', lineNumbers: true),
          theme: ThemeData.plain(),
        ),
        size: size,
      );
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < size.width; x++) {
          expect(t.screen.styleAt(x, y).fg, isNull, reason: '($x, $y)');
        }
      }
      expect(t.screen.lines[0], '1   void main() {');
    });

    testWidgets('an unknown language draws plain in the same place at $size', (
      t,
    ) async {
      await t.pumpWidget(
        _framed(const Code(_source, language: 'nolanguage', lineNumbers: true)),
        size: size,
      );
      expect(t.screen.lines[0], '1   void main() {');
      expect(t.screen.styleAt(4, 0), Style.plain);
    });

    testWidgets('softWrap false clips at the edge, with no mark at $size', (
      t,
    ) async {
      await t.pumpWidget(
        _framed(const Code(_source, softWrap: false)),
        size: size,
      );
      expect(t.screen.lines.take(4), [
        'void main() {',
        "  print('A long message about terminal cells, 日本語, and keeping "
                "every grapheme together on screen.');"
            .substring(0, size == _wide ? null : 77),
        '}',
        'end',
      ]);
    });

    testWidgets('empty source is one blank row, numbered 1, at $size', (
      t,
    ) async {
      await t.pumpWidget(
        _framed(const Code('', lineNumbers: true)),
        size: size,
      );
      expect(t.screen.lines.take(2), ['1', 'end']);
      await t.pumpWidget(_framed(const Code('')), size: size);
      expect(t.screen.lines.take(2), ['', 'end']);
    });

    testWidgets('blank lines, indentation and tabs keep their cells at $size', (
      t,
    ) async {
      await t.pumpWidget(
        _framed(const Code('\n  a\n\n\tb\n', lineNumbers: true)),
        size: size,
      );
      expect(t.screen.lines.take(7), [
        '1',
        '2     a',
        '3',
        '4     b',
        '5',
        'end',
        '',
      ]);
    });

    testWidgets('numbers align right to the last line\'s digits at $size', (
      t,
    ) async {
      final source = List.generate(10, (i) => 'l$i').join('\n');
      await t.pumpWidget(_framed(Code(source, lineNumbers: true)), size: size);
      expect(t.screen.lines[0], ' 1   l0');
      expect(t.screen.lines[9], '10   l9');
    });

    testWidgets('a wide grapheme wraps whole at $size', (t) async {
      // 2 mark cells + 9 cells of code: the fifth 日 does not fit.
      await t.pumpWidget(
        Row(children: [SizedBox(width: 11, child: const Code('日本語日本語'))]),
        size: size,
      );
      expect(t.screen.lines.take(2), ['  日本語日', '↪ 本語']);
    });

    testWidgets('a narrow constraint clips and never paints past it at $size', (
      t,
    ) async {
      final source = List.generate(10, (i) => 'line $i').join('\n');
      for (final width in [0, 1, 3, 5]) {
        await t.pumpWidget(
          Row(
            children: [
              SizedBox(width: width, child: Code(source, lineNumbers: true)),
              Text('|'),
            ],
          ),
          size: size,
        );
        for (var y = 0; y < 10; y++) {
          for (var x = width + 1; x < size.width; x++) {
            expect(t.screen.charAt(x, y), ' ', reason: 'w$width ($x, $y)');
          }
        }
        if (width == 0) expect(t.screen.lines.first, '|');
      }
    });
  }

  testWidgets('a new theme recolours; a new width rewraps', (t) async {
    await t.pumpWidget(
      _framed(const Code(_source, language: 'dart')),
      size: _wide,
    );
    expect(t.screen.styleAt(2, 0), ThemeData.dark().code!.terminal.keyword);
    await t.pumpWidget(
      _framed(const Code(_source, language: 'dart'), theme: ThemeData.light()),
      size: _wide,
    );
    expect(t.screen.styleAt(2, 0), ThemeData.light().code!.terminal.keyword);
    await t.resize(_narrow);
    expect(t.screen.lines[2], "↪ grapheme together on screen.');");
  });

  for (final size in [_wide, _narrow]) {
    testWidgets('a wrap keeps every source space at $size', (t) async {
      // 5 code cells after the mark column.
      Future<List<String>> rows(String source) async {
        await t.pumpWidget(
          Row(children: [SizedBox(width: 7, child: Code(source))]),
          size: size,
        );
        return [
          for (var y = 0; y < 3; y++)
            [for (var x = 0; x < 7; x++) t.screen.charAt(x, y)].join(),
        ];
      }

      expect(await rows('a    b'), ['  a    ', '↪ b    ', '       ']);
      expect(await rows('a      b'), ['  a    ', '↪   b  ', '       ']);
      expect(await rows('        x'), ['       ', '↪    x ', '       ']);
    });
  }
  group('tester: Code cell edges and lifecycle', () {
    testWidgets('zero and one cell viewports recover on resize', (t) async {
      await t.pumpWidget(
        const Code('界e\u0301\nnext', lineNumbers: true),
        size: const Size(0, 0),
      );
      expect(t.screen.text, isEmpty);
      await t.resize(const Size(1, 1));
      expect(t.screen.text, '1');
      await t.resize(_narrow);
      expect(t.screen.lines.take(2), ['1   界e\u0301', '2   next']);
    });

    testWidgets('focus moving away and back leaves read-only code unchanged', (
      t,
    ) async {
      final left = FocusNode();
      final right = FocusNode();
      await t.pumpWidget(
        Column(
          children: [
            Focus(
              focusNode: left,
              child: const Code('const value = 1;', language: 'dart'),
            ),
            Focus(focusNode: right, child: Text('other')),
          ],
        ),
      );
      final before = t.screen.text;
      for (final node in [left, right, left]) {
        node.requestFocus();
        await t.pump();
        await t.press('enter');
        expect(t.screen.text, before);
      }
      t.dispose();
      left.dispose();
      right.dispose();
    });
    for (final size in [_wide, _narrow]) {
      testWidgets('zero to three cells cannot overwrite a neighbour at $size', (
        t,
      ) async {
        for (final width in [0, 1, 2, 3]) {
          for (final numbers in [false, true]) {
            await t.pumpWidget(
              Row(
                children: [
                  SizedBox(
                    width: width,
                    child: Code('界👩‍💻e\u0301\nnext', lineNumbers: numbers),
                  ),
                  Text('|'),
                ],
              ),
              size: size,
            );
            expect(t.screen.charAt(width, 0), '|');
            for (var y = 0; y < 4; y++) {
              for (var x = width + 1; x < size.width; x++) {
                expect(t.screen.charAt(x, y), ' ');
              }
            }
          }
        }
      });

      testWidgets(
        'combining and emoji clusters stay whole at each wrap edge at $size',
        (t) async {
          for (final cluster in ['界', '👩‍💻', 'e\u0301']) {
            final cells = graphemeWidth(cluster);
            for (var offset = 0; offset < 3; offset++) {
              final prefix = 'x' * offset;
              final width = 2 + offset + cells;
              await t.pumpWidget(
                Row(
                  children: [
                    SizedBox(width: width, child: Code('$prefix${cluster}z')),
                  ],
                ),
                size: size,
              );
              expect(t.screen.charAt(2 + offset, 0), cluster);
              expect(t.screen.lines[1], '↪ z');
            }
          }
        },
      );

      testWidgets(
        'unbounded width sizes to the code and its gutters at $size',
        (t) async {
          await t.pumpWidget(
            Row(children: [Code('界e\u0301', lineNumbers: true), Text('|')]),
            size: size,
          );
          expect(t.screen.lines[0], '1   界e\u0301|');
        },
      );

      testWidgets(
        'ANSI text cannot recolour or move the following code at $size',
        (t) async {
          await t.pumpWidget(
            const Code('a\x1b[31mb\x1b[0mc\nnext', language: 'unknown'),
            size: size,
          );
          expect(t.screen.lines.take(2), ['  abc', '  next']);
          expect(t.screen.styleAt(3, 0), Style.plain);
        },
      );
    }

    testWidgets('resizing away and back restores the exact cells', (t) async {
      await t.pumpWidget(
        const Code('  界👩‍💻e\u0301    tail\n\tsecond', lineNumbers: true),
        size: _wide,
      );
      final original = t.screen.text;
      for (final size in [const Size(1, 1), const Size(3, 3), _narrow, _wide]) {
        await t.resize(size);
      }
      expect(t.screen.text, original);
    });

    testWidgets(
      'a thousand changes coalesce and removing Code stops drawing it',
      (t) async {
        final source = ValueNotifier('initial');
        await t.pumpWidget(
          ListenableBuilder(
            listenable: source,
            builder: (context) => source.value == 'removed'
                ? Text('removed')
                : Code(source.value, language: 'dart'),
          ),
        );
        for (var i = 0; i < 1000; i++) {
          source.value = 'const update = $i;';
        }
        await t.pump();
        expect(t.screen.lines.first, '  const update = 999;');
        source.value = 'removed';
        await t.pump();
        expect(t.screen.text, 'removed');
        await t.pump();
        expect(t.screen.text, 'removed');
        t.dispose();
        source.dispose();
      },
    );
  });
}
