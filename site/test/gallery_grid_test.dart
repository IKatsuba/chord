import 'package:chord_site/giant.dart';
import 'package:chord_site/page.dart';
import 'package:chord_site/pages/gallery_grid.dart' show cellGap;
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

/// Where [text] starts on the screen, below the nav's four rows.
(int, int) find(WidgetTester t, String text) {
  for (final (y, line) in t.screen.lines.indexed.skip(4)) {
    final x = line.indexOf(text);
    if (x >= 0) return (x, y);
  }
  throw StateError('"$text" is not on the screen:\n${t.screen.text}');
}

/// The line holding `⏎ RUN`, the selected cell's name row.
String selected(WidgetTester t) =>
    t.screen.lines.firstWhere((l) => l.contains('⏎ RUN'));

MouseEvent at(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

void main() {
  final selectedName = theme.accent.merge(
    const Style(bold: true, inverse: true),
  );

  // 80x60 rather than 80x24: there the split giant word puts the first row
  // of cells below the fold.
  for (final size in const [Size(192, 56), Size(120, 40), Size(80, 60)]) {
    group('at $size', () {
      testWidgets('the kicker, the giant word and the lede, then numbered '
          'cells, the first selected', (t) async {
        await gallery(t, size);
        final (kx, ky) = find(t, '03 / THE GALLERY');
        expect(kx, 4, reason: 'a 4-column margin');
        expect(t.screen.styleAt(kx, ky), theme.accent.merge(Style.bold));
        expect(
          t.screen.lines[ky + 1].replaceAll('┃', '').trim(),
          '',
          reason: 'a blank row under the kicker',
        );
        expect(t.screen.lines[ky + 2], contains('██'), reason: 'giant');
        expect(t.screen, shows("Nine of chord_tui's examples"));
        final (dx, dy) = find(t, 'DEMO');
        expect(t.screen.styleAt(dx, dy), selectedName);
        expect(t.screen.lines[dy], contains('⏎ RUN'));
        expect(t.screen.styleAt(dx, dy + 1), theme.accent, reason: 'rule');
        final (mx, my) = find(t, 'MARKDOWN');
        expect(my, dy, reason: 'the same row');
        expect(t.screen.styleAt(mx, my), theme.text.merge(Style.bold));
        expect(t.screen.styleAt(mx, my + 1), theme.border);
        // The orange numeral sits five rows over the name.
        expect(t.screen.lines[dy - 5].substring(dx, dx + 10), contains('▄'));
        expect(t.screen.styleAt(dx + 2, dy - 5), theme.accent);
      });

      testWidgets('arrows move the selection; Enter runs it', (t) async {
        final host = await gallery(t, size);
        await t.press('right');
        expect(selected(t), contains('MARKDOWN'));
        await t.press('down');
        final below = size.width >= 120 ? 'TEXT AREA' : 'FORM';
        expect(selected(t), contains(below));
        await t.press('enter');
        expect(host.pushed, [
          size.width >= 120 ? '/chord_tui/text_area' : '/chord_tui/form',
        ]);
      });

      testWidgets('a digit runs its cell', (t) async {
        final host = await gallery(t, size);
        await t.press('6');
        expect(host.pushed, ['/chord_tui/diff']);
      });

      testWidgets('a tap runs the cell tapped', (t) async {
        final host = await gallery(t, size);
        final (x, y) = find(t, 'MARKDOWN');
        await t.mouse(at(MouseEventKind.press, x, y + 3));
        expect(host.pushed, ['/chord_tui/markdown']);
      });

      testWidgets('a row of cells ends at the right margin, cells $cellGap '
          'apart', (t) async {
        await gallery(t, size);
        final (dx, dy) = find(t, 'DEMO');
        final rule = t.screen.lines[dy + 1];
        final end = size.width - 1 - 4; // the scrollbar, then the margin
        expect(rule.replaceAll('┃', '').trimRight().length, end);
        if (size.width >= 60) {
          final first = rule.indexOf(' ', dx);
          expect(rule.substring(first, first + cellGap), ' ' * cellGap);
        }
      });
    });
  }

  test('no preview line is wider than the 26 cells a cell has at 80 '
      'columns', () {
    for (final entry in siteGallery.entries) {
      expect(entry.preview, hasLength(4), reason: entry.name);
      for (final row in entry.preview) {
        expect(cellWidth(row), lessThanOrEqualTo(26), reason: row);
      }
    }
  });

  testWidgets('a cell is its numeral, a blank, the name, the rule, the '
      'preview, a blank and two rows of what it shows', (t) async {
    await gallery(t, const Size(192, 56));
    final (x, y) = find(t, 'DEMO');
    expect(
      t.screen.lines[y - 1].replaceAll('┃', '').trim(),
      '',
      reason: 'blank under the numeral',
    );
    expect(t.screen.lines[y + 2].substring(x), startsWith(' ┌ left ─┐'));
    expect(t.screen.lines[y + 6].replaceAll('┃', '').trim(), '');
    expect(
      t.screen.lines[y + 7],
      contains('The framework tour: layout, focus and keys.'),
    );
  });

  testWidgets('a preview fills the cell on raised; █ is a cursor cell; diff '
      'lines take the diff colours', (t) async {
    await gallery(t, const Size(192, 56));
    final (dx, dy) = find(t, 'DEMO');
    final rule = t.screen.lines[dy + 1];
    final width = rule.indexOf(' ', dx) - dx;
    for (var cx = dx; cx < dx + width; cx++) {
      expect(t.screen.styleAt(cx, dy + 2).bg, SiteColors.raised, reason: '$cx');
    }
    final (px, py) = find(t, '› clau');
    expect(t.screen.charAt(px + 6, py), ' ');
    expect(
      t.screen.styleAt(px + 6, py),
      theme.cursor.copyWith(bg: SiteColors.raised),
    );
    final (rx, ry) = find(t, '12  - store');
    expect(t.screen.styleAt(rx + 4, ry).fg, theme.diff.removed.fg);
    final (ax, ay) = find(t, '12  + store');
    expect(t.screen.styleAt(ax + 4, ay).fg, theme.diff.added.fg);
  });

  for (final size in const [Size(54, 56), Size(43, 37)]) {
    testWidgets('a phone has one cell to a row, a 2-column margin and the '
        'word split, at $size', (t) async {
      final host = await gallery(t, size);
      final (kx, _) = find(t, '03 / THE GALLERY');
      expect(kx, 2);
      expect(giantLayout('GALLERY', size.width - 1 - 4).lines, [
        'GALL',
        'ERY.',
      ]);
      expect(selected(t), isNot(contains('MARKDOWN')));
      await t.press('down');
      await t.pump();
      expect(selected(t), contains('MARKDOWN'));
      await t.press('enter');
      expect(host.pushed, ['/chord_tui/markdown']);
    });
  }

  for (final (from, to) in const [
    (Size(192, 56), Size(54, 56)),
    (Size(192, 56), Size(80, 24)),
    (Size(54, 56), Size(192, 56)),
    (Size(80, 24), Size(192, 56)),
  ]) {
    testWidgets('the selected cell stays in sight from $from to $to, and '
        'Enter runs it', (t) async {
      final host = await gallery(t, from);
      for (var n = 0; n < 8; n++) {
        await t.press('right');
        await t.press('down');
      }
      await t.pump();
      expect(selected(t), contains('MOUSE'));
      await t.resize(to);
      await t.pump();
      expect(selected(t), contains('MOUSE'));
      await t.press('enter');
      expect(host.pushed, ['/chord_tui/mouse']);
    });
  }

  testWidgets('moving down at 80x24 keeps the selected row whole in sight', (
    t,
  ) async {
    await gallery(t, const Size(80, 24));
    await t.press('down');
    await t.press('down');
    await t.pump();
    // Two to a row: Demo, Form, Text area.
    expect(selected(t), contains('TEXT AREA'));
    await t.press('up');
    await t.press('up');
    await t.pump();
    expect(selected(t), contains('DEMO'));
  });

  testWidgets('the help row says the grid\'s keys', (t) async {
    await gallery(t, const Size(192, 56));
    final help = t.screen.lines.last;
    expect(help, contains('move'));
    expect(help, contains('enter run'));
    expect(help, contains('1–9 open'));
    expect(help, isNot(contains('scroll')));
  });

  test('the poster measure runs the page to its margins', () {
    expect(pageContentWidth(192, measure: posterMeasure), 192 - 1 - 8);
    expect(pageContentWidth(52, measure: posterMeasure), 52 - 1 - 4);
  });
}
