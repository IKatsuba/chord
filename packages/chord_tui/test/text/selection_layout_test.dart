import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:test/test.dart';

void main() {
  test('graphemes cross style boundaries and keep source offsets', () {
    final layout = TextLayout.compute(
      const TextSpan(
        '',
        children: [
          TextSpan('e', style: Style.bold),
          TextSpan('\u0301👩'),
          TextSpan('\u200d💻界'),
        ],
      ),
    );
    expect(layout.lines.single.map((g) => g.text), ['e\u0301', '👩‍💻', '界']);
    expect(layout.lines.single.map((g) => g.sourceOffset), [0, 1, 2]);
    expect(layout.lines.single.first.style.isBold, isTrue);
  });
  for (final width in [120, 80]) {
    test(
      'shared text and code projections preserve hard/soft breaks and tabs $width',
      () {
        final text = SelectionSource.text(
          id: 't',
          revision: 0,
          text: TextSpan('${'word ' * 40}\nend'),
        );
        final shaped = shapeSelectionSource(text, width: width);
        expect(shaped.selectedText, '${'word ' * 39}word\nend');
        final code = SelectionSource.code(
          id: 'c',
          revision: 0,
          text: '\techo 👩‍💻 e\u0301 界\n\necho done',
          lineNumbers: true,
        );
        final codeShape = shapeSelectionSource(code, width: width);
        expect(codeShape.selectedText, '\techo 👩‍💻 e\u0301 界\n\necho done');
        expect(
          codeShape.rows.first.glyphs
              .where((g) => g.sourceId != null)
              .first
              .offset,
          0,
        );
      },
    );
    test(
      'ellipsis/middle and hidden lines never serialize concealed spans $width',
      () {
        final hidden = SelectionSource.text(
          id: 't',
          revision: 0,
          text: TextSpan('begin ${'x' * width} END\nhidden'),
          softWrap: false,
          overflow: TextOverflow.middle,
          maxLines: 1,
        );
        final shape = shapeSelectionSource(hidden, width: width);
        expect(shape.selectedText, isNot(contains('hidden')));
        expect(shape.selectedText, startsWith('begin'));
        expect(shape.selectedText, endsWith('END'));
        expect(shape.selectedText.length, lessThan(width));
        expect(shape.selectedText, isNot(contains('...')));
      },
    );
    test(
      'Markdown serialization classes and gaps use the shared shape $width',
      () {
        final source = SelectionSource.markdown(
          id: 'm',
          revision: 0,
          text:
              '# Title\n\nfirst soft\nline\n\n- item\n- second\n\n```\n\tcode\n\nend\n```',
        );
        expect(
          shapeSelectionSource(source, width: width).selectedText,
          'Title\n \nfirst soft line\n \nitem\nsecond\n \n\tcode\n\nend',
        );
        final quote = SelectionSource.markdown(
          id: 'q',
          revision: 0,
          text: '> ```\n> echo\n> ```\n>\n> - item',
        );
        final copy = shapeSelectionSource(quote, width: width).selectedText;
        expect(copy, contains('┌'));
        expect(copy, contains('echo'));
        expect(copy, contains('- item'));
        expect(copy, isNot(startsWith('│ ')));
      },
    );
  }
  test('code CRLF and styled tabs use one shared grapheme stream', () {
    final source = SelectionSource.code(
      id: 'code',
      revision: 0,
      text: '\tone\r\n\ttwo',
      lineNumbers: true,
    );
    final shape = shapeSelectionSource(source, width: 80);
    expect(shape.selectedText, '\tone\r\n\ttwo');
    expect(
      shape.rows[1].glyphs.where((cell) => cell.sourceId != null).first.offset,
      5,
    );
  });
  test(
    'table copies the current grid and quoted code copies only its inner box',
    () {
      final table = SelectionSource.markdown(
        id: 'table',
        revision: 0,
        text: '| h |\n|---|\n| c |',
      );
      expect(
        shapeSelectionSource(table, width: 80).selectedText,
        '┌────┐\n│ h  │\n├────┤\n│ c  │\n└────┘',
      );
      final quote = SelectionSource.markdown(
        id: 'quote',
        revision: 0,
        text: '> ```\n> echo\n> ```',
      );
      expect(
        shapeSelectionSource(quote, width: 80).selectedText,
        '┌──────┐\n│ echo │\n└──────┘',
      );
    },
  );
  test(
    'TextArea mapping uses the current controller rows with full source offsets',
    () {
      final controller = TextAreaController(text: 'a\t界👩‍💻\n\necho done');
      final layout = controller.layout(width: 8, maxHeight: 2);
      final shape = shapeTextAreaSelection(
        id: controller,
        text: controller.text,
        layout: layout,
      );
      expect(shape.selectedText, controller.text);
      expect(shape.rows.length, layout.rows.length);
      for (var i = 0; i < shape.rows.length; i++) {
        expect(shape.rows[i].start, layout.rows[i].start);
      }
      controller.dispose();
    },
  );
  test(
    'DiffView copy excludes title, hunk gaps, signs, numbering and omitted rows',
    () {
      final view = parseUnifiedDiff(
        '@@ -1 +1 @@\n-one\n+two\n@@ -20 +20 @@\n-three\n+four\n',
      ).view(maxRows: 4);
      final source = SelectionSource.diff(
        id: 'diff',
        revision: 0,
        view: view,
        title: 'private-label',
      );
      expect(
        shapeSelectionSource(source, width: 80).selectedText,
        'one\ntwo\nthree',
      );
    },
  );
  test(
    'terminal escapes split across styles never leak into cells or copy maps',
    () {
      final text = SelectionSource.text(
        id: 'text',
        revision: 0,
        text: const TextSpan(
          '\x1b[',
          children: [TextSpan('31mred', style: Style.bold)],
        ),
      );
      final shape = shapeSelectionSource(text, width: 80);
      expect(shape.selectedText, 'red');
      expect(
        shape.rows.single.glyphs.map((cell) => cell.glyph.text).join(),
        'red',
      );
      final diff = SelectionSource.diff(
        id: 'diff',
        revision: 0,
        view: diffTexts('old', '\x1b[31mnew').view(),
      );
      expect(shapeSelectionSource(diff, width: 80).selectedText, 'old\nnew');
    },
  );
  test('unbounded nested quote and list sizing stays intrinsic', () {
    final source = SelectionSource.markdown(
      id: 'nested',
      revision: 0,
      text: '> > text\n>\n> - item\n>   - nested',
    );
    expect(shapeSelectionSource(source, width: unbounded).width, lessThan(100));
  });
  for (final (label, text, width, expected) in <(String, String, int, String)>[
    ('exact width', 'abcd\nx', 4, 'abcd\nx'),
    ('trailing LF', 'abcd\n', 4, 'abcd\n'),
    ('blank logical line', 'abcd\n\nx', 4, 'abcd\n\nx'),
    ('trailing blank logical line', 'abcd\n\n', 4, 'abcd\n\n'),
    ('tab boundary', '\t\nx', 4, '\t\nx'),
    ('wide boundary', 'ab界\nx', 4, 'ab界\nx'),
    ('emoji boundary', '👩‍💻界\nx', 4, '👩‍💻界\nx'),
    ('soft then hard break', 'abcdx\ny', 4, 'abcdx\ny'),
    ('multiple full pieces', 'abcdefgh\nx', 4, 'abcdefgh\nx'),
    ('short line', 'ab\nx', 4, 'ab\nx'),
    ('ANSI boundary', '\x1b[31mred\nx', 7, 'red\nx'),
    ('RI neighbors', '🇺\x1b[31m🇸\nx', 6, '🇺🇸\nx'),
    ('tab wide blank lines', '\t界\n\nz', 6, '\t界\n\nz'),
    ('empty', '', 4, ''),
  ]) {
    test('draft hard LF ownership: $label', () {
      final controller = TextAreaController(text: text);
      final cursor = controller.cursor;
      final layout = controller.layout(width: width, maxHeight: 1);
      final shape = shapeTextAreaSelection(
        id: controller,
        text: controller.text,
        layout: layout,
      );
      expect(shape.selectedText, expected);
      expect(shape.rows, hasLength(layout.rows.length));
      expect(
        shape.rows.where((row) => row.hardBreak != null),
        hasLength('\n'.allMatches(expected).length),
      );
      expect(controller.text, text);
      expect(controller.cursor, cursor);
      expect(controller.lastLayout, same(layout));
      controller.dispose();
    });
  }
  test('draft exact-width caret row owns its blank-line endpoint', () {
    final controller = TextAreaController(text: 'abcd\nx');
    final layout = controller.layout(width: 4, maxHeight: 3);
    final shape = shapeTextAreaSelection(
      id: controller,
      text: controller.text,
      layout: layout,
    );
    expect(shape.rows, hasLength(3));
    expect(shape.rows[0].hardBreak, isNull);
    expect(shape.rows[0].softBreak, isTrue);
    expect(shape.rows[1].glyphs, isEmpty);
    expect(shape.rows[1].start, 4);
    expect(shape.rows[1].end, 4);
    expect(shape.rows[1].hardBreak, 4);
    expect(shape.rows[1].softBreak, isFalse);
    expect(shape.rows[2].start, 5);
    expect(shape.fragments.single.extract(4, 6), '\nx');
    controller.dispose();
  });
  test('draft display offsets never index raw ANSI control text', () {
    final controller = TextAreaController(
      text: '\x1b[31mred\x1b[0m\n\tblue \x1b[32m👩‍💻\x1b[0m',
    );
    final original = controller.text, cursor = controller.cursor;
    final layout = controller.layout(width: 80, maxHeight: 1);
    final shape = shapeTextAreaSelection(
      id: controller,
      text: controller.text,
      layout: layout,
    );
    expect(shape.selectedText, 'red\n\tblue 👩‍💻');
    expect(shape.rows.first.glyphs.map((cell) => cell.offset), [0, 1, 2]);
    expect(shape.rows.first.hardBreak, 3);
    expect(shape.rows[1].glyphs.first.offset, 4);
    expect(controller.text, original);
    expect(controller.cursor, cursor);
    expect(controller.lastLayout, same(layout));
    controller.dispose();
  });
  test(
    'draft semantic units stay consistent when ANSI removal joins soft-row graphemes',
    () {
      final controller = TextAreaController(text: '🇺\x1b[31m🇸');
      final layout = controller.layout(width: 6, maxHeight: 2);
      expect(layout.rows, hasLength(2));
      final shape = shapeTextAreaSelection(
        id: controller,
        text: controller.text,
        layout: layout,
      );
      expect(shape.selectedText, '🇺🇸');
      expect(shape.fragments.single.length, 2);
      expect(shape.rows[0].glyphs.single.offset, 0);
      expect(shape.rows[1].glyphs.single.offset, 1);
      expect(controller.text, '🇺\x1b[31m🇸');
      expect(controller.lastLayout, same(layout));
      controller.dispose();
    },
  );
}
