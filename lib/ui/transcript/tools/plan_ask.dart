/// A plan put to the person, as its call draws it in the transcript, from
/// the original's `ui/transcript/tools/plan_ask.ts` and Tool.tsx's
/// `PlanAskBody`: where it stands, its overview and markdown, then cursor's
/// todos in the plan list's marks, under its phases as sent.
library;

import 'package:chord_tui/chord_tui.dart';

import '../../../session/transcript/types.dart';
import '../../plan/plan_rows.dart' show planMarks;
import '../selection.dart' show SourceBuilder, selectionChild;
import 'tool.dart' show Under;

/// The call's line under `⎿`: waiting, or how the person answered.
String planStatus(PlanAsk ask) => switch (ask.answer) {
  null => 'Waiting…',
  PlanAccepted() => 'Accepted',
  PlanKept(note: null) => 'Kept planning',
  PlanKept(:final note?) => 'Kept planning: $note',
  PlanLeft() => 'Left plan mode',
  PlanCancelled() || PlanWithdrawn() => 'Cancelled',
};

/// The plan's text: its overview, then its markdown; none when grok wrote
/// none.
String? planText(PlanAsk ask) {
  final parts = [
    ask.wait.overview,
    ask.wait.plan,
  ].whereType<String>().where((part) => part.trim().isNotEmpty).toList();
  return parts.isEmpty ? null : parts.join('\n\n');
}

/// A row under the plan: a heading over todos, or a todo with its mark.
sealed class TodoRow {
  const TodoRow();
}

final class TodoHeading extends TodoRow {
  const TodoHeading(this.text);
  final String text;
}

final class TodoItem extends TodoRow {
  const TodoItem(this.mark, this.todo);
  final String mark;
  final PlanTodo todo;
}

/// A todo's mark: the plan list's, a cancelled one's box left empty.
String _markOf(PlanTodo todo) =>
    planMarks[todo.status == 'cancelled' ? 'pending' : todo.status] ?? '☐';

/// cursor's phases, each its name over its todos, then its todos under
/// `Todos`; none of either draws no rows. Each as sent, phases first, a todo
/// in both drawn in both.
List<TodoRow> todoRows(PlanAsk ask) {
  List<TodoRow> group(String heading, List<PlanTodo> items) => items.isEmpty
      ? const []
      : [
          TodoHeading(heading),
          for (final todo in items) TodoItem(_markOf(todo), todo),
        ];
  return [
    for (final phase in ask.wait.phases ?? const <PlanPhase>[])
      ...group(phase.name, phase.todos),
    ...group('Todos', ask.wait.todos ?? const []),
  ];
}

/// The line said when grok wrote no plan, [agent] as the window names it.
String noPlanLine(String agent) => '$agent has written no plan.';

/// cursor's todos as one text: each group's heading over its todos, a
/// blank line between groups, a cancelled todo dim and struck through.
TextSpan todoSpan(List<TodoRow> rows, Style dim) => TextSpan(
  '',
  children: [
    for (final (index, row) in rows.indexed) ...[
      if (index > 0) const TextSpan('\n'),
      switch (row) {
        TodoHeading(:final text) => TextSpan(index == 0 ? text : '\n$text'),
        TodoItem(:final mark, :final todo) => TextSpan(
          '$mark ${todo.content}',
          style: todo.status == 'cancelled'
              ? dim.merge(const Style(strikethrough: true))
              : null,
        ),
      },
    ],
  ],
);

/// The plan body's text, as the transcript's selection reads it.
void planSource(SourceBuilder b, PlanAsk ask, String agent) {
  // One row, cut at the edge, as the original's status is.
  b.text(
    'plan-status',
    TextSpan(planStatus(ask)),
    left: 5,
    softWrap: false,
    maxLines: 1,
    overflow: TextOverflow.clip,
    selectable: false,
  );
  final text = planText(ask);
  if (text == null) {
    b.text('plan-none', TextSpan(noPlanLine(agent)), left: 5);
  } else {
    b.markdown('plan', stripAnsi(text), left: 5);
  }
  final rows = todoRows(ask);
  if (rows.isNotEmpty) {
    b.gap('plan-gap');
    b.text('plan-todos', todoSpan(rows, Style.dim), left: 5);
  }
}

/// A plan put to the person, under its call: where it stands, dim, then the
/// plan as any message is drawn, then cursor's todos as the plan list draws
/// its steps, a cancelled one dim and struck through.
class PlanAskBody extends StatelessWidget {
  const PlanAskBody(
    this.ask, {
    super.key,
    required this.agent,
    this.selectionSource,
  });

  /// The call's source, whose plan rows this draws when given.
  final SelectionSource? selectionSource;

  final PlanAsk ask;

  /// The agent as the window names it.
  final String agent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = planText(ask);
    final rows = todoRows(ask);
    final source = selectionSource;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Under(
          first: true,
          child: SelectionContainer.disabled(
            child: Text(
              planStatus(ask),
              style: theme.dim,
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
        ),
        Under(
          first: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (text == null)
                source == null
                    ? Text(noPlanLine(agent))
                    : Text.fromSelectionSource(
                        selectionChild(source, 'plan-none'),
                      )
              else
                source == null
                    ? Markdown(stripAnsi(text))
                    : Markdown.fromSelectionSource(
                        selectionChild(source, 'plan'),
                      ),
              if (rows.isNotEmpty) ...[
                // A blank line sets the todos apart from the plan.
                const SizedBox(height: 1),
                source == null
                    ? Text.rich(todoSpan(rows, theme.dim))
                    : Text.fromSelectionSource(
                        selectionChild(source, 'plan-todos'),
                      ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
