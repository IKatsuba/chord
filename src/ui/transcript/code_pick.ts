/**
 * A reply's code block picked through the leader, `ctrl+x b`
 * (docs/design/CHD-394.md §3): which block is picked, and where ↑ and ↓
 * take the pick. The window draws the picked box and hands its keys here.
 */

/** A code block where it is drawn: its reply's entry, then its place there. */
export interface BlockRef {
  /** The reply's entry in the transcript, by its place among the entries. */
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
