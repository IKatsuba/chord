/// What one `/team` command left in the transcript: the command as typed,
/// then the team `/team show` found, saved or running. From the original's
/// `ui/teams/Teams.tsx`.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart' hide Folded;

import '../../js_trim.dart';
import '../../session/transcript/types.dart';
import '../../teams.dart';
import '../transcript/tools/proposal.dart';
import '../transcript/tools/tool.dart' show Folded, Under, inRoom;
import 'recorded_receipt.dart';
import 'teams.dart';

/// How many of the body's lines `/team show` keeps folded, by the window's
/// rows.
int keptLines(int windowRows) => windowRows >= 30 ? 3 : 1;

/// The body folded as the original's `proposalBody` folds it, from the
/// rows its Markdown draws in [blocks]: the preview, its first [keep] rows
/// that are not blank, read on across the blocks, and how many rows ctrl+o
/// adds to it, each agent's [instructions] and the body, a blank row
/// between its blocks, against a blank row and the preview.
({List<TextSpan> preview, int hidden}) foldedBody(
  List<String> instructions,
  List<List<TextSpan>> blocks,
  int keep,
) {
  final body = [
    for (final (i, block) in blocks.indexed) ...[
      if (i > 0) const TextSpan(''),
      ...block,
    ],
  ];
  final whole = instructions.length + (body.isEmpty ? 0 : 1 + body.length);
  final preview = [
    for (final row in body)
      if (jsTrim(_plain(row)).isNotEmpty) row,
  ].take(keep).toList();
  final shown = preview.isEmpty ? 0 : 1 + preview.length;
  return (preview: preview, hidden: math.max(whole - shown, 0));
}

String _plain(TextSpan row) =>
    [for (final (text, _) in row.flatten()) text].join();

/// `/team`'s entry: the command as typed, then what it showed.
class TeamEntry extends StatelessWidget {
  /// [shown] under `/[command]`, [rows] the window's.
  const TeamEntry({
    super.key,
    required this.command,
    required this.shown,
    required this.expanded,
    required this.rows,
  });

  final String command;
  final TeamShown shown;
  final bool expanded;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The original's width is the window's less the transcript's
        // padding and an entry's gutter, four columns where the port's
        // entry is given two less; the `⎿` and its gutter take five more.
        final inside = math.max(constraints.maxWidth.toInt() - 2 - 5, 1);
        final shown = this.shown;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: 2, child: Text('›', style: theme.dim)),
                Expanded(child: Text('/$command')),
              ],
            ),
            if (shown is TeamSaid)
              for (final (index, line) in [
                for (final line in shown.text.split('\n'))
                  ...wrapLineText(line, inside),
              ].indexed)
                Under(
                  first: index == 0,
                  child: Text(line, style: shown.failed ? theme.error : null),
                ),
            // A run no longer open: the receipt main's record keeps, as
            // chord's own report, a blank line above it.
            if (shown is TeamReceiptShown)
              RecordedReceipt(shown.call, historical: true),
            if (shown is ShownTeam)
              if (shown.running case final run?)
                ..._running(context, shown, run, inside)
              else
                ..._saved(context, shown, inside),
          ],
        );
      },
    );
  }

  /// A team that is not running: its file, its description, a row per
  /// agent as a proposal draws them, and the body folded, ctrl+o adding
  /// the rest and each agent's instructions.
  List<Widget> _saved(BuildContext context, ShownTeam shown, int width) {
    final theme = Theme.of(context);
    final team = shown.team;
    final instructions = instructionLines(team, width);
    final body = foldedBody(
      instructions,
      Markdown.blocksOf(team.body, width, theme: theme),
      keptLines(rows),
    );
    return [
      Under(
        first: true,
        child: Text(
          '${shown.name} · ${shown.file}',
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
      for (final line in wrapLineText(team.description, width))
        Under(first: false, child: Text(line, style: theme.dim)),
      const SizedBox(height: 1),
      for (final line in proposalTable(agentRows(team), width, whole: expanded))
        Under(first: false, child: _tableLine(context, line)),
      // Opened, each agent's instructions and the body whole, rendered.
      if (expanded) ...[
        for (final line in instructions)
          Under(
            first: false,
            child: Text(line.isEmpty ? ' ' : line, softWrap: false),
          ),
        const SizedBox(height: 1),
        Under(first: false, child: inRoom(width, Markdown(team.body))),
      ] else if (body.preview.isNotEmpty) ...[
        const SizedBox(height: 1),
        // The rows the body's Markdown draws, read on without the blank
        // rows between its blocks.
        for (final row in body.preview)
          Under(first: false, child: Text.rich(row, softWrap: false)),
      ],
      if (!expanded && body.hidden > 0) Folded(body.hidden),
    ];
  }

  /// A table line, its mode in the warning colour where it skips the
  /// person's ok, a changed value dim.
  Widget _tableLine(BuildContext context, TableLine line) {
    final theme = Theme.of(context);
    final text = line.text;
    final (start, end) = line.mode;
    if (end <= start || !skipsAsking(line.row.mode)) {
      return Text(text, softWrap: false);
    }
    return Text.rich(
      TextSpan(
        '',
        children: [
          TextSpan(text.substring(0, start)),
          TextSpan(text.substring(start, end), style: theme.warning),
          TextSpan(text.substring(end)),
        ],
      ),
      softWrap: false,
    );
  }

  /// A running team: how long its run has worked on what, and each of the
  /// file's agents with its mode, its state in the list's colours and its
  /// latest call or message, as `/team show` caught them.
  List<Widget> _running(
    BuildContext context,
    ShownTeam shown,
    TeamRunShown run,
    int width,
  ) {
    final theme = Theme.of(context);
    Style toned(String? tone) => switch (tone) {
      'warning' => theme.warning,
      'error' => theme.error,
      'success' => theme.success,
      'working' => theme.accent.merge(const Style(dim: true)),
      _ => theme.dim,
    };
    final header = runningHeader(
      run.name == shown.name ? shown.name : run.name,
      shown.file,
      run,
      width,
    );
    return [
      for (final (index, line) in header.indexed)
        Under(first: index == 0, child: Text(line)),
      // Held: the report sits in the scrolling transcript.
      const SizedBox(height: 1),
      for (final line in runningTable(shown.team, run.agents, width))
        for (final (at, each) in [line.text, ...line.under].indexed)
          Under(
            first: false,
            child: Text.rich(
              TextSpan(
                '',
                children: () {
                  final spans = [
                    if (at == line.stateLine)
                      (span: line.state, tone: line.agent.state?.tone),
                    if (line.mark case final mark? when at == line.markLine)
                      (span: mark, tone: line.agent.mark?.tone),
                  ]..sort((a, b) => a.span.$1 - b.span.$1);
                  var from = 0;
                  final children = <TextSpan>[];
                  for (final (:span, :tone) in spans) {
                    children
                      ..add(TextSpan(each.substring(from, span.$1)))
                      ..add(
                        TextSpan(
                          each.substring(span.$1, span.$2),
                          style: toned(tone),
                        ),
                      );
                    from = span.$2;
                  }
                  children.add(TextSpan(each.substring(from)));
                  return children;
                }(),
              ),
              softWrap: false,
            ),
          ),
    ];
  }
}

/// The team a `/team show` of a team with no file of its own draws, for
/// tests: [team] as found at [file].
ShownTeam shownSaved(String name, String file, Team team) =>
    ShownTeam(name: name, file: file, team: team);
