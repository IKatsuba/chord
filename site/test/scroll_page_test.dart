import 'package:chord_site/palette.dart';
import 'package:chord_site/scroll_page.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A line without the scrollbar's column.
String _bare(String line) => line.replaceAll('┃', '').trimRight();

Widget _page(int count, {List<Binding> bindings = const []}) => Theme(
  data: siteTheme(),
  child: ScrollPage(
    bindings: bindings,
    sections: [
      FullBleed(Text('bleed')),
      for (var i = 0; i < count; i++) Text('section $i'),
    ],
  ),
);

void main() {
  for (final (size, margin) in const [
    (Size(120, 40), 4),
    (Size(80, 24), 4),
    (Size(52, 52), 2),
  ]) {
    testWidgets('sections sit in the margins, a full-bleed one at the edge, '
        'beside a muted scrollbar, at $size', (t) async {
      await t.pumpWidget(_page(200), size: size);
      expect(_bare(t.screen.lines[0]), 'bleed');
      expect(_bare(t.screen.lines[1]), '${' ' * margin}section 0');
      expect(t.screen.charAt(size.width - 1, 0), '┃');
      expect(t.screen.styleAt(size.width - 1, 0), Style(fg: SiteColors.muted));
    });
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('↓, PgDn, End and Home scroll it, at $size', (t) async {
      await t.pumpWidget(_page(200), size: size);
      await t.press('down');
      expect(_bare(t.screen.lines.first).trim(), 'section 0');
      // A page is the view less one row kept from the last.
      await t.press('pagedown');
      expect(_bare(t.screen.lines.first).trim(), 'section ${size.height - 2}');
      await t.press('end');
      expect(_bare(t.screen.lines.last).trim(), 'section 199');
      await t.press('home');
      expect(_bare(t.screen.lines.first), 'bleed');
    });
  }

  testWidgets('the page\'s own keys win over its scroll keys', (t) async {
    var downs = 0;
    await t.pumpWidget(
      _page(200, bindings: [Binding('down', 'next', () => downs++)]),
      size: const Size(80, 24),
    );
    await t.press('down');
    expect(downs, 1);
    expect(_bare(t.screen.lines.first), 'bleed');
  });
}
