// The nearest-word pick as @std/text's closestString and
// levenshteinDistance give it (their own examples and tests), over code
// points as the original splits strings.
import 'package:chord/closest_string.dart';
import 'package:test/test.dart';

void main() {
  test('levenshteinDistance counts edits', () {
    expect(levenshteinDistance('aa', 'bb'), 2);
    expect(levenshteinDistance('', 'abc'), 3);
    expect(levenshteinDistance('abc', ''), 3);
    expect(levenshteinDistance('kitten', 'sitting'), 3);
    expect(levenshteinDistance('same', 'same'), 0);
  });

  test('levenshteinDistance counts code points, not UTF-16 units', () {
    expect(levenshteinDistance('😀', ''), 1);
    expect(levenshteinDistance('--d😀', '-h'), 3);
    expect(levenshteinDistance('--d😀', '--cwd'), 3);
  });

  test('closestString picks the nearest, case ignored, first of equals', () {
    expect(closestString('hep', ['length', 'size', 'blah', 'help']), 'help');
    expect(closestString('-c', ['--help', '-h', '--cwd', '-C']), '-C');
    expect(closestString('-x', ['--help', '-h', '--cwd', '-C']), '-h');
    expect(closestString('--d😀', ['--help', '-h', '--cwd', '-C']), '-h');
  });

  group('tester CTUI-111: code point boundaries', () {
    test('combining, joined emoji and escape text stay literal', () {
      expect(levenshteinDistance('é', 'e\u0301'), 2);
      expect(levenshteinDistance('👩‍💻', ''), 3);
      expect(levenshteinDistance('\x1b[31m', ''), 5);
      expect(levenshteinDistance('界😀e\u0301', '界😀e'), 1);
    });

    test('distant matches have no threshold and equal matches keep order', () {
      expect(closestString('faraway', ['x']), 'x');
      expect(closestString('', ['界', 'ab']), '界');
      expect(closestString('ABC', ['abc', 'ABC']), 'abc');
      expect(closestString('😀', ['界', 'x']), '界');
    });
  });
}
