import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester U2a source selection', () {
    final model = parseUnifiedDiff(
      '@@ -9,2 +9,2 @@\n-old\n+fresh\n tail\n'
      '@@ -99 +100 @@\n-last\n+latest\n'
      '@@ -999 +1000 @@\n-end\n+finish\n',
    );

    test('every cap conserves full counts and selected source identity', () {
      final full = model.view();
      final fullLines = full.rows.whereType<DiffLine>().toList();
      for (var cap = 0; cap <= full.rows.length + 2; cap++) {
        final view = model.view(maxRows: cap);
        final selected = view.rows.whereType<DiffLine>().toList();
        expect(view.added, 3);
        expect(view.removed, 3);
        expect(view.hidden + selected.length, fullLines.length);
        expect(view.rows.length, lessThanOrEqualTo(cap));
        if (view.rows.isNotEmpty) {
          expect(view.rows.first, isA<DiffLine>());
          expect(view.rows.last, isA<DiffLine>());
        }
        for (var i = 0; i < selected.length; i++) {
          expect(selected[i], same(fullLines[i]));
          expect(
            selected[i].text,
            model.sources[selected[i].source].split('\n')[selected[i].line],
          );
        }
      }
    });

    test('number width follows selected rows across decimal boundaries', () {
      expect(model.view(maxRows: 1).numberWidth, 1);
      expect(model.view(maxRows: 3).numberWidth, 2);
      expect(model.view(maxRows: 5).numberWidth, 2);
      expect(model.view(maxRows: 6).numberWidth, 3);
      expect(model.view().numberWidth, 4);
    });

    test('unmodifiable views stay independent after repeated selections', () {
      final kept = model.view(maxRows: 2);
      final originalSources = model.sources.toList();
      for (var i = 0; i < 1000; i++) {
        model.view(maxRows: i % 10);
      }
      expect(kept.rows, hasLength(2));
      expect(kept.hidden, 5);
      expect(model.sources, originalSources);
      expect(() => kept.rows[0] = const DiffGap(), throwsUnsupportedError);
      expect(() => kept.rows.add(const DiffGap()), throwsUnsupportedError);
    });

    test('line-ending normalization survives view selection symmetrically', () {
      for (final (old, fresh) in [
        ('a\r\nb\r\n', 'a\nb'),
        ('a\nb', 'a\r\nb\r\n'),
        ('', ''),
      ]) {
        final view = diffTexts(old, fresh).view(maxRows: 1);
        expect(view.rows, isEmpty);
        expect(
          (view.added, view.removed, view.hidden, view.numberWidth),
          (0, 0, 0, 1),
        );
      }
      for (final model in [diffTexts('', '\n'), diffTexts('\n', '')]) {
        final view = model.view(maxRows: 1);
        expect(view.rows.whereType<DiffLine>().single.text, '');
        expect(view.added + view.removed, 1);
        expect(view.hidden, 0);
      }
    });
  });
}
