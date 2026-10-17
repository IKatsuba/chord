import { describe, expect, test } from 'bun:test';
import {
  queueRowLimit,
  queueRows,
  restoredDraft,
  started,
} from '../../../src/ui/prompt/queue.ts';

const queue = [
  { turnId: 't2', text: 'second' },
  { turnId: 't3', text: 'third' },
];

test('a queued prompt leaves the queue when its turn starts', () => {
  expect(started(queue, 't2')).toStrictEqual([{ turnId: 't3', text: 'third' }]);
  // The turn that was not queued leaves it as it was.
  expect(started(queue, 't1')).toStrictEqual(queue);
});

test('an interrupt puts the queue back ahead of the draft', () => {
  expect(restoredDraft(queue, 'typing')).toStrictEqual('second\nthird\ntyping');
  expect(restoredDraft(queue, '')).toStrictEqual('second\nthird');
  expect(restoredDraft([], 'typing')).toStrictEqual('typing');
});

test('a queued prompt is one row, its first line', () => {
  expect(
    queueRows([{ turnId: 't2', text: 'one\ntwo' }, ...queue], 5),
  ).toStrictEqual([
    { kind: 'prompt', text: 'one …' },
    { kind: 'prompt', text: 'second' },
    { kind: 'prompt', text: 'third' },
  ]);
});

test('a queue taller than its rows folds its newest prompts', () => {
  const long = ['a', 'b', 'c', 'd', 'e'].map((text) => ({
    turnId: text,
    text,
  }));

  expect(queueRows(long, 3)).toStrictEqual([
    { kind: 'prompt', text: 'a' },
    { kind: 'prompt', text: 'b' },
    { kind: 'more', count: 3 },
  ]);
  expect(queueRows(long, 5).length).toStrictEqual(5);
  expect(queueRowLimit(24)).toStrictEqual(4);
  expect(queueRowLimit(6)).toStrictEqual(2);
});

test("a message held for the person's answer says so in its header, ahead of the text the row is cut in", () => {
  expect(
    queueRows(
      [
        {
          turnId: 't2',
          text: 'Then the docs.',
          from: { name: 'main', reachable: true },
          afterAnswer: true,
        },
        {
          turnId: 't3',
          text: 'Done.',
          from: { name: 'main', reachable: true },
        },
      ],
      5,
    ),
  ).toStrictEqual([
    {
      kind: 'message',
      header: 'from @main · after your answer: ',
      text: 'Then the docs.',
    },
    { kind: 'message', header: 'from @main: ', text: 'Done.' },
  ]);
});

test("a message held behind the running turn's calls says so in its header, one note only, among the others in their order", () => {
  const main = { name: 'main', reachable: true } as const;

  expect(
    queueRows(
      [
        { turnId: 't1', text: 'Run the tests.', from: main, afterCalls: true },
        { turnId: 't2', text: 'Then the docs.', from: main, afterAnswer: true },
        { turnId: 't3', text: 'Done.', from: main },
      ],
      5,
    ),
  ).toStrictEqual([
    {
      kind: 'message',
      header: 'from @main · after the running calls: ',
      text: 'Run the tests.',
    },
    {
      kind: 'message',
      header: 'from @main · after your answer: ',
      text: 'Then the docs.',
    },
    { kind: 'message', header: 'from @main: ', text: 'Done.' },
  ]);
});

describe('CHD-385 tester: queued sender identity', () => {
  test('task, monitor and reachable senders retain their own name forms', () => {
    expect(
      queueRows(
        [
          {
            turnId: 'task',
            from: { name: 'parser', runtime: 'fake', note: 'failed' },
            text: 'The agent exited.',
          },
          {
            turnId: 'agent',
            from: { name: 'parser', runtime: 'fake', reachable: true },
            text: 'An answer arrived late.',
            afterAnswer: true,
          },
          {
            turnId: 'monitor',
            from: {
              name: 'CI',
              monitor: { id: 'm1', end: { kind: 'stopped' } },
            },
            text: 'Stopped.\nNo more events.',
          },
        ],
        4,
      ),
    ).toStrictEqual([
      {
        kind: 'message',
        header: 'from parser · fake · failed: ',
        text: 'The agent exited.',
      },
      {
        kind: 'message',
        header: 'from @parser · fake · after your answer: ',
        text: 'An answer arrived late.',
      },
      {
        kind: 'message',
        header: 'from CI · monitor · stopped: ',
        text: 'Stopped. …',
      },
    ]);
  });
});
