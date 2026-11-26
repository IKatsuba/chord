import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('scrollbarThumb', () {
    test('no thumb when the content fits or there is no track', () {
      expect(
        scrollbarThumb(track: 10, view: 10, content: 10, offset: 0),
        isNull,
      );
      expect(
        scrollbarThumb(track: 10, view: 10, content: 4, offset: 0),
        isNull,
      );
      expect(
        scrollbarThumb(track: 0, view: 10, content: 40, offset: 0),
        isNull,
      );
    });

    test('its length is track × view / content, rounded', () {
      expect(scrollbarThumb(track: 10, view: 10, content: 40, offset: 0), (
        top: 0,
        length: 3,
      ));
      expect(scrollbarThumb(track: 20, view: 10, content: 40, offset: 0), (
        top: 0,
        length: 5,
      ));
    });

    test('it is at least one row', () {
      expect(scrollbarThumb(track: 10, view: 10, content: 10000, offset: 0), (
        top: 0,
        length: 1,
      ));
    });

    test('its top follows the offset, end to end', () {
      // track 10, view 10, content 40: length 3, room 7, travel 30.
      expect(
        scrollbarThumb(track: 10, view: 10, content: 40, offset: 30)!.top,
        7,
      );
      expect(
        scrollbarThumb(track: 10, view: 10, content: 40, offset: 15)!.top,
        4,
      );
      expect(
        scrollbarThumb(track: 10, view: 10, content: 40, offset: 99)!.top,
        7,
      );
    });
  });

  group('scrollbarOffsetFor', () {
    test('maps the thumb top back onto the offset, clamped', () {
      expect(scrollbarOffsetFor(top: 0, track: 10, view: 10, content: 40), 0);
      expect(scrollbarOffsetFor(top: 7, track: 10, view: 10, content: 40), 30);
      expect(scrollbarOffsetFor(top: 99, track: 10, view: 10, content: 40), 30);
      expect(scrollbarOffsetFor(top: -3, track: 10, view: 10, content: 40), 0);
    });

    test('is 0 when the thumb cannot move', () {
      expect(scrollbarOffsetFor(top: 3, track: 10, view: 10, content: 8), 0);
      expect(scrollbarOffsetFor(top: 0, track: 1, view: 10, content: 40), 0);
    });
  });
}
