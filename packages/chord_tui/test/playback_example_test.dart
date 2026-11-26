import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/playback.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the recording plays, steps and lists its keys at $size', (
      t,
    ) async {
      await t.pumpWidget(const PlaybackExample(), size: size);
      expect(t.screen.lines.first, '~/project \$');
      // No step is named before the first labelled frame.
      expect(t.screen.lines[size.height - 2], '▶ 0:00 / 0:06');
      await t.press('space');
      await t.press('right');
      expect(t.screen.lines.first, '~/project \$ dart test');
      expect(
        t.screen,
        shows('❚❚ 0:00 / 0:06 · step 1 of 3 · typed the command'),
      );
      await t.press('right');
      await t.press('right');
      expect(t.screen, shows('All tests passed!'));
      expect(t.screen, shows('step 3 of 3 · all tests passed'));
      expect(t.screen, shows('space Play or pause'));
    });
  }

  testWidgets('a room narrower than the recording clips and pans', (t) async {
    await t.pumpWidget(const PlaybackExample(), size: const Size(40, 24));
    expect(t.screen.lines.first, endsWith('›'));
    await t.press('shift+right');
    expect(t.screen.lines.first, startsWith('/project'));
  });
}
