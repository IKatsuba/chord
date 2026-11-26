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

  for (final size in const [Size(120, 40), Size(54, 56)]) {
    testWidgets('the giant word is cream with an orange stop, and the '
        'kicker orange caps, at $size', (t) async {
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
