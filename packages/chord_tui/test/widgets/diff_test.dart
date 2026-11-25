import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/diff.dart'
    show parseUnifiedDiffRemembered, unifiedParses;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _wide = Size(120, 40);
const _narrow = Size(80, 24);

final _dark = ThemeData.dark();

const _old = '''export function greet(name: string): string {
  return "hello " + name;
}
''';

const _new = '''/** Greets someone by name. */
export function greet(name: string): string {
  return `hello, \${name}`;
}
''';

/// The edit.png rows, without the port's words.
const _edit = [
  'src/greeting.ts',
  '1 + /** Greets someone by name. */',
  '2   export function greet(name: string): string {',
  '2 -   return "hello " + name;',
  '3 +   return `hello, \${name}`;',
  '4   }',
];

List<String> _rows(WidgetTester t, int n) => t.screen.lines.take(n).toList();

Widget _themed(ThemeData theme, Widget child) =>
    Theme(data: theme, child: child);

void main() {
  for (final size in [_wide, _narrow]) {
    group('at ${size.width}x${size.height}', () {
      testWidgets('draws chord\'s edit: a dim title, one gutter, signs', (
        t,
      ) async {
        await t.pumpWidget(
          Diff(_old, _new, title: 'src/greeting.ts'),
          size: size,
        );
        expect(_rows(t, 7), [..._edit, '']);
        expect(t.screen.styleAt(0, 0), Style.dim);
      });

      testWidgets('changed rows are tinted across the whole row', (t) async {
        await t.pumpWidget(
          Diff(_old, _new, title: 'src/greeting.ts'),
          size: size,
        );
        final tint = _dark.diff.tint!;
        for (final x in [0, 1, 2, 3, 10, size.width - 1]) {
          expect(t.screen.styleAt(x, 1).bg, tint.added.bg, reason: 'x $x');
          expect(t.screen.styleAt(x, 3).bg, tint.removed.bg, reason: 'x $x');
          expect(t.screen.styleAt(x, 2).bg, isNull, reason: 'x $x');
        }
        expect(t.screen.styleAt(0, 1), Style(dim: true, bg: tint.added.bg));
        expect(
          t.screen.styleAt(2, 1),
          _dark.diff.added.copyWith(bg: tint.added.bg),
        );
        expect(
          t.screen.styleAt(2, 3),
          _dark.diff.removed.copyWith(bg: tint.removed.bg),
        );
      });

      testWidgets('code is highlighted: terminal tones on context, tint '
          'tones on changes', (t) async {
        await t.pumpWidget(
          Diff(_old, _new, title: 'src/greeting.ts'),
          size: size,
        );
        final code = _dark.code!;
        final tint = _dark.diff.tint!;
        // `export` on the context row.
        expect(t.screen.styleAt(4, 2), code.terminal.keyword);
        // `return` on the removed row, on its tint.
        expect(
          t.screen.styleAt(6, 3),
          tint.text.merge(code.tint.keyword).copyWith(bg: tint.removed.bg),
        );
      });

      testWidgets('a wrapped line goes on under its code, gutter blank', (
        t,
      ) async {
        const long =
            "  return 'A message about terminal cells, 日本語, and preserving "
            "every grapheme while the source line wraps';";
        final old = '${List.generate(11, (i) => 'l$i').join('\n')}\n$long\n';
        final fresh =
            "${List.generate(11, (i) => 'l$i').join('\n')}\n"
            "  return 'A shorter message';\n";
        await t.pumpWidget(Diff(old, fresh, context: 0), size: size);
        if (size == _wide) {
          expect(_rows(t, 2), [
            '12 - $long',
            "12 +   return 'A shorter message';",
          ]);
        } else {
          expect(_rows(t, 3), [
            "12 -   return 'A message about terminal cells, 日本語, and preserving "
                'every',
            // At the code column, under the source's own indentation.
            '     grapheme while the source line wraps\';',
            "12 +   return 'A shorter message';",
          ]);
          // The continuation is tinted from its first cell.
          expect(t.screen.styleAt(0, 1).bg, _dark.diff.tint!.removed.bg);
        }
      });

      testWidgets('a gap row stands between hunks, in the sign column', (
        t,
      ) async {
        final old = List.generate(20, (i) => 'line ${i + 1}').join('\n');
        final fresh = old
            .replaceFirst('line 2\n', 'two\n')
            .replaceFirst('line 18\n', 'eighteen\n');
        await t.pumpWidget(Diff(old, fresh), size: size);
        final lines = t.screen.lines;
        expect(lines[0], ' 1   line 1');
        final gap = lines.indexOf('   …');
        expect(gap, 6);
        expect(t.screen.styleAt(3, gap), Style.dim);
        expect(lines[gap + 1], '15   line 15');
        expect(lines.where((l) => l.trim() == '…'), hasLength(1));
        expect(lines[gap + 7], '20   line 20');
        expect(lines[gap + 8], '');
      });

      testWidgets('without a tint the changed line takes the sign\'s colour', (
        t,
      ) async {
        final theme = _dark.copyWith(
          diff: DiffTheme(added: _dark.diff.added, removed: _dark.diff.removed),
        );
        await t.pumpWidget(
          _themed(theme, Diff(_old, _new, title: 'src/greeting.ts')),
          size: size,
        );
        expect(t.screen.styleAt(10, 3), _dark.diff.removed);
        expect(t.screen.styleAt(10, 1), _dark.diff.added);
        expect(t.screen.styleAt(10, 1).bg, isNull);
        expect(t.screen.styleAt(4, 2), _dark.code!.terminal.keyword);
      });

      testWidgets('the plain theme keeps signs and geometry, no colour', (
        t,
      ) async {
        await t.pumpWidget(
          _themed(
            ThemeData.plain(),
            Diff(_old, _new, title: 'src/greeting.ts'),
          ),
          size: size,
        );
        expect(_rows(t, 6), _edit);
        for (var y = 0; y < 6; y++) {
          for (var x = 0; x < size.width; x++) {
            final s = t.screen.styleAt(x, y);
            expect((s.fg, s.bg), (null, null), reason: '($x, $y)');
          }
        }
      });

      testWidgets('an unknown language is tinted but not coloured', (t) async {
        await t.pumpWidget(
          Diff(_old, _new, title: 'notes.nolanguage'),
          size: size,
        );
        final tint = _dark.diff.tint!;
        expect(t.screen.styleAt(6, 3), tint.text.copyWith(bg: tint.removed.bg));
        expect(t.screen.styleAt(4, 2), Style.plain);
      });

      testWidgets('an empty changed line still shows its tint and sign', (
        t,
      ) async {
        await t.pumpWidget(Diff('a\n', 'a\n\n'), size: size);
        expect(_rows(t, 2), ['1   a', '2 +']);
        expect(
          t.screen.styleAt(size.width - 1, 1).bg,
          _dark.diff.tint!.added.bg,
        );
      });

      testWidgets('equal texts draw only the title', (t) async {
        await t.pumpWidget(
          Column(
            children: [
              Diff('a\n', 'a', title: 'x.txt'),
              Text('end'),
            ],
          ),
          size: size,
        );
        expect(_rows(t, 2), ['x.txt', 'end']);
        await t.pumpWidget(
          Column(children: [Diff('a', 'a'), Text('end')]),
          size: size,
        );
        expect(_rows(t, 1), ['end']);
      });

      testWidgets('tabs take two cells; spaces are kept', (t) async {
        await t.pumpWidget(Diff('', '\tx  y\n'), size: size);
        expect(_rows(t, 1), ['1 +   x  y']);
      });

      testWidgets('a comment opened above the context colours the row', (
        t,
      ) async {
        final old =
            '/*\n${List.generate(10, (i) => ' * c$i').join('\n')}\n */\nint x;\n';
        final fresh = old.replaceFirst('int x;', 'int y;');
        await t.pumpWidget(Diff(old, fresh, title: 'a.c'), size: size);
        // The first context row is inside the comment.
        expect(t.screen.lines[1], startsWith('10    * c8'));
        expect(t.screen.styleAt(6, 1), _dark.code!.terminal.comment);
      });

      testWidgets('a narrow constraint clips and never paints past it', (
        t,
      ) async {
        for (final width in [0, 2, 5]) {
          await t.pumpWidget(
            Row(
              children: [
                SizedBox(width: width, child: Diff(_old, _new)),
                Text('|'),
              ],
            ),
            size: size,
          );
          for (var y = 0; y < 6; y++) {
            for (var x = width + 1; x < size.width; x++) {
              expect(t.screen.charAt(x, y), ' ', reason: 'w$width ($x, $y)');
            }
          }
        }
      });

      testWidgets('a unified diff draws as the generated one', (t) async {
        const patch = '''--- a/src/greeting.ts
+++ b/src/greeting.ts
@@ -1,3 +1,4 @@
+/** Greets someone by name. */
 export function greet(name: string): string {
-  return "hello " + name;
+  return `hello, \${name}`;
 }
''';
        await t.pumpWidget(Diff.fromUnified(patch), size: size);
        final unified = t.screen.lines;
        final styles = [for (var x = 0; x < 30; x++) t.screen.styleAt(x, 3)];
        await t.pumpWidget(
          Diff(_old, _new, title: 'src/greeting.ts'),
          size: size,
        );
        expect(unified, t.screen.lines);
        expect([for (var x = 0; x < 30; x++) t.screen.styleAt(x, 3)], styles);
        await t.pumpWidget(
          Diff.fromUnified(patch, title: 'other.ts'),
          size: size,
        );
        expect(t.screen.lines[0], 'other.ts');
      });
    });
  }

  test('the same patch is parsed once, however often it is built', () {
    const patch = '--- a/once.txt\n+++ b/once.txt\n@@ -1 +1 @@\n-a\n+b\n';
    final before = unifiedParses;
    Diff.fromUnified(patch);
    Diff.fromUnified(patch, title: 'other');
    expect(unifiedParses, before + 1);
    expect(
      identical(
        parseUnifiedDiffRemembered(patch),
        parseUnifiedDiffRemembered(patch),
      ),
      isTrue,
    );
    // A malformed patch is not remembered: it throws every time.
    for (var i = 0; i < 2; i++) {
      expect(
        () => Diff.fromUnified('@@ -1,2 +1,2 @@\n-a\n'),
        throwsFormatException,
      );
    }
  });

  test('the parse memo keeps the 64 latest patches', () {
    String patch(int i) => '@@ -1 +1 @@\n-a$i\n+b$i\n';
    final first = parseUnifiedDiffRemembered(patch(0));
    for (var i = 1; i < 64; i++) {
      parseUnifiedDiffRemembered(patch(i));
    }
    expect(identical(parseUnifiedDiffRemembered(patch(0)), first), isTrue);
    for (var i = 64; i < 128; i++) {
      parseUnifiedDiffRemembered(patch(i));
    }
    expect(identical(parseUnifiedDiffRemembered(patch(0)), first), isFalse);
  });

  test('a malformed or several-file patch is refused', () {
    expect(
      () => Diff.fromUnified('@@ -1,2 +1,2 @@\n-a\n'),
      throwsFormatException,
    );
    expect(
      () => Diff.fromUnified(
        '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n'
        '--- a/y\n+++ b/y\n@@ -1 +1 @@\n-c\n+d\n',
      ),
      throwsFormatException,
    );
  });

  testWidgets('a resize rewraps; a theme change recolours', (t) async {
    final long = 'x' * 100;
    await t.pumpWidget(Diff('a\n', '$long\n', title: 'a.ts'), size: _wide);
    expect(t.screen.lines[3], '');
    await t.resize(_narrow);
    expect(t.screen.lines[3], '    ${'x' * 24}');
    await t.pumpWidget(
      _themed(ThemeData.light(), Diff('a\n', '$long\n', title: 'a.ts')),
      size: _narrow,
    );
    expect(t.screen.styleAt(0, 1).bg, ThemeData.light().diff.tint!.removed.bg);
  });
  group('tester: Diff cells and retained state', () {
    for (final size in [_wide, _narrow]) {
      testWidgets(
        'zero to three cells keep tint and furniture inside the clip at $size',
        (t) async {
          for (var width = 0; width <= 3; width++) {
            await t.pumpWidget(
              Row(
                children: [
                  SizedBox(
                    width: width,
                    child: const Diff('界', '👩‍💻e\u0301'),
                  ),
                  Text('|'),
                ],
              ),
              size: size,
            );
            expect(t.screen.charAt(width, 0), '|');
            for (var y = 0; y < size.height; y++) {
              for (var x = width + 1; x < size.width; x++) {
                expect(t.screen.charAt(x, y), ' ');
                expect(t.screen.styleAt(x, y).bg, isNull);
              }
            }
          }
        },
      );

      testWidgets(
        'graphemes wrap whole with blank tinted continuation gutters at $size',
        (t) async {
          for (final cluster in ['界', '👩‍💻', 'e\u0301']) {
            for (var offset = 0; offset < 3; offset++) {
              final width = 4 + offset + graphemeWidth(cluster);
              await t.pumpWidget(
                Row(
                  children: [
                    SizedBox(
                      width: width,
                      child: Diff('', '${'x' * offset}${cluster}z'),
                    ),
                  ],
                ),
                size: size,
              );
              expect(t.screen.charAt(4 + offset, 0), cluster);
              expect(t.screen.lines[1], '    z');
              for (var x = 0; x < width; x++) {
                expect(t.screen.styleAt(x, 1).bg, _dark.diff.tint!.added.bg);
              }
            }
          }
        },
      );

      testWidgets(
        'source whitespace survives wrapping after the number column at $size',
        (t) async {
          await t.pumpWidget(
            Row(
              children: [SizedBox(width: 9, child: const Diff('', 'a      b'))],
            ),
            size: size,
          );
          expect(
            [for (var x = 4; x < 9; x++) t.screen.charAt(x, 0)].join(),
            'a    ',
          );
          expect(
            [for (var x = 4; x < 9; x++) t.screen.charAt(x, 1)].join(),
            '  b  ',
          );
          expect(t.screen.lines[1], '      b');
        },
      );

      testWidgets('title wraps safely and empty diff adds no rows at $size', (
        t,
      ) async {
        await t.pumpWidget(
          Row(
            children: [
              SizedBox(
                width: 3,
                child: Column(
                  children: [
                    const Diff('', '', title: 'abcdef'),
                    Text('end'),
                  ],
                ),
              ),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines.take(3), ['abc', 'def', 'end']);
      });
    }

    testWidgets('unbounded width and a zero viewport preserve complete rows', (
      t,
    ) async {
      await t.pumpWidget(
        Row(children: [const Diff('', '界e\u0301'), Text('|')]),
      );
      expect(t.screen.lines.first, '1 + 界e\u0301|');
      await t.resize(const Size(0, 0));
      expect(t.screen.text, isEmpty);
      await t.resize(const Size(1, 1));
      await t.resize(_wide);
      expect(t.screen.lines.first, '1 + 界e\u0301|');
    });

    testWidgets(
      'a thousand edits and switching constructors reset the displayed diff',
      (t) async {
        final phase = ValueNotifier(0);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: phase,
            builder: (context) => phase.value == 1001
                ? Diff.fromUnified('@@ -7 +9 @@\n-old\n+new\n')
                : Diff('old', 'new ${phase.value}'),
          ),
        );
        for (var i = 1; i <= 1000; i++) {
          phase.value = i;
        }
        await t.pump();
        expect(t.screen.lines.take(2), ['1 - old', '1 + new 1000']);
        phase.value = 1001;
        await t.pump();
        expect(t.screen.lines.take(2), ['7 - old', '9 + new']);
        phase.value = 2;
        await t.pump();
        expect(t.screen.lines.take(2), ['1 - old', '1 + new 2']);
        await t.pumpWidget(Text('removed'));
        phase.value = 3;
        await t.pump();
        expect(t.screen.text, 'removed');
        phase.dispose();
      },
    );

    testWidgets(
      'width theme and inherited style updates equal a fresh render',
      (t) async {
        final dark = ThemeData.dark();
        final theme = ValueNotifier(dark);
        final style = ValueNotifier(Style.plain);
        Widget content() => Theme(
          data: theme.value,
          child: DefaultTextStyle(
            style: style.value,
            child: Diff('old', '界e\u0301 ${'x' * 90}', title: 'file.dart'),
          ),
        );
        await t.pumpWidget(
          ListenableBuilder(
            listenable: theme,
            builder: (context) => ListenableBuilder(
              listenable: style,
              builder: (context) => content(),
            ),
          ),
          size: _wide,
        );
        await t.resize(_narrow);
        theme.value = ThemeData.light();
        style.value = Style.underline;
        await t.pump();
        final cells = t.screen.buffer.lines;
        final styles = [
          for (var y = 0; y < 10; y++)
            for (var x = 0; x < 80; x++) t.screen.styleAt(x, y),
        ];
        await t.pumpWidget(content(), size: _narrow);
        expect(t.screen.buffer.lines, cells);
        expect([
          for (var y = 0; y < 10; y++)
            for (var x = 0; x < 80; x++) t.screen.styleAt(x, y),
        ], styles);
        t.dispose();
        theme.dispose();
        style.dispose();
      },
    );
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
            Focus(focusNode: first, child: const Diff('old', 'new')),
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
}
