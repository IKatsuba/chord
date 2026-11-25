import 'package:chord_tui/src/text/markdown.dart';
import 'package:test/test.dart';

List<String> _parse(String text) =>
    MarkdownParser().update(text).map((b) => b.describe()).toList();

/// A reply with every block chord draws, in the order a reply might.
const _reply = '''# Terminal cells

A paragraph with *emphasis*, **strong**, ~~struck~~, `code`, a
[link](https://example.com) and 日本語.
After a hard break.

Setext heading
--------------

- A first item
- [x] A done task
- [ ] An open task
  - A nested item

3. three
4. four

- loose one

- loose two

> A quoted paragraph.
>
> > Nested quote.

```dart example
void main() {

  print('Hello 日本語');
}
```

| Name | Status | Count |
|:-----|:------:|------:|
| renderer | ready | 2 |
| half

---
<div>raw html</div>

    indented code

Last paragraph, [a reference][ref] and <https://auto.link>.

[ref]: https://ref.example
''';

/// References, fences and containers, where a split matters most.
const _tricky = '''Use [the docs][d] before the fence.

> - quote holding a list
>   continued lazily
lazy line

```
open fence with ``` inside
~~~

[d]: https://docs.example "Title"
````

1) one
2) two
   ```sh
   echo nested
   ```
''';

/// Definitions that become whole only lines after their label begins.
const _definitions = '''[a][r] and [b][long label] and [c][t].

middle

[r]:
https://next.line

[long
label]: https://multi.line

[t]: https://titled
"on the next line"

[r]: https://ignored.repeat

[z]: <https://angle.example>

- [x] loose task

- [ ] other
  [n]: https://nested.def

end [n]
''';

void main() {
  group('tester: CTUI-55 paragraph streaming boundaries', () {
    test('every split preserves trimmed paragraphs and delayed references', () {
      const source =
          '  [界😀é][r]  \n \t*next*\n\n>   quote\n>  tail\n\n- item\n\n   continuation\n\n[r]: https://example.com\n\n final';
      final expected = _parse(source);
      expect(
        expected.first,
        'p(link[https://example.com]("界😀é") br emphasis("next"))',
      );
      expect(expected.last, 'p("final")');
      for (var split = 0; split <= source.length; split++) {
        final parser = MarkdownParser()..update(source.substring(0, split));
        expect(
          parser.update(source).map((b) => b.describe()),
          expected,
          reason: 'split $split',
        );
      }
    });

    test(
      'blank indented chunks can become code without retaining a paragraph',
      () {
        final parser = MarkdownParser();
        expect(parser.update('   '), isEmpty);
        expect(
          parser.update('    界😀é').single.describe(),
          'code[null]("界😀é")',
        );
        expect(parser.update('  界😀é').single.describe(), 'p("界😀é")');
        expect(
          parser.update('  界😀é  \n\tcontinued').single.describe(),
          'p("界😀é" br "continued")',
        );
      },
    );
  });
  group('blocks', () {
    test('headings, ATX and setext, without their marks', () {
      expect(_parse('# One\n### Three ###\nTwo\n---'), [
        'h1("One")',
        'h3("Three")',
        'h2("Two")',
      ]);
    });

    test('a paragraph joins soft breaks with spaces, keeps hard ones', () {
      expect(_parse('one\ntwo  \nthree\\\nfour'), [
        'p("one two" br "three" br "four")',
      ]);
    });

    test('a paragraph line drops its leading whitespace, as CommonMark', () {
      expect(_parse(' Late work 1.'), ['p("Late work 1.")']);
      expect(_parse('   three\t'), ['p("three")']);
      expect(_parse(' **b** x'), ['p(strong("b") " x")']);
      // After a hard break too (CommonMark example 636).
      expect(_parse('a  \n   b\\\n \tc'), ['p("a" br "b" br "c")']);
      expect(_parse(' `a\n  b`'), ['p(code("a b"))']);
      expect(_parse('- i\n\n   x'), ['ul loose(li(p("i"), p("x")))']);
      expect(_parse('>  q'), ['quote(p("q"))']);
    });

    test('code and list content keep their indentation', () {
      expect(_parse('    code\n      more'), [r'code[null]("code\n  more")']);
      expect(_parse(' ```\n  x\n ```'), ['code[null](" x")']);
      expect(_parse('```\n  x\n```'), ['code[null]("  x")']);
      expect(_parse(' - item\n   cont'), ['ul(li(p("item cont")))']);
    });

    test('inline forms', () {
      expect(
        _parse(
          '*em* **strong** ~~gone~~ `a  b` [l](http://x) '
          '![alt](i.png) <b>raw</b> \\*not\\* https://auto.dev',
        ),
        [
          'p(emphasis("em") " " strong("strong") " " '
              'strikethrough("gone") " " code("a  b") " " '
              'link[http://x]("l") " " image[i.png]("alt") " '
              '<b>raw</b> *not* " link[https://auto.dev]("https://auto.dev"))',
        ],
      );
    });

    test('nested emphasis keeps its nesting', () {
      expect(_parse('**bold *and em***'), [
        'p(strong("bold " emphasis("and em")))',
      ]);
    });

    test('tight, loose, nested, numbered and task lists', () {
      expect(_parse('- a\n- b\n  1. c'), [
        'ul(li(p("a")), li(p("b"), ol1(li(p("c")))))',
      ]);
      expect(_parse('- a\n\n- b'), ['ul loose(li(p("a")), li(p("b")))']);
      expect(_parse('7. seven\n8. eight'), [
        'ol7(li(p("seven")), li(p("eight")))',
      ]);
      expect(_parse('- [x] done\n- [ ] open\n- plain'), [
        'ul(li[x](p("done")), li[ ](p("open")), li(p("plain")))',
      ]);
    });

    test('quotes nest; a rule is a rule', () {
      expect(_parse('> a\n>\n> > b\n\n***'), [
        'quote(p("a"), quote(p("b")))',
        'hr',
      ]);
    });

    test('a table keeps alignment, and a short row its cells so far', () {
      expect(_parse('| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 | 3 |\n| 4'), [
        'table(left center right; "a" | "b" | "c"; "1" | "2" | "3"; "4" |  | )',
      ]);
    });

    test('a table header without its delimiter is a paragraph', () {
      expect(_parse('| a | b |'), ['p("| a | b |")']);
      expect(_parse('| a | b |\n|---|---|'), ['table(none none; "a" | "b")']);
    });

    test('a fence takes its label\'s first word and keeps its lines', () {
      expect(_parse('```Dart title="x"\n\na\n\n```'), [
        'code[Dart]("\\na\\n")',
      ]);
      expect(_parse('```nolanguage\nx\n```'), ['code[nolanguage]("x")']);
      expect(_parse('```\nx\n```'), ['code[null]("x")']);
      expect(_parse('    indented\n    code'), [
        'code[null]("indented\\ncode")',
      ]);
    });

    test('an open fence is code to the end, and closing completes it', () {
      expect(_parse('text\n```dart\nvoid f() {'), [
        'p("text")',
        'code[dart]("void f() {")',
      ]);
      expect(_parse('text\n```dart\nvoid f() {\n}\n```\nafter'), [
        'p("text")',
        'code[dart]("void f() {\\n}")',
        'p("after")',
      ]);
    });

    test('an HTML block is its source, as text', () {
      expect(_parse('para\n\n<div>\nraw\n</div>'), [
        'p("para")',
        'p("<div>" br "raw" br "</div>")',
      ]);
    });

    test('a reference resolves wherever it is defined', () {
      expect(_parse('[a][r]\n\n[r]: https://r.example'), [
        'p(link[https://r.example]("a"))',
        'def[r]("[r]: https://r.example")',
      ]);
    });

    test('a definition shows as written; a repeat defines nothing', () {
      expect(_parse('[R]:\n  https://r.example\n  "T"\n\n[r]: https://other'), [
        'def[r]("[R]:\\n  https://r.example\\n  "T"")',
        'def[]("[r]: https://other")',
      ]);
      expect(_parse('[not a definition]'), ['p("[not a definition]")']);
    });

    test('a destination left at its opening < is no definition', () {
      expect(_parse('[a]: <'), ['p("[a]: <")']);
      expect(_parse('[a]:\n  <'), ['p("[a]: <")']);
      expect(_parse('x\n\n[a]:\n<'), ['p("x")', 'p("[a]: <")']);
      expect(_parse('- [a]: <'), ['ul(li(p("[a]: <")))']);
      expect(_parse('> [a]: <'), ['quote(p("[a]: <"))']);
      expect(_parse('[a]: <\n\npara'), ['p("[a]: <")', 'p("para")']);
    });

    test('a soft break joins its lines with one space', () {
      expect(_parse('one  \t\n   two'), ['p("one two")']);
    });

    test('a loose task list keeps its boxes', () {
      expect(_parse('- [x] one\n\n- [ ] two'), [
        'ul loose(li[x](p("one")), li[ ](p("two")))',
      ]);
    });

    test('empty and blank text have no blocks', () {
      expect(_parse(''), isEmpty);
      expect(_parse('\n  \n\n'), isEmpty);
    });
  });

  group('appending', () {
    for (final (name, fixture) in [
      ('reply', _reply),
      ('tricky', _tricky),
      ('definitions', _definitions),
    ]) {
      test('every prefix of the $name parses as a whole parse does', () {
        final parser = MarkdownParser();
        for (var i = 0; i <= fixture.length; i++) {
          final text = fixture.substring(0, i);
          expect(
            parser.update(text).map((b) => b.describe()).toList(),
            _parse(text),
            reason:
                'prefix of $i: ${text.substring(text.length > 40 ? text.length - 40 : 0)}',
          );
        }
      });

      test('chunks of the $name parse as the whole', () {
        for (final size in [3, 17, 64]) {
          final parser = MarkdownParser();
          for (var i = 0; i < fixture.length; i += size) {
            parser.update(
              fixture.substring(0, (i + size).clamp(0, fixture.length)),
            );
          }
          expect(
            parser.blocks.map((b) => b.describe()).toList(),
            _parse(fixture),
            reason: 'chunks of $size',
          );
        }
      });
    }

    test('leading blocks freeze and are reused, the last stays open', () {
      final parser = MarkdownParser();
      parser.update('# A\n\npara one\n\npara');
      expect(parser.frozenCount, 2);
      final heading = parser.blocks.first;
      parser.update('# A\n\npara one\n\npara two\n\n- item');
      expect(parser.frozenCount, 3);
      expect(identical(parser.blocks.first, heading), isTrue);
      expect(parser.blocks.map((b) => b.describe()), [
        'h1("A")',
        'p("para one")',
        'p("para two")',
        'ul(li(p("item")))',
      ]);
    });

    test('the last paragraph can still become a heading or a table', () {
      final parser = MarkdownParser();
      parser.update('first\n\nTitle');
      parser.update('first\n\nTitle\n===');
      expect(parser.blocks.last.describe(), 'h1("Title")');
      parser.update('first\n\nTitle\n===\n\n| a |');
      parser.update('first\n\nTitle\n===\n\n| a |\n|---|');
      expect(parser.blocks.last.describe(), 'table(none; "a")');
    });

    test('a reference defined later re-parses links above it', () {
      final parser = MarkdownParser();
      parser.update('[a][r] here\n\npara\n\nmore');
      expect(parser.frozenCount, 2);
      expect(parser.blocks.first.describe(), 'p("[a][r] here")');
      // The label arrives split across two updates.
      parser.update('[a][r] here\n\npara\n\nmore\n\n[r');
      parser.update('[a][r] here\n\npara\n\nmore\n\n[r]: https://r.example');
      expect(
        parser.blocks.first.describe(),
        'p(link[https://r.example]("a") " here")',
      );
    });

    test('a definition whole only lines later re-parses links above', () {
      for (final (first, rest) in [
        ('[a][r]\n\n[r]:\n', 'https://example.com\n\nend'),
        ('[a][long label]\n\n[long\n', 'label]: https://example.com\n\nend'),
      ]) {
        final parser = MarkdownParser()..update(first);
        expect(
          parser.update(first + rest).map((b) => b.describe()),
          _parse(first + rest),
        );
        expect(
          parser.blocks.first.describe(),
          'p(link[https://example.com]("a"))',
        );
      }
    });

    test('an edit that is no append parses the whole text again', () {
      final parser = MarkdownParser();
      parser.update('# A\n\none\n\ntwo');
      parser.update('# B\n\none');
      expect(parser.blocks.map((b) => b.describe()), ['h1("B")', 'p("one")']);
      parser.update('');
      expect(parser.blocks, isEmpty);
    });

    test('the same text again is the same blocks', () {
      final parser = MarkdownParser();
      final blocks = parser.update('# A\n\ntext');
      expect(identical(parser.update('# A\n\ntext'), blocks), isTrue);
    });
  });
  group('tester: incremental parse boundaries', () {
    final fixtures = <String, String>{
      'opening destination inside quote':
          '[use][q]\n\nfrozen\n\n> [q]:\n>   <https://quoted.example>\n>\n> tail',
      'opening destination inside list':
          '[use][l]\n\nfrozen\n\n- [l]:\n    <https://listed.example>\n\n  tail\n\nend',
      'open fence with Unicode and blank lines':
          '# 界👩‍💻e\u0301\n\nparagraph\n\n```unknown extra\n\n界👩‍💻e\u0301\n``` inside\n\n',
      'open aligned table with escaped pipes':
          'intro\n\n| 界 | emoji | combining |\n|:---|:---:|---:|\n| a\\|b | 👩‍💻 | e\u0301 |\n| incomplete',
      'late normalized reference and losing repeat':
          '[early][WIDE LABEL] and [界].\n\nfrozen **paragraph**\n\n[wide\nlabel]:\n  <https://example.com/path>\n  "late title"\n\n[界]: /unicode\n\n[WIDE LABEL]: /losing\n\n[tail][wide label]',
      'definitions inside containers':
          '[a][quote] [b][list]\n\n> [quote]: /quoted\n>\n> end\n\n- [x] task\n\n  [list]: /listed\n\n- [ ] other\n\n[a][quote] [b][list]',
      'CRLF and indented code':
          '# heading\r\n\r\nfirst\r\nsecond  \r\nthird\r\n\r\n    code\r\n\r\n    next\r\n\r\ntail',
      'HTML block closes then trailing blocks':
          'intro\n\n<!-- open\ncomment\n-->\n\n<div>\nraw 界\n</div>\n\n*tail*',
      'loose nested lists and fenced code':
          '- [X] done\n\n  para\n\n  > quote\n  >\n  > ```dart\n  > value\n  > ```\n\n- [ ] pending\n\n    8. eight\n    9. nine\n\nend',
      'setext and rule transitions':
          'first\n\nTitle\n===\n\nnext\n---\n\n***\n\ntrailing',
    };
    for (final MapEntry(:key, :value) in fixtures.entries) {
      test('every prefix matches a full parse: $key', () {
        final parser = MarkdownParser();
        for (var end = 0; end <= value.length; end++) {
          final prefix = value.substring(0, end);
          final List<String> actual;
          try {
            actual = parser.update(prefix).map((b) => b.describe()).toList();
          } catch (error) {
            fail(
              '$key at UTF-16 prefix $end: ${prefix.replaceAll("\n", r"\n")} throws $error',
            );
          }
          expect(actual, _parse(prefix), reason: '$key at UTF-16 prefix $end');
          expect(identical(parser.update(prefix), parser.blocks), isTrue);
        }
      });
      test('each chunk result matches a full parse: $key', () {
        for (final chunk in [2, 7, 31]) {
          final parser = MarkdownParser();
          for (var end = chunk; end < value.length + chunk; end += chunk) {
            final prefix = value.substring(0, end.clamp(0, value.length));
            expect(
              parser.update(prefix).map((b) => b.describe()).toList(),
              _parse(prefix),
              reason: '$key chunk $chunk end $end',
            );
          }
        }
      });
    }

    test('replacement and shortening clear old reference definitions', () {
      final parser = MarkdownParser();
      for (final source in [
        '[r]: /old\n\n[a][r]\n\nfrozen\n\ntail',
        '[a][r]\n\nfrozen\n\ntail',
        '[r]: /new\n\n[a][r]\n\nend',
        '',
        '[a][r]',
      ]) {
        expect(
          parser.update(source).map((b) => b.describe()).toList(),
          _parse(source),
        );
      }
    });

    test('independent parsers cannot share reference state', () {
      final a = MarkdownParser();
      final b = MarkdownParser();
      const first = '[r]: /one\n\nfrozen\n\n[a][r]';
      const second = '[r]: /two\n\nfrozen\n\n[b][r]';
      for (var end = 0; end <= first.length || end <= second.length; end++) {
        final x = first.substring(0, end.clamp(0, first.length));
        final y = second.substring(0, end.clamp(0, second.length));
        expect(a.update(x).map((b) => b.describe()).toList(), _parse(x));
        expect(b.update(y).map((b) => b.describe()).toList(), _parse(y));
      }
    });
  });
}
