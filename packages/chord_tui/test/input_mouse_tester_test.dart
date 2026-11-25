import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester: SGR modifier and coordinate boundaries', () {
    test(
      'each button modifier and release survives every split at coordinate limits',
      () {
        for (var modifier = 0; modifier < 8; modifier++) {
          for (var button = 0; button < 3; button++) {
            for (final finalByte in ['M', 'm']) {
              final wire =
                  '\x1b[<${button + modifier * 4};999999999;1$finalByte';
              for (var split = 0; split <= wire.length; split++) {
                final parser = InputParser();
                final events = [
                  ...parser.feed(wire.substring(0, split)),
                  ...parser.feed(wire.substring(split)),
                ];
                final event = events.single as MouseEvent;
                expect(event.position, const Offset(999999998, 0));
                expect(
                  event.kind,
                  finalByte == 'M'
                      ? MouseEventKind.press
                      : MouseEventKind.release,
                );
                expect(
                  event.button,
                  [
                    MouseButton.primary,
                    MouseButton.middle,
                    MouseButton.secondary,
                  ][button],
                );
                expect(event.shift, modifier & 1 != 0);
                expect(event.alt, modifier & 2 != 0);
                expect(event.ctrl, modifier & 4 != 0);
                expect(event.scrollDelta, Offset.zero);
                expect(parser.hasPending, isFalse);
              }
            }
          }
        }
      },
    );
    test('thousand concatenated reports never become printable input', () {
      final wire = List.generate(
        1000,
        (i) => '\x1b[<${64 + i % 2};1;1M',
      ).join();
      final parser = InputParser();
      final events = parser.feed('${wire}z');
      expect(events.whereType<MouseEvent>(), hasLength(1000));
      expect(events.whereType<KeyEvent>().map((e) => e.key), ['z']);
      expect(parser.hasPending, isFalse);
    });
  });
}
