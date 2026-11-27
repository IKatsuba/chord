import 'dart:io';

import 'package:chord/ui/theme/theme.dart' show palettes;
import 'package:chord_site/palette.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

RgbColor hexIn(String css, String pattern) {
  final m = RegExp(pattern).firstMatch(css);
  if (m == null) throw StateError('$pattern is not in index.html');
  return RgbColor.hex(m[1]!);
}

void main() {
  test('the accent is chord\'s own dark accent', () {
    expect(SiteColors.accent, RgbColor.hex(palettes['dark']!.accent!));
  });

  test('the theme paints with direction C\'s roles', () {
    final theme = siteTheme();
    final accent = Style(fg: SiteColors.accent);
    expect(theme.brightness, Brightness.dark);
    expect(theme.text, Style.plain, reason: 'the page sets cream');
    expect(theme.dim, Style(fg: SiteColors.muted));
    expect(theme.accent, accent);
    expect(theme.focus, accent);
    expect(theme.link, accent);
    expect(theme.border, Style(fg: SiteColors.rule));
    expect(theme.warning, Style(fg: SiteColors.sand));
    expect(theme.success, Style(fg: SiteColors.green));
    expect(theme.error, Style(fg: SiteColors.red));
    expect(theme.diff.added, Style(fg: SiteColors.green));
    expect(theme.diff.removed, Style(fg: SiteColors.red));
    final code = theme.code!.terminal;
    expect(code.keyword, accent);
    expect(code.string, Style(fg: SiteColors.green));
    expect(code.type, Style(fg: SiteColors.sand));
    expect(code.comment, Style(fg: SiteColors.muted));
    for (final rest in [code.number, code.title, code.name, code.meta]) {
      expect(rest, Style.plain, reason: 'cream');
    }
    final palette = theme.extension<SitePalette>()!;
    expect(palette.bar, Style(bg: SiteColors.bar));
    expect(palette.raised, Style(bg: SiteColors.raised));
  });

  group('index.html', () {
    final page = File('web/index.html').readAsStringSync();
    final terminal = RegExp(r'\n  #terminal \{([^}]*)\}').firstMatch(page)![1]!;

    test('draws the page and the grid in ink and cream', () {
      expect(
        hexIn(page, r'html, body \{[^}]*background: (#[0-9a-f]{6})'),
        SiteColors.ink,
      );
      expect(hexIn(page, r'--term-bg: (#[0-9a-f]{6})'), SiteColors.ink);
      expect(hexIn(page, r'--term-fg: (#[0-9a-f]{6})'), SiteColors.cream);
    });

    test('lets the grid fill the window: no padding, corners or shadow', () {
      expect(terminal, contains('padding: 0;'));
      expect(terminal, contains('border-radius: 0;'));
      expect(terminal, contains('box-shadow: none;'));
    });

    test('one size at every width: 7 px cells on 16 px rows, no '
        'breakpoint', () {
      expect(terminal, contains('--term-font-size: 12.5px;'));
      expect(terminal, contains('--term-row-height: 16px;'));
      expect(terminal, contains('--term-line-height: 1.28;'));
      expect(page, isNot(contains('@media')));
      // JetBrains Mono advances 0.6 em; the spacing takes half a pixel off.
      final spacing = double.parse(
        RegExp(r'letter-spacing: (-?[\d.]+)px;').firstMatch(terminal)![1]!,
      );
      expect(12.5 * 0.6 + spacing, 7);
    });
  });
}
