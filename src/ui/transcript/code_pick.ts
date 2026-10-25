/**
 * A reply's code block picked through the leader, `ctrl+x b`
 * (docs/design/CHD-394.md §3): which block is picked, and where ↑ and ↓
 * take the pick. The window draws the picked box and hands its keys here.
 */

import {
  type Action,
  type Keymap,
  keysOf,
  sequencePanel,
} from '../shortcuts/bindings.ts';
import type { Soft } from './markdown.ts';

/** A code block where it is drawn: the text it is in, then its place there. */
export interface BlockRef {
  /** The reply, message or tool text it is in, by the number its drawing took. */
  readonly entry: number;
  /** Its place among the reply's code blocks, as `codeBlocks` numbers it. */
  readonly block: number;
}

/** The block picked; none while no pick is on. */
export type CodePick = BlockRef | undefined;

export type CodePickAction =
  /**
   * `ctrl+x b`, with every block in the order drawn and those on screen:
   * the newest on screen is picked, or else the newest of all.
   */
  | {
      readonly type: 'code_pick_started';
      readonly blocks: readonly BlockRef[];
      readonly shown: readonly BlockRef[];
    }
  /** ↑ or ↓: the block above or below, in the order drawn. */
  | {
      readonly type: 'code_pick_moved';
      readonly by: -1 | 1;
      readonly blocks: readonly BlockRef[];
    }
  /** c, r, esc or any other key: the pick is over. */
  | { readonly type: 'code_pick_ended' };

export function reduceCodePick(
  state: CodePick,
  action: CodePickAction,
): CodePick {
  switch (action.type) {
    case 'code_pick_started':
      return (
        newest(action.blocks, action.shown) ??
        newest(action.blocks, action.blocks)
      );
    case 'code_pick_moved': {
      if (state === undefined) {
        return undefined;
      }

      const at = action.blocks.findIndex((ref) => same(ref, state));

      // The block gone, as its reply was cleared, the pick goes to the newest.
      if (at === -1) {
        return action.blocks.at(-1);
      }

      // At either end it stays, as the agents list's pick does.
      return action.blocks[
        Math.min(Math.max(at + action.by, 0), action.blocks.length - 1)
      ];
    }
    case 'code_pick_ended':
      return undefined;
  }
}

/** The last of `blocks` that is among `among`; none when none is. */
function newest(
  blocks: readonly BlockRef[],
  among: readonly BlockRef[],
): BlockRef | undefined {
  return blocks.findLast((ref) => among.some((other) => same(ref, other)));
}

function same(a: BlockRef, b: BlockRef): boolean {
  return a.entry === b.entry && a.block === b.block;
}

/**
 * The ids a reply's code boxes and quotes are drawn with, the reply being
 * `entry`, and, by each block's `codeBlocks` index, the id of what it is
 * drawn in: its own box, or the quote whose text holds it. `soft` is the
 * reply as `softMarkdown` laid it out, and `places` as `codePlaces` says.
 */
export function drawnIds(
  soft: readonly Soft[],
  places: {
    readonly boxes: readonly number[];
    readonly quotes: readonly (readonly number[])[];
  },
  entry: number,
): {
  readonly ids: ReadonlyMap<Soft, string>;
  readonly nodes: readonly string[];
} {
  const ids = new Map<Soft, string>();
  const nodes: string[] = [];
  let box = 0;
  let quote = 0;
  const walk = (blocks: readonly Soft[]) => {
    for (const block of blocks) {
      if (block.kind === 'list') {
        for (const item of block.items) {
          walk(item.blocks);
        }
      } else if (block.kind === 'code') {
        const index = places.boxes[box++];

        if (index !== undefined) {
          const id = `code-${entry}-${index}`;

          ids.set(block, id);

          nodes[index] = id;
        }
      } else if (block.kind === 'quote') {
        const held = places.quotes[quote] ?? [];
        const id = `quote-${entry}-${quote++}`;

        ids.set(block, id);

        for (const index of held) {
          nodes[index] = id;
        }
      }
    }
  };

  walk(soft);

  return { ids, nodes };
}

/** Where a drawn block's box, or its quote, is on screen now. */
export interface Placed {
  readonly ref: BlockRef;
  readonly top: number;
  readonly left: number;
  readonly height: number;
}

/**
 * The blocks drawn, in the order they are on screen, top to bottom, then
 * left to right, then as written; and those in `view`, the transcript's
 * rows on screen, by any row of theirs.
 */
export function onScreen(
  drawn: readonly Placed[],
  view: { readonly top: number; readonly height: number },
): { readonly blocks: BlockRef[]; readonly shown: BlockRef[] } {
  const sorted = [...drawn].sort(
    (a, b) => a.top - b.top || a.left - b.left || a.ref.block - b.ref.block,
  );

  return {
    blocks: sorted.map(({ ref }) => ref),
    shown: sorted
      .filter(
        ({ top, height }) =>
          top < view.top + view.height && top + height > view.top,
      )
      .map(({ ref }) => ref),
  };
}

/**
 * The status line while a block is picked: the keys that do something to
 * it, named as the shortcuts panel names them, `r` only on a block with
 * `[run]` (docs/design/CHD-394.md §3). An action with no key bound is left
 * out.
 */
export function pickHint(keymap: Keymap, run: boolean): string {
  const key = (action: Action) => {
    const [first] = keysOf(keymap, action);

    return first === undefined ? undefined : sequencePanel(first);
  };

  const up = key('codeBlock:previous');
  const down = key('codeBlock:next');
  const moves = [up, down].filter((name) => name !== undefined).join(' ');
  const parts: [string | undefined, string][] = [
    [moves === '' ? undefined : moves, 'another block'],
    [key('codeBlock:copy'), 'copy'],
    [run ? key('codeBlock:prompt') : undefined, 'put in the prompt'],
    [key('codeBlock:cancel'), 'done'],
  ];

  return parts
    .flatMap(([keys, words]) =>
      keys === undefined ? [] : [`${keys} ${words}`],
    )
    .join(' · ');
}
