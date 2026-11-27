import 'package:chord_site/giant.dart';
import 'package:chord_site/page.dart';
import 'package:chord_site/palette.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  test('a word is huge where it fits, else large, else split in halves', () {
    expect(giantLayout('APP', 183).size, DisplaySize.huge);
    expect(giantLayout('APP', 183).lines, ['APP.']);
    // GALLERY. at huge needs 188 columns; a 192-column page gives 183.
    expect(giantLayout('GALLERY', 183).size, DisplaySize.large);
    expect(giantLayout('GALLERY', 183).lines, ['GALLERY.']);
    expect(giantLayout('GALLERY', 47).lines, ['GALL', 'ERY.']);
    expect(giantLayout('CHORD', 47).lines, ['CHO', 'RD.']);
    expect(giantLayout('INSTALL', 47).lines, ['INST', 'ALL.']);
  });

  test('where the halves need more than the room at large, the word steps '
      'down to half; the margins stay', () {
    // GALL at large is 4 × 12 − 2 = 46 columns.
    expect(giantLayout('GALLERY', 46).size, DisplaySize.large);
    expect(giantLayout('GALLERY', 46).lines, ['GALL', 'ERY.']);
    // A 360 px phone, 48 columns, leaves 43 inside its margins.
    final narrow = giantLayout('GALLERY', 43);
    expect(narrow.size, DisplaySize.half);
    // Whole at half is 8 × 6 − 1 = 47, more than 43: split again.
    expect(narrow.lines, ['GALL', 'ERY.']);
    expect(giantLayout('INSTALL', 43).size, DisplaySize.half);
    expect(
      giantLayout('CHORD', 43).size,
      DisplaySize.large,
      reason: 'CHO is 34',
    );
  });

  for (final width in const [43, 46]) {
    testWidgets('GALLERY. never draws wider than $width columns', (t) async {
      await t.pumpWidget(
        Theme(
          data: siteTheme(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: const GiantWord('GALLERY')),
          ),
        ),
        size: const Size(80, 40),
      );
      final drawn = t.screen.lines.where((l) => l.contains(RegExp('[█▀▄]')));
      expect(drawn, isNotEmpty);
      for (final line in drawn) {
        expect(line.trimRight().length, lessThanOrEqualTo(width), reason: line);
      }
      // Every glyph whole: the stop's cells are there.
      expect(t.screen.text.contains(RegExp('[█▀▄]')), isTrue);
    });
  }

  for (final size in const [Size(120, 40), Size(54, 56)]) {
    testWidgets('the giant word is cream with a green stop, and the '
        'kicker green caps, at $size', (t) async {
      final theme = siteTheme();
      await t.pumpWidget(
        Theme(
          data: theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const Kicker(4, 'INSTALL'), const GiantWord('APP')],
          ),
        ),
        size: size,
      );
      expect(t.screen.lines.first, '04 / INSTALL');
      expect(t.screen.styleAt(0, 0), theme.accent.merge(Style.bold));
      final stop = t.screen.lines.indexWhere(
        (l) => l.trimRight().endsWith('██'),
      );
      expect(stop, greaterThan(0));
      final line = t.screen.lines.last.isEmpty
          ? t.screen.lines.lastWhere((l) => l.contains('█'))
          : t.screen.lines.last;
      final x = line.trimRight().length - 1;
      final y = t.screen.lines.indexOf(line);
      expect(t.screen.styleAt(x, y), theme.accent, reason: 'the stop');
      expect(t.screen.styleAt(line.indexOf('█'), y), theme.text);
    });
  }

  testWidgets('a paragraph wraps at 90 columns on a wide page', (t) async {
    await t.pumpWidget(Paragraph('word ' * 60), size: const Size(192, 56));
    expect(
      t.screen.lines.where((l) => l.isNotEmpty).every((l) => l.length <= 90),
      isTrue,
    );
  });
}
