import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('CHD-638 tester: scrollbar geometry boundaries', () {
    test('empty views and tracks have no thumb or drag destination', () {
      for (final (track, view) in [(0, 10), (10, 0)]) {
        expect(
          scrollbarThumb(track: track, view: view, content: 100, offset: 0),
          isNull,
        );
        expect(
          scrollbarOffsetFor(top: 5, track: track, view: view, content: 100),
          0,
        );
      }
    });

    test('a one-row track contains the thumb and cannot move it', () {
      expect(scrollbarThumb(track: 1, view: 24, content: 2000, offset: 1000), (
        top: 0,
        length: 1,
      ));
      expect(scrollbarOffsetFor(top: 99, track: 1, view: 24, content: 2000), 0);
    });

    test('different track and view sizes clamp both ends monotonically', () {
      var previous = 0;
      for (var offset = -10; offset <= 1010; offset++) {
        final thumb = scrollbarThumb(
          track: 40,
          view: 10,
          content: 1000,
          offset: offset,
        )!;
        expect(thumb.top, greaterThanOrEqualTo(previous));
        expect(thumb.top + thumb.length, lessThanOrEqualTo(40));
        previous = thumb.top;
      }
      expect(
        scrollbarThumb(track: 40, view: 10, content: 1000, offset: -10)!.top,
        0,
      );
      expect(previous, 39);
    });
  });
}
