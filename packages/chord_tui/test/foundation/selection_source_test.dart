import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/foundation/selection_source.dart';
import 'package:test/test.dart';

SelectionSource _markdown(String text, {SelectionSource? previous}) =>
    SelectionSource.markdown(
      id: 'reply',
      revision: text,
      text: text,
      previous: previous,
    );

void main() {
  test(
    'source snapshots freeze span children and validate lineage and groups',
    () {
      final spans = [const TextSpan('one')];
      final first = SelectionSource.text(
        id: 'text',
        revision: 0,
        text: TextSpan('', children: spans),
      );
      spans.add(const TextSpan('mutated'));
      expect(selectionSourceSpan(first).toPlainText(), 'one');
      expect(
        () => SelectionSource.code(
          id: 'text',
          revision: 1,
          text: 'code',
          previous: first,
        ),
        throwsArgumentError,
      );
      expect(
        () => SelectionSource.text(
          id: 'other',
          revision: 1,
          text: const TextSpan('two'),
          previous: first,
        ),
        throwsArgumentError,
      );
      expect(
        () => SelectionSource.group(
          id: 'root',
          revision: 0,
          children: [
            SelectionSourceChild(source: first),
            SelectionSourceChild(source: first),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => SelectionSource.group(
          id: 'root',
          revision: 0,
          children: [SelectionSourceChild(source: first, insetLeft: -1)],
        ),
        throwsArgumentError,
      );
      final group = SelectionSource.group(
        id: 'root',
        revision: 0,
        children: [SelectionSourceChild(source: first)],
      );
      expect(group.child('text'), same(first));
      expect(() => group.child('absent'), throwsStateError);
      expect(() => group.children.clear(), throwsUnsupportedError);
    },
  );

  test(
    'unique earlier insertion preserves later identities and old snapshots',
    () {
      final first = _markdown('alpha\n\nbeta\n\ngamma');
      final old = selectionSourceNodes(first);
      final second = _markdown(
        'new\n\nalpha\n\nbeta\n\ngamma',
        previous: first,
      );
      final current = selectionSourceNodes(second);
      expect(
        current.skip(1).map((node) => node.id),
        old.map((node) => node.id),
      );
      expect(selectionSourceNodes(first).map((node) => node.fingerprint), [
        'p("alpha")',
        'p("beta")',
        'p("gamma")',
      ]);
    },
  );

  test('same-kind edit retains one token between surviving neighbors', () {
    final first = _markdown('left\n\nchanged\n\nright');
    final old = selectionSourceNodes(first);
    final second = _markdown('left\n\nshort\n\nright', previous: first);
    final current = selectionSourceNodes(second);
    expect(current.map((node) => node.id), old.map((node) => node.id));
    final removed = _markdown('left\n\nright', previous: second);
    expect(selectionSourceNodes(removed).map((node) => node.id), [
      old.first.id,
      old.last.id,
    ]);
  });

  test('duplicate ambiguity and crossed anchors never pair by occurrence', () {
    final first = _markdown('repeat\n\nrepeat');
    final oldIds = selectionSourceNodes(first).map((node) => node.id).toSet();
    final second = _markdown('new\n\nrepeat\n\nrepeat', previous: first);
    expect(
      selectionSourceNodes(second).any((node) => oldIds.contains(node.id)),
      isFalse,
    );
    final ordered = _markdown('a\n\nb\n\nc');
    final ids = selectionSourceNodes(ordered).map((node) => node.id).toList();
    final crossed = _markdown('b\n\na\n\nc', previous: ordered);
    final nodes = selectionSourceNodes(crossed);
    expect(nodes[0].id, isNot(ids[1]));
    expect(nodes[1].id, isNot(ids[0]));
    expect(nodes[2].id, ids[2]);
  });

  test('retyping and reparenting do not inherit nested fragment identity', () {
    final plain = _markdown('```\ncode\n```');
    final token = selectionSourceNodes(plain).single.id;
    final quoted = _markdown('> ```\n> code\n> ```', previous: plain);
    expect(
      selectionSourceNodes(quoted).single.children.single.id,
      isNot(token),
    );
    final paragraph = _markdown('text');
    final heading = _markdown('# text', previous: paragraph);
    expect(
      selectionSourceNodes(heading).single.id,
      isNot(selectionSourceNodes(paragraph).single.id),
    );
  });

  test('reference reparses retain unambiguous current semantic identities', () {
    final first = _markdown(
      'unchanged\n\n[link][ref]\n\nboundary\n\n[ref]: old',
    );
    final old = selectionSourceNodes(first);
    final second = _markdown(
      'unchanged\n\n[link][ref]\n\nboundary\n\n[ref]: new',
      previous: first,
    );
    final current = selectionSourceNodes(second);
    expect(current.first.id, old.first.id);
    expect(current[1].id, old[1].id);
    expect(selectionSourceNodes(first)[1].fingerprint, contains('old'));
    expect(current[1].fingerprint, contains('new'));
  });

  test('an unobserved thousand revisions does not retain a revision chain', () {
    var source = _markdown('start');
    final firstId = selectionSourceNodes(source).single.id;
    for (var i = 0; i < 1000; i++) {
      source = _markdown('start $i', previous: source);
    }
    expect(selectionSourceNodes(source).single.id, firstId);
    expect(selectionSourceRetainedBases(source), 0);
  });
  test(
    'known immutable parser prefix nodes are shared without reflattening them',
    () {
      final first = _markdown('repeat\n\nrepeat');
      final old = selectionSourceNodes(first);
      final next = _markdown('repeat\n\nrepeat\n\nnew', previous: first);
      final current = selectionSourceNodes(next);
      expect(current.first, same(old.first));
      expect(current.first.id, old.first.id);
    },
  );
  test(
    'diff snapshots freeze caller-owned model lists and geometry revisions',
    () {
      final model = diffTexts('old', 'new');
      final source = SelectionSource.diff(
        id: 'diff',
        revision: 0,
        view: model.view(),
      );
      model.sources[0] = 'mutated';
      model.hunks.clear();
      final frozen = selectionSourceDiff(source);
      expect(frozen.model.sources[0], 'old');
      expect(frozen.model.hunks, isNotEmpty);
      expect(() => frozen.model.hunks.clear(), throwsUnsupportedError);
      expect(
        () => SelectionSource.diff(
          id: 'diff',
          revision: 0,
          view: frozen,
          showTitle: false,
          previous: source,
        ),
        throwsArgumentError,
      );
    },
  );
  test('nested list-item diagnostic collisions are equality-confirmed', () {
    final old = _markdown('- ```\n  a\n  b\n  ```');
    final oldId = old.codeBlocks.single.id;
    final next = _markdown('- new\n- ```\n  ${r'a\nb'}\n  ```', previous: old);
    expect(next.codeBlocks.single.id, isNot(oldId));
  });
}
