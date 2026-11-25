// Original diff_test.ts: counts, headlines, folding, line endings and gaps
// carried over. Highlighting/wrapping belongs to framework Diff tests.
import 'package:chord/ui/transcript/tools/diff.dart';
import 'package:test/test.dart';

void main() {
  test('counts additions/removals and names the file in the headline', () {
    final diff = diffView('src/a.ts', 'a\nb\n', 'a\nc\nd\n');
    expect(
      diffHeadline(diff),
      'Updated src/a.ts with 2 additions and 1 removal',
    );
    expect(
      diffHeadline(diff, path: 'a.ts'),
      'Updated a.ts with 2 additions and 1 removal',
    );
    expect(plural(0, 'addition'), '0 additions');
  });
  test('a line ending is no edit; new files have no old text', () {
    expect(diffView('a', 'a\r\n', 'a').view.rows, isEmpty);
    expect(diffView('a', null, 'a\nb').view.added, 2);
  });
  test('normal tool diffs are full; helper can cap future proposals', () {
    final source = List.generate(30, (i) => 'line $i').join('\n');
    final all = diffView('a', null, source);
    final folded = diffView('a', null, source, expanded: false);
    expect(all.view.rows, hasLength(30));
    expect(all.view.hidden, 0);
    expect(folded.view.rows, hasLength(diffRows));
    expect(folded.view.hidden, 20);
  });
}
