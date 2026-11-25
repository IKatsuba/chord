// How long folding a reply's chunks takes when each chunk rebuilds the
// entry's text (`text + chunk`) and the entry list (a copy per update), as a
// literal port of messages.ts's appendText would, against keeping the parts.
//   dart run fold_cost.dart
void main() {
  for (final (label, chunks, size) in [
    ('10 000 chunks of 8 B', 10000, 8),
    ('flood: 1 024 chunks of 64 KiB (64 MiB)', 1024, 64 * 1024),
  ]) {
    final chunk = 'x' * size;
    var watch = Stopwatch()..start();
    var text = '';
    for (var i = 0; i < chunks; i++) {
      text = text + chunk;
    }
    final concat = watch.elapsedMilliseconds;
    watch = Stopwatch()..start();
    final parts = <String>[];
    for (var i = 0; i < chunks; i++) {
      parts.add(chunk);
    }
    final joined = parts.join();
    final kept = watch.elapsedMilliseconds;
    print(
      '$label: text + chunk $concat ms, parts then one join $kept ms '
      '(${text.length == joined.length})',
    );
  }
  for (final entries in [1000, 10000]) {
    final list = List<Object>.generate(entries, (i) => i);
    final watch = Stopwatch()..start();
    var current = list;
    for (var i = 0; i < 1000; i++) {
      current = [...current.take(current.length - 1), i]; // lastReplaced
    }
    print(
      '1 000 updates to the last of $entries entries, list copied each: '
      '${watch.elapsedMilliseconds} ms',
    );
  }
}
