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
