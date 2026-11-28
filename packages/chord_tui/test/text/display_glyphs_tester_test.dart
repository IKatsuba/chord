import 'package:chord_tui/src/text/display_glyphs.dart';
import 'package:test/test.dart';

void main() {
  group('CHD-638 tester: display glyph boundary data', () {
    for (final size in DisplaySize.values) {
      test('non-BMP input takes one fallback glyph at $size', () {
        expect(displayMeasure('🙂', size), displayMeasure('~', size));
        expect(displayRows('🙂', size), displayRows('~', size));
        expect(displayRows('🙂', size).first.single.source, 0);
      });
    }

    test('control and Unicode input only produce block cells and spaces', () {
      const input = '界👩‍💻e\u0301\x1b[31m';
      for (final size in DisplaySize.values) {
        final rows = displayRows(input, size);
        final width = displayMeasure(input, size).width;
        for (final row in rows) {
          final text = row.map((run) => run.text).join();
          expect(text.length, width);
          expect(text, matches(RegExp(r'^[ █▀▄]*$')));
        }
      }
    });
  });
}
