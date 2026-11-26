import 'package:chord_site/chord_art.dart';
import 'package:chord_site/palette.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

final theme = siteTheme();

(int, int) find(WidgetTester t, String text) {
  for (final (y, line) in t.screen.lines.indexed) {
    final x = line.indexOf(text);
    if (x >= 0) return (x, y);
  }
  throw StateError('"$text" is not on the screen:\n${t.screen.text}');
}

Future<FakeHost> missing(WidgetTester t, Size size) async {
  final host = FakeHost('/chord_tui/markdwon');
  await t.pumpWidget(
    Theme(
      data: theme,
      child: Site(host: host),
    ),
    size: size,
  );
  return host;
}

void main() {
  test('the art\'s form follows the content width, never clipped', () {
    expect(artFormFor(136), ArtForm.full);
    expect(artFormFor(57), ArtForm.full);
    expect(artFormFor(56), ArtForm.wordmark);
    expect(artFormFor(45), ArtForm.wordmark);
    expect(artFormFor(44), ArtForm.compact);
  });

  for (final (size, mark, wordmark) in const [
    (Size(171, 50), true, '██████╗ ██╗  ██╗'),
    (Size(80, 24), true, '██████╗ ██╗  ██╗'),
    (Size(54, 56), false, '██████╗ ██╗  ██╗'),
    (Size(43, 37), true, '█▀▀ █ █ █▀█'),
  ]) {
    testWidgets('chord\'s art, then 404, the path and Home, centred, at '
        '$size', (t) async {
      await missing(t, size);
      final (wx, wy) = find(t, wordmark);
      expect(t.screen.text.contains('▀▀▄'), mark, reason: 'the mark');
      expect(t.screen.styleAt(wx, wy).fg, isNotNull, reason: 'chord colours');
      final (x, y) = find(t, '404 · page not found');
      expect(t.screen.styleAt(x, y), theme.text.merge(Style.bold));
      final (px, py) = find(t, '/chord_tui/markdwon');
      expect(py, y + 1);
      expect(t.screen.styleAt(px, py), theme.text);
      // Centred in the window, less the scrollbar.
      final line = t.screen.lines[y].replaceAll('┃', '').trimRight();
      final text = line.trimLeft();
      final left = line.length - text.length;
      expect((left - (size.width - 1 - left - text.length)).abs(), lessThan(3));
      expect(t.screen, shows('Home'));
      expect(t.screen, shows('press enter'));
    });
  }

  testWidgets('Enter, Esc and a click on Home go home', (t) async {
    var host = await missing(t, const Size(120, 40));
    await t.press('enter');
    expect(host.pushed, ['/']);
    host = await missing(t, const Size(120, 40));
    await t.press('esc');
    expect(host.pushed, ['/']);
    host = await missing(t, const Size(120, 40));
    final (x, y) = find(t, 'Home');
    await t.mouse(
      MouseEvent(
        MouseEventKind.press,
        position: Offset(x, y),
        button: MouseButton.primary,
      ),
    );
    await t.mouse(
      MouseEvent(
        MouseEventKind.release,
        position: Offset(x, y),
        button: MouseButton.primary,
      ),
    );
    expect(host.pushed, ['/']);
  });

  testWidgets('the Home button is never a focus place', (t) async {
    await missing(t, const Size(120, 40));
    final (x, y) = find(t, 'Home');
    for (var n = 0; n < 4; n++) {
      await t.press('tab');
      expect(t.screen.styleAt(x, y).isUnderline, isFalse, reason: 'tab $n');
    }
  });
}
