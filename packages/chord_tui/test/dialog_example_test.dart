import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/dialog.dart';

void main() {
  testerEdges();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the dialog sits on the prompt and answers, at $size', (
      t,
    ) async {
      await t.pumpWidget(const DialogExample(), size: size);
      // Opened after the first layout, it settles in the next frame.
      await t.pump();
      final anchor = size.height - 3;
      expect(t.screen.lines[anchor - 1], startsWith('╰'));
      expect(t.screen.lines[anchor - 2], contains('Esc to close'));
      expect(t.screen.lines[anchor + 1], '> /permission');
      expect(t.screen, shows('│ ❯ 1. Allow once'));
      expect(t.focusManager.primaryFocus?.debugLabel, 'dialog');
      await t.press('2');
      expect(t.screen, shows('Answer: rejected'));
      expect(t.screen, isNot(shows('Allow command?')));
      expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
      await t.press('ctrl+o');
      await t.press('esc');
      expect(t.screen, shows('Answer: closed'));
    });
  }

  testWidgets('a short window folds the body, then drops it', (t) async {
    await t.pumpWidget(const DialogExample(), size: const Size(80, 14));
    await t.pump();
    expect(t.screen, shows('│   … 2 more lines'));
    await t.resize(const Size(80, 10));
    expect(t.screen, isNot(shows('Run the requested')));
    expect(t.screen, shows('│ ❯ 1. Allow once'));
  });
}

void testerEdges() {
  group('tester: Dialog example hidden-surface recovery', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('hidden keys never answer after resize recovery at $size', (
        t,
      ) async {
        await t.pumpWidget(const DialogExample(), size: size);
        await t.pump();
        for (final next in const [
          Size.zero,
          Size(1, 1),
          Size(80, 4),
          Size(80, 5),
        ]) {
          await t.resize(next);
          await t.press('1');
          await t.press('enter');
          await t.press('esc');
        }
        await t.resize(size);
        expect(t.screen, shows('Answer: none yet'));
        expect(t.focusManager.primaryFocus?.debugLabel, 'dialog');
        await t.press('2');
        expect(t.screen, shows('Answer: rejected'));
        await t.press('ctrl+o');
        expect(t.screen, shows('Allow command?'));
        await t.press('esc');
        expect(t.screen, shows('Answer: closed'));
        expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      });
    }
  });
}
