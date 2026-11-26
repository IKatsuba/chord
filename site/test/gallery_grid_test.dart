import 'package:chord_site/palette.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../web/gallery.dart';
import 'fake_host.dart';

final theme = siteTheme();

Future<FakeHost> gallery(WidgetTester t, Size size) async {
  final host = FakeHost('/chord_tui/gallery');
  await t.pumpWidget(
    Theme(
      data: theme,
      child: Site(host: host, gallery: siteGallery),
    ),
    size: size,
  );
  return host;
}

/// Where [text] starts on the screen.
(int, int) find(WidgetTester t, String text) {
  for (final (y, line) in t.screen.lines.indexed) {
    final x = line.indexOf(text);
    if (x >= 0) return (x, y);
  }
  throw StateError('"$text" is not on the screen:\n${t.screen.text}');
}

MouseEvent at(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

void main() {
  for (final size in const [Size(171, 50), Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('the header, then three cards to a row, the first '
          'selected', (t) async {
        await gallery(t, size);
        expect(t.screen, shows('Home › Gallery'));
        final (gx, gy) = find(t, 'GALLERY');
        expect(t.screen.styleAt(gx, gy), theme.accent.merge(Style.bold));
        expect(t.screen, shows('The framework, running in your browser.'));
        final (dx, dy) = find(t, '1  Demo');
        final (mx, my) = find(t, '2  Markdown');
        expect(my, dy, reason: 'one row');
        expect(t.screen.lines[dy], contains('3  Picker'));
        expect(t.screen.lines[dy], contains('⏎ run'));
        // The selected card's frame and name are mint, the next one's not.
        expect(t.screen.styleAt(dx - 3, dy - 2), theme.accent);
        expect(t.screen.styleAt(dx + 3, dy), theme.accent.merge(Style.bold));
        expect(t.screen.styleAt(mx - 3, my - 2), theme.border);
        expect(t.screen.styleAt(mx, my), theme.dim, reason: 'the number');
        expect(t.screen.styleAt(mx + 3, my), theme.text.merge(Style.bold));
      });

      testWidgets('arrows move the selection; Enter runs it', (t) async {
        final host = await gallery(t, size);
        await t.press('right');
        expect(t.screen.lines[find(t, '2  Markdown').$2], contains('⏎ run'));
        await t.press('down');
        expect(find(t, '⏎ run').$2, find(t, '5  Text area').$2);
        await t.press('enter');
        expect(host.pushed, ['/chord_tui/text_area']);
      });

      testWidgets('a digit runs its card', (t) async {
        final host = await gallery(t, size);
        await t.press('6');
        expect(host.pushed, ['/chord_tui/diff']);
      });

      testWidgets('a tap runs the card tapped', (t) async {
        final host = await gallery(t, size);
        final (x, y) = find(t, '3  Picker');
        await t.mouse(at(MouseEventKind.press, x, y + 3));
        expect(host.pushed, ['/chord_tui/picker']);
      });
    });
  }

  testWidgets('a card is 13 rows: frame, padding, name, preview, '
      'description', (t) async {
    await gallery(t, const Size(171, 50));
    final (x, y) = find(t, '1  Demo');
    final top = y - 2, bottom = top + 12;
    expect(t.screen.charAt(x - 3, top), '╭');
    expect(t.screen.charAt(x - 3, bottom), '╰');
    expect(t.screen.lines[y + 2].substring(x), startsWith(' ┌ left ─┐'));
    expect(
      t.screen.lines[y + 7],
      contains('The framework tour: layout, focus and keys.'),
    );
  });

  testWidgets('a preview sits on the raised colour; █ is a cursor cell; '
      'diff lines take the diff colours', (t) async {
    await gallery(t, const Size(171, 50));
    final (px, py) = find(t, '› clau');
    expect(t.screen.styleAt(px, py).bg, SiteColors.raised);
    expect(t.screen.charAt(px + 6, py), ' ');
    expect(
      t.screen.styleAt(px + 6, py),
      theme.cursor.copyWith(bg: SiteColors.raised),
    );
    final (rx, ry) = find(t, '12  - final store');
    expect(t.screen.styleAt(rx + 4, ry).fg, theme.diff.removed.fg);
    final (ax, ay) = find(t, '12  + final store');
    expect(t.screen.styleAt(ax + 4, ay).fg, theme.diff.added.fg);
  });

  testWidgets('moving down at 80x24 keeps the selected row in sight', (
    t,
  ) async {
    await gallery(t, const Size(80, 24));
    await t.press('down');
    await t.press('down');
    expect(t.screen, shows('⏎ run'));
    expect(t.screen.lines[find(t, '⏎ run').$2], contains('7  Dialog'));
    await t.press('up');
    await t.press('up');
    expect(t.screen.lines[find(t, '⏎ run').$2], contains('1  Demo'));
  });

  for (final size in const [Size(54, 56), Size(43, 37)]) {
    testWidgets('a phone has one card to a row at $size', (t) async {
      final host = await gallery(t, size);
      final (_, y) = find(t, '1  Demo');
      expect(t.screen.lines[y], isNot(contains('Markdown')));
      await t.press('down');
      expect(t.screen.lines[find(t, '⏎ run').$2], contains('2  Markdown'));
      await t.press('enter');
      expect(host.pushed, ['/chord_tui/markdown']);
    });
  }

  testWidgets('the help row says the grid\'s keys and ↑↓ is theirs', (t) async {
    await gallery(t, const Size(171, 50));
    final help = t.screen.lines.last;
    expect(help, contains('move'));
    expect(help, contains('enter run'));
    expect(help, contains('1–9 open'));
    expect(help, isNot(contains('Scroll up a page')));
    expect(help, isNot(contains('scroll')));
  });
}
