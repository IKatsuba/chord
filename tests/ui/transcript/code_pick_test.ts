import { describe, expect, test } from 'bun:test';
import {
  DEFAULT_KEYMAP,
  readKeybindings,
} from '../../../src/ui/shortcuts/bindings.ts';
import {
  type BlockRef,
  drawnIds,
  inOrder,
  inView,
  listedBlocks,
  pickableBlocks,
  pickHint,
  reduceCodePick,
  wholeInView,
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

test('the blocks the pick reaches are in one transcript order, listed and drawn-only alike (CHD-394)', () => {
  const ref = (entry: number, block = 0) => ({ entry, block });

  expect(
    inOrder(
      [ref(5, 1), ref(1, 0), ref(5, 0)],
      [
        // A tool's summary in entry 3, two boxes one above the other.
        { ref: ref(-2, 1), at: 3, top: 20, left: 0 },
        { ref: ref(-2, 0), at: 3, top: 10, left: 0 },
        // The plan box, outside the transcript: last.
        { ref: ref(-9, 0), at: undefined, top: 1, left: 0 },
        // Drawn in a listed entry: after its listed blocks.
        { ref: ref(-4, 0), at: 5, top: 0, left: 0 },
      ],
    ),
  ).toStrictEqual([
    ref(1, 0),
    ref(-2, 0),
    ref(-2, 1),
    ref(5, 0),
    ref(5, 1),
    ref(-4, 0),
    ref(-9, 0),
  ]);
});

test('a block is in view by any row of its own (CHD-394)', () => {
  const view = { top: 10, height: 10 };

  expect(inView({ top: 8, height: 3 }, view)).toBe(true);
  expect(inView({ top: 19, height: 5 }, view)).toBe(true);
  expect(inView({ top: 20, height: 1 }, view)).toBe(false);
  expect(inView({ top: 5, height: 5 }, view)).toBe(false);
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

test('a block is whole in view only with every row of it in the view (CHD-394)', () => {
  const view = { top: 10, height: 10 };

  expect(wholeInView({ top: 10, height: 10 }, view)).toBe(true);
  expect(wholeInView({ top: 12, height: 3 }, view)).toBe(true);
  expect(wholeInView({ top: 9, height: 3 }, view)).toBe(false);
  expect(wholeInView({ top: 18, height: 3 }, view)).toBe(false);
  expect(wholeInView({ top: 30, height: 1 }, view)).toBe(false);
});

test('a listed block is reached mounted or not, a drawn-only one only while seen, in the view or on the window (CHD-394 §3)', () => {
  const view = { top: 2, height: 10 };
  const screen = { top: 0, height: 24 };
  const ref = (entry: number, block = 0) => ({ entry, block });
  const { blocks, shown } = pickableBlocks(
    [
      // Not mounted, scrolled off and in view.
      { ref: ref(1) },
      { ref: ref(2), at: { top: -30, height: 4 } },
      { ref: ref(3), at: { top: 4, height: 4 } },
    ],
    [
      // Tool output in entry 2 scrolled off, and in entry 3 in view.
      { ref: ref(-5), at: 2, top: -20, left: 0, height: 3 },
      { ref: ref(-6), at: 3, top: 9, left: 0, height: 2 },
      // The plan box below the transcript, on the window; and one past it.
      { ref: ref(-7), at: undefined, top: 15, left: 0, height: 4 },
      { ref: ref(-8), at: undefined, top: 30, left: 0, height: 4 },
    ],
    view,
    screen,
  );

  expect(blocks).toStrictEqual([ref(1), ref(2), ref(3), ref(-6), ref(-7)]);
  expect(shown).toStrictEqual([ref(3), ref(-6), ref(-7)]);
});

describe('CHD-394 U4 tester: eligible block boundaries', () => {
  test('a closed reply survives unmounting, while drawn-only blocks stop at viewport and screen edges', () => {
    const listed = { entry: 7, block: 0 };
    const top = { entry: -1, block: 0 };
    const bottom = { entry: -2, block: 0 };
    const plan = { entry: -3, block: 0 };
    const hiddenPlan = { entry: -4, block: 0 };
    const result = pickableBlocks(
      [{ ref: listed }],
      [
        { ref: top, at: 2, top: 1, left: 0, height: 1 },
        { ref: bottom, at: 3, top: 12, left: 0, height: 1 },
        { ref: plan, at: undefined, top: 23, left: 0, height: 2 },
        { ref: hiddenPlan, at: undefined, top: 24, left: 0, height: 2 },
      ],
      { top: 2, height: 10 },
      { top: 0, height: 24 },
    );

    expect(result.blocks).toStrictEqual([listed, plan]);
    expect(result.shown).toStrictEqual([plan]);
  });

  test('open fences remain ineligible until their matching closer, with quoted runnable text preserved', () => {
    const text =
      '> ```bash\n> $ printf "quoted"\n> ```\n\n````sh\n$ printf "open"\n```';
    const entry = { kind: 'assistant', turnId: 'tall', text } as const;

    expect(listedBlocks([entry])).toMatchObject([
      {
        ref: { entry: 0, block: 0 },
        copy: '$ printf "quoted"',
        run: 'printf "quoted"',
        node: 'quote-0-0',
      },
    ]);
    expect(listedBlocks([{ ...entry, text: text + '\n````' }])).toHaveLength(2);
  });
});
