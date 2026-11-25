import 'package:chord_tui/chord_tui.dart';
import '../../acp/schema.dart' as acp;
import '../transcript/gap.dart';
import '../transcript/tools/tool.dart';
import 'plan_rows.dart';

/// A completed plan kept whole and dim in the transcript.
class PlanRecord extends StatelessWidget {
  /// The plan's final steps in the agent's order.
  const PlanRecord(this.entries, {super.key, this.selectionSource});

  /// Steps the turn completed.
  final List<acp.PlanEntry> entries;

  /// Current composite snapshot when drawn in a lazy transcript item.
  final SelectionSource? selectionSource;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).dim;
    return blockGap(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Gutter('⏺', style: dim),
              SelectionContainer.disabled(child: Text('Plan', style: dim)),
            ],
          ),
          for (final (i, entry) in entries.indexed)
            Under(
              first: i == 0,
              child: Row(
                children: [
                  SelectionContainer.disabled(
                    child: Text(
                      '${switch (entry.status) {
                        'completed' => '☒',
                        'in_progress' => '◐',
                        _ => '☐',
                      }} ',
                      style: dim,
                    ),
                  ),
                  Expanded(
                    child: selectionSource != null
                        ? Text.fromSelectionSource(
                            selectionSource!.children[i + 2],
                            style: dim.merge(
                              Style(strikethrough: entry.status == 'completed'),
                            ),
                          )
                        : Text.rich(
                            TextSpan(
                              '',
                              style: Style(
                                strikethrough: entry.status == 'completed',
                              ),
                              children: [parseAnsi(entry.content)],
                            ),
                            style: dim,
                            softWrap: false,
                            maxLines: 1,
                            overflow: TextOverflow.middle,
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The live plan above the prompt, hanging from the working line while busy.
class Plan extends StatelessWidget {
  const Plan({
    super.key,
    required this.plan,
    required this.limit,
    required this.running,
    this.selectionSource,
  });

  final List<acp.PlanEntry> plan;
  final int limit;
  final bool running;
  final SelectionSource? selectionSource;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).dim;
    final rows = planRows(plan, limit);
    final keys = entryKeys([
      for (final row in rows)
        if (row is EntryPlanRow) row.entry.content else '',
    ]);
    return Padding(
      padding: EdgeInsets.only(left: 2, top: running ? 0 : 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!running)
            SelectionContainer.disabled(
              child: Text(
                planSummary(plan),
                style: dim,
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.middle,
              ),
            ),
          for (final (i, row) in rows.indexed)
            Row(
              key: ValueKey(row is EntryPlanRow ? keys[i] : row.runtimeType),
              children: [
                Gutter(i == 0 ? '⎿' : ' ', width: 3, style: dim),
                if (row is EntryPlanRow &&
                    planMarks.containsKey(row.entry.status)) ...[
                  SelectionContainer.disabled(
                    child: Text(
                      '${planMarks[row.entry.status]} ',
                      style: _style(context, row.entry),
                    ),
                  ),
                  Expanded(
                    child: selectionSource != null
                        ? Text.fromSelectionSource(
                            selectionSource!.children[i + (running ? 0 : 2)],
                            style: _style(context, row.entry).merge(
                              Style(
                                strikethrough: row.entry.status == 'completed',
                              ),
                            ),
                          )
                        : Text.rich(
                            TextSpan(
                              '',
                              style: Style(
                                strikethrough: row.entry.status == 'completed',
                              ),
                              children: [parseAnsi(row.entry.content)],
                            ),
                            style: _style(context, row.entry),
                            softWrap: false,
                            maxLines: 1,
                            overflow: TextOverflow.middle,
                          ),
                  ),
                ] else if (row is! EntryPlanRow)
                  Expanded(
                    child: SelectionContainer.disabled(
                      child: Text(
                        switch (row) {
                          DonePlanRow(:final count) => '… $count done',
                          MorePlanRow(:final count) => '… +$count more',
                          EntryPlanRow() => throw StateError(
                            'entry already drawn',
                          ),
                        },
                        style: dim,
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.middle,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Style _style(BuildContext context, acp.PlanEntry entry) {
    final theme = Theme.of(context);
    return switch (entry.status) {
      'completed' => theme.dim,
      'in_progress' when running => theme.text.merge(Style.bold),
      _ => theme.text,
    };
  }
}
