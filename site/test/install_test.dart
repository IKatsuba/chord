import 'package:chord_site/pages/install.dart';
import 'package:chord_site/palette.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

final theme = siteTheme();

Future<void> install(WidgetTester t, Size size) => t.pumpWidget(
  Theme(
    data: theme,
    child: Site(host: FakeHost('/install')),
  ),
  size: size,
);

(int, int) find(WidgetTester t, String text) {
  // Below the nav's four rows, whose caps would match first.
  for (final (y, line) in t.screen.lines.indexed.skip(4)) {
    final x = line.indexOf(text);
    if (x >= 0) return (x, y);
  }
  throw StateError('"$text" is not on the screen:\n${t.screen.text}');
}

/// The row [text] is on, or -1.
int rowOf(WidgetTester t, String text) =>
    t.screen.lines.indexWhere((l) => l.contains(text));

void main() {
  for (final (size, columns) in const [
    (Size(171, 50), 3),
    (Size(120, 40), 2),
    (Size(80, 24), 1),
    (Size(54, 56), 1),
  ]) {
    group('at $size', () {
      testWidgets('the header, then $columns card(s) to a row, every command '
          'whole', (t) async {
        await install(t, size);
        expect(t.screen, shows('Home › Install'));
        final (ix, iy) = find(t, 'INSTALL');
        expect(t.screen.styleAt(ix, iy), theme.accent.merge(Style.bold));
        expect(t.screen, shows('Three ways in.'));
        final row = rowOf(t, 'Homebrew');
        expect(t.screen.lines[row].contains('npm'), columns >= 2);
        expect(t.screen.lines[row].contains('From source'), columns == 3);
        // Whole wherever the page is scrolled to show them.
        final seen = <String>{};
        for (var n = 0; n < 12; n++) {
          for (final way in installWays) {
            if (t.screen.text.contains('\$ ${way.command}')) {
              seen.add(way.command);
            }
          }
          await t.press('pagedown');
        }
        expect(seen, {for (final way in installWays) way.command});
      });

      testWidgets('the first card is selected and says copy c', (t) async {
        await install(t, size);
        final (x, y) = find(t, 'Homebrew');
        expect(t.screen.styleAt(x, y), theme.accent.merge(Style.bold));
        expect(t.screen.styleAt(x - 3, y - 2), theme.accent, reason: 'frame');
        expect(t.screen.lines[y], contains('copy c'));
        expect(t.screen.lines.where((l) => l.contains('copy c')), hasLength(1));
      });
    });
  }

  testWidgets('←→ move along the cards, ↓ reaches Then, ↑ comes back', (
    t,
  ) async {
    await install(t, const Size(171, 50));
    String selected() => t.screen.lines.firstWhere((l) => l.contains('copy c'));
    await t.press('left');
    expect(selected(), contains('Homebrew'));
    await t.press('right');
    expect(selected(), contains('npm'));
    await t.press('right');
    await t.press('right');
    expect(selected(), contains('From source'));
    await t.press('down');
    expect(selected(), contains('shell'));
    await t.press('down');
    expect(selected(), contains('shell'));
    await t.press('up');
    expect(selected(), contains('From source'));
  });

  testWidgets('c copies the selected command and says copied for two '
      'seconds', (t) async {
    await install(t, const Size(171, 50));
    await t.press('right');
    await t.press('c');
    expect(t.terminal.copied, ['npm i -g @chorded/chord']);
    final (x, y) = find(t, 'copied');
    expect(t.screen.styleAt(x, y), theme.accent);
    expect(t.screen, isNot(shows('copy c')));
    await t.press('down');
    await t.press('c');
    expect(t.terminal.copied.last, thenCommand);
    await t.pump(const Duration(milliseconds: 2100));
    expect(t.screen, shows('copy c'));
    expect(t.screen, isNot(shows('copied')));
  });

  for (final size in const [Size(80, 24), Size(54, 30), Size(43, 20)]) {
    testWidgets('the selection and its copy hint stay in sight at $size', (
      t,
    ) async {
      await install(t, size);
      for (final (key, name, command) in [
        ('right', 'npm', installWays[1].command),
        ('right', 'From source', installWays[2].command),
        ('down', 'shell', thenCommand),
        ('up', 'From source', installWays[2].command),
        ('left', 'npm', installWays[1].command),
        ('left', 'Homebrew', installWays[0].command),
      ]) {
        await t.press(key);
        await t.pump();
        final hint = t.screen.lines.where((l) => l.contains('copy c'));
        expect(hint, hasLength(1), reason: 'after $key');
        expect(hint.single, contains(name), reason: 'after $key');
        await t.press('c');
        expect(t.terminal.copied.last, command);
        expect(t.screen, shows('copied'));
        // The next move takes copied back to copy c.
      }
    });
  }

  testWidgets('a resize keeps the selection in sight', (t) async {
    await install(t, const Size(171, 50));
    await t.press('down');
    expect(t.screen, shows('copy c'));
    await t.resize(const Size(54, 30));
    await t.pump();
    expect(
      t.screen.lines.where((l) => l.contains('copy c')).single,
      contains('shell'),
    );
    await t.press('up');
    await t.pump();
    expect(
      t.screen.lines.where((l) => l.contains('copy c')).single,
      contains('Homebrew'),
    );
    await t.resize(const Size(171, 50));
    await t.pump();
    expect(t.screen, shows('copy c'));
  });

  testWidgets('the Then block is a shell on the raised colour', (t) async {
    await install(t, const Size(171, 50));
    final (x, y) = find(t, 'THEN');
    expect(t.screen.styleAt(x, y), theme.accent.merge(Style.bold));
    final (sx, sy) = find(t, 'shell');
    expect(t.screen.styleAt(sx, sy).bg, SiteColors.raised);
    expect(t.screen, shows('// open a session in your project'));
    expect(t.screen, shows('chord claude -C ~/projects/app'));
  });

  testWidgets('the help row says the keys', (t) async {
    await install(t, const Size(171, 50));
    expect(t.screen.lines.last, contains('c copy'));
    expect(t.screen.lines.last, contains('move'));
  });
}
