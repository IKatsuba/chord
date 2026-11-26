/// The site's dark palette, direction A of CHD-638: as chord_tui roles for
/// the cells, and as [SitePalette] for the site's own surfaces. index.html
/// sets the same background and text colours on the page around the grid.
library;

import 'package:chord_tui/chord_tui.dart';

/// The site's colours, by role, as hex for the page and the cells to agree.
abstract final class SiteColors {
  /// Every cell without its own background, and the page.
  static final background = RgbColor.hex('#0d0e12');

  /// The nav, the help row, the sidebar, inline code strips.
  static final surface = RgbColor.hex('#16171d');

  /// Code blocks, previews, placeholder rooms.
  static final raised = RgbColor.hex('#1d1f27');

  /// Rules, frames, cards and the scrollbar thumb.
  static final line = RgbColor.hex('#2b2e38');

  /// Text, the terminal's own foreground.
  static final text = RgbColor.hex('#e7e7ea');

  /// Descriptions, captions and key hints.
  static final muted = RgbColor.hex('#8d919c');

  /// Focus, the current item, links, the primary button and the band.
  static final mint = RgbColor.hex('#5eead4');

  /// The wordmark's gradient end and code keywords.
  static final violet = RgbColor.hex('#a78bfa');

  /// The wordmark's full stop, strings and warnings.
  static final amber = RgbColor.hex('#fbbf24');

  /// Success and added lines.
  static final green = RgbColor.hex('#4ade80');

  /// Failure and removed lines.
  static final red = RgbColor.hex('#f87171');
}

/// The site's surfaces no chord_tui role names, read with
/// `Theme.of(context).extension<SitePalette>()`.
class SitePalette extends ThemeExtension<SitePalette> {
  /// The palette of [SiteColors].
  const SitePalette();

  /// The nav, help row and sidebar background.
  Style get surface => Style(bg: SiteColors.surface);

  /// Code blocks, previews and placeholder rooms.
  Style get raised => Style(bg: SiteColors.raised);
}

/// The site's theme: chord_tui's dark theme with direction A's colours.
/// Text stays the terminal's own foreground, which index.html sets.
ThemeData siteTheme() {
  final dark = ThemeData.dark();
  final code = dark.code!.terminal;
  return dark.copyWith(
    dim: Style(fg: SiteColors.muted),
    accent: Style(fg: SiteColors.mint),
    link: Style(fg: SiteColors.mint),
    inlineCode: Style(bg: SiteColors.surface),
    success: Style(fg: SiteColors.green),
    warning: Style(fg: SiteColors.amber),
    error: Style(fg: SiteColors.red),
    border: Style(fg: SiteColors.line),
    focus: Style(fg: SiteColors.mint),
    diff: dark.diff.copyWith(
      added: Style(fg: SiteColors.green),
      removed: Style(fg: SiteColors.red),
    ),
    code: CodeTones(
      terminal: Tones(
        keyword: Style(fg: SiteColors.violet),
        string: Style(fg: SiteColors.amber),
        number: code.number,
        comment: Style(fg: SiteColors.muted),
        title: code.title,
        type: code.type,
        name: code.name,
        meta: code.meta,
      ),
    ),
    extensions: const [SitePalette()],
  );
}
