import { expect, test } from 'bun:test';
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
    { kind: 'message', text: '@main · after your answer: Then the docs.' },
    { kind: 'message', text: '@main: Done.' },
  ]);
});
