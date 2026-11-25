import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test('lines that fit are all shown', () {
    expect(foldOf(3, 3), (shown: 3, more: 0));
    expect(foldOf(0, 0), (shown: 0, more: 0));
    expect(foldOf(2, 10), (shown: 2, more: 0));
  });

  test('lines that do not fit leave a row for the count', () {
    expect(foldOf(10, 4), (shown: 3, more: 7));
    expect(foldOf(10, 1), (shown: 0, more: 10));
    expect(foldOf(10, 0), (shown: 0, more: 10));
  });

  test('the count is singular for one line', () {
    expect(moreLines(1), '… 1 more line');
    expect(moreLines(2), '… 2 more lines');
  });
  group('tester: Fold budget invariants', () {
    test('all nonnegative budgets preserve lines and count within room', () {
      for (var lines = 0; lines <= 100; lines++) {
        for (var room = 0; room <= 100; room++) {
          final folded = foldOf(lines, room);
          expect(folded.shown + folded.more, lines);
          expect(folded.shown, inInclusiveRange(0, lines));
          expect(folded.more, inInclusiveRange(0, lines));
          final occupied = folded.shown + (room > 0 && folded.more > 0 ? 1 : 0);
          expect(occupied, lessThanOrEqualTo(room));
          if (room >= lines) expect(folded.more, 0);
        }
      }
    });
  });
}
