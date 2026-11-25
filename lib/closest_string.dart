/// The nearest-word pick the original's Cliffy suggests options with, as
/// @std/text's `closest_string.ts` and `levenshtein_distance.ts`: over
/// code points, as JavaScript's `[...string]` splits them. Our own, as
/// docs/decisions.md says: did_you_mean counts UTF-16 units.
library;

/// The Levenshtein distance between [a] and [b], counted in code points.
int levenshteinDistance(String a, String b) {
  final s = a.runes.toList();
  final t = b.runes.toList();
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;
  var previous = List<int>.generate(t.length + 1, (j) => j);
  for (var i = 1; i <= s.length; i++) {
    final current = List<int>.filled(t.length + 1, 0)..[0] = i;
    for (var j = 1; j <= t.length; j++) {
      final substitute = previous[j - 1] + (s[i - 1] == t[j - 1] ? 0 : 1);
      final delete = previous[j] + 1;
      final insert = current[j - 1] + 1;
      current[j] = [substitute, delete, insert].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[t.length];
}

/// The word of [words] nearest [given], case ignored, the first of equally
/// near ones; [words] must not be empty.
String closestString(String given, List<String> words) {
  final lower = given.toLowerCase();
  var nearest = words.first;
  var least = -1;
  for (final word in words) {
    final distance = levenshteinDistance(lower, word.toLowerCase());
    if (least < 0 || distance < least) {
      nearest = word;
      least = distance;
    }
  }
  return nearest;
}
