import 'package:chord/ui/prompt/prompt.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test('prompt height is a third of the window, bounded to three and ten', () {
    for (final (rows, expected) in [
      (0, 3),
      (8, 3),
      (12, 4),
      (24, 8),
      (29, 9),
      (30, 10),
      (40, 10),
    ]) {
      expect(promptRows(rows), expected);
    }
  });

  test('gutter marks the start, hidden rows above and hidden rows below', () {
    final controller = TextAreaController(text: 'first\nsecond\nthird\nfourth');
    final rows = controller.layout(width: 20, maxHeight: 4).rows;
    expect(rows.map((row) => gutterMark(row, rows)), ['›', '', '', '']);
    final middle = rows.sublist(1, 3);
    expect(middle.map((row) => gutterMark(row, middle)), ['↑', '↓']);
    final bottom = rows.sublist(2);
    expect(bottom.map((row) => gutterMark(row, bottom)), ['↑', '']);
    expect(gutterMark(rows.first, rows.take(2).toList()), '›');
  });

  test('wrapped pieces and a single shown row use the original precedence', () {
    final controller = TextAreaController(text: 'abcdefghij');
    final rows = controller.layout(width: 3, maxHeight: 4).rows;
    final middle = rows.sublist(1, 3);
    expect(middle.map((row) => gutterMark(row, middle)), ['↑', '↓']);
    expect(gutterMark(rows[1], [rows[1]]), '↑');
    expect(gutterMark(rows.first, [rows.first]), '›');
  });

  test('an empty prompt keeps its start mark', () {
    final rows = TextAreaController().layout(width: 20, maxHeight: 3).shownRows;
    expect(gutterMark(rows.single, rows), '›');
  });
  group('tester U3 prompt geometry and gutter fidelity', () {
    test('height changes only at whole thirds and clamps both ends', () {
      for (final (rows, expected) in [
        (-1, 3),
        (1, 3),
        (9, 3),
        (10, 3),
        (11, 3),
        (12, 4),
        (13, 4),
        (14, 4),
        (15, 5),
        (27, 9),
        (28, 9),
        (29, 9),
        (30, 10),
        (31, 10),
        (300, 10),
      ]) {
        expect(promptRows(rows), expected, reason: 'window rows $rows');
      }
    });

    test('original three-row views retain interior and final blank marks', () {
      final controller = TextAreaController(text: 'abcde\nf\ng\nh\ni\nj\nk');
      addTearDown(controller.dispose);
      final rows = controller.layout(width: 3, maxHeight: 10).rows;
      for (final (shown, expected) in [
        (rows.sublist(0, 3), ['›', '', '↓']),
        (rows.sublist(3, 6), ['↑', '', '↓']),
        (rows.sublist(rows.length - 3), ['↑', '', '']),
        (rows.sublist(1, 4), ['↑', '', '↓']),
      ]) {
        expect(shown.map((row) => gutterMark(row, shown)), expected);
      }
    });

    test('single final row keeps upward precedence after trailing newline', () {
      final controller = TextAreaController(text: '界🙂e\u0301\n');
      addTearDown(controller.dispose);
      final layout = controller.layout(width: 3, maxHeight: 1);
      expect(layout.shownRows.single.last, isTrue);
      expect(layout.shownRows.single.text, '');
      expect(gutterMark(layout.shownRows.single, layout.shownRows), '↑');
    });

    test('an exact-width empty continuation is final without a down arrow', () {
      final controller = TextAreaController(text: '界🙂e\u0301');
      addTearDown(controller.dispose);
      final rows = controller.layout(width: 5, maxHeight: 3).rows;
      expect(rows.length, 2);
      expect(rows.last.text, '');
      expect(rows.map((row) => gutterMark(row, rows)), ['›', '']);
    });
  });
}
