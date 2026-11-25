import 'package:chord/ui/transcript/tools/diff.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester U2 tool edit boundaries', () {
    test(
      'creation deletion and unchanged edits keep whole path and counts',
      () {
        for (final (old, fresh, added, removed) in [
          (null, '界\n👩‍💻\ne\u0301', 3, 0),
          ('a\nb', '', 0, 2),
          ('a\r\n', 'a', 0, 0),
        ]) {
          final view = diffView('directory/界.ts', old, fresh);
          expect((view.view.added, view.view.removed), (added, removed));
          expect(view.path, 'directory/界.ts');
          expect(view.view.hidden, 0);
          expect(
            diffHeadline(view, path: 'short.ts'),
            startsWith('Updated short.ts '),
          );
        }
      },
    );

    test('optional cap retains full counts without a dangling gap', () {
      final old = List.generate(40, (i) => 'line $i').join('\n');
      final fresh = old
          .replaceFirst('line 3\n', 'changed\n')
          .replaceFirst('line 35\n', 'changed again\n');
      final full = diffView('a.ts', old, fresh);
      final capped = diffView('a.ts', old, fresh, expanded: false);
      expect((capped.view.added, capped.view.removed), (2, 2));
      expect(capped.view.rows.last, isA<DiffLine>());
      expect(
        capped.view.hidden + capped.view.rows.whereType<DiffLine>().length,
        full.view.rows.whereType<DiffLine>().length,
      );
      expect(diffHeadline(capped), diffHeadline(full));
    });
  });
}
