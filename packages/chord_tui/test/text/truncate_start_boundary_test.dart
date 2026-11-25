import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester: truncateStart boundary integration', () {
    test(
      'OSC hyperlinks survive fitting input and disappear on truncation',
      () {
        for (final terminator in ['\x07', '\x1b\\']) {
          final text =
              '\x1b]8;;https://example.test$terminator'
              'abcdef'
              '\x1b]8;;$terminator';
          expect(truncateStart(text, 6), text);
          expect(truncateStart(text, 5), '…cdef');
          final marker =
              '\x1b]8;;https://example.test$terminator'
              '界x'
              '\x1b]8;;$terminator';
          expect(truncateStart('abcdef', 1, ellipsis: marker), '');
          expect(truncateStart('abcdef', 2, ellipsis: marker), '界');
          expect(truncateStart('abcdef', 4, ellipsis: marker), '界xf');
        }
      },
    );

    test('flags, modifiers, keycaps and joined families remain contiguous', () {
      for (final cluster in [
        '🇺🇳',
        '👍🏽',
        '1️⃣',
        '👨‍👩‍👧‍👦',
        'e\u0301\u0327',
      ]) {
        final cells = cellWidth(cluster);
        expect(truncateStart('prefix${cluster}z', cells + 2), '…${cluster}z');
        expect(truncateStart('prefix${cluster}z', cells + 1), '…z');
        expect(truncateStart('prefix$cluster', cells + 1), '…$cluster');
        expect(truncateStart('prefix$cluster', cells, ellipsis: ''), cluster);
      }
    });

    test('standard terminal budgets retain the complete trailing cells', () {
      for (final width in [80, 120]) {
        final text = 'a' * 1000 + 'tail';
        expect(truncateStart(text, width), '…${'a' * (width - 5)}tail');
        expect(cellWidth(truncateStart(text, width)), width);
      }
    });
  });
}
