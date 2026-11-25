import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/highlight.dart' show highlightWhole;
import 'package:test/test.dart';

Style _c(int i) => Style(fg: IndexedColor(i));

/// Each class its own colour, so a wrong class shows as a wrong style.
final _tones = Tones(
  keyword: _c(1),
  string: _c(2),
  number: _c(3),
  comment: _c(4),
  title: _c(5),
  type: _c(6),
  name: _c(7),
  meta: _c(8),
);

/// Sources whose tokens span lines: block comments, docstrings, template
/// strings, heredocs, embedded languages; one for every common grammar.
const _samples = <String, String>{
  'dart': r'''
/// A doc comment
/// over two lines.
class Point {
  final int x;
  /* a block
     comment */
  String get label => """
    triple $x ${x + 1}
  """;
}
''',
  'typescript': r'''
interface A { b: number }
const s = `line one
line ${two} three`;
/**
 * @param x a value
 */
function f(x: string): void {
  return;
}
''',
  'python': '''
def f(x):
    """A docstring
    over lines."""
    s = \'\'\'raw
    text\'\'\'
    return x + 1  # comment
@decorator
class C: pass
''',
  'bash': r'''
#!/bin/bash
cat <<EOF
heredoc $HOME
still here
EOF
for i in 1 2; do echo "$i ${i}"; done
''',
  'json': '''
{
  "a": [1, 2.5, true, null],
  "b": {"c": "multi
line?"}
}
''',
  'yaml': '''
key: value
list:
  - one
  - "two"
block: |
  literal text
  more text
anchor: &a 12
''',
  'markdown': '''
# Title

Some *emphasis* and **strong** and `code`.

```js
const x = 1;
```

> a quote
- a bullet
''',
  'c': '''
#include <stdio.h>
/* a block comment
 * over lines
 */
int main(void) {
  printf("%d\\n", 1); // line
  return 0;
}
''',
  'xml': '''
<html>
<style>
body { color: red; }
p { margin: 0; }
</style>
<script>
const a = `x
y`;
function f() { return 1; }
</script>
<!-- a
comment -->
</html>
''',
  'rust': r'''
/// doc
fn main() {
    let s = r#"raw
string"#;
    /* nested /* block */ comment */
    println!("{}", s);
}
''',
  'ruby': '''
def f
  s = <<~TEXT
    heredoc
  TEXT
  =begin
  =end
end
''',
  'sql': '''
SELECT a, b -- comment
FROM t /* block
comment */ WHERE a = 'multi
line';
''',
  'php':
      '<?php\n\$s = <<<EOT\nheredoc\nEOT;\n/* c\n */ echo 1;\n?>\n<p>html</p>\n',
  'cpp': 'auto s = R"(raw\nstring)";\n/* a\n b */ int x;\n',
  'go': 'var s = `raw\nstring`\n/* a\nb */ func f() {}\n',
  'javascript': 'const a = `x\n\${y}\nz`;\nconst re = /a\\/b/g;\n',
  'css': 'a {\n  color: red; /* c\n */\n}\n@media (x) {\n p { margin: 0 }\n}\n',
  'kotlin': 'val s = """raw\nstring"""\n/* a\n*/ fun f() {}\n',
  'swift': 'let s = """\nraw\n"""\n/* a\n*/ func f() {}\n',
  'lua': 's = [[long\nstring]]\n--[[ block\ncomment ]] x = 1\n',
  'perl': 'my \$s = <<EOT;\nhere\nEOT\n=pod\ndoc\n=cut\nprint 1;\n',
  'shell': '\$ echo hi\nhi\n\$ ls\na b\n',
  'diff': '--- a\n+++ b\n@@ -1 +1 @@\n-x\n+y\n',
  'ini': '[s]\na = 1\n; c\n',
  'makefile': 'all: x\n\techo \$(CC)\n',
  'java': '/** doc\n * @param x\n */\nString s = """\ntext\n""";\n',
  'csharp': 'var s = @"verb\natim";\n/* a\n*/ int x;\n',
  'graphql': 'query {\n  a(b: "c") { d }\n}\n"""\ndoc\n"""\n',
  'scss': '\$x: 1;\n/* a\n*/ .a { .b { c: \$x } }\n',
  'r': 'x <- "a\nb"\nf <- function(x) x\n',
};

/// In [_samples], the lines a token spans: where a growing source may be
/// coloured differently from the whole until it stops growing.
const _spanning = <String, Set<int>>{
  'yaml': {4, 5, 6}, // a block scalar
  'rust': {2, 3}, // a raw string
  'ruby': {1, 2, 3}, // a heredoc
  'xml': {1, 2, 3, 4, 5, 6, 7, 8, 9}, // embedded css and javascript
};

/// Sources with a token that looks across a line break, each with the
/// lines that token touches.
const _crossing = <(String, String, Set<int>)>[
  ('markdown', 'A title\n===\n', {0, 1}), // a setext heading
  ('javascript', 'const f =\n(x) => x;\n', {0, 1}), // an arrow function
  ('typescript', 'const f =\n(x) => x;\n', {0, 1}),
  ('typescript', 'class\nFoo {}\n', {0, 1}),
  ('python', 'def\nf(): pass\n', {0, 1}),
  ('c', 'int\nmain(void) {}\n', {0, 1}),
  ('java', 'public\nclass\nA {}\n', {0, 1, 2}),
  ('bash', 'f\n() { :; }\n', {0, 1}),
  ('json', '{"a"\n: 1}\n', {0, 1}),
  (
    'dart',
    '/** Title\n * =====\n * *a\n * b*\n */\nvoid f() {}\n',
    {
      0, 1, 2, 3, 4, // markdown inside a doc comment
    },
  ),
  (
    'typescript',
    'const t = html`<a\n href="x"><!-- c\n -->`;\n',
    {
      0, 1, 2, // xml inside a template
    },
  ),
];

/// The lines of [growing] that are not those of [whole].
Set<int> _differing(List<TextSpan> growing, List<TextSpan> whole) {
  expect(growing.length, whole.length);
  return {
    for (var i = 0; i < whole.length; i++)
      if (growing[i] != whole[i]) i,
  };
}

/// [source] fed to [highlightLines] [step] characters at a time while it
/// grows: each prefix differs from its whole highlighting only on the
/// [spanning] lines, and equals it exactly once it stops growing.
void _stream(String language, String source, int step, Set<int> spanning) {
  for (var end = step; ; end += step) {
    final prefix = source.substring(0, end.clamp(0, source.length));
    final whole = highlightWhole(prefix, language, _tones);
    final reason = '$language, step $step, at $end';
    expect(
      _differing(
        highlightLines(prefix, language, _tones, growing: true),
        whole,
      ).difference(spanning),
      isEmpty,
      reason: reason,
    );
    expect(highlightLines(prefix, language, _tones), whole, reason: reason);
    if (end >= source.length) break;
  }
}

void main() {
  _testerCacheCases();
  group('highlightLines on a growing source', () {
    for (final MapEntry(key: language, value: source) in _samples.entries) {
      test('differs from whole only where a token spans lines: $language', () {
        for (final step in [1, 7, 40]) {
          _stream(language, source, step, _spanning[language] ?? const {});
        }
      });
    }

    test('differs from whole only where a token spans lines, by line', () {
      for (final MapEntry(key: language, value: source) in _samples.entries) {
        final lines = source.split('\n');
        for (var i = 1; i <= lines.length; i++) {
          final prefix = lines.take(i).join('\n');
          expect(
            _differing(
              highlightLines(prefix, language, _tones, growing: true),
              highlightWhole(prefix, language, _tones),
            ).difference(_spanning[language] ?? const {}),
            isEmpty,
            reason: '$language, $i lines',
          );
        }
      }
    });

    for (final (language, source, touched) in _crossing) {
      test('a token across lines in $language is whole once finished', () {
        for (final step in [1, 4]) {
          _stream(language, source, step, touched);
        }
        // The first line frozen before the second arrives, then finished.
        final first = source.substring(0, source.indexOf('\n') + 1);
        highlightLines(first, language, _tones, growing: true);
        expect(
          highlightLines(source, language, _tones),
          highlightWhole(source, language, _tones),
        );
      });
    }

    test('a token across lines can colour a growing line differently', () {
      // What the growing contract allows, shown once: javascript's arrow
      // function names its title only when the next line is known.
      const source = 'const f =\n(x) => x;\n';
      highlightLines('const f =\n', 'javascript', _tones, growing: true);
      final growing = highlightLines(
        source,
        'javascript',
        _tones,
        growing: true,
      );
      final whole = highlightWhole(source, 'javascript', _tones);
      expect(growing.first, isNot(whole.first));
      expect(highlightLines(source, 'javascript', _tones), whole);
    });

    test('a continued mode is reused without leaking state', () {
      // The same remembered prefix continued with different tails, in turn,
      // and the same tail twice: each must equal its own whole highlight.
      const base = '/* open\n';
      for (final tail in ['still */ int x;', 'int y; */', 'still */ int x;']) {
        final source = '$base$tail';
        expect(highlightLines(base, 'c', _tones, growing: true), isNotEmpty);
        expect(
          highlightLines(source, 'c', _tones, growing: true),
          highlightWhole(source, 'c', _tones),
          reason: tail,
        );
      }
    });

    test('a source that edits its prefix is highlighted afresh', () {
      const first = 'int a;\n/* b\n';
      const second = 'int a;\nint b;\n';
      highlightLines(first, 'c', _tones, growing: true);
      expect(
        highlightLines('${second}x', 'c', _tones, growing: true),
        highlightWhole('${second}x', 'c', _tones),
      );
    });

    test('blocks of one language grow side by side', () {
      final a = _samples['python']!;
      final b = _samples['python']!.replaceAll('f', 'g');
      for (var end = 5; end < a.length; end += 5) {
        for (final source in [a, b]) {
          final prefix = source.substring(0, end);
          expect(
            highlightLines(prefix, 'python', _tones, growing: true),
            highlightWhole(prefix, 'python', _tones),
          );
        }
      }
    });

    test('a finished source is not taken from a growing one', () {
      // Growing and finished results of one text are kept apart: the
      // finished one is the whole highlight even right after growing.
      const source = 'A title\n===';
      highlightLines('A title\n', 'markdown', _tones, growing: true);
      highlightLines(source, 'markdown', _tones, growing: true);
      expect(
        highlightLines(source, 'markdown', _tones),
        highlightWhole(source, 'markdown', _tones),
      );
    });
  });
}

void _testerCacheCases() {
  group('tester: growing cache isolation', () {
    test('partial tokens resume after growing cache eviction', () {
      const base = '/* retained comment\n';
      highlightLines(base, 'c', _tones, growing: true);
      for (var i = 0; i < 12; i++) {
        highlightLines('int other$i;\n', 'c', _tones, growing: true);
      }
      const source = '${base}still comment */ int answer = 42;';
      for (final end in [base.length + 3, source.length - 2, source.length]) {
        final prefix = source.substring(0, end);
        expect(
          highlightLines(prefix, 'c', _tones, growing: true),
          highlightWhole(prefix, 'c', _tones),
        );
      }
      expect(
        highlightLines(source, 'c', _tones),
        highlightWhole(source, 'c', _tones),
      );
    });

    test('language changes do not reuse another grammar continuation', () {
      const source = '/* open\nconst answer = "value";';
      for (final language in ['c', 'python', 'c', 'javascript', 'python']) {
        highlightLines('/* open\n', language, _tones, growing: true);
        expect(
          highlightLines(source, language, _tones, growing: true),
          highlightWhole(source, language, _tones),
          reason: language,
        );
        expect(
          highlightLines(source, language, _tones),
          highlightWhole(source, language, _tones),
          reason: language,
        );
      }
    });

    test('whole cache eviction cannot return frozen growing colours', () {
      const source = 'const uniqueFunction =\n(x) => x;\n';
      highlightLines(
        'const uniqueFunction =\n',
        'javascript',
        _tones,
        growing: true,
      );
      highlightLines(source, 'javascript', _tones, growing: true);
      final whole = highlightWhole(source, 'javascript', _tones);
      expect(highlightLines(source, 'javascript', _tones), whole);
      for (var i = 0; i < 70; i++) {
        highlightLines('const eviction$i = $i;', 'javascript', _tones);
      }
      expect(highlightLines(source, 'javascript', _tones), whole);
    });

    test('mid-token chunks preserve Unicode and literal escape text', () {
      const source =
          'const label = "界👩‍💻e\u0301";\n'
          '/* \x1b[31m literal\ncomment */ int n = 12345;';
      for (var end = 1; end <= source.length; end++) {
        final prefix = source.substring(0, end);
        expect(
          highlightLines(prefix, 'c', _tones, growing: true),
          highlightWhole(prefix, 'c', _tones),
          reason: 'prefix $end',
        );
      }
    });
  });
}
