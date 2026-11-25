import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/fold.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('open, then closed by ctrl+o, at $size', (t) async {
      await t.pumpWidget(const FoldExample(), size: size);
      expect(t.screen.lines.take(3), [
        '▾ Run checks',
        r'$ dart analyze',
        'Analyzing CTUI-2...',
      ]);
      expect(
        t.screen.lines[9],
        startsWith('Name    Transport  Command or URL'),
      );
      await t.press('ctrl+o');
      expect(t.screen.lines.take(3), ['▸ Run checks', '', startsWith('Name')]);
      expect(t.screen.lines.last, startsWith('ctrl+o Toggle tool details'));
    });
  }

  testWidgets('a short window folds the output under a count', (t) async {
    await t.pumpWidget(const FoldExample(), size: const Size(80, 10));
    // Ten rows less the gap, the two table rows and the keys: six, so
    // four lines and the count.
    expect(t.screen.lines.take(6), [
      '▾ Run checks',
      r'$ dart analyze',
      'Analyzing CTUI-2...',
      'No issues found!',
      r'$ dart format --output=none --set-exit-if-changed .',
      '  … 3 more lines',
    ]);
  });
  group('tester: Fold/Table fixture recovery', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('closed state survives every size boundary at $size', (
        t,
      ) async {
        await t.pumpWidget(const FoldExample(), size: size);
        await t.press('ctrl+o');
        for (final next in const [Size.zero, Size(1, 1), Size(80, 10)]) {
          await t.resize(next);
        }
        await t.resize(size);
        expect(t.screen.lines.first, '▸ Run checks');
        await t.press('ctrl+o');
        expect(t.screen.lines.first, '▾ Run checks');
        expect(t.screen, shows('memory  stdio      npx -y memory'));
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      });
    }
  });
}
