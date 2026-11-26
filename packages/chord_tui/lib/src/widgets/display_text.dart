import '../rendering/basic.dart';
import '../rendering/flex.dart';
import '../terminal/style.dart';
import '../text/display_glyphs.dart';
import '../text/layout.dart';
import '../text/span.dart';
import 'basic.dart';
import 'framework.dart';

/// Display type built from block cells, for a page's giant word or a big
/// number: [text] drawn from chord_tui's own 5x7 glyphs at [size]. It does
/// not wrap; wider than its room, it clips as `Text` with `softWrap: false`.
class DisplayText extends StatelessWidget {
  /// [text] at [size], in [style] (the default text style when null).
  DisplayText(
    String text, {
    super.key,
    this.size = DisplaySize.large,
    this.style,
    this.align = TextAlign.left,
  }) : span = TextSpan(text);

  /// [span]'s text at [size], each run in its own style over [style]: the
  /// orange full stop after a word.
  const DisplayText.rich(
    this.span, {
    super.key,
    this.size = DisplaySize.large,
    this.style,
    this.align = TextAlign.left,
  });

  /// What it draws, with each run's style.
  final TextSpan span;

  /// How big it is drawn.
  final DisplaySize size;

  /// The colour and attributes under [span]'s own.
  final Style? style;

  /// How each row sits in a room wider than the text.
  final TextAlign align;

  /// The cells [text] takes at [size], for a page to choose a size by its
  /// width.
  static ({int width, int height}) measure(String text, DisplaySize size) =>
      displayMeasure(text, size);

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).merge(style);
    final chars = <String>[];
    final styles = <Style>[];
    for (final (text, style) in span.flatten(base)) {
      for (final rune in text.runes) {
        chars.add(String.fromCharCode(rune));
        styles.add(style);
      }
    }
    final rows = displayRows(chars.join(), size);
    final block = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Text.rich(
            TextSpan(
              '',
              children: [
                for (final run in row)
                  TextSpan(
                    run.text,
                    style: run.source < 0 ? null : styles[run.source],
                  ),
              ],
            ),
            softWrap: false,
          ),
      ],
    );
    // The rows share one width: align places the block in the room.
    return switch (align) {
      TextAlign.left => block,
      TextAlign.center => Align(alignment: Alignment.topCenter, child: block),
      TextAlign.right => Align(alignment: Alignment.topRight, child: block),
    };
  }
}
