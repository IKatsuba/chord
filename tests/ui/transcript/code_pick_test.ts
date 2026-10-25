import { expect, test } from 'bun:test';
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
