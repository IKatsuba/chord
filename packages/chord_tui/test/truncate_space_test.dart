import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  // End-position cases from cli-truncate's upstream test.js. ANSI uses
  // truncate's existing plain-output contract rather than styling strings.
  test('word preference matches upstream end-position examples', () {
    for (final (text, width, ellipsis, expected) in [
      ('dragons are awesome', 15, '…', 'dragons are…'),
      ('unicorns rainbow dragons', 6, '…', 'unico…'),
      ('unicorns are awesome dragons here today', 6, '...', 'uni...'),
      ('你好世界你好 are awesome', 18, '…', '你好世界你好 are…'),
      ('ab\tcd ef gh ij kl mn', 6, '…', 'ab\tcd…'),
      ('ab\u200Bcd ef gh ij kl', 6, '…', 'ab\u200Bcd…'),
    ]) {
      expect(
        truncate(
          text,
          width,
          ellipsis: ellipsis,
          preferTruncationOnSpace: true,
        ),
        expected,
      );
    }
  });

  test('searches no farther than three cells behind the budget', () {
    for (final (width, expected) in [
      (5, 'abcd…'),
      (6, 'abcd…'),
      (7, 'abcd…'),
      (8, 'abcd…'),
      (9, 'abcd efg…'),
    ]) {
      expect(
        truncate('abcd efghijklmnop', width, preferTruncationOnSpace: true),
        expected,
      );
    }
    expect(truncate('abcd efghijklmnop', 8), 'abcd ef…');
    expect(
      truncate('abcd\tefghijklmnop', 8, preferTruncationOnSpace: true),
      'abcd\tefg…',
    );
  });

  test('preserves graphemes and respects wide and multi-cell budgets', () {
    for (final text in [
      'café crème brûlée unicorns',
      'cafe\u0301 cre\u0300me bru\u0302le\u0301e unicorns',
      '👩‍💻 日本語 long words',
      'a界 bcdefghijkl',
    ]) {
      for (var width = 0; width < 25; width++) {
        for (final ellipsis in ['…', '...']) {
          final result = truncate(
            text,
            width,
            ellipsis: ellipsis,
            preferTruncationOnSpace: true,
          );
          expect(cellWidth(result), lessThanOrEqualTo(width));
          expect(result, isNot(endsWith('\u200d…')));
        }
      }
    }
    expect(
      truncate('e\u0301abcdef', 3, preferTruncationOnSpace: true),
      'e\u0301a…',
    );
  });

  test('fitting, empty and ANSI input keep existing truncate behavior', () {
    expect(truncate('', 0, preferTruncationOnSpace: true), '');
    expect(truncate('short', 5, preferTruncationOnSpace: true), 'short');
    expect(truncate('long', 0, preferTruncationOnSpace: true), '');
    expect(truncate('long', 1, preferTruncationOnSpace: true), '…');
    expect(
      truncate(
        '\x1b[31mdragons are awesome\x1b[0m',
        15,
        preferTruncationOnSpace: true,
      ),
      'dragons are…',
    );
  });
  group('tester U10a space cutoff boundaries', () {
    test(
      'chooses the nearest of several spaces without trimming the prefix',
      () {
        for (final (text, width, expected) in [
          ('ab cd efghijkl', 8, 'ab cd…'),
          ('ab  cd efghijkl', 8, 'ab  cd…'),
          ('   abcdefghijkl', 6, '  …'),
          ('a bcdefghijkl', 6, 'a bcd…'),
          ('a bcdefghijkl', 5, 'a…'),
        ]) {
          expect(
            truncate(text, width, preferTruncationOnSpace: true),
            expected,
          );
        }
      },
    );

    test('wide and combining clusters locate spaces by cells', () {
      for (final (text, width, expected) in [
        ('界🙂 abcdefghij', 8, '界🙂…'),
        ('界🙂 abcdefghij', 9, '界🙂 abc…'),
        ('e\u0301 xxxxxxxxxxxx', 5, 'e\u0301…'),
        ('👩‍💻 a bcccccccc', 8, '👩‍💻 a…'),
      ]) {
        final result = truncate(text, width, preferTruncationOnSpace: true);
        expect(result, expected);
        expect(cellWidth(result), lessThanOrEqualTo(width));
      }
    });

    test('custom marker budget and ANSI stripping keep existing contracts', () {
      expect(
        truncate(
          'ab cd efghijkl',
          8,
          ellipsis: '>>',
          preferTruncationOnSpace: true,
        ),
        'ab cd>>',
      );
      const colored = '\x1b[31mab cd efghijkl\x1b[0m';
      expect(truncate(colored, 8, preferTruncationOnSpace: true), 'ab cd…');
      expect(truncate(colored, 30, preferTruncationOnSpace: true), colored);
      expect(truncate('abcdef', 0, preferTruncationOnSpace: true), '');
      expect(truncate('abcdef', 1, preferTruncationOnSpace: true), '…');
      expect(
        truncate('abcdef', 2, ellipsis: '...', preferTruncationOnSpace: true),
        '..',
      );
    });

    test('disabled preference remains byte-for-byte the default', () {
      for (final text in [
        'ab cd efghijkl',
        '界🙂 e\u0301 text',
        '\x1b[31mred words\x1b[0m',
        '',
      ]) {
        for (var width = 0; width < 20; width++) {
          expect(
            truncate(text, width, preferTruncationOnSpace: false),
            truncate(text, width),
          );
        }
      }
    });
  });
}
