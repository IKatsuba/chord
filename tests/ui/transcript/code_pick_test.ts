import { describe, expect, test } from 'bun:test';
import {
  type BlockRef,
  reduceCodePick,
} from '../../../src/ui/transcript/code_pick.ts';

/** Two replies: the first with two blocks, the second with one. */
const BLOCKS: readonly BlockRef[] = [
  { entry: 1, block: 0 },
  { entry: 1, block: 1 },
  { entry: 4, block: 0 },
];

test('ctrl+x b picks the newest block on screen, or the newest of all when none is, and none with no block (CHD-394)', () => {
  const start = (shown: readonly BlockRef[], blocks = BLOCKS) =>
    reduceCodePick(undefined, { type: 'code_pick_started', blocks, shown });

  expect(start([BLOCKS[0]!, BLOCKS[1]!])).toStrictEqual(BLOCKS[1]);
  // Scrolled back, the reply below is off screen.
  expect(start([BLOCKS[0]!])).toStrictEqual(BLOCKS[0]);
  expect(start([])).toStrictEqual(BLOCKS[2]);
  expect(start([], [])).toBeUndefined();
});

test('↑ and ↓ move across replies in the order drawn and stay at either end, and the pick ends (CHD-394)', () => {
  const move = (from: BlockRef | undefined, by: -1 | 1) =>
    reduceCodePick(from, { type: 'code_pick_moved', by, blocks: BLOCKS });

  expect(move(BLOCKS[2], -1)).toStrictEqual(BLOCKS[1]);
  expect(move(BLOCKS[1], -1)).toStrictEqual(BLOCKS[0]);
  expect(move(BLOCKS[0], -1)).toStrictEqual(BLOCKS[0]);
  expect(move(BLOCKS[1], 1)).toStrictEqual(BLOCKS[2]);
  expect(move(BLOCKS[2], 1)).toStrictEqual(BLOCKS[2]);
  // A block no longer drawn gives way to the newest; no pick stays none.
  expect(move({ entry: 9, block: 0 }, -1)).toStrictEqual(BLOCKS[2]);
  expect(move(undefined, 1)).toBeUndefined();
  expect(
    reduceCodePick(BLOCKS[1], { type: 'code_pick_ended' }),
  ).toBeUndefined();
});

describe('CHD-394 tester: pick identity and changing blocks', () => {
  test('visible references match by entry and block, with drawn order winning over shown order', () => {
    expect(
      reduceCodePick(BLOCKS[2], {
        type: 'code_pick_started',
        blocks: BLOCKS,
        shown: [
          { entry: 1, block: 1 },
          { entry: 1, block: 0 },
          { entry: 99, block: 0 },
        ],
      }),
    ).toStrictEqual({ entry: 1, block: 1 });
    expect(
      reduceCodePick(undefined, {
        type: 'code_pick_started',
        blocks: BLOCKS,
        shown: [{ entry: 4, block: 1 }],
      }),
    ).toStrictEqual({ entry: 4, block: 0 });
  });

  test('recreated references move across entries and a newly appended block is reachable', () => {
    const blocks = [...BLOCKS, { entry: 4, block: 1 }];

    expect(
      reduceCodePick(
        { entry: 1, block: 1 },
        {
          type: 'code_pick_moved',
          by: 1,
          blocks,
        },
      ),
    ).toStrictEqual({ entry: 4, block: 0 });
    expect(
      reduceCodePick(
        { entry: 4, block: 0 },
        {
          type: 'code_pick_moved',
          by: 1,
          blocks,
        },
      ),
    ).toStrictEqual({ entry: 4, block: 1 });
  });

  test('a removed pick falls back in either direction, while clearing all blocks leaves no pick', () => {
    for (const by of [-1, 1] as const) {
      expect(
        reduceCodePick(
          { entry: 1, block: 1 },
          {
            type: 'code_pick_moved',
            by,
            blocks: [{ entry: 4, block: 0 }],
          },
        ),
      ).toStrictEqual({ entry: 4, block: 0 });
      expect(
        reduceCodePick(BLOCKS[1], {
          type: 'code_pick_moved',
          by,
          blocks: [],
        }),
      ).toBeUndefined();
    }

    expect(
      reduceCodePick(BLOCKS[1], {
        type: 'code_pick_started',
        blocks: [],
        shown: BLOCKS,
      }),
    ).toBeUndefined();
    expect(
      reduceCodePick(undefined, { type: 'code_pick_ended' }),
    ).toBeUndefined();
  });
});
