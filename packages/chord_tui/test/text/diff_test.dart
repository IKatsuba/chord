import 'package:chord_tui/src/text/diff.dart';
import 'package:test/test.dart';

/// Each hunk's lines as ` 2 text`, `+3 text`, `-2 text`, hunks split by `…`.
List<String> _rows(DiffModel model) => [
  for (final (i, hunk) in model.hunks.indexed) ...[
    if (i > 0) '…',
    for (final line in hunk.lines) '$line',
  ],
];

const _old = '''export function greet(name: string): string {
  return "hello " + name;
}
''';

const _new = '''/** Greets someone by name. */
export function greet(name: string): string {
  return `hello, \${name}`;
}
''';

String _lines(int n, [String? Function(int)? at]) =>
    [for (var i = 1; i <= n; i++) at?.call(i) ?? 'line $i'].join('\n');

void main() {
  group('diffTexts', () {
    test('numbers removals by the old file, the rest by the new', () {
      expect(_rows(diffTexts(_old, _new)), [
        '+1 /** Greets someone by name. */',
        ' 2 export function greet(name: string): string {',
        '-2   return "hello " + name;',
        '+3   return `hello, \${name}`;',
        ' 4 }',
      ]);
    });

    test('equal texts have no hunks; line endings are no edit', () {
      expect(diffTexts('a\nb\n', 'a\nb\n').hunks, isEmpty);
      expect(diffTexts('a\r\nb\r\n', 'a\nb').hunks, isEmpty);
      expect(diffTexts('a\nb', 'a\nb\n').hunks, isEmpty);
      expect(diffTexts('', '').hunks, isEmpty);
    });

    test('a new file is all additions, a removed one all removals', () {
      expect(_rows(diffTexts('', 'a\n\nb')), ['+1 a', '+2 ', '+3 b']);
      expect(_rows(diffTexts('a\nb\n', '')), ['-1 a', '-2 b']);
    });

    test('context surrounds each change; far changes make two hunks', () {
      final old = _lines(20);
      final fresh = _lines(20, (i) => i == 2 || i == 18 ? 'new $i' : null);
      final model = diffTexts(old, fresh);
      expect(model.hunks, hasLength(2));
      expect(_rows(model), [
        ' 1 line 1',
        '-2 line 2',
        '+2 new 2',
        ' 3 line 3',
        ' 4 line 4',
        ' 5 line 5',
        '…',
        ' 15 line 15',
        ' 16 line 16',
        ' 17 line 17',
        '-18 line 18',
        '+18 new 18',
        ' 19 line 19',
        ' 20 line 20',
      ]);
      expect(model.hunks.first.oldStart, 1);
      expect(model.hunks.first.oldCount, 5);
      expect(model.hunks.last.newStart, 15);
      expect(model.numberWidth, 2);
    });

    test('hunks whose context meets merge', () {
      final old = _lines(12);
      final fresh = _lines(12, (i) => i == 3 || i == 9 ? 'new $i' : null);
      expect(diffTexts(old, fresh).hunks, hasLength(1));
      expect(diffTexts(old, fresh, context: 1).hunks, hasLength(2));
      expect(
        _rows(diffTexts(old, fresh, context: 0)).where((r) => r == '…'),
        hasLength(1),
      );
    });

    test('a negative context is refused', () {
      expect(() => diffTexts('a', 'b', context: -1), throwsRangeError);
    });

    test('lines index their sources: old for removals, new otherwise', () {
      final model = diffTexts('a\r\nb\r\nc', 'a\nB\nc');
      expect(model.sources, ['a\nb\nc', 'a\nB\nc']);
      for (final line in model.hunks.single.lines) {
        final source = model.sources[line.source].split('\n');
        expect(source[line.line], line.text);
        expect(line.source, line.kind == DiffKind.removed ? 0 : 1);
      }
    });

    test('blank lines and spaces are kept', () {
      expect(_rows(diffTexts('x\n', 'x\n\n  \t \n')), [
        ' 1 x',
        '+2 ',
        '+3   \t ',
      ]);
    });
  });

  group('parseUnifiedDiff', () {
    const patch = '''diff --git a/src/greeting.ts b/src/greeting.ts
--- a/src/greeting.ts
+++ b/src/greeting.ts
@@ -1,3 +1,4 @@
+/** Greets someone by name. */
 export function greet(name: string): string {
-  return "hello " + name;
+  return `hello, \${name}`;
 }
@@ -10,2 +11,2 @@
 save();
-load();
+reload();
\\ No newline at end of file
''';

    test('reads hunks as a generated diff numbers them', () {
      final model = parseUnifiedDiff(patch);
      expect(model.path, 'src/greeting.ts');
      expect(_rows(model), [
        '+1 /** Greets someone by name. */',
        ' 2 export function greet(name: string): string {',
        '-2   return "hello " + name;',
        '+3   return `hello, \${name}`;',
        ' 4 }',
        '…',
        ' 11 save();',
        '-11 load();',
        '+12 reload();',
      ]);
      expect(_rows(model).take(5), _rows(diffTexts(_old, _new)));
    });

    test('each hunk\'s runs are its sources, highlighted apart', () {
      final model = parseUnifiedDiff(patch);
      expect(model.sources, [
        'export function greet(name: string): string {\n'
            '  return "hello " + name;\n}',
        '/** Greets someone by name. */\n'
            'export function greet(name: string): string {\n'
            '  return `hello, \${name}`;\n}',
        'save();\nload();',
        'save();\nreload();',
      ]);
      for (final hunk in model.hunks) {
        for (final line in hunk.lines) {
          expect(model.sources[line.source].split('\n')[line.line], line.text);
        }
      }
    });

    test('a deleted file is named by its old path; a bare hunk by none', () {
      expect(
        parseUnifiedDiff(
          '--- a/gone.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-x\n',
        ).path,
        'gone.txt',
      );
      final bare = parseUnifiedDiff('@@ -1 +1 @@\n-a\n+b\n');
      expect(bare.path, isNull);
      expect(_rows(bare), ['-1 a', '+1 b']);
    });

    test('reads leniently, as jsdiff, the original\'s parser, reads', () {
      // A count of 1 with no such line reads as 0: `@@ -1 +1 @@` leaves
      // its counts out.
      final added = parseUnifiedDiff('@@ -1 +1 @@\n+b');
      expect(added.hunks.single.oldCount, 0);
      expect(_rows(added), ['+1 b']);
      final removed = parseUnifiedDiff('@@ -1 +1 @@\n-a');
      expect(removed.hunks.single.newCount, 0);
      expect(_rows(removed), ['-1 a']);
      // An empty line in a hunk is a blank context line whose space an
      // editor stripped.
      expect(_rows(parseUnifiedDiff('@@ -1 +1 @@\n\n')), [' 1 ']);
      expect(_rows(parseUnifiedDiff('@@ -1,2 +1,2 @@\n a\n\n')), [
        ' 1 a',
        ' 2 ',
      ]);
      // Any line starting with a backslash is metadata, drawn as nothing.
      expect(_rows(parseUnifiedDiff('@@ -1 +1 @@\n-a\n+b\n\\ nonsense\n')), [
        '-1 a',
        '+1 b',
      ]);
    });

    test('blank text is an empty diff', () {
      expect(parseUnifiedDiff('').hunks, isEmpty);
      expect(parseUnifiedDiff('\n \n').hunks, isEmpty);
    });

    test('malformed patches are refused', () {
      for (final bad in [
        '@@ -1,2 +1,2 @@\n-a\n+b\n', // fewer lines than the counts
        '@@ -1,2 +1,2 @@\n-a\n+b', // the same, with no final line break
        '@@ -1 +1 @@\n-a\n-b\n+c\n', // more lines than the counts
        '@@ -1 +1 @@\n*a\n', // a line with no prefix
        '@@ nonsense @@\n-a\n',
        'not a patch at all',
        '@@ -5 +5 @@\n-a\n+b\n@@ -3 +3 @@\n-c\n+d\n', // hunks out of order
      ]) {
        expect(() => parseUnifiedDiff(bad), throwsFormatException, reason: bad);
      }
    });

    test('a patch of several files is refused', () {
      expect(
        () => parseUnifiedDiff(
          '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n'
          '--- a/y\n+++ b/y\n@@ -1 +1 @@\n-c\n+d\n',
        ),
        throwsFormatException,
      );
    });
  });
  group('tester: diff boundaries and source consistency', () {
    test('a single blank line is content on an otherwise empty side', () {
      expect(_rows(diffTexts('', '\n')), ['+1 ']);
      expect(_rows(diffTexts('\n', '')), ['-1 ']);
      expect(_rows(diffTexts('\n', '\n\n')), [' 1 ', '+2 ']);
      expect(diffTexts('\r\n', '\n').hunks, isEmpty);
    });

    test(
      'missing final newline is ignored symmetrically without losing blanks',
      () {
        for (final text in ['a', '界👩‍💻e\u0301', '  \t ', 'a\n\nlast']) {
          expect(diffTexts(text, '$text\n').hunks, isEmpty);
          expect(diffTexts('$text\n', text).hunks, isEmpty);
        }
        expect(_rows(diffTexts('a\n', 'a\n\n')), [' 1 a', '+2 ']);
      },
    );

    test('small generated diffs reconstruct both sides with full context', () {
      final texts = [
        '',
        '\n',
        'a',
        'a\n',
        'a\n\n',
        'b\na',
        'a\nb\na',
        '界\n👩‍💻\ne\u0301',
        '  \t \nlast',
      ];
      List<String> lines(String text) {
        if (text.isEmpty) return [];
        final result = text.replaceAll('\r\n', '\n').split('\n');
        if (result.last.isEmpty) result.removeLast();
        return result;
      }

      for (final old in texts) {
        for (final fresh in texts) {
          final model = diffTexts(old, fresh, context: 100);
          if (model.hunks.isEmpty) {
            expect(lines(old), lines(fresh));
            continue;
          }
          expect(model.hunks, hasLength(1));
          final rows = model.hunks.single.lines;
          expect(
            rows.where((r) => r.kind != DiffKind.added).map((r) => r.text),
            lines(old),
          );
          expect(
            rows.where((r) => r.kind != DiffKind.removed).map((r) => r.text),
            lines(fresh),
          );
          for (final row in rows) {
            expect(model.sources[row.source].split('\n')[row.line], row.text);
          }
        }
      }
    });

    test(
      'unified creation and deletion preserve empty-side counts and path',
      () {
        final created = parseUnifiedDiff(
          '--- /dev/null\n+++ b/new.dart\n@@ -0,0 +1,2 @@\n+one\n+\n',
        );
        expect(created.path, 'new.dart');
        expect(_rows(created), ['+1 one', '+2 ']);
        expect(created.hunks.single.oldCount, 0);
        final removed = parseUnifiedDiff(
          '--- a/gone.dart\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-one\n-\n',
        );
        expect(removed.path, 'gone.dart');
        expect(_rows(removed), ['-1 one', '-2 ']);
        expect(removed.hunks.single.newCount, 0);
      },
    );

    test('no-newline metadata never takes a source index or number', () {
      final model = parseUnifiedDiff(
        '@@ -7,2 +9,2 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file\n tail',
      );
      expect(_rows(model), ['-7 old', '+9 new', ' 10 tail']);
      expect(model.sources, ['old\ntail', 'new\ntail']);
      for (final row in model.hunks.single.lines) {
        expect(model.sources[row.source].split('\n')[row.line], row.text);
      }
    });

    test('unified content retains signs tabs spaces and Unicode literally', () {
      final model = parseUnifiedDiff(
        '@@ -1 +1 @@\n--界\t e\u0301  \n++👩‍💻  \n',
      );
      expect(_rows(model), ['-1 -界\t e\u0301  ', '+1 +👩‍💻  ']);
      expect(model.sources, ['-界\t e\u0301  ', '+👩‍💻  ']);
    });

    test(
      'malformed ranges and overlapping hunks fail without partial output',
      () {
        for (final patch in [
          '@@ -1,3 +1,3 @@\n a\n-b\n+B\n',
          '@@ -1 +1 @@\n-a\n+b\n?garbage\n',
          '@@ -1 +1 @@\n-a\n+b\n@@ -1 +2 @@\n-c\n+d\n',
          '@@ -1 +2 @@\n-a\n+b\n@@ -2 +2 @@\n-c\n+d\n',
          '--- a/x\n+++ b/x\n',
        ]) {
          expect(
            () => parseUnifiedDiff(patch),
            throwsFormatException,
            reason: patch,
          );
        }
      },
    );

    test(
      'disjoint unified hunks retain starts and independent source runs',
      () {
        final model = parseUnifiedDiff(
          '@@ -9 +10 @@\n-a\n+b\n@@ -99 +100 @@\n-c\n+d\n',
        );
        expect(model.numberWidth, 3);
        expect(_rows(model), ['-9 a', '+10 b', '…', '-99 c', '+100 d']);
        expect(model.sources, ['a', 'b', 'c', 'd']);
        expect(model.hunks.map((h) => (h.oldStart, h.newStart)), [
          (9, 10),
          (99, 100),
        ]);
      },
    );
  });
}
