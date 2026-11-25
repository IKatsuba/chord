/// The prompt box's top row while a child is in front: `╭─ docs ───╮`, a
/// member's run after it dim, `╭─ tester · bugfix ───╮`, the original's
/// `NamedTop` (`src/ui/prompt/Prompt.tsx` in `../chord`).
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

/// The child a prompt goes to, named on the box's top: its name and its
/// colour among the theme's agents, none when the theme has none.
final class PromptAgent {
  /// The child [name], drawn in [colour], a member of the run led by
  /// [team].
  const PromptAgent(this.name, {this.colour, this.team});

  /// The child's name.
  final String name;

  /// A member's run, by its lead's name, as two runs may each have a
  /// `tester`; none for any other child.
  final String? team;

  /// Its colour; none draws the edge dim and the name uncoloured.
  final Color? colour;
}

/// The prompt box's edge: the style its border is drawn in, the style a
/// named top's own edges take, and the colour the name on it takes, none
/// when the edge has no colour of its own.
typedef PromptEdge = ({Style style, Style top, Color? tone});

/// The edge of the prompt's box: bash mode's colour, where the theme has
/// one, outranks the agent's, since it says what Enter does; with neither,
/// the edge is the theme's [border] (the original's DIM_BORDER, palette
/// colour 244), or the terminal's own in bash mode, as the original's
/// `border` reads them. A named top has no colour to take there: its edges
/// are dim, as the original's `NamedTop` draws a dim edge.
PromptEdge promptEdge({
  required bool bash,
  required Style bashStyle,
  required Style border,
  Color? agent,
}) {
  if (bash && bashStyle.fg != null) {
    return (style: bashStyle, top: bashStyle, tone: bashStyle.fg);
  }
  if (agent != null) {
    return (style: Style(fg: agent), top: Style(fg: agent), tone: agent);
  }
  return bash
      ? (style: bashStyle, top: bashStyle, tone: null)
      : (style: border, top: const Style(dim: true), tone: null);
}

/// The named top of a box [width] cells wide: `╭─` in the [edge]'s top
/// style, ` name` bold in its tone, then ` `, `─` to the end and `╮` in the
/// edge's top style. One line, longer than [width] when the name does not
/// fit, as the original's is: the row it is drawn in cuts it.
TextSpan namedTop(String name, int width, PromptEdge edge, {String? team}) {
  final after = team == null ? '' : ' · $team';
  final fill = math.max(1, width - cellWidth(name + after) - 5);
  return TextSpan(
    '',
    children: [
      TextSpan('╭─', style: edge.top),
      TextSpan(' $name', style: Style(fg: edge.tone, bold: true)),
      if (team != null) TextSpan(after, style: const Style(dim: true)),
      TextSpan(' ${'─' * fill}╮', style: edge.top),
    ],
  );
}

/// [namedTop] as the row over a box's top border, cut at the box's width;
/// nothing where the box is too narrow to draw a border.
class NamedTop extends StatelessWidget {
  /// The row naming [name] on an edge of [edge].
  const NamedTop({
    super.key,
    required this.name,
    required this.edge,
    this.team,
  });

  /// The child's name.
  final String name;

  /// A member's run, by its lead's name.
  final String? team;

  /// The box's edge.
  final PromptEdge edge;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      // A box under two cells draws no border, so there is no top to name.
      if (width < 2) return const SizedBox();
      return SelectionContainer.disabled(
        child: Text.rich(
          namedTop(name, width, edge, team: team),
          softWrap: false,
          maxLines: 1,
        ),
      );
    },
  );
}
