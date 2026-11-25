import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/foundation/selection.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:test/test.dart';

SelectionSource _reply(String text, {SelectionSource? previous}) =>
    SelectionSource.markdown(
      id: 'reply',
      revision: text,
      text: text,
      previous: previous,
    );

void main() {
  group('tester: immutable source identity and directional ranges', () {
    for (final (oldCode, newCode) in [('a\nb', r'a\nb'), (r'a\nb', 'a\nb')]) {
      test('colliding code descriptions do not become anchors: $oldCode', () {
        final first = _reply('```\n$oldCode\n```\n\nend');
        final before = first.codeBlocks.single;
        final next = _reply(
          'insert\n\n```\n$newCode\n```\n\nend',
          previous: first,
        );
        expect(next.codeBlocks.single.id, isNot(before.id));
        expect(before.text, oldCode);
        expect(first.codeBlocks.single, same(before));
        expect(next.codeBlocks.single.text, newCode);
      });
    }

    test('reordered code anchors cannot migrate a finalized range', () {
      final first = _reply('```\nalpha\n```\n\n```\nbeta\n```\n\nend');
      final old = shapeSelectionSource(first, width: 80).fragments;
      final code = old.first;
      final range = SelectionRangeModel()..begin(code, 0);
      range.extend(old, SelectionPosition(code.id, 4));
      range.finalize();
      final next = _reply(
        '```\nbeta\n```\n\n```\nalpha\n```\n\nend',
        previous: first,
      );
      range.reconcile(shapeSelectionSource(next, width: 80).fragments);
      expect(range.value.phase, SelectionPhase.none);
      expect(range.leases, isEmpty);
    });

    test(
      'old range value and shaped projection survive one thousand revisions',
      () {
        var source = SelectionSource.code(
          id: 'code',
          revision: 0,
          text: 'A界e\u0301',
        );
        final old = shapeSelectionSource(source, width: 80);
        final fragment = old.fragments.single;
        final range = SelectionRangeModel()..begin(fragment, 0);
        range.extend(old.fragments, SelectionPosition(fragment.id, 2));
        range.finalize();
        final snapshot = range.value;
        for (var i = 1; i <= 1000; i++) {
          source = SelectionSource.code(
            id: 'code',
            revision: i,
            text: 'A界e\u0301 tail $i',
            previous: source,
          );
        }
        range.reconcile(shapeSelectionSource(source, width: 80).fragments);
        expect(snapshot.text, 'A界e\u0301');
        expect(old.selectedText, 'A界e\u0301');
        expect(range.value.text, 'A界e\u0301');
        expect(range.leases.single.fragment, isNot(same(fragment)));
        range.clear();
        expect(range.leases, isEmpty);
        expect(snapshot.phase, SelectionPhase.finalized);
      },
    );

    for (final width in [80, 120]) {
      test(
        'nested explicit separators ignore every first-child prefix $width',
        () {
          SelectionSource text(String id, String value) =>
              SelectionSource.text(id: id, revision: 0, text: TextSpan(value));
          final nested = SelectionSource.group(
            id: 'inner',
            revision: 0,
            children: [
              SelectionSourceChild(
                source: text('a', 'A界'),
                separatorBefore: 'BAD',
              ),
              SelectionSourceChild(
                source: text('b', 'Be\u0301'),
                separatorBefore: '::',
              ),
            ],
          );
          final document = SelectionSource.group(
            id: 'outer',
            revision: 0,
            children: [
              SelectionSourceChild(source: nested, separatorBefore: 'BAD'),
              SelectionSourceChild(
                source: text('c', 'C👩‍💻'),
                separatorBefore: '|',
              ),
            ],
          );
          final shape = shapeSelectionSource(document, width: width);
          expect(shape.selectedText, 'A界::Be\u0301|C👩‍💻');
          final range = SelectionRangeModel();
          for (final reverse in [false, true]) {
            final first = reverse
                ? shape.fragments.last
                : shape.fragments.first;
            final last = reverse ? shape.fragments.first : shape.fragments.last;
            range.begin(first, reverse ? first.length - 1 : 0);
            range.extend(
              shape.fragments,
              SelectionPosition(last.id, reverse ? 0 : last.length - 1),
            );
            expect(range.value.text, shape.selectedText);
          }
        },
      );

      test('full reparse leaves old text and descriptors immutable $width', () {
        final first = _reply('[label][ref]\n\n```sh\necho\n```\n\n[ref]: old');
        final oldShape = shapeSelectionSource(first, width: width);
        final oldText = oldShape.selectedText;
        final oldBlock = first.codeBlocks.single;
        final next = _reply(
          '[label][ref]\n\n```sh\necho\n```\n\n[ref]: new',
          previous: first,
        );
        expect(next.codeBlocks.single.id, oldBlock.id);
        expect(
          shapeSelectionSource(next, width: width).selectedText,
          contains('new'),
        );
        expect(oldShape.selectedText, oldText);
        expect(shapeSelectionSource(first, width: width).selectedText, oldText);
        expect(oldBlock.text, 'echo');
        expect(oldBlock.complete, isTrue);
      });
    }
  });
}
