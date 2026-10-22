/**
 * A plan put to the person, as its call draws it in the transcript
 * (docs/design/CHD-437.md): where it stands, its overview and markdown, then
 * cursor's todos in the plan list's marks, under its phases as sent.
 */
import type { PlanTodo } from '../../../acp/plans.ts';
import type { PlanAsk } from '../../../session/transcript/types.ts';
import { PLAN_MARKS } from '../../plan/plan.ts';

/**
 * How cursor's phases and its top-level todos are drawn together, which its
 * docs leave open (the owner's Q132): each as sent, phases first, a todo in
 * both drawn in both. Built so while Q132 is open.
 */
export const PHASES_AS_SENT = true;

/** The call's line under `⎿`: waiting, or how the person answered. */
export function planStatus(ask: PlanAsk): string {
  const { answer } = ask;

  switch (answer?.type) {
    case undefined:
      return 'Waiting…';
    case 'accepted':
      return 'Accepted';
    case 'kept':
      return answer.note === undefined
        ? 'Kept planning'
        : `Kept planning: ${answer.note}`;
    case 'left':
      return 'Left plan mode';
    default:
      return 'Cancelled';
  }
}

/** The plan's text: its overview, then its markdown; none when grok wrote none. */
export function planText(ask: PlanAsk): string | undefined {
  const { overview, plan } = ask.wait;
  const parts = [overview, plan].filter(
    (part): part is string => part !== undefined && part.trim() !== '',
  );

  return parts.length === 0 ? undefined : parts.join('\n\n');
}

/** A row under the plan: a heading over todos, or a todo. */
export type TodoRow =
  | { readonly kind: 'heading'; readonly text: string }
  | { readonly kind: 'todo'; readonly mark: string; readonly todo: PlanTodo };

/** A todo's mark: the plan list's, a cancelled one's box left empty. */
function markOf(todo: PlanTodo): string {
  return todo.status === 'cancelled'
    ? PLAN_MARKS.pending
    : PLAN_MARKS[todo.status];
}

/**
 * cursor's phases, each its name over its todos, then its todos under
 * `Todos`; none of either draws no rows.
 */
export function todoRows(ask: PlanAsk): TodoRow[] {
  const { todos = [], phases = [] } = ask.wait;
  const group = (heading: string, items: readonly PlanTodo[]): TodoRow[] =>
    items.length === 0
      ? []
      : [
          { kind: 'heading', text: heading },
          ...items.map((todo): TodoRow => ({
            kind: 'todo',
            mark: markOf(todo),
            todo,
          })),
        ];

  return [
    ...(PHASES_AS_SENT
      ? phases.flatMap((phase) => group(phase.name, phase.todos))
      : []),
    ...group('Todos', todos),
  ];
}
