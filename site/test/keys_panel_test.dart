import 'package:chord_site/keys_panel.dart';
import 'package:test/test.dart';

void main() {
  test('entries that fit leave room for the rule', () {
    final w = panelWindow(entries: 5, rows: 10, offset: 3);
    expect(
      (w.rule, w.first, w.count, w.above, w.below, w.overflows),
      (true, 0, 5, 0, 0, false),
    );
  });

  test('a panel that reaches the top of the page drops its rule', () {
    final w = panelWindow(entries: 9, rows: 10, offset: 0);
    expect((w.rule, w.count, w.overflows), (false, 9, false));
  });

  test('more entries than rows scroll between the counts', () {
    // Ten rows: the title, then nine for entries and counts.
    var w = panelWindow(entries: 20, rows: 10, offset: 0);
    expect((w.rule, w.first, w.count, w.above, w.below), (false, 0, 8, 0, 12));
    expect(w.overflows, isTrue);
    w = panelWindow(entries: 20, rows: 10, offset: 1);
    expect((w.first, w.count, w.above, w.below), (1, 7, 1, 12));
    final most = panelMaxOffset(entries: 20, rows: 10);
    expect(most, 12);
    w = panelWindow(entries: 20, rows: 10, offset: 99);
    expect((w.first, w.count, w.above, w.below), (12, 8, 12, 0));
  });

  test('every entry is reachable by scrolling', () {
    for (final rows in [4, 7, 10, 37]) {
      for (final entries in [1, 3, 9, 40]) {
        final seen = <int>{};
        final most = panelMaxOffset(entries: entries, rows: rows);
        for (var offset = 0; offset <= most; offset++) {
          final w = panelWindow(entries: entries, rows: rows, offset: offset);
          for (var i = w.first; i < w.first + w.count; i++) {
            seen.add(i);
          }
        }
        expect(seen, hasLength(entries), reason: '$entries in $rows');
      }
    }
  });
}
