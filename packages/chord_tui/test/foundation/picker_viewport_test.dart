import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test(
    'both-side count reserves footer and counts choices instead of lines',
    () {
      for (final top in [0, 2, 5]) {
        final view = (highlighted: top, top: top);
        final result = pickerLines(
          List.filled(8, 1),
          view,
          4,
          countHiddenItemsAbove: true,
        );
        expect(result.lines.length, 3);
        expect(result.hidden, 5);
      }
      final partial = pickerLines(
        [2, 3, 2, 1],
        (highlighted: 1, top: 1),
        4,
        countHiddenItemsAbove: true,
      );
      expect(partial.lines.map((line) => line.index).toSet(), {0, 1});
      expect(partial.hidden, 2);
      expect(
        pickerLines(
          [1, 5, 1],
          (highlighted: 1, top: 1),
          4,
          countHiddenItemsAbove: true,
        ).hidden,
        0,
      );
      expect(
        pickerLines(
          [1, 1],
          (highlighted: 1, top: 0),
          4,
          countHiddenItemsAbove: true,
        ).hidden,
        0,
      );
    },
  );
}
