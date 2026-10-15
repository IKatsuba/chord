import { expect, test } from 'bun:test';
import type { PlanEntry } from '@agentclientprotocol/sdk';
import {
  entryKeys,
  planRowLimit,
  planRows,
  planSummary,
} from '../../../src/ui/plan/plan.ts';

function plan(...statuses: PlanEntry['status'][]): PlanEntry[] {
  return statuses.map((status, index) => ({
    content: `Step ${index + 1}`,
    priority: 'medium',
    status,
  }));
}

/** Each row as text: an entry's content, or the fold's words. */
function rows(entries: PlanEntry[], limit: number): string[] {
  return planRows(entries, limit).map((row) =>
    row.kind === 'entry'
      ? row.entry.content
      : row.kind === 'done'
        ? `${row.count} done`
        : `+${row.count} more`,
  );
}

test('between turns the plan hangs from how much of it is done', () => {
  expect(
    planSummary(plan('completed', 'completed', 'in_progress')),
  ).toStrictEqual('Plan · 2 of 3 done');
  expect(planSummary(plan('pending'))).toStrictEqual('Plan · 0 of 1 done');
});

test('the plan takes a quarter of the window, three rows at least', () => {
  expect(planRowLimit(40)).toStrictEqual(10);
  expect(planRowLimit(24)).toStrictEqual(6);
  expect(planRowLimit(8)).toStrictEqual(3);
});

test('a plan that fits is drawn whole', () => {
  expect(rows(plan('completed', 'in_progress', 'pending'), 3)).toStrictEqual([
    'Step 1',
    'Step 2',
    'Step 3',
  ]);
});

test('a tall plan folds its finished steps first', () => {
  const entries = plan(
    'completed',
    'completed',
    'completed',
    'completed',
    'in_progress',
    'pending',
  );

  expect(rows(entries, 4)).toStrictEqual([
    '3 done',
    'Step 4',
    'Step 5',
    'Step 6',
  ]);
  expect(rows(entries, 3)).toStrictEqual(['4 done', 'Step 5', 'Step 6']);
  expect(rows([...entries, ...plan('pending')], 3)).toStrictEqual([
    '4 done',
    'Step 5',
    '+2 more',
  ]);
});

test('a single finished step is shown rather than folded', () => {
  expect(
    rows(plan('completed', 'in_progress', 'pending', 'pending'), 3),
  ).toStrictEqual(['Step 1', 'Step 2', '+2 more']);
});

test('a tall plan with nothing finished folds its end', () => {
  expect(
    rows(plan('in_progress', 'pending', 'pending', 'pending'), 3),
  ).toStrictEqual(['Step 1', 'Step 2', '+2 more']);
});

test('a plan step is keyed by its words, a repeated one counted (CHD-172)', () => {
  expect(entryKeys(['a', 'b', 'a'])).toStrictEqual(['0 a', '0 b', '1 a']);
  // A step removed leaves the others their keys.
  expect(entryKeys(['b', 'a'])).toStrictEqual(['0 b', '0 a']);
});
