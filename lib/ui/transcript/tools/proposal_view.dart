/// `propose_team`'s team under its call: the description, a row per agent
/// with each mode whole, a mode that skips the person's ok in the warning
/// colour and a change's rows marked, then each agent's instructions and
/// the body, whole as a tool's result is, or a change's body as a diff
/// under a line that counts it, and the line the person's answer left. From
/// the original's `Proposal` and `TableRow` in `ui/transcript/tools/
/// Tool.tsx`.
library;

import 'package:chord_tui/chord_tui.dart' hide Folded;

import '../message.dart' show wrapLine;
import 'diff.dart' show ToolDiffView, diffView;
import '../../../teams.dart' show RowChange;
import 'proposal.dart';
import '../selection.dart' show selectionChild;
import 'tool.dart' show Under, inRoom;

/// What a proposal draws above its body, one string a row: the
/// description wrapped to [width], a blank row, the table ([expanded] opens
/// it) and each agent's instructions. None of it selects, as the
/// original's are furniture.
List<String> proposalHead(
  ProposalView view, {
  required bool expanded,
  required int width,
}) {
  final team = view.team;
  final before = view.before;
  return [
    for (final line in wrapLine(TextSpan(team.description), width))
      line.map((glyph) => glyph.text).join(),
    '',
    for (final line in proposalTable(
      agentRows(team, before),
      width,
      marked: view.change && before != null,
      whole: expanded,
    ))
      line.text,
    ...proposalBody(
      instructions: instructionLines(team, width),
      blocks: const [],
      keep: 0,
      expanded: true,
    ).lines,
  ];
}

/// A change's body as the diff a proposal draws it with, a tool result's,
/// whole, as the original has done since its CHD-422; none for a new team
/// or a change that left the body as it was.
ToolDiffView? proposalChange(ProposalView view) {
  final before = view.before;
  return view.change && before != null && before.body != view.team.body
      ? diffView('${view.name}.md', before.body, view.team.body)
      : null;
}

/// A proposal's rows under its call, [width] the cells beside the `⎿` and
/// its gutter; [expanded] opens the table, each role on lines of its own.
/// A change's body diff selects through [source], its headline and code,
/// as the original's; the rest is furniture.
class ProposalBody extends StatelessWidget {
  /// [view] drawn under its call.
  const ProposalBody(
    this.view, {
    super.key,
    required this.expanded,
    required this.width,
    this.source,
  });

  final ProposalView view;
  final bool expanded;
  final int width;

  /// The call's selection source, whose `proposal-change` and
  /// `proposal-diff` children a body change draws from.
  final SelectionSource? source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final team = view.team;
    final marked = view.change && view.before != null;
    final table = proposalTable(
      agentRows(team, view.before),
      width,
      marked: marked,
      whole: expanded,
    );
    final diff = proposalChange(view);
    final instructions = proposalBody(
      instructions: instructionLines(team, width),
      blocks: const [],
      keep: 0,
      expanded: true,
    ).lines;
    final saved = savedLine(view);
    final source = this.source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionContainer.disabled(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, line) in wrapLine(
                TextSpan(team.description),
                width,
              ).indexed)
                Under(
                  first: index == 0,
                  child: Text(
                    line.map((glyph) => glyph.text).join(),
                    style: theme.dim,
                    softWrap: false,
                  ),
                ),
              const SizedBox(height: 1),
              for (final line in table)
                Under(first: false, child: ProposalTableRow(line)),
              for (final line in instructions)
                Under(
                  first: false,
                  child: Text(line.isEmpty ? ' ' : line, softWrap: false),
                ),
              if (diff == null) ...[
                Under(first: false, child: Text(' ')),
                Under(first: false, child: inRoom(width, Markdown(team.body))),
              ],
            ],
          ),
        ),
        if (diff != null) ...[
          Under(
            first: false,
            child: source == null
                ? Text(bodyChangeLine(view.name, diff.view), style: theme.dim)
                : Text.fromSelectionSource(
                    selectionChild(source, 'proposal-change'),
                    style: theme.dim,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: source == null
                ? Diff.fromView(
                    diff.view,
                    title: diff.path,
                    showTitle: false,
                    wrap: DiffWrap.wrapAnsi,
                    codeInsetRight: 2,
                  )
                : Diff.fromSelectionSource(
                    selectionChild(source, 'proposal-diff'),
                  ),
          ),
        ],
        if (saved != null)
          SelectionContainer.disabled(
            child: Under(
              first: false,
              child: Text(
                saved.text,
                style: saved.saved ? theme.success : theme.dim,
              ),
            ),
          ),
      ],
    );
  }
}

/// One agent's row of a proposal's table, its mode in the warning colour
/// where it skips asking, and what a changed effort and mode were dim; a
/// gone member's row and a role's lines dim whole.
class ProposalTableRow extends StatelessWidget {
  /// [line] drawn.
  const ProposalTableRow(this.line, {super.key});

  final TableLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = line.text;
    if (line.row.change == RowChange.removed || line.role) {
      return Text(text, style: theme.dim, softWrap: false);
    }
    // Painted spans in the order they are in the line, the effort's
    // column being before the mode's, and the text between them plain.
    final spans = [
      if (line.effortWas case final at?) (at: at, style: theme.dim),
      (at: line.mode, style: skipsAsking(line.row.mode) ? theme.warning : null),
      if (line.was case final at?) (at: at, style: theme.dim),
    ].where((span) => span.at.$1 < span.at.$2);
    var read = 0;
    final children = <TextSpan>[];
    for (final (:at, :style) in spans) {
      children
        ..add(TextSpan(text.substring(read, at.$1)))
        ..add(TextSpan(text.substring(at.$1, at.$2), style: style));
      read = at.$2;
    }
    children.add(TextSpan(text.substring(read)));
    return Text.rich(TextSpan('', children: children), softWrap: false);
  }
}
