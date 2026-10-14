/**
 * The agent's plan as the list above the prompt: its marks, the line it hangs
 * from between turns, and how a plan taller than its share of the window
 * folds. A finished plan leaves the list for the transcript when its turn
 * ends (`src/session/transcript/turn.ts`).
 */
import type { PlanEntry } from '@agentclientprotocol/sdk';

/** Claude Code's boxes, with a half-filled one for the step under way. */
export const PLAN_MARKS = {
  pending: '☐',
  in_progress: '◐',
  completed: '☒',
} as const satisfies Record<PlanEntry['status'], string>;

export type PlanRow =
  | { readonly kind: 'entry'; readonly entry: PlanEntry }
  /** Finished entries folded away above the ones still to do. */
  | { readonly kind: 'done'; readonly count: number }
  /** Entries past the last row that fits. */
  | { readonly kind: 'more'; readonly count: number };

/** The line a plan hangs from between turns, when no spinner is there. */
export function planSummary(plan: readonly PlanEntry[]): string {
  const done = plan.filter((entry) => entry.status === 'completed').length;

  return `Plan · ${done} of ${plan.length} done`;
}

/** The plan's share of a window `rows` tall, never under three rows. */
export function planRowLimit(rows: number): number {
  return Math.max(3, Math.floor(rows / 4));
}

/**
 * The rows to draw in at most `limit`: the whole plan when it fits; otherwise
 * finished entries fold to one row first, since what is left to do matters
 * more, and then the end of the list folds to `… +N more`.
 */
export function planRows(plan: readonly PlanEntry[], limit: number): PlanRow[] {
  const entries = plan.map((entry): PlanRow => ({ kind: 'entry', entry }));

  if (plan.length <= limit) {
    return entries;
  }

  const open = plan.findIndex((entry) => entry.status !== 'completed');
  const finished = open === -1 ? plan.length : open;
  // Fold no more finished entries than it takes to fit, and never just one:
  // its row would only trade places with the fold's.
  const folded = Math.min(finished, plan.length - limit + 1);
  const head: PlanRow[] = folded > 1 ? [{ kind: 'done', count: folded }] : [];
  const rest = entries.slice(folded > 1 ? folded : 0);
  const room = limit - head.length;

  if (rest.length <= room) {
    return [...head, ...rest];
  }

  return [
    ...head,
    ...rest.slice(0, room - 1),
    { kind: 'more', count: rest.length - room + 1 },
  ];
}
