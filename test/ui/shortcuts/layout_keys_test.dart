// The US keys a Russian layout's characters are read as, from the
// original's layoutKeys: convert-layout's Russian – PC table, then Apple's
// ё, and nothing for what a US layout types itself.
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:test/test.dart';

void main() {
  group('tester: CTUI-67 table input boundaries', () {
    test(
      'every printable US character and unrelated graphemes stay unchanged',
      () {
        for (var code = 0x20; code <= 0x7e; code++) {
          expect(
            layoutKeys(String.fromCharCode(code)),
            isEmpty,
            reason: '$code',
          );
        }
        for (final text in [
          '界',
          '🙂',
          'e\u0301',
          'ф\u0301',
          'фё',
          '\x1b[31m',
        ]) {
          expect(layoutKeys(text), isEmpty, reason: text);
        }
      },
    );
  });

  test('a Russian character is the US key in its place, Russian – PC '
      'first, then Apple\'s', () {
    expect(layoutKeys('ч'), ['x']);
    expect(layoutKeys('Ф'), ['A']);
    expect(layoutKeys('б'), [',']);
    expect(layoutKeys('Ж'), [':']);
    expect(layoutKeys('№'), ['#']);
    expect(layoutKeys('ё'), ['`', r'\']);
    expect(layoutKeys('Ё'), ['~', '|']);
  });

  test('what a US layout types itself, and what is no one character, is '
      'left alone', () {
    for (final typed in [',', '?', '.', '/', 'a', 'A', ' ', '', 'чх', 'ü']) {
      expect(layoutKeys(typed), isEmpty, reason: typed);
    }
  });
}
