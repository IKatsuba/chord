import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:test/test.dart';
import 'markdown_controls_test.dart' show rowText;

void main() {
  test('both controls grow to original thresholds and drop run first', () {
    for (final (language, minimum) in [
      ('sh', 21),
      ('bash', 23),
      ('custom', 25),
    ]) {
      final source = SelectionSource.markdown(
        id: language,
        revision: 0,
        text: '```$language\nx\n```',
        copyCodeBlocks: true,
        runCodeBlockLanguages: {language},
      );
      final shape = shapeSelectionSource(source, width: 80);
      expect(shape.width, minimum);
      expect(rowText(shape.rows.first), contains('─[copy]─[run]─┐'));
      expect(shape.codeButtons.values.single.width, 6);
      expect(shape.codeRunButtons.values.single.width, 5);
      final narrow = shapeSelectionSource(source, width: minimum - 1);
      expect(rowText(narrow.rows.first), contains('[copy]'));
      expect(narrow.codeRunButtons, isEmpty);
      expect(shape.selectedText, 'x');
    }
  });
  test(
    'run-only custom policy is exact and quoted/open blocks have no controls',
    () {
      for (final text in [
        '```custom\nx\n```',
        '```CUSTOM\nx\n```',
        '```other\nx\n```',
        '```custom\nx',
        '> ```custom\n> x\n> ```',
        '    x',
      ]) {
        final source = SelectionSource.markdown(
          id: text,
          revision: 0,
          text: text,
          runCodeBlockLanguages: {'custom'},
        );
        final shape = shapeSelectionSource(source, width: 80);
        expect(
          shape.codeRunButtons.length,
          text.startsWith('```custom\nx\n```') ? 1 : 0,
        );
        expect(shape.codeButtons, isEmpty);
        if (shape.codeRunButtons.isNotEmpty) expect(shape.width, 18);
      }
    },
  );
  test(
    'picked run controls use accent and bold while plain stays colorless',
    () {
      final source = SelectionSource.markdown(
        id: 'style',
        revision: 0,
        text: '```custom\nx\n```',
        copyCodeBlocks: true,
        runCodeBlockLanguages: {'custom'},
      );
      for (final theme in [
        ThemeData.dark(),
        ThemeData.light(),
        ThemeData.plain(),
      ]) {
        final shape = shapeSelectionSource(
          source,
          width: 80,
          theme: theme,
          selectedCodeBlock: source.codeBlocks.single.id,
        );
        final at = shape.codeRunButtons.values.single.left;
        final style = shape.rows.first.glyphs
            .where((g) => g.x == at)
            .last
            .glyph
            .style;
        expect(style.isBold, isTrue);
        expect(style.fg, theme.accent.fg);
      }
    },
  );

  test('run language snapshots freeze caller sets and getters', () {
    final languages = {'custom'};
    final source = SelectionSource.markdown(
      id: 'm',
      revision: 0,
      text: '```custom\nx\n```',
      runCodeBlockLanguages: languages,
    );
    languages.clear();
    expect(source.runCodeBlockLanguages, {'custom'});
    expect(
      () => source.runCodeBlockLanguages.add('other'),
      throwsUnsupportedError,
    );
    expect(shapeSelectionSource(source, width: 80).codeRunButtons, isNotEmpty);
    final replacement = SelectionSource.markdown(
      id: 'm',
      revision: 1,
      text: '```custom\nx\n```',
      previous: source,
    );
    expect(replacement.codeBlocks.single.id, source.codeBlocks.single.id);
    expect(
      shapeSelectionSource(replacement, width: 80).codeRunButtons,
      isEmpty,
    );
    expect(shapeSelectionSource(source, width: 80).codeRunButtons, isNotEmpty);
  });
  test(
    'run rectangles share nested/group inset transforms and disabled exclusion',
    () {
      final source = SelectionSource.markdown(
        id: 'nested',
        revision: 0,
        text: '- ```custom\n  x\n  ```',
        copyCodeBlocks: true,
        runCodeBlockLanguages: {'custom'},
      );
      final group = SelectionSource.group(
        id: 'group',
        revision: 0,
        children: [SelectionSourceChild(source: source, insetLeft: 3)],
      );
      final shape = shapeSelectionSource(group, width: 80);
      expect(shape.codeRunButtons.values.single.left, 23);
      final excluded = SelectionSource.group(
        id: 'excluded',
        revision: 0,
        children: [
          SelectionSourceChild(source: source, insetLeft: 3, selectable: false),
        ],
      );
      final disabled = shapeSelectionSource(excluded, width: 80);
      expect(disabled.codeRunButtons, isEmpty);
      expect(disabled.codeButtons, isEmpty);
      expect(disabled.rows.map(rowText), shape.rows.map(rowText));
      expect(disabled.selectedText, isEmpty);
    },
  );
}
