import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

Style _c(int i) => Style(fg: IndexedColor(i));

/// Each class its own colour, so a token's class reads from its style.
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

/// The style each piece of [line] is drawn in, by its text.
Map<String, Style> _styles(TextSpan line) => {
  for (final (text, style) in line.flatten()) text: style,
};

String _plain(List<TextSpan> lines) =>
    lines.map((l) => l.toPlainText()).join('\n');

void main() {
  group('fenceLanguage', () {
    test('takes the first word, in any case', () {
      expect(fenceLanguage('DART example'), 'dart');
      expect(fenceLanguage('  python  '), 'python');
    });
    test('resolves aliases to their grammar', () {
      expect(fenceLanguage('ts'), 'typescript');
      expect(fenceLanguage('sh'), 'bash');
      expect(fenceLanguage('console'), 'shell');
      expect(fenceLanguage('html'), 'xml');
      expect(fenceLanguage('yml'), 'yaml');
      expect(fenceLanguage('h'), 'c');
    });
    test('knows every language of chord\'s common set', () {
      for (final name in [
        'arduino', 'bash', 'c', 'cpp', 'csharp', 'css', 'diff', 'go', //
        'graphql', 'ini', 'java', 'javascript', 'json', 'kotlin', 'less',
        'lua', 'makefile', 'markdown', 'objectivec', 'perl', 'php',
        'plaintext', 'python', 'r', 'ruby', 'rust', 'scss', 'shell', 'sql',
        'swift', 'typescript', 'vbnet', 'wasm', 'xml', 'yaml',
      ]) {
        expect(fenceLanguage(name), name);
      }
    });
    test('is null for a missing, empty or unknown label', () {
      expect(fenceLanguage(null), isNull);
      expect(fenceLanguage(''), isNull);
      expect(fenceLanguage('   '), isNull);
      expect(fenceLanguage('nolanguage'), isNull);
    });
  });

  group('pathLanguage', () {
    test('reads the extension, in any case and either slash', () {
      expect(pathLanguage('lib/app.dart'), 'dart');
      expect(pathLanguage(r'src\Main.TS'), 'typescript');
      expect(pathLanguage('a.b/c.py'), 'python');
    });
    test('falls back to the whole name', () {
      expect(pathLanguage('Makefile'), 'makefile');
      expect(pathLanguage('tools/Dockerfile'), 'dockerfile');
    });
    test('is null when neither is known', () {
      expect(pathLanguage('notes.nolanguage'), isNull);
      expect(pathLanguage('README'), isNull);
      expect(pathLanguage(''), isNull);
    });
  });

  group('highlightLines', () {
    test('colours tokens by class, as chord\'s sheet maps them', () {
      final lines = highlightLines(
        'const n = 42; // note\nlet s = "x";',
        'typescript',
        _tones,
      );
      final first = _styles(lines[0]);
      expect(first['const'], _tones.keyword);
      expect(first['42'], _tones.number);
      expect(first['// note'], _tones.comment);
      expect(_styles(lines[1])['"x"'], _tones.string);
    });

    test('a keyword or a string inside meta takes keyword or string', () {
      final line = highlightLines('#include <stdio.h>', 'c', _tones).single;
      final styles = _styles(line);
      expect(styles['include'], _tones.keyword);
      expect(styles['<stdio.h>'], _tones.string);
      expect(styles['#'], _tones.meta);
    });

    test('a class\'s name is a title, a built-in a type', () {
      final line = highlightLines('class A { int x; }', 'java', _tones).single;
      expect(_styles(line)['A'], _tones.title);
      expect(_styles(line)['int'], _tones.type);
    });

    test('emphasis is italic and strong bold', () {
      final styles = _styles(
        highlightLines('*a* **b**', 'markdown', _tones).single,
      );
      expect(styles['*a*'], Style.italic);
      expect(styles['**b**'], Style.bold);
    });

    test('a comment over several lines is coloured on each', () {
      final lines = highlightLines('/* one\ntwo */ x', 'c', _tones);
      expect(lines[0].flatten().single, ('/* one', _tones.comment));
      expect(lines[1].flatten().first, ('two */', _tones.comment));
      expect(lines[1].flatten().last.$1, ' x');
      expect(lines[1].flatten().last.$2, Style.plain);
    });

    test('lines join back into the source, blank lines included', () {
      for (final source in ['', '\n', 'a', '\n\nx = 1\n\n', 'a\n\n\nb\n']) {
        final lines = highlightLines(source, 'python', _tones);
        expect(_plain(lines), source, reason: source);
        expect(lines.length, source.split('\n').length);
        expect(lines.every((l) => !l.toPlainText().contains('\n')), isTrue);
      }
      expect(highlightLines('', 'python', _tones), [const TextSpan('')]);
    });

    test('an unknown or missing language, or no tones, is plain', () {
      for (final lines in [
        highlightLines('int x;\nint y;', 'nolanguage', _tones),
        highlightLines('int x;\nint y;', null, _tones),
        highlightLines('int x;\nint y;', 'c', null),
      ]) {
        expect(lines, [const TextSpan('int x;'), const TextSpan('int y;')]);
      }
    });

    test('an alias highlights as its grammar', () {
      expect(
        highlightLines('const a = 1', 'TS', _tones),
        highlightLines('const a = 1', 'typescript', _tones),
      );
    });

    test('the result is unmodifiable', () {
      final lines = highlightLines('x', 'c', _tones);
      expect(() => lines.add(const TextSpan('y')), throwsUnsupportedError);
    });

    test('a repeat is the cached result; other tones are not', () {
      const source = 'fn cache_hit() {}';
      final first = highlightLines(source, 'rust', _tones);
      expect(identical(highlightLines(source, 'rust', _tones), first), isTrue);
      expect(identical(highlightLines(source, 'rs', _tones), first), isTrue);
      final other = Tones(keyword: _c(9));
      final again = highlightLines(source, 'rust', other);
      expect(identical(again, first), isFalse);
      expect(_styles(again.single)['fn'], _c(9));
    });

    test('the cache keeps the 64 latest texts', () {
      const source = 'fn evicted() {}';
      final first = highlightLines(source, 'rust', _tones);
      for (var i = 0; i < 63; i++) {
        highlightLines('fn f$i() {}', 'rust', _tones);
      }
      expect(identical(highlightLines(source, 'rust', _tones), first), isTrue);
      for (var i = 0; i < 64; i++) {
        highlightLines('fn g$i() {}', 'rust', _tones);
      }
      final again = highlightLines(source, 'rust', _tones);
      expect(identical(again, first), isFalse);
      expect(again, first);
    });
  });
  group('tester: highlighting boundaries and cache isolation', () {
    test(
      'a multiline string keeps its tone through blank and Unicode lines',
      () {
        const source =
            'value = """first\n\n日本語 👩‍💻 e\u0301\nlast"""\nnext = 1';
        final lines = highlightLines(source, 'python', _tones);
        expect(_plain(lines), source);
        expect(lines[1].toPlainText(), isEmpty);
        for (final index in [2, 3]) {
          expect(lines[index].flatten(), isNotEmpty);
          expect(
            lines[index].flatten().every((run) => run.$2 == _tones.string),
            isTrue,
          );
        }
        expect(_styles(lines.last)['1'], _tones.number);
      },
    );

    test('highlighting preserves controls, CRLF and grapheme sequences', () {
      const source = '\n// 界👩‍💻e\u0301\t\r\n"\x1b[31mred\x1b[0m"\n\n';
      for (final language in ['javascript', '', 'unknown-language', null]) {
        final lines = highlightLines(source, language, _tones);
        expect(_plain(lines), source, reason: '$language');
        expect(lines.length, 5);
      }
    });

    test('null tones remove emphasis attributes as well as colours', () {
      final lines = highlightLines(
        '*italic* **bold**\n`code`',
        'markdown',
        null,
      );
      expect(_plain(lines), '*italic* **bold**\n`code`');
      expect(
        lines
            .expand((line) => line.flatten())
            .every((run) => run.$2 == Style.plain),
        isTrue,
      );
    });

    test('every highlighted descendant list resists mutation', () {
      final lines = highlightLines(
        'const value = "text";\n// note',
        'js',
        _tones,
      );
      void check(TextSpan span) {
        for (final child in span.children) {
          check(child);
        }
        expect(
          () => span.children.add(const TextSpan('changed')),
          throwsUnsupportedError,
        );
      }

      for (final line in lines) {
        check(line);
      }
      expect(_plain(lines), 'const value = "text";\n// note');
    });

    test('equal tone values share cached results', () {
      final equalTones = Tones(
        keyword: _c(1),
        string: _c(2),
        number: _c(3),
        comment: _c(4),
        title: _c(5),
        type: _c(6),
        name: _c(7),
        meta: _c(8),
      );
      const source = 'const value_tones = 17;';
      final first = highlightLines(source, 'js', _tones);
      expect(
        identical(highlightLines(source, 'javascript', equalTones), first),
        isTrue,
      );
    });

    test('a cache hit does not refresh insertion order', () {
      const source = 'const insertion_order = 0;';
      final first = highlightLines(source, 'js', _tones);
      for (var i = 0; i < 63; i++) {
        highlightLines('const insertion_$i = $i;', 'js', _tones);
      }
      expect(identical(highlightLines(source, 'js', _tones), first), isTrue);
      highlightLines('const insertion_overflow = 64;', 'js', _tones);
      final afterEviction = highlightLines(source, 'js', _tones);
      expect(identical(afterEviction, first), isFalse);
      expect(afterEviction, first);
    });

    test('a thousand updates leave an earlier result unchanged', () {
      const source = 'const original_snapshot = 7;\n// retained';
      final before = highlightLines(source, 'js', _tones);
      final styles = before.map((line) => line.flatten()).toList();
      for (var i = 0; i < 1000; i++) {
        highlightLines('const update_$i = $i;', 'js', _tones);
      }
      expect(_plain(before), source);
      expect(before.map((line) => line.flatten()).toList(), styles);
    });
  });
}
