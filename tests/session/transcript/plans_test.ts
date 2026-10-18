import { expect, test } from 'bun:test';
import type { PlanEntry, SessionUpdate } from '@agentclientprotocol/sdk';
import type { TranscriptAction } from '../../../src/session/transcript/types.ts';
import { fold } from './fold.ts';

test('a plan by id: entries are the live list, markdown the reply', () => {
  const update = (update: SessionUpdate): TranscriptAction => ({
    type: 'update',
    turnId: 't1',
    update,
  });
  const entries = (status: 'pending' | 'completed'): PlanEntry[] => [
    { content: 'Read the code', priority: 'high', status },
  ];
  const items = (planId: string, status: 'pending' | 'completed') =>
    update({
      sessionUpdate: 'plan_update',
      plan: { type: 'items', planId, entries: entries(status) },
    });
  const markdown = (content: string) =>
    update({
      sessionUpdate: 'plan_update',
      plan: { type: 'markdown', planId: 'm', content },
    });
  const removed = (planId: string) =>
    update({ sessionUpdate: 'plan_removed', planId });
  const start: TranscriptAction = {
    type: 'prompt',
    turnId: 't1',
    text: 'plan',
    at: 0,
  };

  expect(fold([start, items('p', 'pending')]).plan).toStrictEqual(
    entries('pending'),
  );
  expect(
    fold([start, items('p', 'pending'), items('p', 'completed')]).plan,
  ).toStrictEqual(entries('completed'));
  expect(fold([start, items('p', 'pending'), removed('q')]).plan).toStrictEqual(
    [...entries('pending')],
  );
  expect(fold([start, items('p', 'pending'), removed('p')]).plan).toStrictEqual(
    [],
  );

  const state = fold([
    start,
    markdown('1. Read'),
    update({
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: 'Shall I go on?' },
    }),
    markdown('1. Read\n2. Write'),
  ]);

  expect(state.plan).toStrictEqual([]);
  expect(
    state.entries.map((e) => [e.kind, 'text' in e ? e.text : undefined]),
  ).toStrictEqual([
    ['user', 'plan'],
    ['assistant', '1. Read\n2. Write'],
    ['assistant', 'Shall I go on?'],
  ]);

  const other = update({
    sessionUpdate: 'plan_update',
    plan: { type: 'file', planId: 'f', uri: 'file:///plan.md' },
  });
  const kept = fold([
    start,
    markdown('1. Read'),
    update({
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: 'Shall I go on?' },
    }),
    other,
    items('p', 'pending'),
    removed('m'),
  ]);

  expect(kept.plan).toStrictEqual(entries('pending'));
  expect(
    kept.entries.map((e) => [e.kind, 'text' in e ? e.text : undefined]),
  ).toStrictEqual([
    ['user', 'plan'],
    ['assistant', 'Shall I go on?'],
    ['assistant', 'file:///plan.md'],
  ]);
  expect(
    fold([start, other, removed('f')]).entries.map((e) => e.kind),
  ).toStrictEqual(['user']);
});

test("an approved plan shows once: a markdown plan_update takes it from the turn's mode switch that carries it", () => {
  const PLAN = '# Route\n\n1. Read.\n2. Move.\n';
  const update = (update: SessionUpdate, turnId = 't1'): TranscriptAction => ({
    type: 'update',
    turnId,
    update,
  });
  const exit = (id: string, text: string, turnId?: string) =>
    update(
      {
        sessionUpdate: 'tool_call',
        toolCallId: id,
        title: 'Approve Plan',
        kind: 'switch_mode',
        status: 'pending',
        content: [{ type: 'content', content: { type: 'text', text } }],
      },
      turnId,
    );
  const approved = update({
    sessionUpdate: 'plan_update',
    plan: { type: 'markdown', planId: 'plan-mode', content: PLAN.trim() },
  });
  const start = (turnId: string): TranscriptAction => ({
    type: 'prompt',
    turnId,
    text: 'plan',
    at: 0,
  });
  const contents = (actions: TranscriptAction[]) =>
    fold(actions).entries.flatMap((entry): unknown[] =>
      entry.kind === 'tool'
        ? [{ id: entry.call.id, content: entry.call.content }]
        : entry.kind === 'assistant'
          ? [{ plan: entry.text }]
          : [],
    );
  const text = (value: string) => [
    { type: 'content', content: { type: 'text', text: value } },
  ];

  expect(contents([start('t1'), exit('e1', PLAN), approved])).toStrictEqual([
    { id: 'e1', content: [] },
    { plan: PLAN.trim() },
  ]);
  // Only the latest switch of the turn, and only when its text is the plan.
  expect(
    contents([start('t1'), exit('e1', PLAN), exit('e2', 'Another.'), approved]),
  ).toStrictEqual([
    { id: 'e1', content: text(PLAN) },
    { id: 'e2', content: text('Another.') },
    { plan: PLAN.trim() },
  ]);
  expect(
    contents([start('t0'), exit('e0', PLAN, 't0'), start('t1'), approved]),
  ).toStrictEqual([{ id: 'e0', content: text(PLAN) }, { plan: PLAN.trim() }]);
});
