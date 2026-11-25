import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart'
    show shapeSelectionSource;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

// The original wraps a diff's code with message.ts's wrapLine: wrap-ansi
// with hard and trim, the indent on the first row only (CTUI-60). The rows
// below are docs/design/CTUI-60.md's, made with wrap-ansi 10.0.2.
const _patch = r'''--- a/src/greeting.ts
+++ b/src/greeting.ts
@@ -11,3 +11,3 @@
 export function greet(name: string): string {
-    return 'Hello, ' + name + '! Welcome back to the project, it is good to see you again today.';
+    return `Hello, ${name}! Welcome back to the project, it is good to see you again today, and here is a long_identifier_that_cannot_break_anywhere_at_all_in_this_row`;
 }
''';

const _rows = {
  115: [
    '11   export function greet(name: string): string {',
    "12 -     return 'Hello, ' + name + '! Welcome back to the project, it is good to see you again today.';",
    r'12 +     return `Hello, ${name}! Welcome back to the project, it is good to see you again today, and here is a',
    '     long_identifier_that_cannot_break_anywhere_at_all_in_this_row`;',
    '13   }',
  ],
  75: [
    '11   export function greet(name: string): string {',
    "12 -     return 'Hello, ' + name + '! Welcome back to the project, it is",
    "     good to see you again today.';",
    r'12 +     return `Hello, ${name}! Welcome back to the project, it is good to',
    '     see you again today, and here is a',
    '     long_identifier_that_cannot_break_anywhere_at_all_in_this_row`;',
    '13   }',
  ],
  40: [
    '11   export function greet(name:',
    '     string): string {',
    "12 -     return 'Hello, ' + name + '!",
    '     Welcome back to the project, it',
    '     is good to see you again',
    "     today.';",
    r'12 +     return `Hello, ${name}! Welcome',
    '     back to the project, it is good',
    '     to see you again today, and',
    '     here is a long_identifier_that_',
    '     cannot_break_anywhere_at_all_in',
    '     _this_row`;',
    '13   }',
  ],
};

DiffView _view(String patch) => parseUnifiedDiff(patch).view();

List<String> _shown(WidgetTester t) {
  final lines = [for (final line in t.screen.lines) line.trimRight()];
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

void main() {
  for (final MapEntry(key: width, value: rows) in _rows.entries) {
    testWidgets('wrapAnsi draws the original\'s rows at $width cells', (
      t,
    ) async {
      await t.pumpWidget(
        Diff.fromView(_view(_patch), showTitle: false, wrap: DiffWrap.wrapAnsi),
        size: Size(width, 20),
      );
      expect(_shown(t), rows);
      expect(
        Diff.measure(_view(_patch), width, wrap: DiffWrap.wrapAnsi),
        rows.length,
      );
    });
  }

  testWidgets('keepSpaces stays the default and draws as before', (t) async {
    await t.pumpWidget(
      Diff.fromView(_view(_patch), showTitle: false),
      size: const Size(40, 20),
    );
    final before = _shown(t);
    expect(before[1], startsWith('     string): string {'));
    await t.pumpWidget(
      Diff.fromView(_view(_patch), showTitle: false, wrap: DiffWrap.keepSpaces),
      size: const Size(40, 20),
    );
    expect(_shown(t), before);
  });

  testWidgets('a width inside the indent keeps as much as leaves one cell', (
    t,
  ) async {
    const patch = '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-        ab cd\n+x\n';
    // Room 3: the eight-space indent keeps two cells, and the code has the
    // one cell left on every row, as wrap-ansi wraps the trimmed line.
    await t.pumpWidget(
      Diff.fromView(_view(patch), showTitle: false, wrap: DiffWrap.wrapAnsi),
      size: const Size(7, 10),
    );
    expect(_shown(t), ['1 -   a', '    b', '    c', '    d', '1 + x']);
  });

  testWidgets('tabs are two spaces, and a blank line one row', (t) async {
    const patch = '--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n-\tab\n+\n x\n';
    await t.pumpWidget(
      Diff.fromView(_view(patch), showTitle: false, wrap: DiffWrap.wrapAnsi),
      size: const Size(20, 10),
    );
    expect(_shown(t), ['1 -   ab', '1 +', '2   x']);
  });

  testWidgets('the tint fills continuation rows too', (t) async {
    await t.pumpWidget(
      Diff.fromView(_view(_patch), showTitle: false, wrap: DiffWrap.wrapAnsi),
      size: const Size(40, 20),
    );
    final tint = ThemeData.dark().diff.tint!;
    for (final y in [2, 3, 4, 5]) {
      for (final x in [0, 4, 39]) {
        expect(t.screen.styleAt(x, y).bg, tint.removed.bg, reason: '$x,$y');
      }
    }
    for (final y in [6, 11]) {
      expect(t.screen.styleAt(39, y).bg, tint.added.bg, reason: 'row $y');
    }
  });

  testWidgets('codeInsetRight narrows the wrap, and the tint still fills', (
    t,
  ) async {
    await t.pumpWidget(
      Diff.fromView(_view(_patch), showTitle: false, wrap: DiffWrap.wrapAnsi),
      size: const Size(40, 20),
    );
    final narrow = _shown(t);
    await t.pumpWidget(
      Diff.fromView(
        _view(_patch),
        showTitle: false,
        wrap: DiffWrap.wrapAnsi,
        codeInsetRight: 2,
      ),
      size: const Size(42, 20),
    );
    // The code breaks where it does in 40 cells; the rows are 42 wide.
    expect(_shown(t), narrow);
    final tint = ThemeData.dark().diff.tint!;
    for (final y in [2, 3, 4, 5]) {
      expect(t.screen.styleAt(41, y).bg, tint.removed.bg, reason: 'row $y');
    }
    expect(
      Diff.measure(
        _view(_patch),
        42,
        wrap: DiffWrap.wrapAnsi,
        codeInsetRight: 2,
      ),
      narrow.length,
    );
  });

  test('codeInsetRight is never negative, and a bound Diff is checked', () {
    expect(
      () => SelectionSource.diff(
        id: Object(),
        revision: 0,
        view: _view(_patch),
        codeInsetRight: -1,
      ),
      throwsArgumentError,
    );
    final source = SelectionSource.diff(
      id: Object(),
      revision: 0,
      view: _view(_patch),
      codeInsetRight: 2,
    );
    expect(Diff.fromSelectionSource(source).codeInsetRight, 2);
    expect(
      () => Diff.fromSelectionSource(source, codeInsetRight: 0),
      throwsArgumentError,
    );
  });

  group('measure equals the drawn height', () {
    const gapPatch =
        '--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n a b c d e f\n-\t  gh ij kl mn\n+op\n'
        '@@ -20,2 +20,2 @@\n x\n-yy yy yy yy yy yy yy\n+zz\n';
    for (final wrap in DiffWrap.values) {
      for (final patch in [_patch, gapPatch]) {
        final view = _view(patch);
        testWidgets('${wrap.name}, ${patch == _patch ? 'long' : 'gaps'}, '
            'every width', (t) async {
          final widest = Diff.measure(view, 1 << 20, wrap: wrap) > 0 ? 160 : 0;
          for (var width = 1; width <= widest; width++) {
            await t.pumpWidget(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Diff.fromView(view, showTitle: false, wrap: wrap),
                  Text('END'),
                ],
              ),
              size: Size(width, 600),
            );
            final end = t.screen.lines.indexWhere(
              (line) => line.startsWith(width < 3 ? 'E' : 'END'),
            );
            expect(
              Diff.measure(view, width, wrap: wrap),
              end,
              reason: 'width $width',
            );
          }
        });
      }
    }
  });

  test('copying wrapped lines gives their source text whole', () {
    final view = _view(_patch);
    final source = SelectionSource.diff(
      id: 'diff',
      revision: 0,
      view: view,
      wrap: DiffWrap.wrapAnsi,
    );
    final shape = shapeSelectionSource(source, width: 40);
    expect(shape.rows.length, greaterThan(view.rows.length + 1));
    expect(
      shape.selectedText,
      [for (final row in view.rows.whereType<DiffLine>()) row.text].join('\n'),
    );
  });

  test('copying gives back the spaces the wrap does not draw', () {
    // An indent cut short, a trimmed end and a line of spaces only.
    const patch = '''--- a/f
+++ b/f
@@ -1,2 +1,2 @@
         abc def ghi  
-      
+x
''';
    final view = _view(patch);
    final whole = [
      for (final row in view.rows.whereType<DiffLine>()) row.text,
    ].join('\n');
    for (final width in [5, 7, 12, 40]) {
      final source = SelectionSource.diff(
        id: 'diff',
        revision: 0,
        view: view,
        wrap: DiffWrap.wrapAnsi,
      );
      expect(
        shapeSelectionSource(source, width: width).selectedText,
        whole,
        reason: 'at $width',
      );
    }
  });

  test('a source keeps its wrap, and a bound Diff is checked against it', () {
    final source = SelectionSource.diff(
      id: Object(),
      revision: 0,
      view: _view(_patch),
      wrap: DiffWrap.wrapAnsi,
    );
    expect(
      Diff.fromSelectionSource(source, wrap: DiffWrap.wrapAnsi).wrap,
      DiffWrap.wrapAnsi,
    );
    expect(Diff.fromSelectionSource(source).wrap, DiffWrap.wrapAnsi);
    expect(
      () => Diff.fromSelectionSource(source, wrap: DiffWrap.keepSpaces),
      throwsArgumentError,
    );
  });
}
