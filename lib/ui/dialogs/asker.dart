/// Who a box that asks the person names as asking, from the original's
/// `ui/dialogs/asker.ts` and `Asker.tsx`, so the form, link, question and
/// permission boxes say it the same way: a subagent or task by its way down
/// from the session, as its call is headed, in the accent colour; a child
/// in front by its name, bold in its colour; the session's agent by its
/// name, or `main` between turns.
library;

import 'package:chord_tui/chord_tui.dart';

import '../transcript/agents/subagents.dart' show AskerPiece;

/// Said dim after who asks a request that came with no turn running.
const betweenNote = ' · between turns';

/// The long-lived child or member in front, whose session asks: its
/// [name], its [colour] where the palette gives agents one, and a member's
/// [team] by its lead's name.
typedef PickedAsker = ({String name, Color? colour, String? team});

/// [picked] as a box names it, for the rows it wraps to.
String pickedText(PickedAsker picked) =>
    picked.team == null ? picked.name : '${picked.name} · ${picked.team}';

/// [picked]'s pieces: its name bold in its colour over [base], a member's
/// team after it, dim, in [base]'s colour.
List<TextSpan> pickedSpans(PickedAsker picked, Style base) => [
  TextSpan(
    picked.name,
    style: base.merge(
      picked.colour == null ? Style.bold : Style(fg: picked.colour, bold: true),
    ),
  ),
  if (picked.team case final team?)
    TextSpan(' · $team', style: Style(fg: base.fg, dim: true)),
];

/// A box's heading, `<asker> <says>`: [asker]'s pieces in the accent
/// colour, the names bold, then [says] in [style]; with no pieces, the
/// child [picked] in front, else [agent] in their place, or `main`
/// [between] turns. One asked between turns says so after it, dim.
TextSpan askerHeading({
  required List<AskerPiece> asker,
  required String agent,
  required String says,
  required bool between,
  required Style style,
  required ThemeData theme,
  PickedAsker? picked,
}) => TextSpan(
  '',
  children: [
    if (asker.isNotEmpty) ...[
      for (final piece in asker)
        TextSpan(
          piece.text,
          style: piece.bold ? theme.accent.merge(Style.bold) : theme.accent,
        ),
      TextSpan(' $says', style: style),
    ] else if (picked != null) ...[
      // A child in front names itself even between turns, as the
      // original's `askerParts` puts `picked` before `main`.
      ...pickedSpans(picked, style),
      TextSpan(' $says', style: style),
    ] else
      // Between turns, main names itself.
      TextSpan('${between ? 'main' : agent} $says', style: style),
    if (between) TextSpan(betweenNote, style: theme.dim),
  ],
);

/// [row], the permission box's `… asks`, without its verb, for a heading
/// that says its own.
List<AskerPiece> askerOf(List<AskerPiece> row) =>
    row.isEmpty ? const [] : row.sublist(0, row.length - 1);
