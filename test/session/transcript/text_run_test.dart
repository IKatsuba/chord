import 'package:chord/session/transcript/text_run.dart';
import 'package:test/test.dart';

void main() {
  test('a run reads what was appended to it, in order', () {
    final run = TextRun.empty.plus('Hello').plus(', world').plus('.');

    expect(run.text, 'Hello, world.');
    expect(run.length, 13);
  });

  test('an earlier snapshot still reads its own prefix', () {
    final first = TextRun.empty.plus('Hello');
    final second = first.plus(', world');

    second.plus('.');

    expect(first.text, 'Hello');
    expect(second.text, 'Hello, world');
  });

  test('appending to an earlier snapshot forks, leaving the later one', () {
    final first = TextRun.empty.plus('Hello');
    final later = first.plus(', world');
    final fork = first.plus(' there');

    expect(fork.text, 'Hello there');
    expect(later.text, 'Hello, world');
    expect(later.plus('!').text, 'Hello, world!');
    expect(fork.plus('!').text, 'Hello there!');
  });

  test('a read text is kept, and a later append does not change it', () {
    final run = TextRun.empty.plus('a');

    expect(run.text, 'a');
    run.plus('b');
    expect(run.text, 'a');
    expect(identical(run.text, run.text), isTrue);
  });

  test('the empty run stays empty, and nothing appended is the same run', () {
    final one = TextRun.empty.plus('one');
    final two = TextRun.empty.plus('two');

    expect(TextRun.empty.text, '');
    expect(one.text, 'one');
    expect(two.text, 'two');
    expect(identical(one.plus(''), one), isTrue);
  });

  test("the fake's flood, 1 024 chunks of 64 KiB, folds within a bound", () {
    final chunk = 'x' * (64 * 1024);
    final watch = Stopwatch()..start();
    var run = TextRun.empty;

    for (var i = 0; i < 1024; i++) {
      run = run.plus(chunk);
    }

    final folded = watch.elapsed;

    expect(run.length, 1024 * 64 * 1024);
    expect(run.text.length, run.length);
    // A copy per chunk took 3 632 ms (runtime's fold_cost.txt); appending
    // in place takes a few.
    expect(folded, lessThan(const Duration(milliseconds: 500)));
  });
}
