/// The background's summary line, the last of the area under the status
/// line, after the agents list: `background`, then a group per state,
/// wrapped between groups and never cut. From the original's
/// `ui/background/Background.tsx`.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../theme/theme.dart';
import 'background.dart';

/// The lines the summary line takes for [items] at [width], the list's
/// cells inside its padding; none with no item.
int summaryLineCount(List<BackgroundItem> items, int width) => items.isEmpty
    ? 0
    : summaryLines(summaryGroups(items), math.max(1, width - 2)).length;

/// The background's summary line over [items], [focused] while the list
/// has the keys and the `❯` is on it. It takes no keys itself; the window
/// routes them.
class SummaryLine extends StatelessWidget {
  /// The line for [items] in the theme's [palette].
  const SummaryLine({
    super.key,
    required this.items,
    required this.focused,
    required this.palette,
  });

  final List<BackgroundItem> items;
  final bool focused;
  final Palette palette;

  /// A group's colour: its state's role, or dim for those at work or
  /// stopped.
  Style _style(SummaryTone tone) {
    final colour = switch (tone) {
      GroupTone(group: BackgroundGroup.asking) => palette.warning,
      GroupTone(group: BackgroundGroup.failed) => palette.error,
      GroupTone(group: BackgroundGroup.done) => palette.success,
      _ => null,
    };
    if (colour != null) return Style(fg: colorOf(colour));
    return tone is LabelTone && focused ? Style.bold : const Style(dim: true);
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox();
    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Past the `❯` and its space, which every line keeps room for.
            final lines = summaryLines(
              summaryGroups(items),
              math.max(1, constraints.maxWidth - 2),
            );
            final mark = palette.permission == null
                ? Style.plain
                : Style(fg: colorOf(palette.permission!));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, line) in lines.indexed)
                  Text.rich(
                    TextSpan(
                      '',
                      children: [
                        TextSpan(
                          focused && index == 0 ? '❯ ' : '  ',
                          style: mark,
                        ),
                        for (final piece in line)
                          TextSpan(piece.text, style: _style(piece.tone)),
                      ],
                    ),
                    softWrap: false,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
