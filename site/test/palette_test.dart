import 'dart:io';

import 'package:chord_site/palette.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

RgbColor hexIn(String css, String pattern) {
  final m = RegExp(pattern).firstMatch(css);
  if (m == null) throw StateError('$pattern is not in index.html');
  return RgbColor.hex(m[1]!);
}

void main() {
  test('the theme paints with direction A\'s roles', () {
    final theme = siteTheme();
    expect(theme.brightness, Brightness.dark);
    expect(theme.text, Style.plain, reason: 'the page sets the foreground');
    expect(theme.dim, Style(fg: SiteColors.muted));
    expect(theme.accent, Style(fg: SiteColors.mint));
    expect(theme.focus, Style(fg: SiteColors.mint));
    expect(theme.link, Style(fg: SiteColors.mint));
    expect(theme.border, Style(fg: SiteColors.line));
    expect(theme.warning, Style(fg: SiteColors.amber));
    expect(theme.success, Style(fg: SiteColors.green));
    expect(theme.error, Style(fg: SiteColors.red));
    expect(theme.inlineCode, Style(bg: SiteColors.surface));
    expect(theme.code!.terminal.keyword, Style(fg: SiteColors.violet));
    expect(theme.code!.terminal.string, Style(fg: SiteColors.amber));
    final palette = theme.extension<SitePalette>()!;
    expect(palette.surface, Style(bg: SiteColors.surface));
    expect(palette.raised, Style(bg: SiteColors.raised));
  });

  group('index.html', () {
    final page = File('web/index.html').readAsStringSync();

    test('draws the page and the grid in the palette\'s background and '
        'text', () {
      expect(
        hexIn(page, r'html, body \{[^}]*background: (#[0-9a-f]{6})'),
        SiteColors.background,
      );
      expect(hexIn(page, r'--term-bg: (#[0-9a-f]{6})'), SiteColors.background);
      expect(hexIn(page, r'--term-fg: (#[0-9a-f]{6})'), SiteColors.text);
    });

    test('lets the grid fill the window: no padding, corners or shadow', () {
      final terminal = RegExp(
        r'\n  #terminal \{([^}]*)\}',
      ).firstMatch(page)![1]!;
      expect(terminal, contains('padding: 0;'));
      expect(terminal, contains('border-radius: 0;'));
      expect(terminal, contains('box-shadow: none;'));
    });

    test('uses 14 px on 18 px rows, and 12 px on 15 px under 600 px', () {
      final terminal = RegExp(
        r'\n  #terminal \{([^}]*)\}',
      ).firstMatch(page)![1]!;
      expect(terminal, contains('--term-font-size: 14px;'));
      expect(terminal, contains('--term-row-height: 18px;'));
      expect(terminal, contains('--term-line-height: 1.25;'));
      final phone = RegExp(
        r'@media \(max-width: 599\.98px\) \{\s*#terminal \{([^}]*)\}',
      ).firstMatch(page)![1]!;
      expect(phone, contains('--term-font-size: 12px;'));
      expect(phone, contains('--term-row-height: 15px;'));
    });
  });
}
