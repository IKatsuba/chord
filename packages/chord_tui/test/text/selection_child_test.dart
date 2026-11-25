import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:test/test.dart';

SelectionSource text(String id, String value) =>
    SelectionSource.text(id: id, revision: 0, text: TextSpan(value));

void main() {
  final children = [
    text('a', 'first'),
    text('b', 'wrapped furniture ' * 8),
    text('c', 'last'),
  ];
  for (final flags in <List<bool>>[
    [true, true, true],
    [false, true, true],
    [true, false, true],
    [true, true, false],
    [false, false, false],
  ]) {
    test(
      'child eligibility $flags keeps exact rows and only eligible boundaries',
      () {
        SelectionSource group(List<bool> flags) => SelectionSource.group(
          id: 'group',
          revision: flags.toString(),
          children: [
            for (var i = 0; i < children.length; i++)
              SelectionSourceChild(
                source: children[i],
                selectable: flags[i],
                insetLeft: 2,
                insetRight: 1,
                separatorBefore: '<$i>',
              ),
          ],
        );
        final full = shapeSelectionSource(group([true, true, true]), width: 20);
        final shaped = shapeSelectionSource(group(flags), width: 20);
        expect(shaped.height, full.height);
        expect(shaped.width, full.width);
        expect(
          shaped.rows
              .map(
                (r) => r.glyphs
                    .map(
                      (g) => (g.x, g.glyph.text, g.glyph.width, g.glyph.style),
                    )
                    .toList(),
              )
              .toList(),
          full.rows
              .map(
                (r) => r.glyphs
                    .map(
                      (g) => (g.x, g.glyph.text, g.glyph.width, g.glyph.style),
                    )
                    .toList(),
              )
              .toList(),
        );
        final expected = StringBuffer();
        var first = true;
        for (var i = 0; i < children.length; i++) {
          if (!flags[i]) continue;
          if (!first) expected.write('<$i>');
          expected.write(
            shapeSelectionSource(children[i], width: 17).selectedText,
          );
          first = false;
        }
        expect(shaped.selectedText, expected.toString());
        if (shaped.fragments.isNotEmpty) {
          expect(shaped.fragments.first.separatorBefore, '');
        }
        final start = shapeSelectionSource(children.first, width: 17).height;
        final end = start + shapeSelectionSource(children[1], width: 17).height;
        if (!flags[1]) {
          for (final row in shaped.rows.sublist(start, end)) {
            expect(row.sourceId, isNull);
            expect(row.blankLane, isNull);
            expect(
              row.glyphs.every((g) => g.sourceId == null && g.offset == null),
              isTrue,
            );
          }
        }
      },
    );
  }

  test(
    'nested disabled branch keeps code geometry but no parent descriptors or bounds',
    () {
      final code = SelectionSource.markdown(
        id: 'code',
        revision: 0,
        text: '```dart\necho\n```',
      );
      final inner = SelectionSource.group(
        id: 'inner',
        revision: 0,
        children: [SelectionSourceChild(source: code)],
      );
      final parent = SelectionSource.group(
        id: 'parent',
        revision: 0,
        children: [SelectionSourceChild(source: inner, selectable: false)],
      );
      expect(parent.children.single, same(inner));
      expect(parent.child('code'), same(code));
      expect(parent.codeBlocks, isEmpty);
      final omitted = shapeSelectionSource(parent, width: 30);
      final standalone = shapeSelectionSource(code, width: 30);
      expect(omitted.height, standalone.height);
      expect(omitted.fragments, isEmpty);
      expect(omitted.hitRects, isEmpty);
      expect(omitted.codeBounds, isEmpty);
      expect(code.codeBlocks, hasLength(1));
      expect(standalone.codeBounds, hasLength(1));
      expect(standalone.selectedText, 'echo');
    },
  );

  test(
    'flag snapshots are immutable, revisions replace eligibility and disabled IDs still validate',
    () {
      final source = text('body', 'body');
      final slots = [SelectionSourceChild(source: source)];
      final first = SelectionSource.group(
        id: 'group',
        revision: 0,
        children: slots,
      );
      slots[0] = SelectionSourceChild(source: source, selectable: false);
      final next = SelectionSource.group(
        id: 'group',
        revision: 1,
        children: slots,
        previous: first,
      );
      expect(shapeSelectionSource(first, width: 20).selectedText, 'body');
      expect(shapeSelectionSource(next, width: 20).selectedText, '');
      expect(first.revision, 0);
      expect(next.revision, 1);
      expect(() => first.children.clear(), throwsUnsupportedError);
      expect(
        () => SelectionSource.group(
          id: 'duplicate',
          revision: 0,
          children: [
            SelectionSourceChild(source: source, selectable: false),
            SelectionSourceChild(source: source),
          ],
        ),
        throwsArgumentError,
      );
    },
  );
}
