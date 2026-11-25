import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _wide = Size(120, 40);
const _narrow = Size(80, 24);

final _dark = ThemeData.dark();

/// The column of [needle] on row [y], or fails.
int _at(WidgetTester t, int y, String needle) {
  final x = t.screen.lines[y].indexOf(needle);
  expect(x, isNot(-1), reason: '"$needle" on row $y: ${t.screen.lines[y]}');
  // Columns are cells; the rows these tests search hold one-cell text
  // before the needle.
  return x;
}

Future<void> _show(WidgetTester t, String text, Size size, {int? width}) =>
    t.pumpWidget(
      width == null
          ? Markdown(text)
          : Row(
              children: [SizedBox(width: width, child: Markdown(text))],
            ),
      size: size,
    );

List<String> _rows(WidgetTester t, int n) => t.screen.lines.take(n).toList();

void main() {
  group('tester: CTUI-55 trimmed paragraph geometry', () {
    for (final size in [_wide, _narrow]) {
      for (final grapheme in ['界', '👩‍💻', 'é']) {
        testWidgets('trimmed $grapheme stays whole at both edges at $size', (
          t,
        ) async {
          final text =
              '$grapheme${'x' * (size.width - 2 * cellWidth(grapheme))}$grapheme';
          final c = SelectionController();
          addTearDown(c.dispose);
          for (final bound in [false, true]) {
            await t.pumpWidget(
              SelectionArea(
                controller: c,
                selectionStyle: const Style(inverse: true),
                child: bound
                    ? Markdown.fromSelectionSource(
                        SelectionSource.markdown(
                          id: 'trim',
                          revision: 0,
                          text: '   $text',
                        ),
                      )
                    : Markdown('   $text'),
              ),
              size: size,
            );
            expect(t.screen.lines.first, text);
            MouseEvent at(MouseEventKind kind, int x) => MouseEvent(
              kind,
              position: Offset(x, 0),
              button: MouseButton.primary,
            );
            await t.mouse(at(MouseEventKind.press, 0));
            await t.mouse(at(MouseEventKind.move, size.width - 1));
            await t.mouse(at(MouseEventKind.release, size.width - 1));
            expect(c.snapshot()?.text, text);
            c.clear();
          }
        });
      }
    }

    testWidgets(
      'unbounded trimmed content recovers through zero and one cell',
      (t) async {
        await t.pumpWidget(
          Row(children: [const Markdown(' **界é**'), Text('|')]),
          size: _wide,
        );
        expect(t.screen.lines.first, '界é|');
        await t.resize(const Size(0, 0));
        expect(t.screen.text, isEmpty);
        await t.resize(const Size(1, 1));
        await t.resize(_narrow);
        expect(t.screen.lines.first, '界é|');
      },
    );

    testWidgets(
      'a thousand indented chunks settle and detach without stale updates',
      (t) async {
        final value = ValueNotifier(' Initial');
        addTearDown(value.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: value,
            builder: (context) => Markdown(value.value, growing: true),
          ),
          size: _wide,
        );
        for (var i = 0; i < 1000; i++) {
          value.value = ' 界😀é $i  \n   end\x1b[31m!\x1b[0m';
        }
        await t.pump();
        await t.resize(_narrow);
        expect(t.screen.lines.take(2), ['界😀é 999', 'end!']);
        expect(t.screen.text, isNot(contains('\x1b')));
        await t.pumpWidget(Text('removed'), size: _narrow);
        value.value = ' should never appear';
        await t.pump();
        expect(t.screen.text, 'removed');
      },
    );
  });
  _testerGrowingCases();
  _leadingWhitespaceCases();
  for (final size in [_wide, _narrow]) {
    group('at ${size.width}x${size.height}', () {
      testWidgets('headings drop their marks; h1 underlined, all bold', (
        t,
      ) async {
        await _show(t, '# One\n\n## Two', size);
        expect(_rows(t, 3), ['One', '', 'Two']);
        expect(
          t.screen.styleAt(0, 0),
          const Style(bold: true, underline: true),
        );
        expect(t.screen.styleAt(0, 2), Style.bold);
      });

      testWidgets('inline styles, inline code and links', (t) async {
        await _show(
          t,
          '**b** *i* ~~s~~ `c` [l](http://x.dev) <http://y.dev> '
          '[m](mailto:a@b.c) ![img](p.png)end',
          size,
        );
        final line = t.screen.lines[0];
        expect(line, 'b i s c l (http://x.dev) http://y.dev m end');
        expect(t.screen.styleAt(0, 0), Style.bold);
        expect(t.screen.styleAt(2, 0), Style.italic);
        expect(t.screen.styleAt(4, 0), Style.strikethrough);
        expect(t.screen.styleAt(6, 0), _dark.inlineCode);
        expect(t.screen.styleAt(8, 0), _dark.link.merge(Style.underline));
        expect(t.screen.styleAt(11, 0), Style.dim); // the url
        final auto = _at(t, 0, 'http://y.dev');
        expect(t.screen.styleAt(auto, 0), _dark.link.merge(Style.underline));
        expect(t.screen.styleAt(_at(t, 0, ' m ') + 1, 0), Style.plain);
      });

      testWidgets('a paragraph wraps at the edge, wide graphemes whole', (
        t,
      ) async {
        final text = '${'word ' * 30}${'日本語' * 30}';
        await _show(t, text, size);
        for (final line in t.screen.lines.take(5)) {
          expect(cellWidth(line), lessThanOrEqualTo(size.width));
        }
        expect(t.screen.lines.join().replaceAll(' ', ''), contains('日本語' * 10));
      });

      testWidgets('a hard break stays; soft breaks join', (t) async {
        await _show(t, 'one\ntwo  \nthree', size);
        expect(_rows(t, 3), ['one two', 'three', '']);
      });

      testWidgets('a rule is 40 dim em dashes, fewer when narrower', (t) async {
        await _show(t, 'a\n\n---', size);
        expect(t.screen.lines[2], '—' * 40);
        expect(t.screen.styleAt(0, 2), Style.dim);
        await _show(t, '---', size, width: 12);
        expect(t.screen.lines[0], '—' * 12);
      });

      testWidgets('a definition shows as written; an image draws nothing', (
        t,
      ) async {
        await _show(t, '![alt](p.png)\n\n[r]: https://r.dev "T"', size);
        expect(_rows(t, 2), ['[r]: https://r.dev "T"', '']);
      });

      testWidgets('lists: dim markers, hanging text, nesting, numbers, '
          'tasks', (t) async {
        await _show(
          t,
          '- one\n- ${'long ' * 30}\n  - nested\n\n'
          '7. seven\n8. eight\n\n- [x] done\n- [ ] open',
          size,
        );
        final lines = t.screen.lines;
        expect(lines[0], '- one');
        expect(t.screen.styleAt(0, 0), Style.dim);
        expect(lines[1], startsWith('- long'));
        expect(lines[2], startsWith('  long'));
        final nested = lines.indexWhere((l) => l.contains('nested'));
        expect(lines[nested], '  - nested');
        expect(lines[nested + 2], '7. seven');
        expect(lines[nested + 3], '8. eight');
        expect(lines[nested + 5], '[x] done');
        expect(lines[nested + 6], '[ ] open');
        expect(t.screen.styleAt(1, nested + 5), Style.dim);
      });

      testWidgets('a loose list puts a blank row between items', (t) async {
        await _show(t, '- a\n\n- b\n\n  more', size);
        expect(_rows(t, 6), ['- a', '', '- b', '', '  more', '']);
      });

      testWidgets('a quote keeps its bar on every row, nested too', (t) async {
        await _show(t, '> ${'quoted ' * 30}\n>\n> > inner', size);
        final lines = t.screen.lines;
        expect(lines[0], startsWith('│ quoted'));
        expect(lines[1], startsWith('│ quoted'));
        final inner = lines.indexWhere((l) => l.contains('inner'));
        expect(lines[inner], '│ │ inner');
        expect(lines[inner - 1], startsWith('│ quoted'));
        expect(t.screen.styleAt(0, 0), Style.dim);
        expect(t.screen.styleAt(2, 0), const Style(dim: true, italic: true));
      });

      testWidgets('without quote bars, a quote reads as the text around '
          'it, and its source says so', (t) async {
        const text = 'Before.\n\n> quoted line\n> > inner\n\nAfter.';
        await t.pumpWidget(const Markdown(text, quoteBars: false), size: size);
        // As inside a bar, a quote's own blocks take no blank row.
        expect(_rows(t, 6), [
          'Before.',
          '',
          'quoted line',
          'inner',
          '',
          'After.',
        ]);
        expect(t.screen.styleAt(0, 2), Style.plain);
        final source = SelectionSource.markdown(
          id: 'm',
          revision: 0,
          text: text,
          quoteBars: false,
        );
        await t.pumpWidget(Markdown.fromSelectionSource(source), size: size);
        expect(_rows(t, 3), ['Before.', '', 'quoted line']);
        expect(Markdown.fromSelectionSource(source).quoteBars, isFalse);
        // Its height is the rows it draws, as a fold of the caller's counts.
        expect(Markdown.heightOf(source, size.width), 6);
        final narrow = SelectionSource.markdown(
          id: 'n',
          revision: 0,
          text: 'word ' * 10,
        );
        expect(Markdown.heightOf(narrow, 12), 5);
      });

      testWidgets('a code block is boxed, labelled and coloured', (t) async {
        await _show(t, '```dart\nvoid main() {}\n```', size);
        expect(_rows(t, 4), [
          '┌─ dart ─────────┐',
          '│ void main() {} │',
          '└────────────────┘',
          '',
        ]);
        expect(t.screen.styleAt(0, 0), _dark.border);
        expect(t.screen.styleAt(3, 0), _dark.border); // the label, not bold
        expect(t.screen.styleAt(2, 1), _dark.code!.terminal.keyword);
      });

      testWidgets('an unlabelled or unknown fence, and indented code', (
        t,
      ) async {
        await _show(t, '```\nx\n```\n\n```nolang\nint x\n```\n\n    y', size);
        expect(_rows(t, 11), [
          '┌───┐',
          '│ x │',
          '└───┘',
          '',
          '┌─ nolang ─┐',
          '│ int x    │',
          '└──────────┘',
          '',
          '┌───┐',
          '│ y │',
          '└───┘',
        ]);
        expect(t.screen.styleAt(4, 5), Style.plain);
      });

      testWidgets('a long code line wraps inside the box by character', (
        t,
      ) async {
        final line = 'x' * (size.width + 10);
        await _show(t, '```\n$line\n```', size);
        expect(t.screen.lines[0], '┌${'─' * (size.width - 2)}┐');
        expect(t.screen.lines[1], '│ ${'x' * (size.width - 4)} │');
        expect(t.screen.lines[2], '│ ${'x' * 14}${' ' * (size.width - 18)} │');
      });

      testWidgets('a label that does not fit is left out', (t) async {
        await _show(t, '```averyverylonglabel\nx\n```', size, width: 12);
        expect(t.screen.lines[0], '┌──────────┐');
      });

      testWidgets('an open fence is a box to the end', (t) async {
        await _show(t, 'text\n\n```dart\nvoid f() {', size);
        expect(_rows(t, 5), [
          'text',
          '',
          '┌─ dart ─────┐',
          '│ void f() { │',
          '└────────────┘',
        ]);
      });

      testWidgets('a table: bold heading, dim grid, aligned cells', (t) async {
        await _show(t, '| Name | n |\n|:-----|--:|\n| renderer | 2 |', size);
        expect(_rows(t, 6), [
          '┌──────────┬────┐',
          '│ Name     │  n │',
          '├──────────┼────┤',
          '│ renderer │  2 │',
          '└──────────┴────┘',
          '',
        ]);
        expect(t.screen.styleAt(0, 0), Style.dim);
        expect(t.screen.styleAt(2, 1), Style.bold);
        expect(t.screen.styleAt(2, 3), Style.plain);
      });

      testWidgets('a table wraps its cells to fit, or cuts every cell', (
        t,
      ) async {
        await _show(
          t,
          '| a | b |\n|---|---|\n| one two three four | five |',
          size,
          width: 30,
        );
        // The widest column gives way until the grid fits 30 cells by
        // markdansi's count, two cells a column more than drawn.
        expect(_rows(t, 6), [
          '┌─────────────────┬──────┐',
          '│ a               │ b    │',
          '├─────────────────┼──────┤',
          '│ one two three   │ five │',
          '│ four            │      │',
          '└─────────────────┴──────┘',
        ]);
      });

      testWidgets('a word too long for its column cuts every cell', (t) async {
        await _show(
          t,
          '| a | b |\n|---|---|\n| unbreakable | one two |',
          size,
          width: 16,
        );
        expect(_rows(t, 5), [
          '┌────┬─────┐',
          '│ a  │ b   │',
          '├────┼─────┤',
          '│ u… │ on… │',
          '└────┴─────┘',
        ]);
      });

      testWidgets('a table narrower than its grid is clipped', (t) async {
        await _show(
          t,
          '| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |',
          size,
          width: 6,
        );
        for (var y = 0; y < 5; y++) {
          for (var x = 6; x < size.width; x++) {
            expect(t.screen.charAt(x, y), ' ');
          }
        }
      });

      testWidgets('blocks: one blank row at the top level, none inside a '
          'quote or a tight list', (t) async {
        await _show(t, 'para\n# head\n- a\n- b\n\n> x\n>\n> y', size);
        expect(_rows(t, 9), [
          'para',
          '',
          'head',
          '',
          '- a',
          '- b',
          '',
          '│ x',
          '│ y',
        ]);
      });

      testWidgets('an empty quote, or one of images, draws nothing', (t) async {
        await _show(t, 'a\n\n>\n\nb\n\n> ![x](y.png)\n\n> >\n\nc', size);
        expect(_rows(t, 6), ['a', '', 'b', '', 'c', '']);
      });

      testWidgets('table text takes the text role, as paragraphs do', (
        t,
      ) async {
        const text = 'para\n\n| h |\n|---|\n| c |\n\n> | q |\n> |---|\n> | r |';
        Future<void> pump(Color colour) => t.pumpWidget(
          Theme(
            data: _dark.copyWith(text: Style(fg: colour)),
            child: DefaultTextStyle(
              style: Style.underline,
              child: Markdown(text),
            ),
          ),
          size: size,
        );
        await pump(Colors.magenta);
        const magenta = Style(fg: Colors.magenta, underline: true);
        expect(t.screen.styleAt(0, 0), magenta); // para
        expect(t.screen.styleAt(2, 3), magenta.merge(Style.bold)); // h
        expect(t.screen.styleAt(2, 5), magenta); // c
        final q = t.screen.lines.indexWhere((l) => l.contains(' q '));
        expect(
          t.screen.styleAt(t.screen.lines[q].indexOf('q'), q),
          magenta.merge(const Style(dim: true, italic: true, bold: true)),
        );
        await pump(Colors.cyan);
        expect(
          t.screen.styleAt(2, 5),
          const Style(fg: Colors.cyan, underline: true),
        );
      });

      testWidgets('empty and blank text draw nothing', (t) async {
        await t.pumpWidget(
          Column(children: [Markdown(''), Markdown('\n \n'), Text('end')]),
          size: size,
        );
        expect(t.screen.lines[0], 'end');
      });

      testWidgets('a reply streamed in chunks draws as the whole', (t) async {
        const reply =
            '# Title\n\nSome *text* and `code`.\n\n```ts\nconst a = 1;\n'
            'const b = 2;\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- x\n- y\n';
        await _show(t, reply, size);
        final whole = t.screen.lines;
        for (var i = 1; i <= reply.length; i += 5) {
          await _show(t, reply.substring(0, i), size);
        }
        await _show(t, reply, size);
        expect(t.screen.lines, whole);
      });
    });
  }

  testWidgets('a width change rewraps; a theme change restyles', (t) async {
    final text = 'a ${'word ' * 20}\n\n```dart\nvoid f() {}\n```';
    await _show(t, text, _wide);
    expect(t.screen.lines[0], startsWith('a word'));
    expect(t.screen.lines[1], '');
    await t.resize(const Size(40, 24));
    expect(t.screen.lines[1], startsWith('word'));
    await t.pumpWidget(
      Theme(data: ThemeData.light(), child: Markdown(text)),
      size: const Size(40, 24),
    );
    final y = t.screen.lines.indexWhere((l) => l.contains('void'));
    expect(
      t.screen.styleAt(_at(t, y, 'void'), y),
      ThemeData.light().code!.terminal.keyword,
    );
  });
  group('tester: Markdown boundaries and retained state', () {
    const fixtures = [
      '> - 界👩‍💻e\u0301\n>   continuation',
      '```dart\nconst text = "界👩‍💻e\\u0301";\n```',
      '| 界 | 👩‍💻 |\n|---|---|\n| e\u0301 | value |',
      '[x](https://example.com) **界👩‍💻e\u0301**',
    ];
    for (final size in [_wide, _narrow]) {
      testWidgets(
        'widths zero through three clip all block furniture at $size',
        (t) async {
          for (final source in fixtures) {
            for (var width = 0; width <= 3; width++) {
              await t.pumpWidget(
                Row(
                  children: [
                    SizedBox(width: width, child: Markdown(source)),
                    Text('|'),
                  ],
                ),
                size: size,
              );
              expect(t.screen.charAt(width, 0), '|');
              for (var y = 0; y < size.height; y++) {
                for (var x = width + 1; x < size.width; x++) {
                  expect(t.screen.charAt(x, y), ' ');
                }
              }
            }
          }
        },
      );

      testWidgets('body graphemes wrap whole at the edge at $size', (t) async {
        for (final cluster in ['界', '👩‍💻', 'e\u0301']) {
          for (var offset = 0; offset < 3; offset++) {
            await _show(
              t,
              '${'x' * offset}${cluster}z',
              size,
              width: offset + graphemeWidth(cluster),
            );
            expect(t.screen.charAt(offset, 0), cluster);
            expect(t.screen.lines[1], 'z');
          }
        }
      });

      testWidgets(
        'a mounted streamed reply matches fresh rendering at every prefix at $size',
        (t) async {
          const source =
              '[a][r]\n\n```\n界👩‍💻e\u0301\n```\n\n| a | b |\n|---|---|\n| 界\n\n[r]: <https://example.com>';
          final value = ValueNotifier('');
          final fresh = WidgetTester();
          try {
            await t.pumpWidget(
              ListenableBuilder(
                listenable: value,
                builder: (context) => Markdown(value.value),
              ),
              size: size,
            );
            for (var end = 0; end <= source.length; end++) {
              value.value = source.substring(0, end);
              await t.pump();
              await fresh.pumpWidget(Markdown(value.value), size: size);
              expect(
                t.screen.buffer.lines,
                fresh.screen.buffer.lines,
                reason: 'prefix $end',
              );
              expect(
                [
                  for (var y = 0; y < size.height; y++)
                    for (var x = 0; x < size.width; x++) t.screen.styleAt(x, y),
                ],
                [
                  for (var y = 0; y < size.height; y++)
                    for (var x = 0; x < size.width; x++)
                      fresh.screen.styleAt(x, y),
                ],
                reason: 'styles at prefix $end',
              );
            }
            t.dispose();
          } finally {
            fresh.dispose();
            value.dispose();
          }
        },
      );

      testWidgets(
        'escape sequences in text code tables and links do not move cells at $size',
        (t) async {
          for (final source in [
            'a\x1b[31mb\x1b[0mc',
            '```unknown\na\x1b[31mb\x1b[0mc\n```',
            '| h |\n|---|\n| a\x1b[31mb\x1b[0mc |',
          ]) {
            await _show(t, source, size);
            expect(t.screen.text, contains('abc'));
            expect(t.screen.text, isNot(contains('\x1b')));
            for (var y = 0; y < size.height; y++) {
              for (var x = 0; x < size.width; x++) {
                expect(t.screen.styleAt(x, y).fg, isNot(const IndexedColor(1)));
              }
            }
          }
        },
      );
    }

    testWidgets('unbounded width and zero viewport recover after resize', (
      t,
    ) async {
      await t.pumpWidget(
        Row(children: [const Markdown('**界e\u0301**'), Text('|')]),
      );
      expect(t.screen.lines.first, '界e\u0301|');
      await t.resize(const Size(0, 0));
      expect(t.screen.text, isEmpty);
      await t.resize(const Size(1, 1));
      await t.resize(_narrow);
      expect(t.screen.lines.first, '界e\u0301|');
    });

    testWidgets('a thousand updates then replacement drops obsolete blocks', (
      t,
    ) async {
      final value = ValueNotifier('# retained\n\ntail');
      await t.pumpWidget(
        ListenableBuilder(
          listenable: value,
          builder: (context) => Markdown(value.value),
        ),
      );
      for (var i = 0; i < 1000; i++) {
        value.value = '# retained\n\ntail $i';
      }
      await t.pump();
      expect(t.screen.lines.take(3), ['retained', '', 'tail 999']);
      value.value = '![gone](image.png)';
      await t.pump();
      expect(t.screen.text, isEmpty);
      value.value = '> new';
      await t.pump();
      expect(t.screen.text, '│ new');
      t.dispose();
      value.dispose();
    });
  });
  group('tester: passive focus', () {
    testWidgets('focus moving away and back does not change the content', (
      t,
    ) async {
      final first = FocusNode();
      final second = FocusNode();
      await t.pumpWidget(
        Column(
          children: [
            Focus(focusNode: first, child: const Markdown('**text**')),
            Focus(focusNode: second, child: Text('other')),
          ],
        ),
      );
      final before = t.screen.buffer.lines;
      for (final node in [first, second, first]) {
        node.requestFocus();
        await t.pump();
        await t.press('enter');
        expect(t.screen.buffer.lines, before);
      }
      t.dispose();
      first.dispose();
      second.dispose();
    });
  });

  group('a growing reply', () {
    for (final size in [_wide, _narrow]) {
      testWidgets('colours its open code block whole once finished at $size', (
        t,
      ) async {
        // javascript names an arrow function only once the next line is
        // known: frozen while growing, the name keeps its plain colour.
        const source = '```js\nconst f =\n(x) => x;';
        final value = ValueNotifier(('', true));
        await t.pumpWidget(
          ListenableBuilder(
            listenable: value,
            builder: (context) =>
                Markdown(value.value.$1, growing: value.value.$2),
          ),
          size: size,
        );
        for (final end in [source.indexOf('=') + 2, source.length]) {
          value.value = (source.substring(0, end), true);
          await t.pump();
        }
        final y = t.screen.lines.indexWhere((l) => l.contains('const f'));
        final x = _at(t, y, 'const f') + 6;
        final growing = t.screen.styleAt(x, y);

        value.value = (source, false);
        await t.pump();
        final finished = t.screen.styleAt(x, y);
        final fresh = WidgetTester();
        await fresh.pumpWidget(const Markdown(source), size: size);
        expect(finished, fresh.screen.styleAt(x, y));
        expect(finished, isNot(growing));
        expect(t.screen.lines, fresh.screen.lines);
      });

      testWidgets('colours a code block whole once another follows at $size', (
        t,
      ) async {
        const code = '```js\nconst f =\n(x) => x;\n```';
        final value = ValueNotifier('```js\nconst f =\n');
        await t.pumpWidget(
          ListenableBuilder(
            listenable: value,
            builder: (context) => Markdown(value.value, growing: true),
          ),
          size: size,
        );
        value.value = code;
        await t.pump();
        value.value = '$code\n\nafter';
        await t.pump();
        final fresh = WidgetTester();
        await fresh.pumpWidget(Markdown(value.value), size: size);
        expect(t.screen.lines, fresh.screen.lines);
        expect(
          [
            for (var y = 0; y < size.height; y++)
              for (var x = 0; x < size.width; x++) t.screen.styleAt(x, y),
          ],
          [
            for (var y = 0; y < size.height; y++)
              for (var x = 0; x < size.width; x++) fresh.screen.styleAt(x, y),
          ],
        );
      });
    }
  });
}

void _testerGrowingCases() {
  group('tester: growing nested code and resize', () {
    for (final size in [_wide, _narrow]) {
      testWidgets('nested code always uses whole colours at $size', (t) async {
        const source = '> ```js\n> const nested =\n> (x) => x;\n> ```';
        final fresh = WidgetTester();
        try {
          await t.pumpWidget(const Markdown(source, growing: true), size: size);
          await fresh.pumpWidget(const Markdown(source), size: size);
          expect(t.screen.lines, fresh.screen.lines);
          for (var y = 0; y < size.height; y++) {
            for (var x = 0; x < size.width; x++) {
              expect(t.screen.styleAt(x, y), fresh.screen.styleAt(x, y));
            }
          }
        } finally {
          fresh.dispose();
        }
      });
    }

    testWidgets('a thousand code updates finish whole after resize', (t) async {
      final value = ValueNotifier(('```js\nconst resized =\n', true));
      final fresh = WidgetTester();
      try {
        await t.pumpWidget(
          ListenableBuilder(
            listenable: value,
            builder: (context) =>
                Markdown(value.value.$1, growing: value.value.$2),
          ),
          size: _wide,
        );
        for (var i = 0; i < 1000; i++) {
          value.value = ('```js\nconst resized =\n(x) => x + $i;\n```', true);
        }
        await t.pump();
        await t.resize(_narrow);
        value.value = (value.value.$1, false);
        await t.pump();
        await fresh.pumpWidget(Markdown(value.value.$1), size: _narrow);
        expect(t.screen.lines, fresh.screen.lines);
        for (var y = 0; y < _narrow.height; y++) {
          for (var x = 0; x < _narrow.width; x++) {
            expect(t.screen.styleAt(x, y), fresh.screen.styleAt(x, y));
          }
        }
      } finally {
        t.dispose();
        fresh.dispose();
        value.dispose();
      }
    });
  });
}

/// What a drag over the whole first row selects.
Future<String?> _firstRowSelection(
  WidgetTester t,
  SelectionController c,
) async {
  MouseEvent at(MouseEventKind kind, int x) =>
      MouseEvent(kind, position: Offset(x, 0), button: MouseButton.primary);
  await t.mouse(at(MouseEventKind.press, 0));
  await t.mouse(at(MouseEventKind.move, t.screen.lines[0].length));
  await t.mouse(at(MouseEventKind.release, t.screen.lines[0].length));
  return c.snapshot()?.text;
}

void _leadingWhitespaceCases() {
  group('a paragraph line drops its leading whitespace', () {
    for (final size in [_wide, _narrow]) {
      testWidgets('drawn, and around a hard break, at $size', (t) async {
        await _show(t, ' Late work 1.\n\n- i\n\n   x\n\na  \n   b', size);
        expect(_rows(t, 8), [
          'Late work 1.',
          '',
          '- i',
          '',
          '  x',
          '',
          'a',
          'b',
        ]);
      });

      testWidgets('code keeps its indentation at $size', (t) async {
        await _show(t, ' para\n\n    code\n      more', size);
        expect(t.screen.lines[0], 'para');
        final y = t.screen.lines.indexWhere((l) => l.contains('code'));
        expect(t.screen.lines[y + 1].indexOf('more') - _at(t, y, 'code'), 2);
      });

      for (final bound in [false, true]) {
        testWidgets('selected and copied as drawn bound=$bound at $size', (
          t,
        ) async {
          const text = ' Late work 1.';
          final c = SelectionController();
          await t.pumpWidget(
            SelectionArea(
              controller: c,
              selectionStyle: const Style(inverse: true),
              child: bound
                  ? Markdown.fromSelectionSource(
                      SelectionSource.markdown(
                        id: 'reply',
                        revision: 0,
                        text: text,
                      ),
                    )
                  : const Markdown(text),
            ),
            size: size,
          );
          expect(t.screen.lines[0], 'Late work 1.');
          expect(await _firstRowSelection(t, c), 'Late work 1.');
          c.dispose();
        });
      }

      testWidgets('a growing reply whose first chunk starts with a space '
          'at $size', (t) async {
        final value = ValueNotifier((' Late', true));
        final c = SelectionController();
        await t.pumpWidget(
          SelectionArea(
            controller: c,
            selectionStyle: const Style(inverse: true),
            child: ListenableBuilder(
              listenable: value,
              builder: (context) =>
                  Markdown(value.value.$1, growing: value.value.$2),
            ),
          ),
          size: size,
        );
        expect(t.screen.lines[0], 'Late');
        value.value = (' Late work', true);
        await t.pump();
        expect(t.screen.lines[0], 'Late work');
        value.value = (' Late work 1.', true);
        await t.pump();
        expect(t.screen.lines[0], 'Late work 1.');
        expect(await _firstRowSelection(t, c), 'Late work 1.');
        value.value = (' Late work 1.', false);
        await t.pump();
        expect(t.screen.lines[0], 'Late work 1.');
        c.dispose();
        value.dispose();
      });
    }
  });
}
