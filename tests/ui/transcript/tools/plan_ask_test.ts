import { expect, test } from 'bun:test';
import type { PlanAsk } from '../../../../src/session/transcript/types.ts';
import {
  planStatus,
  planText,
  todoRows,
} from '../../../../src/ui/transcript/tools/plan_ask.ts';

const ask = (
  more: Partial<PlanAsk['wait']> = {},
  answer?: PlanAsk['answer'],
): PlanAsk => ({
  turnId: 't1',
  wait: { id: 'p', agent: 'cursor', toolCallId: 'c', plan: '# Route', ...more },
  ...(answer === undefined ? {} : { answer }),
});

test('the call says it waits, then how the person answered (CHD-437)', () => {
  expect(
    [
      undefined,
      { type: 'accepted' },
      { type: 'kept' },
      { type: 'kept', note: 'smaller' },
      { type: 'left' },
      { type: 'cancelled' },
      { type: 'withdrawn' },
    ].map((answer) => planStatus(ask({}, answer as PlanAsk['answer']))),
  ).toStrictEqual([
    'Waiting…',
    'Accepted',
    'Kept planning',
    'Kept planning: smaller',
    'Left plan mode',
    'Cancelled',
    'Cancelled',
  ]);
});

test('the plan reads its overview, then its markdown; none when grok wrote none', () => {
  expect(planText(ask({ overview: 'Split it.' }))).toBe('Split it.\n\n# Route');
  expect(
    planText({
      turnId: 't1',
      wait: { id: 'p', agent: 'grok', toolCallId: 'c' },
    }),
  ).toBe(undefined);
  expect(planText(ask({ plan: '  ' }))).toBe(undefined);
});

test("cursor's phases as sent, each over its todos, then all its todos under Todos, a cancelled one's box empty (Q132 option 1)", () => {
  const read = { id: 'r', content: 'Read', status: 'completed' } as const;
  const move = { id: 'm', content: 'Move', status: 'in_progress' } as const;
  const drop = { id: 'd', content: 'Drop', status: 'cancelled' } as const;

  expect(
    todoRows(
      ask({
        todos: [read, move, drop],
        phases: [{ name: 'Move', todos: [move] }],
      }),
    ).map((row) =>
      row.kind === 'heading' ? row.text : `${row.mark} ${row.todo.content}`,
    ),
  ).toStrictEqual(['Move', '◐ Move', 'Todos', '☒ Read', '◐ Move', '☐ Drop']);
  expect(todoRows(ask())).toStrictEqual([]);
});
