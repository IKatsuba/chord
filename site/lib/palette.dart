/// The site's palette, direction C of CHD-638: ink, cream and one signal
/// orange, as chord_tui roles for the cells and as [SitePalette] for the
/// site's own surfaces. index.html sets the same ink and cream on the page.
library;

import 'package:chord_tui/chord_tui.dart';

/// The site's colours, by role, as hex for the page and the cells to agree.
abstract final class SiteColors {
  /// Every cell without its own background, and the page.
  static final ink = RgbColor.hex('#0c0c0c');

  /// Text, the terminal's own foreground.
  static final cream = RgbColor.hex('#f2ead9');

  /// Accent, links and focus: the one loud colour.
  static final orange = RgbColor.hex('#ff5a1f');

  /// Descriptions, captions and key words.
  static final muted = RgbColor.hex('#8a8478');

  /// Rules, frames and cells.
  static final rule = RgbColor.hex('#2e2b26');

  /// Code blocks and previews.
  static final raised = RgbColor.hex('#171614');

  /// The help row.
  static final bar = RgbColor.hex('#141312');

  /// Success, and added lines.
  static final green = RgbColor.hex('#8fbf73');

  /// Failure, and removed lines.
  static final red = RgbColor.hex('#e5484d');

  /// Warnings, and code types.
  static final sand = RgbColor.hex('#e8c58a');
}

/// The site's surfaces no chord_tui role names, read with
/// `Theme.of(context).extension<SitePalette>()`.
class SitePalette extends ThemeExtension<SitePalette> {
  /// The palette of [SiteColors].
  const SitePalette();

  /// The help row's background.
  Style get bar => Style(bg: SiteColors.bar);

  /// Code blocks and previews.
  Style get raised => Style(bg: SiteColors.raised);
}

/// The site's theme: chord_tui's dark theme in direction C's colours. Text
/// stays the terminal's own foreground, cream, which index.html sets.
ThemeData siteTheme() {
  final dark = ThemeData.dark();
  final orange = Style(fg: SiteColors.orange);
  return dark.copyWith(
    dim: Style(fg: SiteColors.muted),
    accent: orange,
    link: orange,
    focus: orange,
    inlineCode: Style(bg: SiteColors.raised),
    success: Style(fg: SiteColors.green),
    warning: Style(fg: SiteColors.sand),
    error: Style(fg: SiteColors.red),
    border: Style(fg: SiteColors.rule),
    diff: dark.diff.copyWith(
      added: Style(fg: SiteColors.green),
      removed: Style(fg: SiteColors.red),
    ),
    code: CodeTones(
      terminal: Tones(
        keyword: orange,
        string: Style(fg: SiteColors.green),
        type: Style(fg: SiteColors.sand),
        comment: Style(fg: SiteColors.muted),
        number: Style.plain,
        title: Style.plain,
        name: Style.plain,
        meta: Style.plain,
      ),
    ),
    extensions: const [SitePalette()],
  );
}
