import 'package:chord_site/palette.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

final theme = siteTheme();

(int, int) find(WidgetTester t, String text) {
  for (final (y, line) in t.screen.lines.indexed.skip(4)) {
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
  for (final (size, rows, margin) in const [
    (Size(192, 56), 14, 4),
    (Size(120, 40), 14, 4),
    // 80x40: at 80x24 the button falls below the fold.
    (Size(80, 40), 14, 4),
    (Size(52, 52), 7, 2),
    (Size(43, 37), 7, 2),
  ]) {
    testWidgets('the giant 404 in green, PAGE NOT FOUND., the path and '
        'HOME on Enter, at $size', (t) async {
      await missing(t, size);
      final lines = t.screen.lines;
      final top = lines.indexWhere((l) => l.contains('█'));
      final x = lines[top].indexOf('█');
      expect(t.screen.styleAt(x, top), theme.accent);
      // huge where it fits, large on the phone.
      final drawn = lines.skip(top).takeWhile((l) => l.contains('█'));
      expect(drawn.length, rows);
      final (px, py) = find(t, 'PAGE NOT FOUND.');
      expect(px, margin);
      expect(py, top + rows + 1);
      expect(t.screen.styleAt(px, py), theme.text.merge(Style.bold));
      expect(lines[py + 1], startsWith('${' ' * margin}/chord_tui/markdwon'));
      final (hx, hy) = find(t, 'HOME  enter');
      expect(hy, py + 4);
      expect(
        t.screen.styleAt(hx, hy),
        theme.accent.merge(const Style(bold: true, inverse: true)),
      );
    });
  }

  testWidgets('Enter, Esc and a click on HOME go home', (t) async {
    var host = await missing(t, const Size(120, 40));
    await t.press('enter');
    expect(host.pushed, ['/']);
    host = await missing(t, const Size(120, 40));
    await t.press('esc');
    expect(host.pushed, ['/']);
    host = await missing(t, const Size(120, 40));
    final (x, y) = find(t, 'HOME  enter');
    for (final kind in [MouseEventKind.press, MouseEventKind.release]) {
      await t.mouse(
        MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary),
      );
    }
    expect(host.pushed, ['/']);
  });

  testWidgets('the HOME button is never a focus place', (t) async {
    await missing(t, const Size(120, 40));
    final (x, y) = find(t, 'HOME');
    for (var n = 0; n < 4; n++) {
      await t.press('tab');
      expect(t.screen.styleAt(x, y).isUnderline, isFalse, reason: 'tab $n');
    }
  });
}
