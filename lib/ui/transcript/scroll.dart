import 'package:chord_tui/chord_tui.dart';

import '../app/state.dart';

// The framework owns scrolling and anchors. M1 omits mount.ts.

/// A piece of the below rule, optionally drawn in the accent.
final class Segment {
  /// Text and its accent flag.
  const Segment(this.text, {this.accent = false});

  /// The rule's wording or padding.
  final String text;

  /// New output is accented; other words are dim.
  final bool accent;
}

/// Rows below the view, including the row covered by the rule; none while
/// following, nor while a press holds the view at the bottom, where nothing
/// is below until output arrives under it (the original's CHD-397).
int? rowsBelow(ScrollState scroll) =>
    scroll.following || (scroll.held && scroll.top >= scroll.bottomTop)
    ? null
    : (scroll.content - scroll.top - (scroll.view - 1)).clamp(1, unbounded);

/// The original below rule; the one-row widget clips it in a narrow room.
List<Segment> indicator(ScrollState scroll, int width, String? bottomKey) {
  final below = rowsBelow(scroll);
  if (below == null) return const [];
  final count = '$below ${below == 1 ? 'line' : 'lines'} below';
  const news = '↓ new output';
  final words = scroll.news ? '$news · $count' : '↓ $count';
  final back = bottomKey == null ? '' : ' · $bottomKey to jump to the bottom';
  final whole = '── $words$back ';
  final text = cellWidth(whole) < width ? whole : '── $words ';
  final padding = (width - cellWidth(text)).clamp(0, unbounded);
  final line = '$text${'─' * padding}';
  if (!scroll.news) return [Segment(line)];
  final at = line.indexOf(news);
  return [
    Segment(line.substring(0, at)),
    const Segment(news, accent: true),
    Segment(line.substring(at + news.length)),
  ];
}

/// Chord's transcript scrolling keys, leaving plain arrows to the prompt.
const chordScrollKeys = ScrollKeys(
  pageUp: ['pageup', 'shift+pageup'],
  pageDown: ['pagedown', 'shift+pagedown'],
  lineUp: ['shift+up'],
  lineDown: ['shift+down'],
  top: ['home', 'shift+home'],
  bottom: ['end', 'shift+end'],
);

/// Applies CTUI-15's event effect to the framework-owned scroll state.
void applyScrollEffect(ScrollController controller, ScrollEffect effect) {
  switch (effect) {
    case ScrollEffect.bottom:
      controller.toBottom();
    case ScrollEffect.news:
      controller.markNews();
    case ScrollEffect.none:
      break;
  }
}
