import { describe, expect, test } from 'bun:test';
import {
  appended,
  inBatch,
  lastReplaced,
  replacedAt,
} from '../../../src/session/transcript/entries.ts';
import { reduceTranscript } from '../../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type Entry,
} from '../../../src/session/transcript/types.ts';
import { pastOf } from './past.ts';

const note = (text: string): Entry => ({
  kind: 'error',
  turnId: 't',
  message: text,
});

describe("a transcript's entries, written live and in a batch (CHD-559)", () => {
  test('live, each write gives a new array and leaves the one it was given', () => {
    const entries = [note('a'), note('b')];

    expect(appended(entries, note('c'))).toStrictEqual([
      note('a'),
      note('b'),
      note('c'),
    ]);
    expect(lastReplaced(entries, note('z'))).toStrictEqual([
      note('a'),
      note('z'),
    ]);
    expect(replacedAt(entries, 0, note('y'))).toStrictEqual([
      note('y'),
      note('b'),
    ]);
    expect(entries).toStrictEqual([note('a'), note('b')]);
    expect(appended(entries)).not.toBe(entries);
  });

  test('in a batch, an array from before it is copied, and one it made is written in place', () => {
    const held = [note('a')];

    inBatch(() => {
      const first = appended(held, note('b'));

      expect(first).not.toBe(held);
      expect(appended(first, note('c'))).toBe(first);
      expect(lastReplaced(first, note('d'))).toBe(first);
      expect(replacedAt(first, 0, note('e'))).toBe(first);
      expect(first).toStrictEqual([note('e'), note('b'), note('d')]);
    });

    expect(held).toStrictEqual([note('a')]);
  });

  test('an array a batch made is not written once it has ended', () => {
    const made = inBatch(() => appended([], note('a')));

    expect(appended(made, note('b'))).not.toBe(made);
    expect(made).toStrictEqual([note('a')]);
    // Nor by a later batch.
    inBatch(() => expect(appended(made, note('c'))).not.toBe(made));
    expect(made).toStrictEqual([note('a')]);
  });

  test('a batch that throws leaves nothing written in place after it', () => {
    let made: readonly Entry[] = [];

    expect(() =>
      inBatch(() => {
        made = appended([], note('a'));

        throw new Error('stop');
      }),
    ).toThrow('stop');
    expect(appended(made, note('b'))).not.toBe(made);
  });

  test('a past folded in a batch gives the entries folding it an action at a time gives', () => {
    const past = pastOf(40);
    const fold = (from = emptyTranscript) =>
      past.reduce(reduceTranscript, from);
    const whole = fold();

    // Every kind of entry the past is there to reach.
    for (const kind of [
      'user',
      'thought',
      'assistant',
      'tool',
      'plan',
      'subagent',
      'item_ended',
      'cancelled',
      'warning',
      'error',
    ]) {
      expect(
        whole.entries.some((each) => each.kind === kind),
        kind,
      ).toBe(true);
    }

    expect(
      whole.entries.some((each) => each.kind === 'tool' && each.call.cut),
    ).toBe(true);
    expect(inBatch(() => fold())).toStrictEqual(whole);
  });

  test('a batch from a transcript with entries leaves those it was given as they were', () => {
    const start = pastOf(3).reduce(reduceTranscript, emptyTranscript);
    const entries = [...start.entries];
    const after = inBatch(() => pastOf(6).reduce(reduceTranscript, start));

    expect(start.entries).toStrictEqual(entries);
    expect(after.entries).not.toBe(start.entries);
  });
});
