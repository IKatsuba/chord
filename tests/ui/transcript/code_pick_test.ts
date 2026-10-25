import { describe, expect, test } from 'bun:test';
import {
  DEFAULT_KEYMAP,
  readKeybindings,
} from '../../../src/ui/shortcuts/bindings.ts';
import {
  type BlockRef,
  drawnIds,
  onScreen,
  pickHint,
  reduceCodePick,
} from '../../../src/ui/transcript/code_pick.ts';
import {
  codePlaces,
  softMarkdown,
} from '../../../src/ui/transcript/markdown.ts';

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

test("a reply's boxes and quotes are given ids, and each block the id of what it is drawn in (CHD-394)", () => {
  const text = [
    '```sh',
    'ls',
    '```',
    '',
    '> quoted:',
    '>',
    '> ```console',
    '> $ pwd',
    '> ```',
    '',
    '- then',
    '',
    '  ```bash',
    '  echo hi',
    '  ```',
  ].join('\n');
  const soft = softMarkdown(text, 80, false);
  const { ids, nodes } = drawnIds(soft, codePlaces(text), 7);

  // The quoted block is the second written: drawn into the quote.
  expect(codePlaces(text)).toStrictEqual({ boxes: [0, 2], quotes: [[1]] });
  expect(nodes).toStrictEqual(['code-7-0', 'quote-7-0', 'code-7-2']);
  expect([...ids.values()]).toStrictEqual([
    'code-7-0',
    'quote-7-0',
    'code-7-2',
  ]);
});

test('the blocks drawn are ordered as on screen, and those in view told apart (CHD-394)', () => {
  const at = (entry: number, top: number, left = 0, height = 3) => ({
    ref: { entry, block: 0 },
    top,
    left,
    height,
  });
  const { blocks, shown } = onScreen(
    [at(3, 30), at(1, 2), at(2, 12, 4), at(4, 12, 0)],
    { top: 10, height: 10 },
  );

  expect(blocks.map(({ entry }) => entry)).toStrictEqual([1, 4, 2, 3]);
  // A box whose rows reach into the view counts; one wholly past it does not.
  expect(shown.map(({ entry }) => entry)).toStrictEqual([4, 2]);
  expect(onScreen([], { top: 0, height: 10 })).toStrictEqual({
    blocks: [],
    shown: [],
  });
});

test("a picked block's line of keys names the bound ones, r only with [run] (CHD-394)", () => {
  expect(pickHint(DEFAULT_KEYMAP, true)).toStrictEqual(
    '↑ ↓ another block · c copy · r put in the prompt · esc done',
  );
  expect(pickHint(DEFAULT_KEYMAP, false)).toStrictEqual(
    '↑ ↓ another block · c copy · esc done',
  );

  const { keymap } = readKeybindings(
    JSON.stringify({
      bindings: [
        { context: 'CodeBlock', bindings: { y: 'codeBlock:copy', c: null } },
      ],
    }),
  );

  expect(pickHint(keymap, false)).toStrictEqual(
    '↑ ↓ another block · y copy · esc done',
  );
});
