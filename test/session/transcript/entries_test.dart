import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart' show describedEntry;

void main() {
  const a = UserEntry('t1', 'a');
  const b = UserEntry('t1', 'b');
  const c = UserEntry('t1', 'c');

  test('appended gives a new list, the old one as it was', () {
    final before = [a];
    final after = appended(before, [b, c]);

    expect(after.map(describedEntry), [a, b, c].map(describedEntry));
    expect(before, [a]);
  });

  test(
    'replacedAt and lastReplaced give a new list, the old one as it was',
    () {
      final before = appended(const [], [a, b]);

      expect(
        replacedAt(before, 0, c).map(describedEntry),
        [c, b].map(describedEntry),
      );
      expect(
        lastReplaced(before, c).map(describedEntry),
        [a, c].map(describedEntry),
      );
      expect(before.map(describedEntry), [a, b].map(describedEntry));
    },
  );

  test('a written list cannot be changed in place', () {
    expect(() => appended(const [], [a]).add(b), throwsUnsupportedError);
    expect(() => lastReplaced([a], b)[0] = c, throwsUnsupportedError);
  });

  test('the entries a write did not touch are the identical objects', () {
    final after = lastReplaced([a, b], c);

    expect(identical(after[0], a), isTrue);
  });

  test('replacing the last of no entries throws, for the caller to catch', () {
    expect(() => lastReplaced(const [], a), throwsRangeError);
  });
}
