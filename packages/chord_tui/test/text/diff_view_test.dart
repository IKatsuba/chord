import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  final model = parseUnifiedDiff(
    '@@ -1,2 +1,2 @@\n-old\n+new\n tail\n@@ -99 +100 @@\n-last\n+fresh\n',
  );
  test('full counts and limits exclude gaps from hidden lines', () {
    final full = model.view();
    expect(
      (full.added, full.removed, full.hidden, full.numberWidth),
      (2, 2, 0, 3),
    );
    expect(full.rows, hasLength(6));
    expect(full.rows[3], isA<DiffGap>());
    expect(model.view(maxRows: 2).rows, hasLength(2));
    final before = model.view(maxRows: 3);
    final on = model.view(maxRows: 4);
    final after = model.view(maxRows: 5);
    expect(before.rows, hasLength(3));
    expect(on.rows, before.rows);
    expect(on.hidden, 2);
    expect(after.rows, hasLength(5));
    expect(after.hidden, 1);
    expect(before.numberWidth, 1);
    expect(after.numberWidth, 2);
  });
  test('empty hunks never introduce orphan gaps or consume a cap', () {
    const empty = DiffHunk(
      oldStart: 0,
      oldCount: 0,
      newStart: 0,
      newCount: 0,
      lines: [],
    );
    final first = model.hunks.first;
    final second = model.hunks.last;
    final sparse = DiffModel([
      empty,
      first,
      empty,
      empty,
      second,
      empty,
    ], model.sources);
    expect(
      sparse.view().rows.map((row) => row is DiffGap ? 'gap' : '$row'),
      model.view().rows.map((row) => row is DiffGap ? 'gap' : '$row'),
    );
    for (final cap in [0, 1, 3, 4, 5, 20]) {
      final selected = sparse.view(maxRows: cap);
      expect(
        selected.rows.map((row) => row is DiffGap ? 'gap' : '$row'),
        model
            .view(maxRows: cap)
            .rows
            .map((row) => row is DiffGap ? 'gap' : '$row'),
      );
      expect(selected.hidden, model.view(maxRows: cap).hidden);
    }
    final onlyEmpty = const DiffModel([empty, empty, empty], []).view();
    expect(onlyEmpty.rows, isEmpty);
    expect((onlyEmpty.added, onlyEmpty.removed, onlyEmpty.hidden), (0, 0, 0));
  });
  test('zero retains full counts; negative is refused; large is full', () {
    final zero = model.view(maxRows: 0);
    expect(zero.rows, isEmpty);
    expect(
      (zero.added, zero.removed, zero.hidden, zero.numberWidth),
      (2, 2, 5, 1),
    );
    expect(() => model.view(maxRows: -1), throwsRangeError);
    expect(model.view(maxRows: 100).rows, model.view().rows);
    for (final diff in [diffTexts('', ''), diffTexts('a\r\n', 'a')]) {
      final view = diff.view();
      expect(view.rows, isEmpty);
      expect(
        (view.added, view.removed, view.hidden, view.numberWidth),
        (0, 0, 0, 1),
      );
    }
  });
  test(
    'selection keeps sources and row identity without mutating another view',
    () {
      final full = model.view();
      final selected = model.view(maxRows: 1);
      expect(selected.model, same(model));
      expect(selected.model.sources, same(model.sources));
      expect(selected.rows.first, same(full.rows.first));
      expect(() => selected.rows.clear(), throwsUnsupportedError);
      expect(full.rows, hasLength(6));
      expect(model.hunks, hasLength(2));
    },
  );
}
