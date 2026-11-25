import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('full view matches existing Diff at $size', (t) async {
      const old = 'export function greet() {\n  return "old";\n}\n';
      const fresh = 'export function greet() {\n  return "new";\n}\n';
      await t.pumpWidget(const Diff(old, fresh, title: 'a.ts'), size: size);
      final lines = t.screen.lines.toList();
      final styles = [
        for (var y = 0; y < size.height; y++)
          [for (var x = 0; x < size.width; x++) t.screen.styleAt(x, y)],
      ];
      await t.pumpWidget(
        Diff.fromView(diffTexts(old, fresh).view(), title: 'a.ts'),
        size: size,
      );
      expect(t.screen.lines, lines);
      for (var y = 0; y < size.height; y++) {
        for (var x = 0; x < size.width; x++) {
          expect(t.screen.styleAt(x, y), styles[y][x]);
        }
      }
    });
    testWidgets(
      'selection highlights from complete sources with title hidden at $size',
      (t) async {
        final old =
            '/* comment opens\n${List.filled(8, 'inside comment').join('\n')}\nold\n*/';
        final fresh = old.replaceFirst('old', 'new');
        final view = diffTexts(old, fresh, context: 0).view(maxRows: 1);
        await t.pumpWidget(
          Diff.fromView(view, title: 'a.dart', showTitle: false),
          size: size,
        );
        expect(t.screen.lines.first, '10 - old');
        final theme = ThemeData.dark();
        expect(
          t.screen.styleAt(5, 0),
          theme.diff.tint!.text
              .merge(theme.code!.tint.comment)
              .copyWith(bg: theme.diff.tint!.removed.bg),
        );
        expect(t.screen.lines[1], isEmpty);
      },
    );
    testWidgets('one selected source row wraps whole at $size', (t) async {
      final text = List.filled(15, 'terminal cells').join(' ');
      final view = diffTexts(text, 'short', context: 0).view(maxRows: 1);
      await t.pumpWidget(Diff.fromView(view, showTitle: false), size: size);
      expect(view.rows, hasLength(1));
      expect(view.hidden, 1);
      expect(
        t.screen.lines.where((line) => line.isNotEmpty).length,
        greaterThan(1),
      );
      expect(t.screen.lines.where((line) => line.contains('short')), isEmpty);
    });
    testWidgets('empty view keeps optional title at $size', (t) async {
      final view = diffTexts('a', 'b').view(maxRows: 0);
      await t.pumpWidget(Diff.fromView(view, title: 'a.txt'), size: size);
      expect(t.screen.lines.take(2), ['a.txt', '']);
      await t.pumpWidget(
        Diff.fromView(view, title: 'a.txt', showTitle: false),
        size: size,
      );
      expect(t.screen.lines.every((line) => line.isEmpty), isTrue);
    });
  }
}
