import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/foundation/selection.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:test/test.dart';

List<SelectionFragmentProjection> _shape(SelectionSource source) =>
    shapeSelectionSource(source, width: 80).fragments;

void main() {
  test(
    'inclusive forward/reverse endpoints, equality empty and release unchanged',
    () {
      final source = SelectionSource.text(
        id: 'text',
        revision: 0,
        text: const TextSpan('This 👩‍💻 e\u0301界'),
      );
      final fragment = _shape(source).single;
      final model = SelectionRangeModel();
      model.begin(fragment, 0);
      model.extend([fragment], SelectionPosition(fragment.id, 3));
      expect(model.value.text, 'This');
      model.finalize();
      expect(model.value.phase, SelectionPhase.finalized);
      model.begin(fragment, 3);
      model.extend([fragment], SelectionPosition(fragment.id, 0));
      expect(model.value.text, 'This');
      model.extend([fragment], SelectionPosition(fragment.id, 3));
      expect(model.value.text, isEmpty);
      expect(model.leases, isEmpty);
    },
  );
  test('mixed source order/separators is identical in both directions', () {
    final source = SelectionSource.group(
      id: 'document',
      revision: 0,
      children: [
        SelectionSourceChild(
          source: SelectionSource.text(
            id: 'header',
            revision: 0,
            text: const TextSpan('Header'),
          ),
        ),
        SelectionSourceChild(
          source: SelectionSource.markdown(
            id: 'reply',
            revision: 0,
            text: 'first\n\nsecond',
          ),
        ),
        SelectionSourceChild(
          source: SelectionSource.code(id: 'draft', revision: 0, text: 'draft'),
        ),
      ],
    );
    final fragments = _shape(source);
    final model = SelectionRangeModel();
    model.begin(fragments.first, 0);
    model.extend(fragments, SelectionPosition(fragments.last.id, 4));
    expect(model.value.text, 'Header\nfirst\n \nsecond\ndraft');
    model.begin(fragments.last, 4);
    model.extend(fragments, SelectionPosition(fragments.first.id, 0));
    expect(model.value.text, 'Header\nfirst\n \nsecond\ndraft');
  });
  test(
    'same-source edits clamp while finalized output never extends on append',
    () {
      var source = SelectionSource.text(
        id: 'text',
        revision: 0,
        text: const TextSpan('abcdef'),
      );
      var fragment = _shape(source).single;
      final model = SelectionRangeModel()..begin(fragment, 1);
      model.extend([fragment], SelectionPosition(fragment.id, 5));
      model.finalize();
      source = SelectionSource.text(
        id: 'text',
        revision: 1,
        text: const TextSpan('abcdefgh'),
        previous: source,
      );
      fragment = _shape(source).single;
      model.reconcile([fragment]);
      expect(model.value.text, 'bcdef');
      source = SelectionSource.text(
        id: 'text',
        revision: 2,
        text: const TextSpan('abc'),
        previous: source,
      );
      model.reconcile(_shape(source));
      expect(model.value.text, 'bc');
      model.reconcile([]);
      expect(model.value.phase, SelectionPhase.none);
      expect(model.leases, isEmpty);
    },
  );
  test(
    'new fragments cannot inherit ranges; surviving selected text remains',
    () {
      var source = SelectionSource.markdown(
        id: 'reply',
        revision: 0,
        text: 'first\n\nsecond',
      );
      final fragments = _shape(source);
      final model = SelectionRangeModel()..begin(fragments.first, 0);
      model.extend(fragments, SelectionPosition(fragments.last.id, 5));
      model.finalize();
      source = SelectionSource.markdown(
        id: 'reply',
        revision: 1,
        text: 'new\n\nfirst',
        previous: source,
      );
      model.reconcile(_shape(source));
      expect(model.value.text, 'first');
      expect(model.leases, hasLength(1));
      model.clear();
      expect(model.leases, isEmpty);
    },
  );
  test('same source token cannot carry a lease across reparenting', () {
    final leaf = SelectionSource.text(
      id: 'leaf',
      revision: 0,
      text: const TextSpan('text'),
    );
    final first = SelectionSource.group(
      id: 'parent-a',
      revision: 0,
      children: [SelectionSourceChild(source: leaf)],
    );
    final fragment = _shape(first).single;
    final model = SelectionRangeModel()..begin(fragment, 0);
    model.extend([fragment], SelectionPosition(fragment.id, 3));
    final other = SelectionSource.group(
      id: 'parent-b',
      revision: 0,
      children: [SelectionSourceChild(source: leaf)],
    );
    model.reconcile(_shape(other));
    expect(model.value.phase, SelectionPhase.none);
  });
  test('reparented endpoints migrate only to surviving selected fragments', () {
    final a = SelectionSource.text(
      id: 'a',
      revision: 0,
      text: const TextSpan('first'),
    );
    final b = SelectionSource.text(
      id: 'b',
      revision: 0,
      text: const TextSpan('second'),
    );
    final first = SelectionSource.group(
      id: 'root',
      revision: 0,
      children: [
        SelectionSourceChild(source: a),
        SelectionSourceChild(source: b),
      ],
    );
    final old = _shape(first);
    final model = SelectionRangeModel()..begin(old.first, 0);
    model.extend(old, SelectionPosition(old.last.id, 5));
    model.finalize();
    final next = SelectionSource.group(
      id: 'root',
      revision: 1,
      previous: first,
      children: [
        SelectionSourceChild(
          source: SelectionSource.group(
            id: 'nested',
            revision: 0,
            children: [SelectionSourceChild(source: a)],
          ),
        ),
        SelectionSourceChild(source: b),
      ],
    );
    model.reconcile(_shape(next));
    expect(model.value.text, 'second');
    expect(model.value.anchor, SelectionPosition(old.last.id, 0));
    expect(model.value.extent, SelectionPosition(old.last.id, 5));
  });
  test('blank code-line boundaries preserve LF only when crossed', () {
    final fragment = _shape(
      SelectionSource.code(id: 'code', revision: 0, text: '\necho done'),
    ).single;
    final model = SelectionRangeModel()..begin(fragment, 0);
    model.extend([fragment], SelectionPosition(fragment.id, 0));
    expect(model.value.text, isEmpty);
    model.extend([fragment], SelectionPosition(fragment.id, 9));
    expect(model.value.text, '\necho done');
    model.begin(fragment, 9);
    model.extend([fragment], SelectionPosition(fragment.id, 0));
    expect(model.value.text, '\necho done');
  });
  test(
    'diagnostic newline collisions cannot authorize ambiguous source identity',
    () {
      final old = SelectionSource.markdown(
        id: 'reply',
        revision: 0,
        text: '```\na\nb\n```\n\nend',
      );
      final oldFragments = _shape(old);
      final code = oldFragments.first;
      final model = SelectionRangeModel()..begin(code, 0);
      model.extend(oldFragments, SelectionPosition(code.id, 2));
      model.finalize();
      expect(model.value.text, 'a\nb');
      final next = SelectionSource.markdown(
        id: 'reply',
        revision: 1,
        previous: old,
        text: 'new\n\n```\n${r'a\nb'}\n```\n\nend',
      );
      final current = _shape(next);
      expect(next.codeBlocks.single.id, isNot(old.codeBlocks.single.id));
      model.reconcile(current);
      expect(model.value.phase, SelectionPhase.none);
      expect(model.leases, isEmpty);
    },
  );
}
